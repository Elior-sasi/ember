import SwiftUI
import SwitcherKit
import WidgetKit

enum Connection: Equatable {
    case connecting, ok, away, noAnswer, notSetUp
}

@MainActor
final class AppModel: ObservableObject {
    @Published var config: HeaterConfig = Store.shared.config
    @Published var snapshot: Snapshot? = Store.shared.snapshot
    @Published var connection: Connection = .connecting
    @Published var busy = false
    @Published var toast: String?
    @Published var schedules: [HeaterSchedule] = []
    @Published var parked: [ParkedSchedule] = Store.shared.parked
    @Published var unlimited: Bool = Store.shared.unlimitedRun
    @Published var now = Date()

    /// minutes chosen on the dial while the heater is off (0 = no timer)
    @Published var chosen: Int = (Store.shared.defaults.object(forKey: "chosenMinutes") as? Int) ?? 45 {
        didSet { Store.shared.defaults.set(chosen, forKey: "chosenMinutes") }
    }

    private var poll: Task<Void, Never>?
    private var tick: Timer?

    var isOn: Bool { snapshot?.state.isOn == true }
    /// seconds left, counted down locally between polls
    var secondsLeft: Int {
        guard let end = snapshot?.endsAt else { return 0 }
        return max(0, Int(end.timeIntervalSince(now)))
    }
    var secondsOn: Int {
        guard let start = snapshot?.startedAt else { return 0 }
        return max(0, Int(now.timeIntervalSince(start)))
    }
    var totalSeconds: Int { max(1, secondsLeft + secondsOn) }

    func start() {
        if !config.isComplete { connection = .notSetUp; return }
        poll?.cancel()
        poll = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(quiet: true)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        Task { await loadSchedules() }
    }

    func stop() {
        poll?.cancel(); poll = nil
        tick?.invalidate(); tick = nil
    }

    func refresh(quiet: Bool = false) async {
        guard config.isComplete else { connection = .notSetUp; return }
        do {
            let s = try await HeaterController.refresh()
            apply(s)
        } catch {
            handle(error, quiet: quiet)
        }
    }

    // MARK: actions

    func powerTapped() {
        if isOn { act("הדוד כבוי") { try await HeaterController.turnOff() } }
        else {
            let m = chosen
            act(m == 0 ? "הדוד דולק בלי טיימר" : "הדוד דולק ל-\(m) דקות") { try await HeaterController.turnOn(minutes: m) }
        }
    }

    func addTime(_ m: Int) {
        act(m > 0 ? "נוספו \(m) דקות" : "הורדו \(-m) דקות") { try await HeaterController.addTime(minutes: m) }
    }

    /// −/+ on the dial: changes the chosen minutes when off, or the running timer when on.
    func nudge(_ delta: Int) {
        if isOn {
            guard !unlimited else { return }
            if delta < 0 && secondsLeft <= 6 * 60 { return }
            addTime(delta)
        } else {
            let base = chosen == 0 ? 45 : chosen
            chosen = min(DialView.maxM, max(DialView.minM, base + delta))
            Haptics.tap()
        }
    }

    /// Preset tiles: pick the minutes when off, start a new timer when on.
    func preset(_ m: Int) {
        if isOn && !unlimited {
            act("הדוד דולק ל-\(m) דקות") { try await HeaterController.turnOn(minutes: m) }
        } else if !isOn {
            chosen = m
            Haptics.tap()
        }
    }

    func setAutoShutdown(_ minutes: Int) {
        act("הכיבוי האוטומטי עודכן") {
            try await HeaterController.setAutoShutdown(minutes: minutes)
            return try await HeaterController.refresh()
        }
    }

    private func act(_ done: String, _ op: @escaping () async throws -> Snapshot) {
        guard !busy else { return }
        busy = true
        Haptics.tap()
        Task {
            defer { busy = false }
            do {
                apply(try await op())
                show(done)
                Haptics.success()
            } catch {
                handle(error, quiet: false)
                Haptics.error()
            }
        }
    }

    private func apply(_ s: Snapshot) {
        snapshot = s
        unlimited = Store.shared.unlimitedRun
        connection = .ok
        now = Date()
    }

    private func handle(_ error: Error, quiet: Bool) {
        switch error as? HeaterProblem {
        case .away?: connection = .away
        case .notSetUp?: connection = .notSetUp
        default: connection = .noAnswer
        }
        if !quiet, let msg = (error as? LocalizedError)?.errorDescription { show(msg) }
    }

    func show(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if toast == text { toast = nil }
        }
    }

    // MARK: schedules

    func loadSchedules() async {
        guard config.isComplete else { return }
        if let list = try? await HeaterController.schedules() {
            schedules = list
            Store.shared.cachedSchedules = list
            WidgetCenter.shared.reloadAllTimelines()
        }
        parked = Store.shared.parked
    }

    func saveSchedule(replacing slot: Int?, days: Set<Int>, start: Int, end: Int) {
        Task {
            do {
                if let slot { try await HeaterController.deleteSchedule(slot: slot) }
                try await HeaterController.addSchedule(weekdays: WeekdayBits.mask(days), start: start, end: end)
                await loadSchedules()
                show("התזמון נשמר בדוד")
            } catch { handle(error, quiet: false) }
        }
    }

    func deleteSchedule(_ s: HeaterSchedule) {
        Task {
            do {
                try await HeaterController.deleteSchedule(slot: s.slot)
                await loadSchedules()
                show("התזמון נמחק")
            } catch { handle(error, quiet: false) }
        }
    }

    /// Switching a schedule off removes it from the heater and keeps it in the app.
    func park(_ s: HeaterSchedule) {
        Task {
            do {
                try await HeaterController.deleteSchedule(slot: s.slot)
                Store.shared.parked.append(ParkedSchedule(weekdays: s.weekdays, startMinutes: s.startMinutes, endMinutes: s.endMinutes))
                await loadSchedules()
                show("התזמון הושבת")
            } catch { handle(error, quiet: false) }
        }
    }

    func unpark(_ p: ParkedSchedule) {
        Task {
            do {
                try await HeaterController.addSchedule(weekdays: p.weekdays, start: p.startMinutes, end: p.endMinutes)
                Store.shared.parked.removeAll { $0.id == p.id }
                await loadSchedules()
                show("התזמון הופעל")
            } catch { handle(error, quiet: false) }
        }
    }

    func deleteParked(_ p: ParkedSchedule) {
        Store.shared.parked.removeAll { $0.id == p.id }
        parked = Store.shared.parked
        show("התזמון נמחק")
    }

    var nextSchedule: HeaterSchedule? { Store.nextRun(schedules, now: now)?.schedule }

    // MARK: settings

    func saveConfig(_ c: HeaterConfig) {
        Store.shared.config = c
        config = c
        connection = .connecting
        start()
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}
