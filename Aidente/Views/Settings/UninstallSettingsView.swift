import SwiftUI

struct UninstallSettingsView: View {
    private let uninstaller = CompleteUninstaller.shared
    @State private var showConfirmation = false

    var body: some View {
        AidenteCard("完全卸载 Aidente", subtitle: "恢复充电状态并清理应用组件。", icon: "trash", colors: AidenteTheme.aboutColors) {
            Text(AidenteL10n.t(
                "移除后台服务、恢复备份和登录项，清除本账户的设置，并将历史记录、缓存和应用移入废纸篓。不会清理其他账户、另存的诊断包、下载的 DMG 或官方 AlDente。",
                "Removes the service, recovery backups and login item, clears this account’s preferences, and moves history, caches and the app to Trash. Other accounts, exported diagnostics, downloaded DMGs and official AlDente are kept."
            )).font(.callout).foregroundStyle(.secondary)
            if uninstaller.isRunning {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(uninstaller.status).font(.caption)
                }
            }
            if AidenteRuntime.isUIPreview {
                Text(AidenteL10n.t("预览模式只展示确认说明，不执行卸载。", "Preview mode shows the confirmation without performing an uninstall."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button(role: .destructive) { showConfirmation = true } label: {
                Label(AidenteL10n.t("完全卸载 Aidente…", "Uninstall Aidente Completely…"), systemImage: "trash")
            }.disabled(uninstaller.isRunning)
        }
        .alert(AidenteL10n.t("完全卸载 Aidente？", "Uninstall Aidente Completely?"), isPresented: $showConfirmation) {
            Button(AidenteL10n.t("取消", "Cancel"), role: .cancel) {}
            Button(AidenteL10n.t("卸载并退出", "Uninstall and Quit"), role: .destructive) { uninstaller.start() }
                .disabled(AidenteRuntime.isUIPreview)
        } message: {
            Text(AidenteL10n.t(
                "先恢复默认充电控制，再移除系统后台服务及其恢复备份。随后清除本账户的设置，将历史记录、缓存和应用移入废纸篓并退出。移除系统组件需要 macOS 管理员授权。\n如果恢复充电失败，会停止卸载并保留服务和数据。下载的 DMG、另存的诊断包和系统日志不会删除。",
                "Restores default charging first, then removes the service and its recovery backups. Clears this account’s preferences, moves history, caches and the app to Trash, and quits. macOS administrator authorization is required for system components.\nIf charging restoration fails, removal stops and the service and data are kept. Downloaded DMGs, exported diagnostics and system logs are not deleted."
            ))
        }
        .alert(AidenteL10n.t("卸载未完成", "Uninstall Incomplete"), isPresented: Binding(
            get: { uninstaller.errorMessage != nil }, set: { if !$0 { uninstaller.dismissError() } }
        )) {
            Button(AidenteL10n.t("好", "OK")) { uninstaller.dismissError() }
        } message: { Text(uninstaller.errorMessage ?? "") }
    }
}
