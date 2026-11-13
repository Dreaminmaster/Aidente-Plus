import Foundation

public enum AppListOrder {
    /// Activity readings never participate in ordering.
    public static func orderedIDs(names: [String: String]) -> [String] {
        names.keys.sorted {
            let order = names[$0]!.localizedStandardCompare(names[$1]!)
            return order == .orderedSame ? $0 < $1 : order == .orderedAscending
        }
    }
    /// Hold the click targets while a list is hovered or a quit dialog is open.
    public static func presentationIDs(current: [String], incoming: [String], interacting: Bool) -> [String] {
        interacting && !current.isEmpty ? current : incoming
    }
}
