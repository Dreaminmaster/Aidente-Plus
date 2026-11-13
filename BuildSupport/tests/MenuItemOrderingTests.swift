import AidenteShared
@main struct MenuItemOrderingTests {
    static func main() {
        let main = MenuItemOrdering.main
        precondition(MenuItemOrdering.layout(metrics: ["temperature"], mainPosition: 0, includeMain: true) == [main, "temperature"])
        precondition(MenuItemOrdering.layout(metrics: ["temperature"], mainPosition: 1, includeMain: true) == ["temperature", main])
        precondition(MenuItemOrdering.layout(metrics: ["temperature","cycleCount"], mainPosition: 1, includeMain: true) == ["temperature",main,"cycleCount"])
        precondition(MenuItemOrdering.moving(main, onto: "temperature", in: [main,"temperature"]) == ["temperature",main])
        precondition(MenuItemOrdering.moving("temperature", onto: main, in: [main,"temperature"]) == ["temperature",main])
        precondition(MenuItemOrdering.moving(main, onto: "cycleCount", in: [main,"temperature","cycleCount"]) == ["temperature","cycleCount",main])
        precondition(MenuItemOrdering.layout(metrics: ["temperature","temperature",main], mainPosition: 50, includeMain: true) == ["temperature",main])
        precondition(MenuItemOrdering.layout(metrics: ["temperature"], mainPosition: 1, includeMain: false) == ["temperature"])
        precondition(MenuItemOrdering.moving("absent", onto: main, in: [main,"temperature"]) == [main,"temperature"])
        precondition(MenuItemOrdering.layout(metrics: [], mainPosition: -4, includeMain: true) == [main])
        print("PASS: 10 unified main-icon and metric ordering checks")
    }
}
