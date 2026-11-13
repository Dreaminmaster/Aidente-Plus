import Foundation
import Darwin

/// /dev/console tracks the signed-in foreground account even while locked.
/// A missing owner fails closed; background accounts must not fight the active one.
public enum ConsoleSessionPolicy {
    public static var consoleUID: UInt32? {
        var info = stat()
        guard lstat("/dev/console", &info) == 0 else { return nil }
        return info.st_uid
    }
    public static func mayControl(caller: UInt32, console: UInt32?) -> Bool {
        caller == 0 || (console != nil && caller == console)
    }
    public static var currentUserIsActive: Bool {
        mayControl(caller: getuid(), console: consoleUID)
    }
}
