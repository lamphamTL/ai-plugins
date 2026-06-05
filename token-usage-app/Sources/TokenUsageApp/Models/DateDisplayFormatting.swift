import Foundation

enum DateDisplayFormatting {
    static func monthDay(_ date: Date, calendar: Calendar, timeZone: TimeZone) -> String {
        string(from: date, template: "MMM d", calendar: calendar, timeZone: timeZone)
    }

    static func monthYear(_ date: Date, calendar: Calendar, timeZone: TimeZone) -> String {
        string(from: date, template: "MMM y", calendar: calendar, timeZone: timeZone)
    }

    static func month(_ date: Date, calendar: Calendar, timeZone: TimeZone) -> String {
        string(from: date, template: "MMM", calendar: calendar, timeZone: timeZone)
    }

    static func weekday(_ date: Date, calendar: Calendar, timeZone: TimeZone) -> String {
        string(from: date, template: "EEE", calendar: calendar, timeZone: timeZone)
    }

    static func day(_ date: Date, calendar: Calendar, timeZone: TimeZone) -> String {
        string(from: date, template: "d", calendar: calendar, timeZone: timeZone)
    }

    static func monthDayTime(_ date: Date, calendar: Calendar, timeZone: TimeZone) -> String {
        string(from: date, template: "MMM d, j:mm", calendar: calendar, timeZone: timeZone)
    }

    private static func string(from date: Date, template: String, calendar: Calendar, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
