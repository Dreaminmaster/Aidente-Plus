import Foundation

public enum ScheduleRecurrence {
    public static func next(after now: Date, previous: Date, rule: String, weekdays: [Int],
                            anchorDay: Int?, anchorMonth: Int?, calendar: Calendar) -> Date? {
        let time = calendar.dateComponents([.hour, .minute, .second], from: previous)
        let startDay = anchorDay ?? calendar.component(.day, from: previous)
        let startMonth = anchorMonth ?? calendar.component(.month, from: previous)
        switch rule {
        case "never": return nil
        case "daily", "weekdays", "weekly", "biweekly":
            let selected: Set<Int>
            if rule == "weekdays" { selected = [2,3,4,5,6] }
            else if rule == "weekly" || rule == "biweekly" {
                let valid = weekdays.filter { (1...7).contains($0) }
                selected = Set(valid.isEmpty ? [calendar.component(.weekday, from: previous)] : valid)
            } else { selected = Set(1...7) }
            let originalWeek = calendar.dateInterval(of: .weekOfYear, for: previous)!.start
            var date = calendar.startOfDay(for: now)
            for _ in 0..<22 {
                defer { date = calendar.date(byAdding: .day, value: 1, to: date)! }
                guard selected.contains(calendar.component(.weekday, from: date)) else { continue }
                if rule == "biweekly" {
                    let week = calendar.dateInterval(of: .weekOfYear, for: date)!.start
                    let count = calendar.dateComponents([.weekOfYear], from: originalWeek, to: week).weekOfYear ?? 0
                    if count % 2 != 0 { continue }
                }
                if let candidate = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                                                 second: time.second ?? 0, of: date,
                                                 matchingPolicy: .nextTimePreservingSmallerComponents,
                                                 repeatedTimePolicy: .first, direction: .forward), candidate > now {
                    return candidate
                }
            }
            return nil
        case "monthly", "yearly":
            var month = calendar.dateComponents([.year, .month], from: now)
            if rule == "yearly" { month.month = startMonth }
            for _ in 0..<3 {
                guard let first = calendar.date(from: month), let days = calendar.range(of: .day, in: .month, for: first) else { return nil }
                var components = month
                components.day = min(max(1, startDay), days.count)
                let day = calendar.date(from: components)!
                let candidate = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                    second: time.second ?? 0, of: day, matchingPolicy: .nextTimePreservingSmallerComponents,
                    repeatedTimePolicy: .first, direction: .forward)!
                if candidate > now { return candidate }
                if rule == "yearly" { month.year = (month.year ?? 0) + 1 }
                else { month = calendar.dateComponents([.year, .month], from: calendar.date(byAdding: .month, value: 1, to: first)!) }
            }
            return nil
        default: return nil
        }
    }
}
