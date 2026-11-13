import Defaults
import Foundation
import Observation
import AidenteShared

enum ScheduleActionKind: String, Codable, CaseIterable, Identifiable {
    case setChargeLimit
    case startCalibration
    case topUp
    case pauseCharging
    case dischargeTo
    case enableLowPower
    case disableLowPower

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setChargeLimit: AidenteL10n.t("设置充电上限")
        case .startCalibration: AidenteL10n.t("开始电池校准")
        case .topUp: AidenteL10n.t("临时充至 100%")
        case .pauseCharging: AidenteL10n.t("暂停充电")
        case .dischargeTo: AidenteL10n.t("放电至")
        case .enableLowPower: AidenteL10n.t("启用低功耗模式", "Enable Low Power Mode")
        case .disableLowPower: AidenteL10n.t("关闭低功耗模式", "Disable Low Power Mode")
        }
    }

    var usesValue: Bool {
        self == .setChargeLimit || self == .dischargeTo
    }
}

enum ScheduleRepeatRule: String, Codable, CaseIterable, Identifiable {
    case never
    case daily
    case weekdays
    case weekly
    case biweekly
    case monthly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: AidenteL10n.t("仅一次")
        case .daily: AidenteL10n.t("每天")
        case .weekdays: AidenteL10n.t("工作日")
        case .weekly: AidenteL10n.t("每周")
        case .biweekly: AidenteL10n.t("每两周")
        case .monthly: AidenteL10n.t("每月")
        case .yearly: AidenteL10n.t("每年", "Yearly")
        }
    }
}

struct ScheduleTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var action: ScheduleActionKind
    var value: Int
    var repeatRule: ScheduleRepeatRule
    var nextRun: Date
    var isActive: Bool
    var weekdays: [Int]? = nil
    var anchorDay: Int? = nil
    var anchorMonth: Int? = nil
    var runAtNextOpportunity: Bool

    var summary: String {
        if action.usesValue {
            "\(action.title) \(value)%"
        } else {
            action.title
        }
    }
}

@MainActor
@Observable
final class ScheduleStore {
    static let shared = ScheduleStore()

    private(set) var tasks: [ScheduleTask] = []
    private(set) var history: [ScheduleHistoryEntry] = []
    func record(_ task: ScheduleTask, outcome: String, detail: String = "") {
        history.insert(ScheduleHistoryEntry(id: UUID(), date: Date(), action: task.action.rawValue,
            summary: task.summary, outcome: outcome, detail: detail), at: 0)
        history = Array(history.prefix(200))
        Defaults[.scheduleHistoryData] = (try? JSONEncoder().encode(history)) ?? Data()
    }
    func clearHistory() { history = []; Defaults[.scheduleHistoryData] = Data() }
    func update(_ task: ScheduleTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var task = task
        task.anchorDay = Calendar.autoupdatingCurrent.component(.day, from: task.nextRun)
        task.anchorMonth = Calendar.autoupdatingCurrent.component(.month, from: task.nextRun)
        tasks[index] = task
        tasks.sort { $0.nextRun < $1.nextRun }; save()
    }

    private init() {
        load()
    }

    func add(_ task: ScheduleTask) {
        var task = task
        task.anchorDay = Calendar.autoupdatingCurrent.component(.day, from: task.nextRun)
        task.anchorMonth = Calendar.autoupdatingCurrent.component(.month, from: task.nextRun)
        tasks.append(task)
        tasks.sort { $0.nextRun < $1.nextRun }
        save()
    }

    func remove(_ task: ScheduleTask) {
        tasks.removeAll { $0.id == task.id }
        save()
    }

    func setActive(_ active: Bool, for task: ScheduleTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isActive = active
        save()
    }

    func takeDueTasks(at date: Date = Date()) -> [ScheduleTask] {
        var due: [ScheduleTask] = []
        var advancedTask = false

        for index in tasks.indices where tasks[index].isActive && tasks[index].nextRun <= date {
            let lateness = date.timeIntervalSince(tasks[index].nextRun)
            if lateness <= 600 || (Defaults[.scheduleCatchUpEnabled] && tasks[index].runAtNextOpportunity) {
                due.append(tasks[index])
            } else { record(tasks[index], outcome: "skipped") }
            advanceTask(at: index, after: date)
            advancedTask = true
        }

        if advancedTask {
            tasks.sort { $0.nextRun < $1.nextRun }
            save()
        }

        return due
    }

    private func advanceTask(at index: Int, after date: Date) {
        guard tasks.indices.contains(index) else { return }
        let calendar = Calendar.autoupdatingCurrent

        if tasks[index].repeatRule == .never {
            tasks[index].isActive = false
            return
        }

        if tasks[index].anchorDay == nil { tasks[index].anchorDay = calendar.component(.day, from: tasks[index].nextRun) }
        if tasks[index].anchorMonth == nil { tasks[index].anchorMonth = calendar.component(.month, from: tasks[index].nextRun) }
        if let next = ScheduleRecurrence.next(after: date, previous: tasks[index].nextRun,
            rule: tasks[index].repeatRule.rawValue, weekdays: tasks[index].weekdays ?? [],
            anchorDay: tasks[index].anchorDay, anchorMonth: tasks[index].anchorMonth, calendar: calendar) {
            tasks[index].nextRun = next
        } else { tasks[index].isActive = false }
    }

    private func load() {
        history = (try? JSONDecoder().decode([ScheduleHistoryEntry].self, from: Defaults[.scheduleHistoryData])) ?? []
        let data = Defaults[.scheduleTasksData]
        guard !data.isEmpty,
            let decoded = try? JSONDecoder().decode([ScheduleTask].self, from: data)
        else {
            tasks = []
            return
        }
        tasks = decoded.sorted { $0.nextRun < $1.nextRun }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        Defaults[.scheduleTasksData] = data
    }
}

struct ScheduleHistoryEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let action: String
    let summary: String
    let outcome: String
    let detail: String
}
