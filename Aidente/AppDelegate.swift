import AppKit
import AppIntents
import Defaults
import Darwin
import IOKit
import Observation
import UserNotifications
import smc_power

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarManager: StatusBarManager!
    private var batteryService: BatteryService!
    private var viewModel: MenuViewModel!
    private var chargeManager: ChargeManager!
    private var diagnosticCenter: DiagnosticCenter!
    private var batteryHistoryService: BatteryHistoryService!
    private var updateService: UpdateService!
    private var settingsWindowController: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--render-power-flow=") }) {
            do { try PowerFlowPreview.render(to:String(argument.dropFirst("--render-power-flow=".count)));Darwin.exit(0) }
            catch { fputs("FLOW_PREVIEW_FAILED: \(error)\n",stderr);Darwin.exit(1) }
        }
        if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--render-status-icons=") }) {
            do {
                try StatusIconPreview.render(to: String(argument.dropFirst("--render-status-icons=".count)))
                Darwin.exit(0)
            } catch { Darwin.exit(1) }
        }
        if CommandLine.arguments.contains("--check-control-signing") {
            do {
                try ChargingHelperManager.shared.validateSigningIdentity()
                print("CONTROL_SIGNING_OK")
                Darwin.exit(0)
            } catch {
                print("CONTROL_SIGNING_FAILED: \(error.localizedDescription)")
                Darwin.exit(1)
            }
        }
        if !AidenteRuntime.isUIPreview { AidenteMigration.migrateLegacyPreferencesIfNeeded() }

        // Health-only integration probe: no charge policy, LED changes or UI
        // services. Run from the installed bundle so SMAppService resolves it.
        if CommandLine.arguments.contains("--check-control-service") {
            Task {
                do {
                    try await ChargingHelperManager.shared.enableForUser()
                    print("CONTROL_SERVICE_HEALTH_OK")
                    Darwin.exit(0)
                } catch {
                    print("CONTROL_SERVICE_HEALTH_FAILED: \(error.localizedDescription)")
                    Darwin.exit(1)
                }
            }
            return
        }

        if CommandLine.arguments.contains("--print-effective-defaults") {
            print("manageCharging=\(Defaults[.manageCharging])")
            print("manualPauseActive=\(Defaults[.manualPauseActive])")
            Darwin.exit(0)
        }

        if CommandLine.arguments.contains("--print-energy-apps") {
            _ = AppEnergyUsageService.readTopApps(limit: 10, stabilize: false)
            Thread.sleep(forTimeInterval: 2)
            for app in AppEnergyUsageService.readTopApps(limit: 10, stabilize: false) ?? [] {
                print(
                    "\(app.name)\t\(String(format: "%.2f", app.cpuUsage))%\t\(app.bundlePath)"
                )
            }
            Darwin.exit(0)
        }

        if CommandLine.arguments.contains("--unregister-helper") {
            Task {
                do {
                    try await ChargingHelperManager.shared.uninstall()
                    Darwin.exit(0)
                } catch { Darwin.exit(1) }
            }
            return
        }

        if CommandLine.arguments.contains("--test-update-version") {
            let passed = UpdateService.runVersionSelfTest()
            fputs(passed ? "PASS\n" : "FAIL\n", stdout)
            fflush(stdout)
            Darwin.exit(passed ? 0 : 1)
        }

        // Exit the app immediately if the device doesn't have a battery
        let batteryIOService = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard batteryIOService != 0 else {
            NSApplication.shared.terminate(nil)
            return
        }
        IOObjectRelease(batteryIOService)

        if !AidenteRuntime.isUIPreview && Defaults[.launchAtLogin]
            && !LaunchAtLoginService.shared.isEnabled
        {
            LaunchAtLoginService.shared.setLaunchAtLogin(true)
        }

        Task {
            ensureChargingHelperRegistration()
            await setupServices()
            if CommandLine.arguments.contains("--preview-window") {
                statusBarManager.showWindowForPreview()
            } else if CommandLine.arguments.contains("--dashboard-window") {
                statusBarManager.showDashboardWindow()
            } else if CommandLine.arguments.contains("--show-popover") {
                statusBarManager.showPopoverForPreview()
            }
            observePowerEvents()
            openSettingsFromCommandLineIfRequested()
            BatteryManagementSetup.shared.showWelcomeIfNeeded()
            if !AidenteRuntime.isUIPreview && Defaults[.popoverShowOnLaunch] { statusBarManager.showPopoverForPreview() }
            if AidenteRuntime.isUIPreview, let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--dump-preview-metrics=") }) {
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    let metrics = self.batteryService.metrics
                    let report: [String: Any] = ["preview": true, "controlEnabled": Defaults[.manageCharging],
                        "batteryPercentage": metrics.batteryPercentage, "hardwarePercentage": metrics.hardwareBatteryPercentage,
                        "hardwarePercentageAvailable": metrics.hasHardwarePercentage, "temperature": metrics.batteryTemperature,
                        "health": metrics.batteryHealth, "fullCapacity": metrics.estimatedFullChargeCapacityMilliampHours,
                        "designCapacity": metrics.designCapacityMilliampHours, "cycleCount": metrics.cycleCount,
                        "energySources": EnergyModeService.shared.readings.count]
                    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                        try? data.write(to: URL(fileURLWithPath: String(argument.dropFirst("--dump-preview-metrics=".count))), options: .atomic)
                    }
                }
            }
            updateService.presentPreviewAlertIfRequested()
        }
    }

    private func ensureChargingHelperRegistration() {
        guard !AidenteRuntime.isUIPreview else { return }
        guard Defaults[.manageCharging] else { return }
        do {
            try ChargingHelperManager.shared.ensureInstalled()
        } catch {
            // The settings page exposes the stored registration error and the
            // approval/repair actions. Read-only monitoring still starts.
        }
    }

    private func openSettingsFromCommandLineIfRequested() {
        guard let argument = CommandLine.arguments.first(where: {
            $0.hasPrefix("--settings-tab=")
        }) else {
            return
        }
        let value = String(argument.dropFirst("--settings-tab=".count))
        let tab = SettingsTab(urlValue: value) ?? .general
        settingsWindowController.showSettings(tab: tab)
    }

    private func setupServices() async {
        batteryService = BatteryService()
        await batteryService.loadCapabilities()
        chargeManager = ChargeManager(batteryService: batteryService)
        chargeManager.configureHelperDisconnectPolicy()
        chargeManager.checkControlService()
        batteryHistoryService = BatteryHistoryService(
            batteryService: batteryService
        )
        diagnosticCenter = DiagnosticCenter(
            batteryService: batteryService,
            chargeManager: chargeManager
        )
        updateService = UpdateService.shared
        viewModel = MenuViewModel(
            batteryService: batteryService,
            chargeManager: chargeManager,
            batteryHistoryService: batteryHistoryService
        )
        EnergyModeService.shared.configure { [weak self] mode, source in
            guard let self else { throw XPCError.helperUnavailable }
            try await self.batteryService.setEnergyMode(mode, source: source)
        }
        SystemCalibrationService.shared.onEvidenceChanged = { [weak self] in self?.chargeManager.recheckSystemCalibration() }
        SystemCalibrationService.shared.start()
        if AidenteRuntime.isUIPreview {
            // Remove only geometry keys written by the earlier preview build's
            // NSWindow autosave. New geometry uses the isolated preview suite.
            UserDefaults.standard.removeObject(forKey: "NSWindow Frame PreviewDashboard")
            UserDefaults.standard.removeObject(forKey: "NSWindow Frame PreviewSettings")
        }
        PowerMetadataService.shared.readSystemFullCharge = { [weak self] in
            guard let self else { return 0 }; return try await self.batteryService.readLastSystemFullCharge()
        }
        PowerMetadataService.shared.start()
        configureApplicationActions()
        BatteryManagementSetup.shared.onEnabled = { [weak self] in self?.chargeManager.retryControlAfterRepair() }
        if !AidenteRuntime.isUIPreview { AidenteAppShortcuts.updateAppShortcutParameters() }
        SleepBehaviorService.shared.startMonitoring()
        configureCompleteUninstaller()
        settingsWindowController = SettingsWindowController(
            viewModel: viewModel,
            capabilities: batteryService.deviceCapabilities,
            chargeManager: chargeManager,
            diagnosticCenter: diagnosticCenter,
            updateService: updateService
        )
        statusBarManager = StatusBarManager(
            viewModel: viewModel,
            settingsWindowController: settingsWindowController
        )
        if !AidenteRuntime.isUIPreview { updateService.start() }
    }

    private func configureApplicationActions() {
        ApplicationActions.shared.configure(handler: { [weak self] command, value in
            guard let self else { throw XPCError.helperUnavailable }
            if ["low-on", "low-off", "high-on", "high-off"].contains(command) {
                try await ApplicationActions.shared.energy(command == "low-on" ? .low : command == "high-on" ? .high : .automatic)
                return
            }
            if command == "sleep-prevent" {
                guard let value, (1...10080).contains(value) else { throw XPCError.commandFailed("Invalid sleep duration") }
                guard SleepBehaviorService.shared.prevent(minutes: value) else { throw XPCError.commandFailed(SleepBehaviorService.shared.error ?? "Unable to prevent sleep") }
                return
            }
            if command == "sleep-stop" { SleepBehaviorService.shared.stopManual(); return }
            if command == "led-policy" {
                try await ChargingHelperManager.shared.prepareForControl()
                let behavior = Defaults[.ledBehavior]
                try await self.batteryService.configureLED(enabled: Defaults[.manageMagSafeLED],
                    mode: behavior == .alwaysOff ? 1 : behavior == .offDuringSleep ? 2 : 0,
                    blink: Defaults[.blinkLEDWhileDischarging])
                return
            }
            if command == "led" {
                guard let value, let state = smc_power.MagSafeLEDState(rawValue: UInt8(clamping: value)), [1,3,4,6].contains(value) else { throw XPCError.commandFailed("Invalid LED state") }
                try await ChargingHelperManager.shared.prepareForControl()
                try await self.batteryService.configureLED(enabled: true, mode: 0, blink: false)
                try await self.batteryService.manageMagsafeLED(target: state); return
            }
            guard !SystemCalibrationService.shared.isActive else { throw XPCError.commandFailed(SystemCalibrationService.shared.status) }
            guard Defaults[.manageCharging] else { throw XPCError.commandFailed(AidenteL10n.t("请先在充电管理中启用控制服务。", "Enable charging management first.")) }
            try await ChargingHelperManager.shared.prepareForControl()
            switch command {
            case "set-limit":
                guard let value, (20...100).contains(value) else { throw XPCError.commandFailed("Charge limit must be 20–100") }
                Defaults[.chargeLimit] = value; self.chargeManager.resumeNormalManagement()
            case "pause":
                Defaults[.chargeLimit] = max(20, self.batteryService.metrics.batteryPercentage)
                self.chargeManager.pauseCharging()
            case "resume": self.chargeManager.resumeNormalManagement()
            case "top-up": self.chargeManager.startTopUp()
            case "discharge":
                guard self.batteryService.metrics.batteryPercentage > Defaults[.chargeLimit] else { throw XPCError.commandFailed("Battery is already at or below the discharge target") }
                self.chargeManager.startDischarge(to: Defaults[.chargeLimit])
            case "calibrate": self.chargeManager.startCalibration()
            case "stop-calibration": self.chargeManager.cancelCalibration()
            default: throw XPCError.commandFailed("Unknown command")
            }
            try await self.chargeManager.waitForControlRequest()
        }, query: { [weak self] name in
            guard let self else { return "" }
            switch name {
            case "percentage": return String(self.batteryService.metrics.batteryPercentage)
            case "limit": return String(self.viewModel.effectiveChargeLimit)
            case "temperature": return String(self.batteryService.metrics.batteryTemperature)
            case "state": return self.chargeManager.automationStateCode
            default: return ""
            }
        })
    }

    private func configureCompleteUninstaller() {
        CompleteUninstaller.shared.configure(
            prepare: { [weak self] in
                guard let self, !self.updateService.isBusy, !self.diagnosticCenter.isExporting else {
                    throw XPCError.commandFailed(AidenteL10n.t("请等待更新或诊断导出完成后再卸载。", "Wait for the update or diagnostic export to finish before uninstalling."))
                }
                await self.chargeManager.prepareForCompleteUninstall()
            },
            stopWriters: { [weak self] in
                guard let self else { return }
                SleepBehaviorService.shared.suspendForUninstall()
                SystemCalibrationService.shared.stop()
                PowerMetadataService.shared.stop()
                self.updateService.stop()
                self.diagnosticCenter.stop()
                await self.batteryHistoryService.prepareForUninstall()
                await DashboardTrendStore.shared.prepareForUninstall()
            },
            resume: { [weak self] serviceRemoved in
                guard let self else { return }
                self.chargeManager.resumeAfterUninstallFailure(serviceRemoved: serviceRemoved)
                if !serviceRemoved {
                    SleepBehaviorService.shared.resumeAfterUninstallFailure()
                    SystemCalibrationService.shared.start()
                    PowerMetadataService.shared.start()
                    self.batteryHistoryService.resumeAfterUninstallFailure()
                    DashboardTrendStore.shared.resumeAfterFailure()
                    if !AidenteRuntime.isUIPreview { self.updateService.start() }
                }
            }
        )
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }

    @objc private func handleSessionBecameActive(_ notification: Notification) {
        chargeManager.consoleSessionChanged(active: true)
    }
    @objc private func handleSessionResignedActive(_ notification: Notification) {
        chargeManager.consoleSessionChanged(active: false)
    }

    private func observePowerEvents() {
        NSWorkspace.shared.notificationCenter.addObserver(self,
            selector: #selector(handleSessionBecameActive(_:)),
            name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,
            selector: #selector(handleSessionResignedActive(_:)),
            name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleSystemWillSleep(_ notification: Notification) {
        chargeManager.prepareForSleep()
    }

    @objc private func handleSystemDidWake(_ notification: Notification) {
        EnergyModeService.shared.refresh()
        chargeManager.resumeFromSleep()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !CompleteUninstaller.shared.isRunning else { return }
        for url in urls where url.scheme == "aidente" {
            if url.host == "settings" {
                let tabValue = URLComponents(
                    url: url,
                    resolvingAgainstBaseURL: false
                )?.queryItems?.first(where: { $0.name == "tab" })?.value
                let tab = tabValue.flatMap(SettingsTab.init(urlValue:)) ?? .general
                settingsWindowController.showSettings(tab: tab)
            } else if url.host == "dashboard" {
                statusBarManager.showDashboardWindow()
            } else {
                chargeManager.handleAutomationURL(url)
            }
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard statusBarManager != nil, !CompleteUninstaller.shared.isRunning else { return false }
        statusBarManager.showDashboardWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        CompleteUninstaller.shared.isRunning ? .terminateCancel : .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !CompleteUninstaller.shared.hasRemovedService else { return }
        SleepBehaviorService.shared.stop()
        chargeManager.configureHelperDisconnectPolicy()
        diagnosticCenter.stop()
        updateService.stop()
        batteryHistoryService.stop()
        chargeManager.stop()
        batteryService.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
