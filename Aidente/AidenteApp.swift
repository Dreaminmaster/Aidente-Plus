import SwiftUI

@main
struct AidenteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }.commands {
            CommandGroup(replacing: .appSettings) {
                Button(AidenteL10n.t("设置…", "Settings…")) {
                    if let url = URL(string: "aidente://settings?tab=general") { NSWorkspace.shared.open(url) }
                }.keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
