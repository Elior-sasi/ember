import SwiftUI
import SwitcherKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var phase
    @State private var sheet: SheetKind?

    enum SheetKind: Identifiable {
        case menu, stats, settings, autoOff, schedules, schedule(HeaterSchedule?), parked(ParkedSchedule)
        var id: String {
            switch self {
            case .menu: return "menu"
            case .stats: return "stats"
            case .settings: return "settings"
            case .autoOff: return "auto"
            case .schedules: return "schedules"
            case .schedule(let s): return "s\(s?.slot ?? -1)"
            case .parked(let p): return p.id.uuidString
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Backdrop(on: model.isOn)
            ScrollView {
                VStack(spacing: 12) {
                    Header(sheet: $sheet)
                    switch model.connection {
                    case .notSetUp: SetupView()
                    case .away: AwayView()
                    case .noAnswer: NoAnswerView(openSettings: { sheet = .settings })
                    default: MainPanel(sheet: $sheet)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, showBar ? 100 : 30)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .refreshable { await model.refresh() }

            if showBar { BottomBar(sheet: $sheet).padding(.horizontal, 14).padding(.bottom, 6) }

            if let t = model.toast {
                Text(t)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.glassEdge, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.3), radius: 15, y: 8)
                    .padding(.bottom, showBar ? 84 : 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.toast)
        .foregroundStyle(Theme.fg)
        .sheet(item: $sheet) { kind in
            Group {
                switch kind {
                case .menu: MenuSheet(sheet: $sheet)
                case .stats: StatsView()
                case .settings: SettingsView()
                case .autoOff: AutoOffSheet()
                case .schedules: SchedulesSheet(sheet: $sheet)
                case .schedule(let s): ScheduleSheet(existing: s)
                case .parked(let p): ParkedSheet(item: p)
                }
            }
            .environmentObject(model)
            .environment(\.layoutDirection, .rightToLeft)
            .presentationDetents(kind.id == "menu" ? [.height(390)] : [.medium, .large])
            .presentationCornerRadius(36)
            .presentationBackground(.regularMaterial)
            .presentationDragIndicator(.visible)
        }
        .onChange(of: phase) { _, p in
            if p == .active { model.start() } else { model.stop() }
        }
        .onAppear { model.start() }
    }

    var showBar: Bool { model.connection == .ok || (model.connection == .connecting && model.snapshot != nil) }
}

/// Black (or light grey) page with a soft copper glow, like Breeze's tinted background.
struct Backdrop: View {
    var on: Bool
    var body: some View {
        ZStack {
            Theme.bg
            RadialGradient(colors: [Theme.accentSoft, .clear], center: .init(x: 0.5, y: 0.24), startRadius: 0, endRadius: 420)
                .opacity(on ? 1 : 0.35)
            RadialGradient(colors: [Color(hex: 0xff5a28).opacity(0.08), .clear], center: .init(x: 0.85, y: 0.85), startRadius: 0, endRadius: 320)
        }
        .animation(.easeInOut(duration: 0.6), value: on)
        .ignoresSafeArea()
    }
}

// MARK: - header

struct Header: View {
    @EnvironmentObject var model: AppModel
    @Binding var sheet: ContentView.SheetKind?

    var body: some View {
        HStack(spacing: 8) {
            Text("Ember")
                .font(.system(size: 28, weight: .bold))
                .kerning(-0.8)
                .foregroundStyle(LinearGradient(colors: [Theme.fg, Theme.fg, Theme.accent], startPoint: .leading, endPoint: .trailing))
                .environment(\.layoutDirection, .leftToRight)
            Spacer()
            Button { Task { await model.refresh() } } label: {
                Circle().fill(dotColor).frame(width: 10, height: 10)
                    .shadow(color: dotColor, radius: 4)
                    .frame(width: 38, height: 38)
                    .glass(19)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(statusText)
            Button { sheet = .menu } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.muted)
                    .frame(width: 38, height: 38)
                    .glass(19)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("תפריט")
        }
    }

    var dotColor: Color {
        switch model.connection {
        case .ok: return Theme.ok
        case .connecting, .away, .notSetUp: return Theme.warn
        case .noAnswer: return Theme.bad
        }
    }
    var statusText: String {
        switch model.connection {
        case .ok: return "מחובר"
        case .connecting: return "מתחבר"
        case .away: return "מחוץ לבית"
        case .noAnswer: return "הדוד לא עונה"
        case .notSetUp: return "לא מוגדר"
        }
    }
}

// MARK: - main panel

struct MainPanel: View {
    @EnvironmentObject var model: AppModel
    @Binding var sheet: ContentView.SheetKind?
    @AppStorage("detailsOpen") private var detailsOpen = false

    var body: some View {
        VStack(spacing: 12) {
            DialView().padding(.bottom, -22)
            HStack(spacing: 10) {
                PowerButton()
                SideButton()
            }
            .fixedSize(horizontal: false, vertical: true)
            StatusChip()
            VStack(alignment: .leading, spacing: 6) {
                Text("זמן מהיר").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                Presets()
            }
            Details(open: $detailsOpen, sheet: $sheet)
        }
        .disabled(model.connection != .ok && model.snapshot == nil)
    }
}

struct PowerButton: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Button { model.powerTapped() } label: {
            HStack(spacing: 10) {
                if model.busy { ProgressView().tint(model.isOn ? Theme.fg : Theme.onAccent) }
                else { Image(systemName: "power").font(.system(size: 19, weight: .bold)) }
                Text(title).font(.system(size: 17, weight: .semibold))
            }
            .frame(maxWidth: .infinity).padding(15)
            .foregroundStyle(model.isOn ? Theme.fg : Theme.onAccent)
            .background {
                if model.isOn {
                    Capsule().fill(Theme.glass2)
                } else {
                    Capsule().fill(Theme.heat)
                        .overlay(Capsule().stroke(.white.opacity(0.45), lineWidth: 1).mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center)))
                }
            }
            .overlay { if model.isOn { Capsule().strokeBorder(Theme.glassEdge, lineWidth: 0.5) } }
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

/// Off: toggles "no timer". On: adds 15 minutes.
struct SideButton: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if model.isOn && model.unlimited {
            EmptyView()
        } else {
            let selected = !model.isOn && model.chosen == 0
            Button {
                if model.isOn { model.addTime(15) }
                else { model.chosen = model.chosen == 0 ? 45 : 0; Haptics.tap() }
            } label: {
                VStack(spacing: 2) {
                    Text(model.isOn ? "+15" : "∞").font(Theme.num(19, .regular))
                        .environment(\.layoutDirection, .leftToRight)
                        .foregroundStyle(selected ? Theme.accentInk : Theme.fg)
                    Text(model.isOn ? "עוד זמן" : "ללא טיימר").font(.system(size: 12))
                        .foregroundStyle(selected ? Theme.accentInk : Theme.muted)
                }
                .frame(width: 76).frame(maxHeight: .infinity)
                .glass(38, selected: selected)
            }
            .buttonStyle(PressStyle())
            .fixedSize(horizontal: true, vertical: false)
            .disabled(model.busy || model.connection != .ok)
        }
    }
}

