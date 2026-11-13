import Foundation

/// Connection truth never comes from cached adapter specifications or old wattage.
public struct PowerConnectionSnapshot:Equatable,Sendable {
    public let connected,charging:Bool
    public init(connected:Bool,charging:Bool) { self.connected=connected;self.charging=connected && charging }
    public static func resolve(externalConnected:Bool?,providingAC:Bool,charging:Bool)->Self {
        .init(connected:externalConnected ?? providingAC,charging:charging)
    }
}
