import AppKit
import Defaults
import SwiftUI

struct AutomationSettingsView: View {
    @Default(.appLanguage) private var appLanguage

    @State private var scheduleStore = ScheduleStore.shared
    @State private var showingNewTask = false
    @State private var editingTask: ScheduleTask?

    @Default(.scheduleCatchUpEnabled) private var catchUp
    @State private var clearHistory = false
    @State private var deleting: ScheduleTask?
    var body: some View {
        AidenteSettingsPage {
            AidenteCard("任务", subtitle: "按设定时间自动调整上限、补电、校准、暂停或放电。", icon: "text.badge.checkmark", colors: []) {
                UtilitySurface {
                    VStack(spacing: 14) {
                        if scheduleStore.tasks.isEmpty {
                            Text(AidenteL10n.t("点击“+”按钮添加新任务，或从模板中选择。", "Click + to add a task, or choose a template."))
                                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 280)
                        } else {
                            ForEach(scheduleStore.tasks) { task in
                                HStack(spacing: 10) {
                                    Image(systemName: task.action.icon).frame(width: 22)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(task.summary).font(.system(size: 12, weight: .semibold))
                                        Text(task.nextRun.formatted(date: .abbreviated, time: .shortened) + " · " + task.repeatRule.title).font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture { editingTask = task; showingNewTask = true }
                                    Toggle("", isOn: Binding(get: { task.isActive }, set: { scheduleStore.setActive($0, for: task) })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                                    Button { editingTask = task; showingNewTask = true } label: { Image(systemName: "pencil") }.help(AidenteL10n.t("编辑任务", "Edit Task"))
                                    Button { deleting = task } label: { Image(systemName: "trash") }.help(AidenteL10n.t("删除任务", "Delete Task"))
                                }.buttonStyle(.borderless)
                                if task.id != scheduleStore.tasks.last?.id { Divider() }
                            }
                        }
                    }.frame(minHeight: scheduleStore.tasks.isEmpty ? 280 : 80, alignment: .top)
                }
                HStack {
                    Button { editingTask = nil; showingNewTask = true } label: { Image(systemName: "plus.app").font(.system(size: 18)) }
                        .help(AidenteL10n.t("添加计划任务", "Add Task"))
                    Menu {
                        Button(AidenteL10n.t("每月校准", "Monthly Calibration")) { addTemplate(.startCalibration, .monthly) }
                        Button(AidenteL10n.t("每两周校准", "Biweekly Calibration")) { addTemplate(.startCalibration, .biweekly) }
                        Button(AidenteL10n.t("工作日补电", "Weekday Top Up")) { addTemplate(.topUp, .weekdays) }
                        Button(AidenteL10n.t("每天限充 80%", "Daily 80% Limit")) { addTemplate(.setChargeLimit, .daily) }
                    } label: { Label(AidenteL10n.t("模板", "Templates"), systemImage: "doc.on.doc") }.fixedSize()
                    Spacer()
                }.buttonStyle(AidenteActionButtonStyle(colors: []))
            }
            AidenteSettingToggle("自动补做未完成的任务", subtitle: "Mac 唤醒后补做错过的任务；也需该任务允许补做。", icon: "arrow.clockwise", colors: [], isOn: $catchUp)
            AidenteCard("任务历史", subtitle: "记录任务触发、跳过或失败；触发不代表硬件操作已经完成。", icon: "rectangle.and.pencil.and.ellipsis", colors: []) {
                UtilitySurface {
                    if scheduleStore.history.isEmpty {
                        Text(AidenteL10n.t("已触发的任务将显示在此处。", "Triggered tasks will appear here.")).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 70)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(scheduleStore.history.prefix(30)) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.summary).font(.system(size: 12, weight: .semibold))
                                    Text("\(entry.date.formatted()) · \(entry.outcome == "triggered" ? AidenteL10n.t("已触发", "Triggered") : entry.outcome == "skipped" ? AidenteL10n.t("已跳过", "Skipped") : AidenteL10n.t("失败", "Failed"))").font(.caption).foregroundStyle(.secondary)
                                    if !entry.detail.isEmpty { Text(entry.detail).font(.caption).foregroundStyle(.red) }
                                }
                            }
                            Button(AidenteL10n.t("清空历史", "Clear History")) { clearHistory = true }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewTask) { NewScheduleTaskView(isPresented: $showingNewTask, editingTask: editingTask) }
        .confirmationDialog(AidenteL10n.t("清空任务历史？", "Clear task history?"), isPresented: $clearHistory) {
            Button(AidenteL10n.t("清空历史", "Clear History"), role: .destructive) { scheduleStore.clearHistory() }
        }
        .confirmationDialog(AidenteL10n.t("删除此任务？", "Delete this task?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(AidenteL10n.t("删除任务", "Delete Task"), role: .destructive) { if let task = deleting { scheduleStore.remove(task) }; deleting = nil }
        }
    }
    private func addTemplate(_ action: ScheduleActionKind, _ rule: ScheduleRepeatRule) {
        ScheduleStore.shared.add(ScheduleTask(action: action, value: 80, repeatRule: rule,
            nextRun: Date().addingTimeInterval(3600), isActive: false, runAtNextOpportunity: true))
    }

}

private struct NewScheduleTaskView: View {
    @Binding var isPresented: Bool
    let editingTask: ScheduleTask?
    @State private var weekdays: [Int] = []