struct StatusChip: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Text(text)
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(model.isOn ? Theme.accentInk : Theme.muted)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .glass(20)
    }
    var text: String {
        guard let s = model.snapshot else { return "מתחבר לדוד..." }
        if s.state.isOn { return "מחמם · \(s.state.powerWatts.formatted()) וואט" }
        if let off = Store.shared.lastOff { return "כבוי · כבה \(Fmt.ago(off, now: model.now))" }
        return "כבוי"
    }
}

struct Presets: View {
    @EnvironmentObject var model: AppModel
    static let items: [(m: Int, title: String, icon: String)] = [
        (15, "קצר", "drop"), (30, "מקלחת", "shower"), (45, "שתי מקלחות", "person.2"), (60, "אמבטיה", "bathtub"),
    ]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Self.items, id: \.m) { p in
                let selected = !model.isOn && model.chosen == p.m
                Button { model.preset(p.m) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: p.icon).font(.system(size: 19)).foregroundStyle(selected ? Theme.accentInk : Theme.muted)
                        Text(p.title).font(.system(size: 13, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                            .foregroundStyle(selected ? Theme.accentInk : Theme.fg)
                        Text("\(p.m) דק׳").font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 2)
                    .glass(22, selected: selected)
                }
                .buttonStyle(PressStyle())
            }
        }
        .disabled(model.busy || model.connection != .ok || (model.isOn && model.unlimited))
    }
}

struct Details: View {
    @EnvironmentObject var model: AppModel
    @Binding var open: Bool
    @Binding var sheet: ContentView.SheetKind?

    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.25)) { open.toggle() } } label: {
                HStack {
                    Text("פרטים ותזמונים").font(.system(size: 16))
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.isOn ? "עכשיו" : "חימום אחרון").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                        Readings()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("תזמונים").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                        ScheduleList(sheet: $sheet)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glass(26)
    }
}

struct Readings: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 8) {
            if model.isOn, let s = model.snapshot?.state {
                tile(s.powerWatts.formatted(), "וואט")
                tile(String(format: "%.1f", Double(s.powerWatts) / 220), "אמפר")
                tile(shekel(Double(s.powerWatts) * Double(model.secondsOn) / 3_600_000), "עלות")
            } else if let last = Store.shared.lastSession {
                tile("\(Int(last.minutes.rounded()))", "דקות")
                tile(String(format: "%.1f", last.kWh), "קוט״ש")
                tile(shekel(last.kWh), "עלות")
            } else {
                tile("-", "דקות"); tile("-", "קוט״ש"); tile("-", "עלות")
            }
        }
    }
    func shekel(_ kWh: Double) -> String { "₪" + String(format: "%.2f", kWh * model.config.tariff) }
    func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.num(20, .light)).lineLimit(1).minimumScaleFactor(0.7).environment(\.layoutDirection, .leftToRight)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 11)
        .glass(18)
    }
}

