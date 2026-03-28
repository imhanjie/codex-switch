import Foundation

public enum UsageDisplayFormatter {
    public static func percentText(for window: UsageWindow?) -> String {
        guard let window else { return "-" }
        return "\(window.remainingPercent)%"
    }

    public static func resetText(for window: UsageWindow?, weekly: Bool) -> String {
        guard let date = window?.resetAt else {
            return "-"
        }

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_CN")
        timeFormatter.dateFormat = "HH:mm"
        let time = timeFormatter.string(from: date)

        guard weekly else {
            return "\(time) 重置"
        }

        let weekday = Calendar.current.component(.weekday, from: date)
        let weekdayLabel = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][max(0, min(weekday - 1, 6))]
        return "\(weekdayLabel) - \(time) 重置"
    }
}
