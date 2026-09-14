import Foundation

/// 3.0 rhythm: quiet nights and screen-lock silence. Pure and testable.
enum Rhythm {
    static let quietKey = "critter.quiet"
    static let onboardKey = "critter.onboarded"
    static let startHour = 23
    static let endHour = 7

    /// 23:00–07:00 local time. Overnight wrap handled by the OR.
    static func isQuiet(date: Date = .now) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= startHour || hour < endHour
    }

    static func date(hour: Int) -> Date {
        var parts = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        parts.hour = hour
        parts.minute = 0
        return Calendar.current.date(from: parts) ?? .now
    }
}
