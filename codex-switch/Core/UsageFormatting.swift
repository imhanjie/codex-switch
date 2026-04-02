import Foundation

public enum UsageDisplayFormatter {
    public static func percentText(for window: UsageWindow?) -> String {
        guard let window else { return "-" }
        return "\(window.remainingPercent)%"
    }

    public static func lastRefreshText(
        for date: Date?,
        relativeTo referenceDate: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "zh_CN")
    ) -> String {
        guard let date else { return "上次刷新 · -" }
        return "上次刷新 · \(relativeDateTimeText(for: date, relativeTo: referenceDate, calendar: calendar, locale: locale))"
    }

    public static func relativeDateTimeText(
        for date: Date,
        relativeTo referenceDate: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "zh_CN")
    ) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.calendar = calendar
        timeFormatter.dateFormat = "HH:mm"
        let time = timeFormatter.string(from: date)

        if calendar.isDate(date, inSameDayAs: referenceDate) {
            return time
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 \(time)"
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "明天 \(time)"
        }

        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.locale = locale
        dateTimeFormatter.calendar = calendar
        dateTimeFormatter.dateFormat = "MM月dd日 HH:mm"
        return dateTimeFormatter.string(from: date)
    }

    public static func resetText(for window: UsageWindow?, weekly _: Bool) -> String {
        guard let date = window?.resetAt else {
            return "-"
        }
        return "\(relativeDateTimeText(for: date)) 重置"
    }
}
