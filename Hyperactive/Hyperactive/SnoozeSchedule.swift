import Foundation

/// One active stretch inside a single local day. `startMinute` is inclusive,
/// `endMinute` is exclusive, and both are minutes from local midnight.
/// `1440` is the start of the next day, so a window can end at midnight.
struct DailyWindow: Codable, Equatable, Identifiable {
    var id: UUID
    var startMinute: Int
    var endMinute: Int

    init(id: UUID = UUID(), startMinute: Int, endMinute: Int) {
        self.id = id
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    enum CodingKeys: String, CodingKey {
        case id
        case start
        case end
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        startMinute = try container.decode(Int.self, forKey: .start)
        endMinute = try container.decode(Int.self, forKey: .end)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startMinute, forKey: .start)
        try container.encode(endMinute, forKey: .end)
    }
}

enum Weekday: String, Codable, CaseIterable, Identifiable {
    case sunday
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }

    var isWeekend: Bool {
        self == .saturday || self == .sunday
    }

    static let displayedOrder: [Weekday] = [
        .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday,
    ]

    static let weekdays: [Weekday] = [
        .monday, .tuesday, .wednesday, .thursday, .friday,
    ]

    /// Gregorian `Calendar` weekday components are 1 for Sunday through 7 for Saturday.
    init(date: Date, calendar: Calendar) {
        switch calendar.component(.weekday, from: date) {
        case 1: self = .sunday
        case 2: self = .monday
        case 3: self = .tuesday
        case 4: self = .wednesday
        case 5: self = .thursday
        case 6: self = .friday
        default: self = .saturday
        }
    }
}

enum OutsideMode: String, Codable, Equatable {
    case off
    case screenOnly
}

enum Activity: Equatable {
    case nudge
    case display
    case idle
}

/// A manual Start or Stop while Snooze is on.
///
/// `forceNudge` lasts until the next window starts or the local day ends,
/// whichever comes first. The year, month, and day are the calendar day it
/// was requested on, so midnight, a wake, or a clock change drops it and the
/// next day's own windows take over.
/// `forceIdle` lasts only while the schedule still wants a nudge, which is
/// the end of the current window.
enum ManualOverride: Equatable {
    case forceNudge(year: Int, month: Int, day: Int)
    case forceIdle
}

struct SnoozeDecision: Equatable {
    var activity: Activity
    var override: ManualOverride?
    var nextChange: Date?
}

/// What Snooze should be doing at an instant. The stored schedule is one
/// window list per weekday. `weekdaysOnly` ignores Saturday and Sunday
/// without deleting the hours saved for them.
struct SnoozeSettings: Codable, Equatable {
    static let storageKey = "snoozeSettings"
    static let currentVersion = 1

    enum DecodeError: Error {
        case unsupportedVersion
    }

    var enabled: Bool
    var outsideMode: OutsideMode
    var weekdaysOnly: Bool
    var days: [Weekday: [DailyWindow]]

    static var disabled: SnoozeSettings {
        SnoozeSettings(
            enabled: false,
            outsideMode: .off,
            weekdaysOnly: false,
            days: emptyWeek()
        )
    }

    static func emptyWeek() -> [Weekday: [DailyWindow]] {
        Dictionary(uniqueKeysWithValues: Weekday.allCases.map { ($0, []) })
    }

    enum CodingKeys: String, CodingKey {
        case version
        case enabled
        case outsideMode
        case weekdaysOnly
        case days
    }

