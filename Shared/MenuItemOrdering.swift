import Foundation

/// Main icon and readouts share a single order; hidden items do not destroy it.
public enum MenuItemOrdering {
    public static let main = "__mainIcon"
    public static func layout(metrics: [String], mainPosition: Int, includeMain: Bool) -> [String] {
        var seen = Set<String>()
        var items = metrics.filter { $0 != main && seen.insert($0).inserted }
        if includeMain { items.insert(main, at: min(items.count, max(0, mainPosition))) }
        return items
    }
    public static func moving(_ item: String, onto target: String, in items: [String]) -> [String] {
        guard item != target, let from = items.firstIndex(of: item), let to = items.firstIndex(of: target) else { return items }
        var result = items; result.remove(at: from); result.insert(item, at: to)
        return result
    }
}
