import Foundation

/// Live API contract check. It never sends an accepted write or changes power.
@main struct NativeChargeLimitReadOnlyTests {
    static func main() throws {
        let client = try NativeChargeLimit()
        let limits = try client.availableLimits()
        precondition(!limits.isEmpty && limits.allSatisfy { (80...100).contains($0) })
        let original = try client.read()
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NativeChargeLimit.State.self, from: encoded)
        precondition(decoded == original)
        for invalid in [-1, 0, 79, 101, 256] {
            do { try client.set(invalid); fatalError("Unsupported limit was accepted") }
            catch { /* Invalid input must be rejected before sending a write. */ }
            let after = try client.read()
            precondition(after == original)
        }
        print("7 native read-only checks passed; limits=\(limits), state=\(original)")
    }
}