    init(enabled: Bool, outsideMode: OutsideMode, weekdaysOnly: Bool, days: [Weekday: [DailyWindow]]) {
        self.enabled = enabled
        self.outsideMode = outsideMode
        self.weekdaysOnly = weekdaysOnly
        self.days = days
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        guard version == Self.currentVersion else { throw DecodeError.unsupportedVersion }
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        outsideMode = try container.decodeIfPresent(OutsideMode.self, forKey: .outsideMode) ?? .off
        weekdaysOnly = try container.decodeIfPresent(Bool.self, forKey: .weekdaysOnly) ?? false
        let stored = try container.decodeIfPresent([String: [DailyWindow]].self, forKey: .days) ?? [:]
        var days = Self.emptyWeek()
        for day in Weekday.allCases {
            days[day] = Self.normalize(stored[day.rawValue] ?? [])
        }
        self.days = days
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(outsideMode, forKey: .outsideMode)
        try container.encode(weekdaysOnly, forKey: .weekdaysOnly)
        let canonical = normalized()
        var payload: [String: [DailyWindow]] = [:]
        for day in Weekday.allCases {
            payload[day.rawValue] = canonical.days[day] ?? []
        }
        try container.encode(payload, forKey: .days)
    }

    func normalized() -> SnoozeSettings {
        var copy = self
        for day in Weekday.allCases {
            copy.days[day] = Self.normalize(copy.days[day] ?? [])
        }
        return copy
    }

    /// Joins overlaps and windows that touch. Drops a window that is empty,
    /// backwards, or outside a single local day.
    static func normalize(_ windows: [DailyWindow]) -> [DailyWindow] {
        let valid = windows
            .filter { window in
                window.startMinute >= 0
                    && window.endMinute <= 1_440
                    && window.endMinute > window.startMinute
            }
            .sorted { lhs, rhs in
                if lhs.startMinute != rhs.startMinute {
                    return lhs.startMinute < rhs.startMinute
                }
                return lhs.endMinute < rhs.endMinute
            }
        var merged: [DailyWindow] = []
        for window in valid {
            guard let last = merged.last, window.startMinute <= last.endMinute else {
                merged.append(window)
                continue
            }
            merged[merged.count - 1] = DailyWindow(
                id: last.id,
                startMinute: last.startMinute,
                endMinute: max(last.endMinute, window.endMinute)
            )
        }
        return merged
    }

    func effectiveWindows(on weekday: Weekday) -> [DailyWindow] {
        if weekdaysOnly && weekday.isWeekend {
            return []
        }
        return Self.normalize(days[weekday] ?? [])
    }

    var hasEffectiveWindow: Bool {
        Weekday.allCases.contains { !effectiveWindows(on: $0).isEmpty }
    }

    var hasInvalidWindow: Bool {
        days.values.contains { windows in
            windows.contains { window in
                window.endMinute <= window.startMinute
                    || window.startMinute < 0
                    || window.endMinute > 1_440
            }
        }
    }

    func copying(day source: Weekday, to targets: [Weekday]) -> SnoozeSettings {
        var copy = self
        let sourceWindows = days[source] ?? []
        for target in targets {
            copy.days[target] = sourceWindows.map {
                DailyWindow(startMinute: $0.startMinute, endMinute: $0.endMinute)
            }
        }
        return copy
    }

    func settingWeekdays(startMinute: Int, endMinute: Int) -> SnoozeSettings {
        var copy = self
        for day in Weekday.weekdays {
            copy.days[day] = [DailyWindow(startMinute: startMinute, endMinute: endMinute)]
        }
        return copy
    }

    /// The first time Snooze is turned on with a blank week, offer 9:00–17:00
    /// on weekdays. A week that already has any hours is left alone.
    func seededForFirstEnable() -> SnoozeSettings {
        let hasAnyHours = days.values.contains { !$0.isEmpty }
        if hasAnyHours {
            return self
        }
        return settingWeekdays(startMinute: 9 * 60, endMinute: 17 * 60)
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(normalized()) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    static func load(from defaults: UserDefaults = .standard) -> SnoozeSettings {
        guard let data = defaults.data(forKey: storageKey) else { return .disabled }
        do {
            return try JSONDecoder().decode(SnoozeSettings.self, from: data)
        } catch {
            return .disabled
        }
    }
}

enum SnoozeSchedule {
    static let boundaryHop: TimeInterval = 15 * 60