    @State private var action: ScheduleActionKind = .setChargeLimit
    @State private var value = 80
    @State private var repeatRule: ScheduleRepeatRule = .never
    @State private var nextRun = Date().addingTimeInterval(3_600)
    @State private var runAtNextOpportunity = true

    var body: some View {
        ZStack {
            AidenteSettingsBackground()

            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    AidenteIconBadge(
                        icon: "calendar.badge.plus",
                        colors: AidenteTheme.automationColors,
                        size: 44
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AidenteL10n.t(editingTask == nil ? "添加计划任务" : "编辑任务"))
                            .font(.title2.bold())
                        Text(AidenteL10n.t("选择动作、执行时间和重复规则"))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                AidenteCard(
                    "任务设置",
                    icon: "slider.horizontal.3",
                    colors: AidenteTheme.automationColors
                ) {
                    AidenteControlRow(
                        "执行动作",
                        icon: action.icon,
                        colors: action.colors
                    ) {
                        Picker("", selection: $action) {
                            ForEach(ScheduleActionKind.allCases) { action in
                                Text(action.title).tag(action)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }

                    if action.usesValue {
                        AidenteRowDivider()
                        AidenteControlRow(
                            AidenteL10n.t(
                                action == .setChargeLimit ? "充电上限" : "放电目标"
                            ),
                            icon: "percent",
                            colors: AidenteTheme.chargingColors
                        ) {
                            HStack {
                                Slider(
                                    value: Binding(
                                        get: { Double(value) },
                                        set: { value = Int($0) }
                                    ),
                                    in: 20...100,
                                    step: 1
                                )
                                .frame(width: 150)
                                Text("\(value)%")
                                    .monospacedDigit()
                                    .frame(width: 42, alignment: .trailing)
                            }
                        }
                    }

                    AidenteRowDivider()
                    AidenteControlRow(
                        "首次执行",
                        icon: "clock.badge.fill",
                        colors: AidenteTheme.generalColors
                    ) {
                        DatePicker(
                            "",
                            selection: $nextRun
                        )
                        .labelsHidden()
                    }

                    AidenteRowDivider()
                    AidenteControlRow(
                        "重复",
                        icon: "repeat.circle.fill",
                        colors: AidenteTheme.dashboardColors
                    ) {
                        Picker("", selection: $repeatRule) {
                            ForEach(ScheduleRepeatRule.allCases) { rule in
                                Text(rule.title).tag(rule)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }

                    if repeatRule == .weekly || repeatRule == .biweekly {
                        HStack {
                            ForEach(1...7, id: \.self) { day in
                                Toggle(Calendar.autoupdatingCurrent.shortWeekdaySymbols[day - 1], isOn: Binding(
                                    get: { weekdays.contains(day) }, set: { enabled in
                                        if enabled { weekdays.append(day) } else { weekdays.removeAll { $0 == day } }
                                    })).toggleStyle(.button)
                            }
                        }
                    }
                    AidenteRowDivider()
                    AidenteSettingToggle(
                        "错过后尽快补做",
                        subtitle: "Mac 唤醒并运行 Aidente 后执行",
                        icon: "arrow.clockwise.circle.fill",
                        colors: AidenteTheme.automationColors,
                        isOn: $runAtNextOpportunity
                    )
                }

                HStack {
                    Button(AidenteL10n.t("取消")) {
                        isPresented = false
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button {
                        var task = ScheduleTask(
                                action: action,
                                value: value,
                                repeatRule: repeatRule,
                                nextRun: nextRun,
                                isActive: true,
                                runAtNextOpportunity: runAtNextOpportunity
                            )
                        task.weekdays = weekdays
                        if let editingTask { task.id = editingTask.id; task.isActive = editingTask.isActive; ScheduleStore.shared.update(task) }
                        else { ScheduleStore.shared.add(task) }
                        isPresented = false
                    } label: {
                        Label(AidenteL10n.t(editingTask == nil ? "添加任务" : "保存更改", editingTask == nil ? "Add Task" : "Save Changes"), systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(AidenteActionButtonStyle(colors: AidenteTheme.automationColors))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        }
        .frame(width: 620, height: 690)
        .onAppear {
            if let task = editingTask {
                action = task.action; value = task.value; repeatRule = task.repeatRule
                nextRun = task.nextRun; runAtNextOpportunity = task.runAtNextOpportunity
                weekdays = task.weekdays ?? []
            }
        }
    }
}

private extension ScheduleActionKind {
    var icon: String {
        switch self {
        case .setChargeLimit: "battery.75percent"
        case .startCalibration: "arrow.triangle.2.circlepath.circle.fill"
        case .topUp: "bolt.circle.fill"
        case .pauseCharging: "pause.circle.fill"
        case .dischargeTo: "arrow.down.circle.fill"
        case .enableLowPower, .disableLowPower: "leaf"
        }
    }

    var colors: [Color] {
        switch self {
        case .setChargeLimit: AidenteTheme.chargingColors
        case .startCalibration: AidenteTheme.dashboardColors
        case .topUp: AidenteTheme.automationColors
        case .pauseCharging: [AidenteTheme.coral, AidenteTheme.amber]
        case .dischargeTo: AidenteTheme.generalColors
        case .enableLowPower, .disableLowPower: AidenteTheme.chargingColors
        }
    }
}
