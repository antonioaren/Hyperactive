import AppKit
import SwiftUI

/// Shows the Snooze schedule editor. A menu-bar app has no Dock icon, so the
/// window is created only when asked for and then brought forward.
final class SnoozeEditorPresenter: NSObject, NSWindowDelegate {
    static let shared = SnoozeEditorPresenter()

    private var window: NSWindow?

    func show(
        draft: SnoozeSettings,
        enableOnDone: Bool,
        onDone: @escaping (SnoozeSettings) -> Void
    ) {
        DispatchQueue.main.async {
            self.showNow(draft: draft, enableOnDone: enableOnDone, onDone: onDone)
        }
    }

    private func showNow(
        draft: SnoozeSettings,
        enableOnDone: Bool,
        onDone: @escaping (SnoozeSettings) -> Void
    ) {
        let view = SnoozeEditorView(
            draft: draft,
            enableOnDone: enableOnDone,
            onDone: { [weak self] settings in
                onDone(settings)
                self?.close()
            },
            onCancel: { [weak self] in
                self?.close()
            }
        )
        let controller = NSHostingController(rootView: view)
        let window = self.window ?? makeWindow()
        window.contentViewController = controller
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Snooze"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 460, height: 420)
        window.delegate = self
        window.center()
        return window
    }

    private func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
    }
}

struct SnoozeEditorView: View {
    @State private var draft: SnoozeSettings
    @State private var selectedDay: Weekday = .monday
    private let enableOnDone: Bool
    private let onDone: (SnoozeSettings) -> Void
    private let onCancel: () -> Void