    static func decide(
        now: Date,
        calendar: Calendar,
        settings: SnoozeSettings,
        override: ManualOverride?
    ) -> SnoozeDecision {
        let schedule = scheduleActivity(at: now, calendar: calendar, settings: settings)
        var override = override

        if case let .forceNudge(year, month, day) = override {
            let parts = calendar.dateComponents([.year, .month, .day], from: now)
            let sameDay = parts.year == year && parts.month == month && parts.day == day
            if sameDay && schedule != .nudge {
                let midnight = nextMidnight(after: now, calendar: calendar)
                let upcoming = nextWindowStart(after: now, calendar: calendar, settings: settings)
                let change = (upcoming != nil && upcoming! < midnight) ? upcoming! : midnight
                return SnoozeDecision(activity: .nudge, override: override, nextChange: change)
            }
            override = nil
        }

        if case .forceIdle = override {
            if schedule == .nudge {
                let end = activeWindowEnd(after: now, calendar: calendar, settings: settings)
                    ?? nextMidnight(after: now, calendar: calendar)
                return SnoozeDecision(activity: .idle, override: .forceIdle, nextChange: end)
            }
            override = nil
        }

        return SnoozeDecision(
            activity: schedule,
            override: nil,
            nextChange: nextScheduleChange(after: now, calendar: calendar, settings: settings)
        )
    }

    static func timerFireDate(now: Date, nextChange: Date?) -> Date? {
        guard let nextChange, nextChange > now else { return nil }
        return min(nextChange, now.addingTimeInterval(boundaryHop))
    }

    static func symbol(
        nudging: Bool,
        snoozeEnabled: Bool,
        showingDisplay: Bool,
        paused: Bool,
        blocked: Bool
    ) -> String {
        if nudging {
            return "cursorarrow.motionlines"
        }
        if !snoozeEnabled || paused || blocked {
            return "cursorarrow"
        }
        if showingDisplay {
            return "display"
        }
        return "moon.zzz"
    }

    static func statusLine(
        now: Date,
        calendar: Calendar,
        decision: SnoozeDecision,
        nudgeCount: Int,
        lastNudge: Date?,
        accessibilityBlocked: Bool,
        locale: Locale
    ) -> String {
        if accessibilityBlocked {
            return "Nudging is blocked — Accessibility not granted"
        }
        switch decision.activity {
        case .nudge:
            let until = decision.nextChange.map {
                changePhrase(now: now, change: $0, calendar: calendar, locale: locale)
            }
            let leading = until.map { "Nudging until \($0)" } ?? "Nudging"
            return leading + nudgeSuffix(count: nudgeCount, last: lastNudge, calendar: calendar, locale: locale)
        case .idle:
            if case .forceIdle = decision.override {
                guard let change = decision.nextChange else { return "Paused" }
                let phrase = changePhrase(now: now, change: change, calendar: calendar, locale: locale)
                return "Paused until \(phrase)"
            }
            guard let change = decision.nextChange else { return "Snoozed all week" }
            let phrase = changePhrase(now: now, change: change, calendar: calendar, locale: locale)
            return "Snoozed until \(phrase)"
        case .display:
            guard let change = decision.nextChange else { return "Screen only all week" }
            let phrase = changePhrase(now: now, change: change, calendar: calendar, locale: locale)
            return "Screen only until \(phrase)"
        }
    }

    private static func scheduleActivity(
        at now: Date,
        calendar: Calendar,
        settings: SnoozeSettings
    ) -> Activity {
        let weekday = Weekday(date: now, calendar: calendar)
        let minuteNow = minute(of: now, calendar: calendar)
        let inside = settings.effectiveWindows(on: weekday).contains { window in
            minuteNow >= window.startMinute && minuteNow < window.endMinute
        }
        if inside {
            return .nudge
        }
        return settings.outsideMode == .screenOnly ? .display : .idle
    }

