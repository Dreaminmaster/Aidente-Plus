import AppKit
import AidenteShared
import Defaults
import Foundation
import Observation
import ServiceManagement
import UserNotifications

@MainActor @Observable
final class CompleteUninstaller {
    static let shared = CompleteUninstaller()
    private(set) var isRunning = false
    private(set) var hasRemovedService = false
    private(set) var status = ""
    private(set) var errorMessage: String?
    private var prepare: (() async throws -> Void)?
    private var stopWriters: (() async -> Void)?
    private var resume: ((Bool) -> Void)?

    func configure(prepare: @escaping () async throws -> Void,
                   stopWriters: @escaping () async -> Void,
                   resume: @escaping (Bool) -> Void) {
        self.prepare = prepare
        self.stopWriters = stopWriters
        self.resume = resume
    }

    func dismissError() { errorMessage = nil }

    func start() {
        guard !isRunning, !AidenteRuntime.isUIPreview else { return }
        guard Bundle.main.bundleURL.standardizedFileURL.path == "/Applications/Aidente.app" else {
            errorMessage = AidenteL10n.t("请从“应用程序”中的 Aidente 执行卸载。", "Run the uninstaller from Aidente in Applications.")
            return
        }
        guard let prepare, let stopWriters, let resume else { return }
        isRunning = true
        errorMessage = nil
        Task {
            var didSuspend = false
            do {
                let otherInstances = NSRunningApplication.runningApplications(withBundleIdentifier: "com.aidente.app")
                    .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
                guard otherInstances.isEmpty else {
                    throw XPCError.commandFailed(AidenteL10n.t("请先退出其他正在运行的 Aidente 副本。", "Quit other running copies of Aidente first."))
                }
                let legacy = SMAppService.daemon(plistName: "com.aidente.app.control.plist")
                // The current local helper restores firmware before it is removed.
                // A still-active legacy helper must first be migrated through Repair.
                guard legacy.status != .enabled && legacy.status != .requiresApproval else {
                    throw XPCError.commandFailed(AidenteL10n.t(
                        "检测到旧版后台服务。请先在充电管理中修复控制服务，再执行完全卸载。",
                        "A legacy service is still registered. Repair the control service in Charging, then uninstall."
                    ))
                }
                let plan = UninstallPlan(home: FileManager.default.homeDirectoryForCurrentUser)
                let candidates = try userDataCandidates(plan)
                for url in candidates { try plan.validateUserTarget(url) }
                _ = try validatedUpdateBackups()
                status = AidenteL10n.t("正在暂停充电管理…", "Pausing charging management…")
                try await prepare()
                didSuspend = true
                await stopWriters()
                try await UninstallSequence.run(
                    removeService: {
                        self.status = AidenteL10n.t("正在恢复充电状态并移除后台服务…", "Restoring charging and removing the service…")
                        try await ChargingHelperManager.shared.uninstallCompletely()
                        self.hasRemovedService = true
                        // Prevent another instance from reenabling stale management after a later failure.
                        Defaults[.manageCharging] = false
                        Defaults[.launchAtLogin] = false
                    },
                    removeLoginItem: {
                        self.status = AidenteL10n.t("正在移除登录项…", "Removing the login item…")
                        try await LaunchAtLoginService.shared.unregisterForUninstall()
                        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                    },
                    removeUserData: {
                        self.status = AidenteL10n.t("正在清理当前账户的数据…", "Cleaning this account’s data…")
                        try self.cleanUserData(plan: plan)
                    },
                    trashApplication: {
                        self.status = AidenteL10n.t("正在将应用移入废纸篓…", "Moving the app to Trash…")
                        try FileManager.default.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)
                    }
                )
                self.isRunning = false
                NSApplication.shared.terminate(nil)
            } catch {
                if didSuspend { resume(self.hasRemovedService) }
                self.errorMessage = AidenteL10n.t(
                    "卸载未完成，应用已保留，可修复后重试。\n", "Uninstall did not finish. The app was kept so you can retry.\n"
                ) + error.localizedDescription
                self.isRunning = false
            }
        }
    }

    private func userDataCandidates(_ plan: UninstallPlan) throws -> [URL] {
        let directory = plan.home.appendingPathComponent("Library/Preferences/ByHost")
        // Validate the directory path without enumerating a redirected parent.
        try plan.validateUserTarget(directory.appendingPathComponent("com.aidente.app.00000000-0000-0000-0000-000000000000.plist"))
        let entries: [URL]
        if try UninstallPlan.entryExists(directory) {
            entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } else { entries = [] }
        return plan.userData + plan.byHostPreferences(in: entries)
    }

    private func validatedUpdateBackups() throws -> [URL] {
        let manager = FileManager.default
        let app = Bundle.main.bundleURL.standardizedFileURL
        let entries = try manager.contentsOfDirectory(at: app.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        let backups = UninstallPlan.updateBackups(in: entries, application: app)
        for backup in backups {
            let metadata = try manager.attributesOfItem(atPath: backup.path)
            // Moving a leaf symlink to Trash does not follow it.
            if metadata[.type] as? FileAttributeType == .typeSymbolicLink { continue }
            guard metadata[.type] as? FileAttributeType == .typeDirectory,
                  Bundle(url: backup)?.bundleIdentifier == "com.aidente.app" else {
                throw XPCError.commandFailed(AidenteL10n.t("无法确认更新备份的归属，已停止清理：", "Cannot identify an update backup; cleanup stopped: ") + backup.lastPathComponent)
            }
        }
        return backups
    }

    private func cleanUserData(plan: UninstallPlan) throws {
        let manager = FileManager.default
        let candidates = try userDataCandidates(plan)
        for url in candidates { try plan.validateUserTarget(url) }
        for window in NSApplication.shared.windows {
            window.setFrameAutosaveName("")
            window.isRestorable = false
        }
        // Clear cfprefsd's domain cache, not just its on-disk plist.
        for domain in UninstallPlan.preferenceDomains {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        guard UserDefaults.standard.synchronize() else {
            throw XPCError.commandFailed(AidenteL10n.t("设置清理未能同步，请重试。", "Preference cleanup could not be synchronized. Retry."))
        }
        for url in candidates {
            // attributesOfItem detects a broken leaf symlink; trash moves the link, not its target.
            if try UninstallPlan.entryExists(url) {
                try plan.validateUserTarget(url)
                try manager.trashItem(at: url, resultingItemURL: nil)
            }
        }
        for url in try validatedUpdateBackups() { try manager.trashItem(at: url, resultingItemURL: nil) }
        let temporary = manager.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let temporaryEntries = try manager.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)
        for url in UninstallPlan.diagnosticTemporaryFiles(in: temporaryEntries, temporaryDirectory: temporary) {
            try manager.trashItem(at: url, resultingItemURL: nil)
        }

    }
}
