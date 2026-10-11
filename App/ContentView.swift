import SwiftUI
import SwitcherKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var phase
    @State private var sheet: SheetKind?

    enum SheetKind: Identifiable {
        case stats, settings, autoOff, schedule(HeaterSchedule?), parked(ParkedSchedule)
        var id: String {
            switch self {
            case .stats: return "stats"
            case .settings: return "settings"
            case .autoOff: return "auto"
            case .schedule(let s): return "s\(s?.slot ?? -1)"
            case .parked(let p): return p.id.uuidString
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    TopBar(sheet: $sheet)
                    switch model.connection {
                    case .notSetUp:
                        SetupView()
                    case .away:
                        AwayView()
                    case .noAnswer:
                        NoAnswerView(openSettings: { sheet = .settings })
                    default:
                        MainPanel(sheet: $sheet)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.refresh() }

            if let t = model.toast {
                Text(t)
                    .font(.system(size: 14))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
        .foregroundStyle(Theme.fg)
        .sheet(item: $sheet) { kind in
            Group {
                switch kind {
                case .stats: StatsView()
                case .settings: SettingsView()
                case .autoOff: AutoOffSheet()
                case .schedule(let s): ScheduleSheet(existing: s)
                case .parked(let p): ParkedSheet(item: p)
                }
            }
            .environmentObject(model)
            .environment(\.layoutDirection, .rightToLeft)
            .presentationDetents([.medium, .large])
            .presentationBackground(Theme.surface)
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
        .onChange(of: phase) { _, p in
            if p == .active { model.start() } else { model.stop() }
        }
        .onAppear { model.start() }
    }
}

// MARK: - top bar

struct TopBar: View {
    @EnvironmentObject var model: AppModel
    @Binding var sheet: ContentView.SheetKind?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.config.name).font(.system(size: 22, weight: .bold))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(dotColor).frame(width: 7, height: 7)
                Text(pillText).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(Theme.line))
            IconButton(system: "chart.bar") { sheet = .stats }
            IconButton(system: "gearshape") { sheet = .settings }
        }
    }

    var subtitle: String {
        guard model.connection == .ok, let s = model.snapshot else { return " " }
        if s.state.isOn { return "מחמם · נכבה ב-\(s.endsAt.map(Fmt.time) ?? "")" }
        if let off = Store.shared.lastOff { return "כבוי · כבה \(Fmt.ago(off, now: model.now))" }
        if let n = model.nextSchedule { return "כבוי · התזמון הבא \(Fmt.hm(n.startMinutes))" }
        return "כבוי"
    }
    var pillText: String {
        switch model.connection {
        case .ok: return "בבית · מחובר"
        case .connecting: return "מתחבר..."
        case .away: return "מחוץ לבית"
        case .noAnswer: return "הדוד לא עונה"
        case .notSetUp: return "לא מוגדר"
        }
    }
    var dotColor: Color {
        switch model.connection {
        case .ok: return Theme.ok
        case .connecting, .away, .notSetUp: return Theme.warn
        case .noAnswer: return Theme.bad
        }
    }
}

struct IconButton: View {
    let system: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 15)).foregroundStyle(Theme.muted)
                .frame(width: 36, height: 36)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - main panel

struct MainPanel: View {
    @EnvironmentObject var model: AppModel
    @Binding var sheet: ContentView.SheetKind?

    var body: some View {
        VStack(spacing: 18) {
            DialView()
            PowerButton()
            section(model.isOn ? "הוסף זמן" : "זמן מהיר") { QuickChips() }
            section(model.isOn ? "עכשיו" : "חימום אחרון") { Readings(sheet: $sheet) }
            section("תזמונים") { ScheduleList(sheet: $sheet) }
        }
        .disabled(model.connection != .ok && model.snapshot == nil)
    }

