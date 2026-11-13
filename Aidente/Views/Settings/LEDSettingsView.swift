import Defaults
import SwiftUI

struct LEDSettingsView:View {
    var onOpenChargeSettings:()->Void = {}
    @Default(.manageCharging) private var chargingManaged
    @Default(.interfaceAppearance) private var appearance
    @Default(.manageMagSafeLED) private var managed
    @Default(.ledBehavior) private var behavior
    @Default(.blinkLEDWhileDischarging) private var blink
    @State private var draftBehavior:LEDBehavior?
    @State private var draftBlink:Bool?
    @State private var error:String?
    @State private var applying=false
    private let setup=BatteryManagementSetup.shared
    private let helper=ChargingHelperManager.shared
    private var ready:Bool { chargingManaged && helper.isInstalled && helper.registrationError == nil }
    var body:some View {
        AidenteSettingsPage {
            AidenteControlRow("界面外观",subtitle:"跟随 macOS，或只为 Aidente 固定浅色、深色；立即应用到菜单、仪表板和设置窗口。",icon:"circle.lefthalf.filled",colors:[]) {
                Picker(AidenteL10n.t("界面外观","Appearance"),selection:$appearance) { ForEach(InterfaceAppearance.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(width:160)
            }
            AidenteCard("MagSafe 指示灯",subtitle:"限充与指示灯共用电池管理服务，无需额外的指示灯权限。",icon:"lightbulb",colors:[]) {
                if !ready {
                    VStack(alignment:.leading,spacing:10) {
                        Label(AidenteL10n.t(chargingManaged ? "电池管理需要修复":"需要启用电池管理",chargingManaged ? "Battery Management Needs Repair":"Battery Management Required"),systemImage:"info.circle")
                        Text(AidenteL10n.t("尚未启用。可以先选择模式；启用成功后会应用当前选择，取消不会开启。","Not enabled. Preview modes first; successful setup applies your selection. Cancel leaves control off.")).font(.caption).foregroundStyle(.secondary)
                        Button(AidenteL10n.t(chargingManaged ? "修复并继续":"启用并继续",chargingManaged ? "Repair and Continue":"Enable and Continue")) { enableAndApply() }
                            .buttonStyle(.borderedProminent).disabled(setup.enabling || helper.isBusy || applying)
                    }
                }
                AidenteSettingToggle("由 Aidente 管理指示灯",subtitle:"开启后可让灯光表示充电状态、一直关闭，或仅睡眠时关闭。关闭此开关会将灯光控制交还 macOS。",icon:"lightbulb",colors:[],isOn:Binding(get:{ ready && managed },set:{ value in
                    if !ready && value { enableAndApply() }
                    else if ready { managed=value;apply() }
                })).disabled(setup.enabling || applying)
                if ready && !managed {
                    Text(AidenteL10n.t("尚未启用指示灯管理；所选模式会在开启后应用。","LED management is off. The selected mode applies after enabling it.")).font(.caption).foregroundStyle(.secondary)
                }
                AidenteControlRow("指示灯模式",subtitle:"指示充电上限：保持时显示绿色，充电时显示橙色；始终关闭：一直熄灯；睡眠时关闭：仅在睡眠时熄灯。",icon:"lightbulb",colors:[]) {
                    Picker(AidenteL10n.t("指示灯模式","LED Setting"),selection:Binding(get:{ ready ? behavior:(draftBehavior ?? behavior) },set:{ value in
                        if ready { behavior=value;if managed { apply() } } else { draftBehavior=value }
                    })) { ForEach(LEDBehavior.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(width:180).disabled(setup.enabling || applying)
                }
                AidenteSettingToggle("放电时闪烁橙灯",icon:"lightbulb.max",colors:[],isOn:Binding(get:{ ready ? blink:(draftBlink ?? blink) },set:{ value in
                    if ready { blink=value;if managed { apply() } } else { draftBlink=value }
                })).disabled(setup.enabling || applying)
                Text(AidenteL10n.t("不支持 MagSafe 灯光的设备或固件不会强制生效。普通模式切换不需要重复输入管理员密码。","Unsupported hardware cannot be forced to control an LED. Ordinary mode changes do not need repeated administrator passwords.")).font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }.onAppear { helper.refreshStatus() }
    }
    private func enableAndApply() {
        Task {
            do {
                guard try await setup.enable(onAuthorized:{
                    if let draftBehavior { behavior=draftBehavior };if let draftBlink { blink=draftBlink }
                    draftBehavior=nil;draftBlink=nil;managed=true
                }) else { return }
                applying=true
                defer { applying=false }
                try await ApplicationActions.shared.execute("led-policy");error=nil
            } catch { managed=false;self.error=error.localizedDescription }
        }
    }
    private func apply() {
        guard ready,!AidenteRuntime.isUIPreview,!applying else { return }
        applying=true
        Task {
            defer { applying=false }
            do { try await ApplicationActions.shared.execute("led-policy");error=nil }
            catch { managed=false;self.error=error.localizedDescription }
        }
    }
}