    init(
        draft: SnoozeSettings,
        enableOnDone: Bool,
        onDone: @escaping (SnoozeSettings) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        self.enableOnDone = enableOnDone
        self.onDone = onDone
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Weekdays only", isOn: $draft.weekdaysOnly)
            Text("Active hours apply Monday through Friday. Saturday and Sunday use the outside mode. Their saved hours are kept and apply again when you turn this off.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Day", selection: $selectedDay) {
                ForEach(Weekday.displayedOrder) { day in
                    Text(day.title).tag(day)
                }
            }

            if draft.weekdaysOnly && selectedDay.isWeekend {
                Text("\(selectedDay.title) uses the outside mode while Weekdays only is on. These hours are saved for when you turn it off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    dayEditor
                    convenienceButtons
                    weekSummary
                }
            }

            if let footerMessage {
                Text(footerMessage)
                    .font(.caption)
                    .foregroundStyle(draft.hasInvalidWindow ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Done", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(doneDisabled)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 560)
    }

    private var dayEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(selectedDay.title) hours")
                .font(.headline)
            let windows = draft.days[selectedDay] ?? []
            if windows.isEmpty {
                Text("No hours. This day uses the outside mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(windows) { window in
                windowRow(window)
            }
            if selectedDayHasInvalidWindow {
                Text("End time must be later than the start time.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button("Add window") {
                addWindow(to: selectedDay)
            }
        }
    }

    private var convenienceButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Set weekdays to 9:00–17:00") {
                draft = draft.settingWeekdays(startMinute: 9 * 60, endMinute: 17 * 60)
            }
            Button("Copy \(selectedDay.title) to weekdays") {
                draft = draft.copying(day: selectedDay, to: Weekday.weekdays)
            }
            Button("Copy \(selectedDay.title) to every day") {
                draft = draft.copying(day: selectedDay, to: Weekday.allCases)
            }
        }
    }

    private var weekSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("This week")
                .font(.headline)
            ForEach(Weekday.displayedOrder) { day in
                HStack(alignment: .firstTextBaseline) {
                    Text(day.title)
                        .frame(width: 100, alignment: .leading)
                    Text(hoursText(day))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
            }
        }
    }

    private func windowRow(_ window: DailyWindow) -> some View {
        HStack(spacing: 8) {
            DatePicker(
                "Start",
                selection: minuteBinding(day: selectedDay, id: window.id, keyPath: \.startMinute),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            Text("to")
            if window.endMinute >= 1_440 {
                Text("Midnight")
                    .frame(minWidth: 80, alignment: .leading)
                Button("Set time") {
                    setEndToClockTime(day: selectedDay, id: window.id)
                }
            } else {
                DatePicker(
                    "End",
                    selection: minuteBinding(day: selectedDay, id: window.id, keyPath: \.endMinute),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                Button("Midnight") {
                    update(selectedDay, id: window.id) { $0.endMinute = 1_440 }
                }
            }
            Button {
                remove(day: selectedDay, id: window.id)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Remove window")
        }
    }

    private var selectedDayHasInvalidWindow: Bool {
        (draft.days[selectedDay] ?? []).contains { $0.endMinute <= $0.startMinute }
    }

    private var doneDisabled: Bool {
        if draft.hasInvalidWindow {
            return true
        }
        if enableOnDone && !draft.normalized().hasEffectiveWindow {
            return true
        }
        return false
    }

    private var footerMessage: String? {
        if draft.hasInvalidWindow {
            return "End time must be later than the start time. A window stays inside one day; add another window after midnight."
        }
        if enableOnDone && !draft.normalized().hasEffectiveWindow {
            if draft.weekdaysOnly {
                return "Add hours on Monday through Friday, or turn off Weekdays only, to turn Snooze on."
            }
            return "Add hours on at least one day to turn Snooze on."
        }
        return "Overlapping hours on a day are joined when you click Done."
    }

    private func commit() {
        guard !doneDisabled else { return }
        onDone(draft.normalized())
    }

    private func hoursText(_ day: Weekday) -> String {
        let windows = draft.days[day] ?? []
        let body: String
        if windows.isEmpty {
            body = "No hours"
        } else {
            body = windows.map { window in
                let end = window.endMinute >= 1_440 ? "midnight" : timeLabel(window.endMinute)
                return "\(timeLabel(window.startMinute)) – \(end)"
            }.joined(separator: ", ")
        }
        if draft.weekdaysOnly && day.isWeekend && !windows.isEmpty {
            return body + " · ignored while Weekdays only is on"
        }
        if draft.weekdaysOnly && day.isWeekend {
            return "Outside mode while Weekdays only is on"
        }
        return body
    }

    private func timeLabel(_ minute: Int) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: Self.date(forMinute: minute))
    }

    private static func date(forMinute minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 5
        let capped = min(max(minute, 0), 23 * 60 + 59)
        components.hour = capped / 60
        components.minute = capped % 60
        return calendar.date(from: components) ?? Date()
    }

    private func minuteBinding(
        day: Weekday,
        id: UUID,
        keyPath: WritableKeyPath<DailyWindow, Int>
    ) -> Binding<Date> {
        Binding(
            get: {
                let minute = draft.days[day]?.first { $0.id == id }?[keyPath: keyPath] ?? 0
                return Self.date(forMinute: minute)
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                update(day, id: id) { window in
                    window[keyPath: keyPath] = minute
                }
            }
        )
    }

    private func addWindow(to day: Weekday) {
        var windows = draft.days[day] ?? []
        let start: Int
        let end: Int
        if windows.isEmpty {
            start = 9 * 60
            end = 17 * 60
        } else if let lastEnd = windows.map(\.endMinute).max(), lastEnd < 23 * 60 {
            start = lastEnd
            end = min(1_440, lastEnd + 60)
        } else {
            start = 9 * 60
            end = 17 * 60
        }
        windows.append(DailyWindow(startMinute: start, endMinute: end))
        draft.days[day] = windows
    }

    private func remove(day: Weekday, id: UUID) {
        draft.days[day] = (draft.days[day] ?? []).filter { $0.id != id }
    }

    private func setEndToClockTime(day: Weekday, id: UUID) {
        update(day, id: id) { window in
            let candidate = min(23 * 60 + 59, window.startMinute + 60)
            window.endMinute = candidate > window.startMinute ? candidate : window.startMinute + 1
        }
    }

    private func update(_ day: Weekday, id: UUID, _ body: (inout DailyWindow) -> Void) {
        guard var windows = draft.days[day], let index = windows.firstIndex(where: { $0.id == id }) else { return }
        body(&windows[index])
        draft.days[day] = windows
    }
}
