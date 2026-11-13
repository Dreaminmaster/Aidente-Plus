import Foundation

@main struct SignedUpdateVerifierTests {
    static func main() throws {
        let current=URL(fileURLWithPath:"/Applications/Aidente.app")
        try SignedUpdateVerifier.verify(candidate:CommandLine.arguments.count>1 ? URL(fileURLWithPath:CommandLine.arguments[1]):current,installed:current)
        var passed=1
        for candidate in [URL(fileURLWithPath:"/System/Applications/Calculator.app"),URL(fileURLWithPath:"/missing/Aidente.app"),URL(fileURLWithPath:"Build/UntrustedUpdateFixture.app")] {
            do { try SignedUpdateVerifier.verify(candidate:candidate,installed:current);fatalError("Untrusted candidate accepted") }
            catch { passed += 1 }
        }
        print("PASS: \(passed) update signer continuity checks")
    }
}