/// iOS settings-style grouped list of schedules.
struct ScheduleList: View {
    @EnvironmentObject var model: AppModel
    @Binding var sheet: ContentView.SheetKind?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(model.schedules) { s in
                row(time: "\(Fmt.hm(s.startMinutes)) - \(Fmt.hm(s.endMinutes))", days: Fmt.days(s.weekdays), on: true,
                    open: { sheet = .schedule(s) }, toggle: { model.park(s) })
                Divider().overlay(Theme.line)
            }
            ForEach(model.parked) { p in
                row(time: "\(Fmt.hm(p.startMinutes)) - \(Fmt.hm(p.endMinutes))", days: Fmt.days(p.weekdays) + " · מושבת", on: false,
                    open: { sheet = .parked(p) }, toggle: { model.unpark(p) })
                Divider().overlay(Theme.line)
            }
            if model.schedules.count < 8 {
                Button { sheet = .schedule(nil) } label: {
                    Text("+ תזמון חדש").font(.system(size: 15)).foregroundStyle(Theme.accentInk)
                        .frame(maxWidth: .infinity).padding(13).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .glass(20)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    func row(time: String, days: String, on: Bool, open: @escaping () -> Void, toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(time).font(Theme.num(19, .light)).environment(\.layoutDirection, .leftToRight)
                    Text(days).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(on ? 1 : 0.45)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(get: { on }, set: { _ in toggle() }))
                .labelsHidden().tint(Theme.ok)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}

// MARK: - floating bar

struct BottomBar: View {
    @EnvironmentObject var model: AppModel
    @Binding var sheet: ContentView.SheetKind?

    var body: some View {
        HStack(spacing: 6) {
            item(icon: "timer", label: "כיבוי אוטומטי", value: Fmt.hm((model.snapshot?.state.autoShutdownSeconds ?? 0) / 60)) { sheet = .autoOff }
            item(icon: "calendar", label: "תזמון הבא", value: nextText) { sheet = .schedules }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.glassEdge, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 17, y: 12)
        .frame(maxWidth: 440)
    }

    var nextText: String {
        guard let n = Store.nextRun(model.schedules, now: model.now) else { return "אין" }
        let soon = n.at.timeIntervalSince(model.now) < 86_400
        let day = Calendar.current.component(.weekday, from: n.at) - 1
        return (soon ? "" : Fmt.dayLetters[day] + " ") + Fmt.hm(n.schedule.startMinutes)
    }

    func item(icon: String, label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accentInk)
                    .frame(width: 34, height: 34)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(1)
                    Text(value).font(.system(size: 15, weight: .medium, design: .rounded)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .frame(maxWidth: .infinity)
    }
}

// MARK: - menu

struct MenuSheet: View {
    @Binding var sheet: ContentView.SheetKind?
    var body: some View {
        SheetFrame(title: "תפריט") {
            VStack(spacing: 0) {
                row("chart.bar", "צריכה וחיסכון") { go(.stats) }
                Divider().overlay(Theme.line)
                row("calendar", "תזמונים") { go(.schedules) }
                Divider().overlay(Theme.line)
                row("timer", "כיבוי אוטומטי") { go(.autoOff) }
                Divider().overlay(Theme.line)
                row("gearshape", "הגדרות") { go(.settings) }
            }
            .glass(20)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("Ember · גרסה \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
        }
    }
    /// switch sheets after this one has gone away
    func go(_ next: ContentView.SheetKind) {
        sheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { sheet = next }
    }
    func row(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Theme.accentInk).frame(width: 26)
                Text(title).font(.system(size: 16))
                Spacer()
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SchedulesSheet: View {
    @Binding var sheet: ContentView.SheetKind?
    @State private var inner: ContentView.SheetKind?
    var body: some View {
        SheetFrame(title: "תזמונים") {
            ScheduleList(sheet: $inner)
            Text("מתג כבוי משבית תזמון בלי למחוק אותו.").font(.system(size: 13)).foregroundStyle(Theme.muted)
        }
        .onChange(of: inner?.id) { _, _ in
            guard let next = inner else { return }
            inner = nil
            sheet = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { sheet = next }
        }
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
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 54, weight: .light)).foregroundStyle(Theme.muted)
            Text(title).font(.system(size: 22, weight: .bold))
            Text(text).font(.system(size: 15)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).lineSpacing(3)
            actions.padding(.top, 6)
        }
        .padding(.top, 56).padding(.horizontal, 8)
    }
}

// MARK: - shared controls

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct PrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity).padding(14)
            .foregroundStyle(Theme.onAccent)
            .background(Theme.accent, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct SecondaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity).padding(14)
            .glass(26)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
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
