import Foundation

struct UsageDateContext: Sendable {
  let now: Date
  let timeZone: TimeZone
  let calendar: Calendar
  let todayKey: String
  let usageWindowStartKey: String
  let startOfToday: Date
  let startOfNextDay: Date
  let includesYear: Bool
  let yearStart: Date
  let yearEnd: Date

  init(now: Date = Date(), timeZone: TimeZone = .autoupdatingCurrent, includesYear: Bool = false) {
    let capturedTimeZone = TimeZone(identifier: timeZone.identifier) ?? timeZone
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = capturedTimeZone
    let startOfToday = calendar.startOfDay(for: now)
    guard
      let startOfNextDay = calendar.date(
        byAdding: .day,
        value: 1, to: startOfToday),
      let recentWindowStart = calendar.date(
        byAdding: .day,
        value: -29, to: startOfToday),
      let month = calendar.dateInterval(of: .month, for: now),
      let yearStart = calendar.date(byAdding: .month, value: -11, to: month.start)
    else {
      preconditionFailure("Unable to calculate usage date bounds")
    }

    self.now = now
    self.timeZone = capturedTimeZone
    self.calendar = calendar
    self.todayKey = DateHelper.dateKey(for: now, in: capturedTimeZone)
    self.usageWindowStartKey = DateHelper.dateKey(
      for: includesYear ? yearStart : recentWindowStart, in: capturedTimeZone)
    self.startOfToday = startOfToday
    self.startOfNextDay = startOfNextDay
    self.includesYear = includesYear
    self.yearStart = yearStart
    self.yearEnd = month.end
  }
}

enum DateHelper {
  private static let dateFormatters: NSCache<NSString, DateFormatter> = {
    let cache = NSCache<NSString, DateFormatter>()
    cache.countLimit = 32
    return cache
  }()

  static func dateKey(for date: Date) -> String {
    dateKey(for: date, in: .autoupdatingCurrent)
  }

  static func dateKey(for date: Date, in timeZone: TimeZone) -> String {
    makeDateFormatter(format: "yyyy-MM-dd", timeZone: timeZone).string(from: date)
  }

  static func date(fromKey key: String) -> Date? {
    date(fromKey: key, in: .autoupdatingCurrent)
  }

  static func date(fromKey key: String, in timeZone: TimeZone) -> Date? {
    makeDateFormatter(format: "yyyy-MM-dd", timeZone: timeZone).date(from: key)
  }

  static func normalizedDateKey(from raw: String) -> String? {
    normalizedDateKey(from: raw, in: .autoupdatingCurrent)
  }

  static func normalizedDateKey(from raw: String, in timeZone: TimeZone) -> String? {
    let canonicalFormatter = makeDateFormatter(
      format: "yyyy-MM-dd",
      timeZone: timeZone)
    if let date = canonicalFormatter.date(from: raw) {
      return canonicalFormatter.string(from: date)
    }

    let formats = [
      "MMM d, yyyy",
      "MMMM d, yyyy",
      "d MMM yyyy",
      "d MMMM yyyy",
      "yyyy/MM/dd",
      "yyyy.MM.dd",
    ]
    for format in formats {
      let formatter = makeDateFormatter(format: format, timeZone: timeZone)
      if let date = formatter.date(from: raw) {
        return canonicalFormatter.string(from: date)
      }
    }

    return nil
  }

  static func startOfToday() -> Date {
    Calendar.autoupdatingCurrent.startOfDay(for: Date())
  }

  static func dateKeyDaysAgo(_ days: Int) -> String {
    let calendar = Calendar.autoupdatingCurrent
    let base = calendar.startOfDay(for: Date())
    let target = calendar.date(byAdding: .day, value: -days, to: base) ?? base
    return dateKey(for: target)
  }

  private static func makeDateFormatter(
    format: String,
    timeZone: TimeZone
  ) -> DateFormatter {
    let identifier = timeZone.identifier
    let key = "\(identifier)|\(format)" as NSString
    if let formatter = dateFormatters.object(forKey: key) {
      return formatter
    }

    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    // Cached formatters must keep their timezone when the system timezone changes.
    formatter.timeZone = TimeZone(identifier: identifier) ?? timeZone
    formatter.dateFormat = format
    formatter.isLenient = false
    dateFormatters.setObject(formatter, forKey: key)
    return formatter
  }
}
