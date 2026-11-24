import XCTest

final class SnoozeScheduleTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US")
    }

    // MARK: - Per-day windows

    func testEachWeekdayKeepsItsOwnWindows() {
        let settings = makeSettings([
            .monday: [(8 * 60 + 30, 18 * 60 + 30)],
            .friday: [(8 * 60, 14 * 60)],
        ])

        XCTAssertEqual(hours(settings, .monday), spans([(8 * 60 + 30, 18 * 60 + 30)]))
        XCTAssertEqual(hours(settings, .friday), spans([(8 * 60, 14 * 60)]))
        XCTAssertEqual(hours(settings, .thursday), spans([]))
        XCTAssertTrue(settings.hasEffectiveWindow)

        let monday = decide(settings, at: date(2026, 3, 9, 9, 0))
        XCTAssertEqual(monday.activity, .nudge)
        XCTAssertEqual(monday.nextChange, date(2026, 3, 9, 18, 30))

        let friday = decide(settings, at: date(2026, 3, 6, 9, 0))
        XCTAssertEqual(friday.activity, .nudge)
        XCTAssertEqual(friday.nextChange, date(2026, 3, 6, 14, 0))

        let fridayAfter = decide(settings, at: date(2026, 3, 6, 15, 0))
        XCTAssertEqual(fridayAfter.activity, .idle)
        XCTAssertEqual(fridayAfter.nextChange, date(2026, 3, 9, 8, 30))
        XCTAssertEqual(
            normalize(status(settings, fridayAfter, at: date(2026, 3, 6, 15, 0))),
            "Snoozed until Monday 8:30 AM"
        )
    }

    func testEmptyDayIsOutsideUntilALaterDayStarts() {
        let settings = makeSettings([
            .tuesday: [(8 * 60 + 30, 18 * 60 + 30)],
            .wednesday: [],
            .thursday: [(8 * 60 + 30, 18 * 60 + 30)],
        ])
        let evening = date(2026, 3, 10, 19, 0)
        let decision = decide(settings, at: evening)
        XCTAssertEqual(decision.activity, .idle)
        XCTAssertEqual(decision.nextChange, date(2026, 3, 12, 8, 30))
        XCTAssertEqual(
            normalize(status(settings, decision, at: evening)),
            "Snoozed until Thursday 8:30 AM"
        )
    }

    func testWindowStartIsInclusiveAndEndIsExclusive() {
        let settings = makeSettings([.friday: [(8 * 60 + 30, 14 * 60)]])
        XCTAssertEqual(decide(settings, at: date(2026, 3, 6, 8, 30)).activity, .nudge)
        XCTAssertEqual(decide(settings, at: date(2026, 3, 6, 13, 59)).activity, .nudge)
        XCTAssertEqual(decide(settings, at: date(2026, 3, 6, 14, 0)).activity, .idle)
        XCTAssertEqual(
            decide(settings, at: date(2026, 3, 6, 13, 59)).nextChange,
            date(2026, 3, 6, 14, 0)
        )
    }

    func testInsideAWindowTheNextChangeIsThatWindowsEnd() {
        let settings = makeSettings([
            .friday: [(8 * 60, 10 * 60), (13 * 60, 14 * 60)],
        ])
        let morning = decide(settings, at: date(2026, 3, 6, 9, 0))
        XCTAssertEqual(morning.nextChange, date(2026, 3, 6, 10, 0))
        let gap = decide(settings, at: date(2026, 3, 6, 10, 0))
        XCTAssertEqual(gap.activity, .idle)
        XCTAssertEqual(gap.nextChange, date(2026, 3, 6, 13, 0))
    }

    func testOnlyMondayLooksAFullWeekAhead() {
        let settings = makeSettings([.monday: [(8 * 60 + 30, 18 * 60 + 30)]])
        let after = decide(settings, at: date(2026, 3, 9, 19, 0))
        XCTAssertEqual(after.activity, .idle)
        XCTAssertEqual(after.nextChange, date(2026, 3, 16, 8, 30))
        XCTAssertEqual(Weekday(date: after.nextChange!, calendar: calendar), .monday)
    }

    func testNoWindowsLeavesTheOutsideModeWithNoBoundary() {
        let off = makeSettings([:])
        let offDecision = decide(off, at: date(2026, 3, 6, 12, 0))
        XCTAssertEqual(offDecision.activity, .idle)
        XCTAssertNil(offDecision.nextChange)
        XCTAssertEqual(normalize(status(off, offDecision, at: date(2026, 3, 6, 12, 0))), "Snoozed all week")

        let screen = makeSettings([:], outside: .screenOnly)
        let screenDecision = decide(screen, at: date(2026, 3, 6, 12, 0))
        XCTAssertEqual(screenDecision.activity, .display)
        XCTAssertNil(screenDecision.nextChange)
        XCTAssertEqual(
            normalize(status(screen, screenDecision, at: date(2026, 3, 6, 12, 0))),
            "Screen only all week"
        )
    }

    func testNormalizeJoinsOverlapAndAbutmentPerDay() {
        var settings = SnoozeSettings.disabled
        settings.days[.friday] = [
            DailyWindow(startMinute: 8 * 60 + 30, endMinute: 15 * 60),
            DailyWindow(startMinute: 14 * 60, endMinute: 18 * 60),
            DailyWindow(startMinute: 14 * 60, endMinute: 15 * 60),
            DailyWindow(startMinute: 15 * 60, endMinute: 18 * 60),
        ]
        settings.days[.thursday] = [
            DailyWindow(startMinute: 9 * 60, endMinute: 10 * 60),
        ]
        settings.days[.friday]?.append(DailyWindow(startMinute: 22 * 60, endMinute: 6 * 60))
        settings.days[.friday]?.append(DailyWindow(startMinute: 12 * 60, endMinute: 12 * 60))
        let normalized = settings.normalized()
        XCTAssertEqual(hours(normalized, .friday), spans([(8 * 60 + 30, 18 * 60)]))
        XCTAssertEqual(hours(normalized, .thursday), spans([(9 * 60, 10 * 60)]))
    }

    func testEndOfDayIsALegalWindow() {
        let settings = makeSettings([.monday: [(22 * 60, 24 * 60)]])
        let decision = decide(settings, at: date(2026, 3, 9, 23, 0))
        XCTAssertEqual(decision.activity, .nudge)
        XCTAssertEqual(decision.nextChange, date(2026, 3, 10, 0, 0))
        XCTAssertEqual(
            normalize(status(settings, decision, at: date(2026, 3, 9, 23, 0), nudgeCount: 1)),
            "Nudging until midnight — 1 nudge"
        )
    }

    func testSundayEndingAtMidnightContinuesWhenMondayStartsAtMidnight() {
        let settings = makeSettings([
            .sunday: [(22 * 60, 24 * 60)],
            .monday: [(0, 8 * 60)],
        ])
        let before = decide(settings, at: date(2026, 3, 8, 23, 0))
        XCTAssertEqual(before.activity, .nudge)
        XCTAssertEqual(before.nextChange, date(2026, 3, 9, 0, 0))
        let atMidnight = decide(settings, at: date(2026, 3, 9, 0, 0))
        XCTAssertEqual(atMidnight.activity, .nudge)
        XCTAssertEqual(atMidnight.nextChange, date(2026, 3, 9, 8, 0))
    }

    // MARK: - Weekdays only

    func testWeekdaysOnlyIgnoresSavedWeekendHoursUntilTheFlagIsOff() {
        var settings = makeSettings(
            [
                .monday: [(8 * 60 + 30, 17 * 60)],
                .saturday: [(10 * 60, 12 * 60)],
            ],
            weekdaysOnly: true
        )
        XCTAssertEqual(hours(settings, .saturday, stored: true), spans([(10 * 60, 12 * 60)]))
        XCTAssertEqual(hours(settings, .saturday), spans([]))

        let saturday = date(2026, 3, 7, 11, 0)
        let hidden = decide(settings, at: saturday)
        XCTAssertEqual(hidden.activity, .idle)
        XCTAssertEqual(hidden.nextChange, date(2026, 3, 9, 8, 30))
        XCTAssertEqual(
            normalize(status(settings, hidden, at: saturday)),
            "Snoozed until Monday 8:30 AM"
        )

        settings.weekdaysOnly = false
        let restored = decide(settings, at: saturday)
        XCTAssertEqual(restored.activity, .nudge)
        XCTAssertEqual(restored.nextChange, date(2026, 3, 7, 12, 0))
    }

    func testSundayBeforeAMondayWindowSaysTomorrow() {
        let settings = makeSettings(
            [.monday: [(8 * 60 + 30, 17 * 60)]],
            weekdaysOnly: true
        )
        let sunday = date(2026, 3, 8, 10, 0)
        XCTAssertEqual(Weekday(date: sunday, calendar: calendar), .sunday)
        let decision = decide(settings, at: sunday)
        XCTAssertEqual(decision.nextChange, date(2026, 3, 9, 8, 30))
        XCTAssertEqual(
            normalize(status(settings, decision, at: sunday)),
            "Snoozed until tomorrow 8:30 AM"
        )
    }

    // MARK: - Manual override

    func testManualStartStopsAtMidnightWhenTheNextWindowIsAnotherDay() {
        let settings = makeSettings([
            .friday: [(8 * 60, 14 * 60)],
            .saturday: [(10 * 60, 12 * 60)],
            .monday: [(8 * 60 + 30, 18 * 60 + 30)],
        ])
        let friday = date(2026, 3, 6, 15, 0)
        let override = ManualOverride.forceNudge(year: 2026, month: 3, day: 6)

        let started = decide(settings, at: friday, override: override)
        XCTAssertEqual(started.activity, .nudge)
        XCTAssertEqual(started.override, override)
        XCTAssertEqual(started.nextChange, date(2026, 3, 7, 0, 0))
        let startedLine = normalize(status(settings, started, at: friday))
        XCTAssertEqual(startedLine, "Nudging until midnight — 0 nudges")
        XCTAssertFalse(startedLine.contains("Saturday"))

        let late = decide(settings, at: date(2026, 3, 6, 23, 30), override: override)
        XCTAssertEqual(late.activity, .nudge)
        XCTAssertEqual(late.nextChange, date(2026, 3, 7, 0, 0))

        let saturdayMidnight = decide(settings, at: date(2026, 3, 7, 0, 0), override: override)
        XCTAssertNil(saturdayMidnight.override)
        XCTAssertEqual(saturdayMidnight.activity, .idle)
        XCTAssertEqual(saturdayMidnight.nextChange, date(2026, 3, 7, 10, 0))

        let saturdayWindow = decide(settings, at: date(2026, 3, 7, 10, 0))
        XCTAssertEqual(saturdayWindow.activity, .nudge)
        XCTAssertEqual(saturdayWindow.nextChange, date(2026, 3, 7, 12, 0))

        let monday = decide(settings, at: date(2026, 3, 9, 8, 30))
        XCTAssertEqual(monday.activity, .nudge)
        XCTAssertEqual(monday.nextChange, date(2026, 3, 9, 18, 30))
    }

    func testManualStartStopsAtTheNextWindowWhenThatIsSoonerThanMidnight() {
        let settings = makeSettings([.friday: [(16 * 60, 17 * 60)]])
        let override = ManualOverride.forceNudge(year: 2026, month: 3, day: 6)
        let started = decide(settings, at: date(2026, 3, 6, 15, 0), override: override)
        XCTAssertEqual(started.activity, .nudge)
        XCTAssertEqual(started.nextChange, date(2026, 3, 6, 16, 0))
        XCTAssertEqual(
            normalize(status(settings, started, at: date(2026, 3, 6, 15, 0))),
            "Nudging until 4:00 PM — 0 nudges"
        )

        let atWindow = decide(settings, at: date(2026, 3, 6, 16, 0), override: override)
        XCTAssertNil(atWindow.override)
        XCTAssertEqual(atWindow.activity, .nudge)
        XCTAssertEqual(atWindow.nextChange, date(2026, 3, 6, 17, 0))
    }

    func testManualStopIdlesUntilTheCurrentWindowEnds() {
        let settings = makeSettings([
            .friday: [(8 * 60, 12 * 60), (13 * 60, 14 * 60)],
            .monday: [(8 * 60 + 30, 17 * 60)],
        ])
        let paused = decide(settings, at: date(2026, 3, 6, 10, 0), override: .forceIdle)
        XCTAssertEqual(paused.activity, .idle)
        XCTAssertEqual(paused.override, .forceIdle)
        XCTAssertEqual(paused.nextChange, date(2026, 3, 6, 12, 0))
        XCTAssertEqual(
            normalize(status(settings, paused, at: date(2026, 3, 6, 10, 0))),
            "Paused until 12:00 PM"
        )

        let gap = decide(settings, at: date(2026, 3, 6, 12, 0), override: .forceIdle)
        XCTAssertNil(gap.override)
        XCTAssertEqual(gap.activity, .idle)
        XCTAssertEqual(gap.nextChange, date(2026, 3, 6, 13, 0))

        let second = decide(settings, at: date(2026, 3, 6, 13, 0))
        XCTAssertEqual(second.activity, .nudge)
        XCTAssertEqual(second.nextChange, date(2026, 3, 6, 14, 0))
    }

    func testScreenOnlyUsesTheSameBoundaries() {
        let settings = makeSettings([.friday: [(8 * 60, 14 * 60)]], outside: .screenOnly)
        let gap = decide(settings, at: date(2026, 3, 6, 15, 0))
        XCTAssertEqual(gap.activity, .display)
        XCTAssertEqual(gap.nextChange, date(2026, 3, 13, 8, 0))
        XCTAssertEqual(
            normalize(status(settings, gap, at: date(2026, 3, 6, 15, 0))),
            "Screen only until Friday 8:00 AM"
        )
    }

    // MARK: - DST

    func testNextMondaySurvivesTheSpringForward() {
        let settings = makeSettings(
            [
                .friday: [(8 * 60, 14 * 60)],
                .monday: [(8 * 60 + 30, 17 * 60)],
            ],
            weekdaysOnly: true
        )
        let friday = date(2026, 3, 6, 15, 0)
        let decision = decide(settings, at: friday)
        let monday = date(2026, 3, 9, 8, 30)
        XCTAssertEqual(decision.nextChange, monday)
        let threeExactDays: TimeInterval = 3 * 24 * 60 * 60
        XCTAssertNotEqual(monday.timeIntervalSince(friday), threeExactDays)
    }

    func testBothFallBackHoursFollowLocalMinutes() {
        let settings = makeSettings([.sunday: [(0, 4 * 60)]])
        let first = Date(timeIntervalSince1970: 1_793_511_000) // 2026-11-01 01:30 EDT
        let second = Date(timeIntervalSince1970: 1_793_514_600) // 2026-11-01 01:30 EST
        XCTAssertEqual(calendar.component(.hour, from: first), 1)
        XCTAssertEqual(calendar.component(.minute, from: first), 30)
        XCTAssertEqual(calendar.component(.hour, from: second), 1)
        XCTAssertEqual(calendar.component(.minute, from: second), 30)
        XCTAssertEqual(calendar.component(.day, from: first), calendar.component(.day, from: second))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(decide(settings, at: first).activity, .nudge)
        XCTAssertEqual(decide(settings, at: second).activity, .nudge)

        let after = Date(timeIntervalSince1970: 1_793_525_400) // 2026-11-01 04:30 EST
        XCTAssertEqual(decide(settings, at: after).activity, .idle)
    }

    func testSkippedSpringForwardHourDoesNotCrash() {
        let missing = makeSettings([.sunday: [(2 * 60, 3 * 60)]])
        let beforeJump = date(2026, 3, 8, 1, 30)
        let missingDecision = decide(missing, at: beforeJump)
        XCTAssertEqual(missingDecision.activity, .idle)
        XCTAssertNotEqual(missingDecision.nextChange, beforeJump)

        let spanning = makeSettings([.sunday: [(1 * 60, 4 * 60)]])
        let afterJump = date(2026, 3, 8, 3, 0)
        XCTAssertEqual(decide(spanning, at: afterJump).activity, .nudge)
        XCTAssertEqual(decide(spanning, at: afterJump).nextChange, date(2026, 3, 8, 4, 0))
    }

    // MARK: - Timer cap, status, storage

    func testTimerFiresAtTheBoundaryOrFifteenMinutes() {
        let now = date(2026, 3, 6, 12, 0)
        let soon = now.addingTimeInterval(4 * 60)
        XCTAssertEqual(SnoozeSchedule.timerFireDate(now: now, nextChange: soon), soon)
        let later = now.addingTimeInterval(3 * 24 * 60 * 60)
        XCTAssertEqual(
            SnoozeSchedule.timerFireDate(now: now, nextChange: later),
            now.addingTimeInterval(SnoozeSchedule.boundaryHop)
        )
        XCTAssertNil(SnoozeSchedule.timerFireDate(now: now, nextChange: nil))
        XCTAssertNil(SnoozeSchedule.timerFireDate(now: now, nextChange: now))
    }

    func testStatusIncludesTheLastNudgeAndAccessibilityBlock() {
        let settings = makeSettings([.friday: [(8 * 60, 14 * 60)]])
        let now = date(2026, 3, 6, 9, 0)
        let decision = decide(settings, at: now)
        let line = status(settings, decision, at: now, nudgeCount: 2, lastNudge: date(2026, 3, 6, 8, 5))
        XCTAssertEqual(normalize(line), "Nudging until 2:00 PM — 2 nudges (last: 8:05 AM)")
        XCTAssertEqual(
            SnoozeSchedule.statusLine(
                now: now,
                calendar: calendar,
                decision: decision,
                nudgeCount: 2,
                lastNudge: nil,
                accessibilityBlocked: true,
                locale: Locale(identifier: "en_US")
            ),
            "Nudging is blocked — Accessibility not granted"
        )
    }

    func testSymbols() {
        XCTAssertEqual(
            SnoozeSchedule.symbol(nudging: true, snoozeEnabled: true, showingDisplay: false, paused: false, blocked: false),
            "cursorarrow.motionlines"
        )
        XCTAssertEqual(
            SnoozeSchedule.symbol(nudging: false, snoozeEnabled: true, showingDisplay: true, paused: false, blocked: false),
            "display"
        )
        XCTAssertEqual(
            SnoozeSchedule.symbol(nudging: false, snoozeEnabled: true, showingDisplay: false, paused: false, blocked: false),
            "moon.zzz"
        )
        XCTAssertEqual(
            SnoozeSchedule.symbol(nudging: false, snoozeEnabled: false, showingDisplay: false, paused: false, blocked: false),
            "cursorarrow"
        )
        XCTAssertEqual(
            SnoozeSchedule.symbol(nudging: false, snoozeEnabled: true, showingDisplay: false, paused: true, blocked: false),
            "cursorarrow"
        )
        XCTAssertEqual(
            SnoozeSchedule.symbol(nudging: false, snoozeEnabled: true, showingDisplay: false, paused: false, blocked: true),
            "cursorarrow"
        )
    }

    func testCopyAndWeekdayPresetKeepIndependentCopies() {
        var settings = makeSettings([
            .friday: [(8 * 60, 14 * 60)],
            .saturday: [(10 * 60, 12 * 60)],
        ])
        let fridayID = settings.days[.friday]!.first!.id
        settings = settings.copying(day: .friday, to: Weekday.weekdays)
        XCTAssertEqual(hours(settings, .monday), spans([(8 * 60, 14 * 60)]))
        XCTAssertEqual(hours(settings, .friday), spans([(8 * 60, 14 * 60)]))
        XCTAssertNotEqual(settings.days[.monday]!.first!.id, fridayID)
        XCTAssertEqual(hours(settings, .saturday), spans([(10 * 60, 12 * 60)]))

        settings = settings.settingWeekdays(startMinute: 9 * 60, endMinute: 17 * 60)
        XCTAssertEqual(hours(settings, .wednesday), spans([(9 * 60, 17 * 60)]))
        XCTAssertEqual(hours(settings, .saturday), spans([(10 * 60, 12 * 60)]))
    }

    func testSeedFillsEmptyWeekdaysOnly() {
        let seeded = SnoozeSettings.disabled.seededForFirstEnable()
        XCTAssertEqual(hours(seeded, .monday), spans([(9 * 60, 17 * 60)]))
        XCTAssertEqual(hours(seeded, .friday), spans([(9 * 60, 17 * 60)]))
        XCTAssertEqual(hours(seeded, .saturday), spans([]))
        let custom = makeSettings([.saturday: [(10 * 60, 12 * 60)]])
        XCTAssertEqual(hours(custom.seededForFirstEnable(), .saturday), spans([(10 * 60, 12 * 60)]))
        XCTAssertEqual(hours(custom.seededForFirstEnable(), .monday), spans([]))
    }

    func testPersistenceRoundTripKeepsEmptyDaysAndDropsBadData() throws {
        var settings = makeSettings(
            [
                .friday: [(8 * 60, 14 * 60), (13 * 60, 18 * 60)],
                .sunday: [],
            ],
            outside: .screenOnly,
            weekdaysOnly: true,
            enabled: true
        )
        settings.days[.monday] = [DailyWindow(startMinute: 18 * 60, endMinute: 9 * 60)]
        let suite = "snooze-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        settings.normalized().save(to: defaults)

        let data = try XCTUnwrap(defaults.data(forKey: SnoozeSettings.storageKey))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let days = try XCTUnwrap(object["days"] as? [String: Any])
        let sunday = try XCTUnwrap(days["sunday"] as? [Any])
        XCTAssertTrue(sunday.isEmpty)

        let loaded = SnoozeSettings.load(from: defaults)
        XCTAssertTrue(loaded.enabled)
        XCTAssertEqual(loaded.outsideMode, .screenOnly)
        XCTAssertTrue(loaded.weekdaysOnly)
        XCTAssertEqual(hours(loaded, .friday), spans([(8 * 60, 18 * 60)]))
        XCTAssertEqual(hours(loaded, .sunday), spans([]))
        XCTAssertEqual(hours(loaded, .monday), spans([]))
        XCTAssertEqual(loaded.days[.friday]?.first?.id, settings.days[.friday]?.first?.id)

        defaults.set(Data("[]".utf8), forKey: SnoozeSettings.storageKey)
        XCTAssertEqual(SnoozeSettings.load(from: defaults), .disabled)

        let future = #"{"version":2,"enabled":true,"outsideMode":"off","weekdaysOnly":false,"days":{}}"#
        defaults.set(Data(future.utf8), forKey: SnoozeSettings.storageKey)
        XCTAssertEqual(SnoozeSettings.load(from: defaults), .disabled)

        defaults.removeObject(forKey: SnoozeSettings.storageKey)
        XCTAssertEqual(SnoozeSettings.load(from: defaults), .disabled)
    }

    // MARK: - Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return components.date!
    }

    private func makeSettings(
        _ hoursByDay: [Weekday: [(Int, Int)]],
        outside: OutsideMode = .off,
        weekdaysOnly: Bool = false,
        enabled: Bool = true
    ) -> SnoozeSettings {
        var settings = SnoozeSettings.disabled
        settings.enabled = enabled
        settings.outsideMode = outside
        settings.weekdaysOnly = weekdaysOnly
        for (day, ranges) in hoursByDay {
            settings.days[day] = ranges.map { DailyWindow(startMinute: $0.0, endMinute: $0.1) }
        }
        return settings.normalized()
    }

    private struct Span: Equatable {
        var start: Int
        var end: Int
    }

    private func spans(_ pairs: [(Int, Int)]) -> [Span] {
        pairs.map { Span(start: $0.0, end: $0.1) }
    }

    private func hours(_ settings: SnoozeSettings, _ day: Weekday, stored: Bool = false) -> [Span] {
        let windows = stored ? (settings.days[day] ?? []) : settings.effectiveWindows(on: day)
        return windows.map { Span(start: $0.startMinute, end: $0.endMinute) }
    }

    private func decide(
        _ settings: SnoozeSettings,
        at now: Date,
        override: ManualOverride? = nil
    ) -> SnoozeDecision {
        SnoozeSchedule.decide(now: now, calendar: calendar, settings: settings, override: override)
    }

    private func status(
        _ settings: SnoozeSettings,
        _ decision: SnoozeDecision,
        at now: Date,
        nudgeCount: Int = 0,
        lastNudge: Date? = nil
    ) -> String {
        SnoozeSchedule.statusLine(
            now: now,
            calendar: calendar,
            decision: decision,
            nudgeCount: nudgeCount,
            lastNudge: lastNudge,
            accessibilityBlocked: false,
            locale: Locale(identifier: "en_US")
        )
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
