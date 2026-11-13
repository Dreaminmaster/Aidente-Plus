import Foundation

public enum ManagementPreferenceMigration {
    public static func apply(to defaults:UserDefaults,domain:String) {
        let marker="didMigrateManagementDefaultsV2"
        guard !defaults.bool(forKey:marker) else { return }
        let stored=defaults.persistentDomain(forName:domain) ?? [:]
        let existing=["manageCharging","chargeLimit","menuBarIconStyle"].contains { stored[$0] != nil }
        // Preserve the previous implicit defaults for existing installations, not new profiles.
        if existing {
            for key in ["stopChargingWhileSleeping","manageMagSafeLED"] where stored[key] == nil { defaults.set(true,forKey:key) }
        }
        defaults.set(true,forKey:marker)
    }
}
