import Foundation

@main struct ManagementSetupTests {
    static func main() {
        var count=0
        func check(_ v:Bool,_ name:String) { precondition(v,name);count += 1 }
        for kind in [0,1,2] {
            let name="com.aidente.test.setup.\(UUID().uuidString)"
            let isolated=UserDefaults(suiteName:name)!
            defer { isolated.removePersistentDomain(forName:name) }
            if kind>0 { isolated.set(true,forKey:"manageCharging") }
            if kind==2 { isolated.set(false,forKey:"stopChargingWhileSleeping");isolated.set(false,forKey:"manageMagSafeLED") }
            ManagementPreferenceMigration.apply(to:isolated,domain:name)
            if kind==0 { check(isolated.object(forKey:"stopChargingWhileSleeping")==nil,"Fresh profile keeps new default");check(isolated.object(forKey:"manageMagSafeLED")==nil,"Fresh LED remains disabled") }
            if kind==1 { check(isolated.bool(forKey:"stopChargingWhileSleeping"),"Existing implicit sleep policy preserved");check(isolated.bool(forKey:"manageMagSafeLED"),"Existing implicit LED policy preserved") }
            if kind==2 { check(!isolated.bool(forKey:"stopChargingWhileSleeping"),"Explicit sleep choice preserved");check(!isolated.bool(forKey:"manageMagSafeLED"),"Explicit LED choice preserved") }
            isolated.set(false,forKey:"stopChargingWhileSleeping")
            ManagementPreferenceMigration.apply(to:isolated,domain:name)
            check(!isolated.bool(forKey:"stopChargingWhileSleeping"),"Migration never overwrites later choice")
        }
        check(!PowerConnectionSnapshot.resolve(externalConnected:false,providingAC:true,charging:true).connected,"Registry disconnect beats stale AC snapshot")
        check(!PowerConnectionSnapshot(connected:false,charging:true).charging,"Disconnected cannot show charging")
        check(PowerConnectionSnapshot.resolve(externalConnected:nil,providingAC:true,charging:false).connected,"AC fallback without registry property")
        print("PASS: \(count) setup migration and fast power-state checks")
    }
}