    func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted).kerning(0.6)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PowerButton: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Button { model.powerTapped() } label: {
            HStack(spacing: 12) {
                if model.busy { ProgressView().tint(model.isOn ? Theme.fg : Theme.onAccent) }
                else { Image(systemName: "power").font(.system(size: 20, weight: .bold)) }
                Text(title).font(.system(size: 17, weight: .bold))
            }
            .frame(maxWidth: .infinity).padding(16)
            .foregroundStyle(model.isOn ? Theme.fg : Theme.onAccent)
            .background {
                if model.isOn {
                    RoundedRectangle(cornerRadius: 20).fill(Theme.surface2)
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line))
                } else {
                    RoundedRectangle(cornerRadius: 20).fill(Theme.heat)
                }
            }
        }
        .buttonStyle(PressStyle())
        .disabled(model.connection != .ok)
        .opacity(model.connection == .ok ? 1 : 0.5)
    }
    var title: String {
        if model.isOn { return "כבה" }
        return model.chosen == 0 ? "הדלק ללא טיימר" : "הדלק ל-\(model.chosen) דקות"
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.98 : 1).animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct QuickChips: View {
    @EnvironmentObject var model: AppModel
    var options: [Int] { model.isOn ? (model.unlimited ? [] : [15, 30, 45, 60, 90]) : [0, 15, 30, 45, 60, 90] }

    var body: some View {
        if options.isEmpty {
            Text("הדוד דולק בלי טיימר. כדי לקבוע זמן, כבה והדלק מחדש.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
        } else {
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { m in
                    let selected = !model.isOn && model.chosen == m
                    Button {
                        if model.isOn { model.addTime(m) } else { model.chosen = m; Haptics.tap() }
                    } label: {
                        VStack(spacing: 1) {
                            Text(m == 0 ? "∞" : (model.isOn ? "+\(m)" : "\(m)")).font(Theme.num(17, .light))
                            Text(m == 0 ? "ללא" : "דק׳").font(.system(size: 11))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .foregroundStyle(selected ? Theme.accent : Theme.muted)
                        .background(selected ? Theme.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line))
            .disabled(model.busy || model.connection != .ok)
        }
    }
}

struct Readings: View {
    @EnvironmentObject var model: AppModel
    @Binding var sheet: ContentView.SheetKind?

    var body: some View {
        HStack(spacing: 8) {
            if model.isOn, let s = model.snapshot?.state {
                tile("\(s.powerWatts.formatted())", "וואט")
                tile(String(format: "%.1f", Double(s.powerWatts) / 220), "אמפר")
            } else if let last = Store.shared.lastSession {
                tile("\(Int(last.minutes.rounded()))", "דקות")
                tile(String(format: "%.1f", last.kWh), "קוט״ש")
            } else {
                tile("-", "דקות")
                tile("-", "קוט״ש")
            }
            Button { sheet = .autoOff } label: {
                tile(Fmt.hm((model.snapshot?.state.autoShutdownSeconds ?? 0) / 60), "כיבוי אוטומטי", chevron: true)
            }
            .buttonStyle(PressStyle())
        }
    }

    func tile(_ value: String, _ label: String, chevron: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(Theme.num(21, .light)).environment(\.layoutDirection, .leftToRight)
            HStack(spacing: 4) {
                Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
                if chevron { Image(systemName: "chevron.left").font(.system(size: 9)).foregroundStyle(Theme.muted) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
    }
}

struct ScheduleList: View {
    @EnvironmentObject var model: AppModel
    @Binding var sheet: ContentView.SheetKind?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(model.schedules) { s in
                row(time: "\(Fmt.hm(s.startMinutes)) - \(Fmt.hm(s.endMinutes))", days: Fmt.days(s.weekdays), on: true,
                    open: { sheet = .schedule(s) }, toggle: { model.park(s) })
            }
            ForEach(model.parked) { p in
                row(time: "\(Fmt.hm(p.startMinutes)) - \(Fmt.hm(p.endMinutes))", days: Fmt.days(p.weekdays) + " · מושבת", on: false,
                    open: { sheet = .parked(p) }, toggle: { model.unpark(p) })
            }
            if model.schedules.count < 8 {
                Button { sheet = .schedule(nil) } label: {
                    Label("תזמון חדש", systemImage: "plus").font(.system(size: 14)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity).padding(12)
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [5])))
                }
                .buttonStyle(.plain)
            }
        }
    }

    func row(time: String, days: String, on: Bool, open: @escaping () -> Void, toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(time).font(Theme.num(20, .light)).environment(\.layoutDirection, .leftToRight)
                    Text(days).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(on ? 1 : 0.45)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(get: { on }, set: { _ in toggle() }))
                .labelsHidden().tint(Theme.accent)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
    }
}

// MARK: - away / no answer

struct AwayView: View {
    var body: some View {
        StateMessage(icon: "wifi.slash", title: "אתה מחוץ לבית",
                     text: "הדוד עונה רק ברשת ה-WiFi של הבית. כדי לשלוט בו מבחוץ, פתח את האפליקציה של סוויץ׳ר.") {
            Button("פתח את סוויץ׳ר") { SwitcherApp.open() }.buttonStyle(PrimaryStyle())
        }
    }
}

struct NoAnswerView: View {
    @EnvironmentObject var model: AppModel
    var openSettings: () -> Void
    var body: some View {
        StateMessage(icon: "exclamationmark.circle", title: "הדוד לא עונה",
                     text: "אתה מחובר ל-WiFi, אבל הדוד לא מגיב בכתובת \(model.config.host). ייתכן שאתה ברשת אחרת, שהדוד התנתק מה-WiFi או שקיבל כתובת חדשה מהראוטר.") {
            HStack(spacing: 8) {
                Button("בדוק הגדרות", action: openSettings).buttonStyle(SecondaryStyle())
                Button("נסה שוב") { Task { await model.refresh() } }.buttonStyle(PrimaryStyle())
            }
        }
    }
}

struct StateMessage<Actions: View>: View {
    let icon: String, title: String, text: String
    @ViewBuilder var actions: Actions
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 54, weight: .light)).foregroundStyle(Theme.muted)
            Text(title).font(.system(size: 20, weight: .bold))
            Text(text).font(.system(size: 15)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).lineSpacing(3)
            actions.padding(.top, 6)
        }
        .padding(.vertical, 48).padding(.horizontal, 8)
    }
}

struct PrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity).padding(14)
            .foregroundStyle(Theme.onAccent)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SecondaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity).padding(14)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

enum SwitcherApp {
    /// Opens Switcher's own app, or the App Store search if the guess at its link fails.
    static func open() {
        let candidates = ["switcher://", "switchersmart://"]
        func attempt(_ i: Int) {
            guard i < candidates.count, let url = URL(string: candidates[i]) else {
                if let store = URL(string: "itms-apps://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?media=software&term=switcher%20smart") {
                    UIApplication.shared.open(store)
                }
                return
            }
            UIApplication.shared.open(url) { ok in if !ok { attempt(i + 1) } }
        }
        attempt(0)
    }
}