    private static func nextScheduleChange(
        after now: Date,
        calendar: Calendar,
        settings: SnoozeSettings
    ) -> Date? {
        let today = calendar.startOfDay(for: now)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let weekday = Weekday(date: day, calendar: calendar)
            let windows = settings.effectiveWindows(on: weekday)
            let minuteNow = offset == 0 ? minute(of: now, calendar: calendar) : Int.min
            if offset == 0,
               let active = windows.first(where: { minuteNow >= $0.startMinute && minuteNow < $0.endMinute }),
               let end = date(on: day, minute: active.endMinute, calendar: calendar),
               end > now {
                return end
            }
            for window in windows {
                if offset == 0 && window.startMinute <= minuteNow {
                    continue
                }
                if let start = date(on: day, minute: window.startMinute, calendar: calendar), start > now {
                    return start
                }
            }
        }
        return nil
    }

    private static func nextWindowStart(
        after now: Date,
        calendar: Calendar,
        settings: SnoozeSettings
    ) -> Date? {
        let today = calendar.startOfDay(for: now)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let weekday = Weekday(date: day, calendar: calendar)
            let minuteNow = offset == 0 ? minute(of: now, calendar: calendar) : Int.min
            for window in settings.effectiveWindows(on: weekday) {
                if offset == 0 && window.startMinute <= minuteNow {
                    continue
                }
                if let start = date(on: day, minute: window.startMinute, calendar: calendar), start > now {
                    return start
                }
            }
        }
        return nil
    }

    private static func activeWindowEnd(
        after now: Date,
        calendar: Calendar,
        settings: SnoozeSettings
    ) -> Date? {
        let day = calendar.startOfDay(for: now)
        let weekday = Weekday(date: now, calendar: calendar)
        let minuteNow = minute(of: now, calendar: calendar)
        guard let active = settings.effectiveWindows(on: weekday).first(where: {
            minuteNow >= $0.startMinute && minuteNow < $0.endMinute
        }) else {
            return nil
        }
        guard let end = date(on: day, minute: active.endMinute, calendar: calendar), end > now else {
            return nil
        }
        return end
    }

    private static func nextMidnight(after now: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(24 * 60 * 60)
    }

    private static func minute(of date: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    /// Local time on `day` at `minute`, or the next midnight when `minute` is 1440.
    /// Returns nil when that clock time does not exist, which is the skipped DST hour.
    private static func date(on day: Date, minute: Int, calendar: Calendar) -> Date? {
        let start = calendar.startOfDay(for: day)
        if minute >= 1_440 {
            return calendar.date(byAdding: .day, value: 1, to: start)
        }
        guard minute >= 0 else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: start)
        components.hour = minute / 60
        components.minute = minute % 60
        components.second = 0
        components.timeZone = calendar.timeZone
        guard let resolved = calendar.date(from: components) else { return nil }
        let resolvedMinute = self.minute(of: resolved, calendar: calendar)
        guard resolvedMinute == minute else { return nil }
        return resolved
    }

    private static func changePhrase(now: Date, change: Date, calendar: Calendar, locale: Locale) -> String {
        let midnight = nextMidnight(after: now, calendar: calendar)
        if abs(change.timeIntervalSince(midnight)) < 1 {
            return "midnight"
        }
        let time = timeString(change, calendar: calendar, locale: locale)
        let startNow = calendar.startOfDay(for: now)
        let startChange = calendar.startOfDay(for: change)
        let dayDelta = calendar.dateComponents([.day], from: startNow, to: startChange).day ?? 0
        if dayDelta <= 0 {
            return time
        }
        if dayDelta == 1 {
            return "tomorrow \(time)"
        }
        let weekday = weekdayString(change, calendar: calendar, locale: locale)
        return "\(weekday) \(time)"
    }

    private static func nudgeSuffix(
        count: Int,
        last: Date?,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let noun = count == 1 ? "nudge" : "nudges"
        var text = " — \(count) \(noun)"
        if let last {
            text += " (last: \(timeString(last, calendar: calendar, locale: locale)))"
        }
        return text
    }

    private static func timeString(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func weekdayString(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}
