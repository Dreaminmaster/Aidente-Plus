import Foundation

public enum GaugingMetadata {
    public static func lastFullCharge(in dictionary: [String: Any], now: Date) -> Date? {
        for key in ["lastFullChargeDate", "lastFullCharge"] {
            guard let value = dictionary[key] else { continue }
            let candidates: [Date]
            if let date = value as? Date { candidates = [date] }
            else if let value = value as? NSNumber, value.doubleValue > 0, value.doubleValue.isFinite {
                candidates = [Date(timeIntervalSince1970: value.doubleValue), Date(timeIntervalSinceReferenceDate: value.doubleValue)]
            } else { continue }
            // Accommodate the two numeric epochs without inventing a timestamp
            // from missing, zero, malformed or future metadata.
            if let date = candidates.first(where: { $0.timeIntervalSince1970 > 978307200 && $0 <= now.addingTimeInterval(300) }) { return date }
        }
        return nil
    }
}
