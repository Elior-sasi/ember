import SwiftUI
import SwitcherKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var phase
    @State private var sheet: SheetKind?

    enum SheetKind: Identifiable {
        case menu, stats, settings, autoOff, schedules, fault, schedule(ScheduleSheet.Source)
        var id: String {
            switch self {
            case .menu: return "menu"
            case .stats: return "stats"
            case .settings: return "settings"
            case .autoOff: return "auto"
            case .schedules: return "schedules"
            case .fault: return "fault"
            case .schedule(let src):
                switch src {
                case .new: return "new"
                case .heater(let s): return "s\(s.slot)"
                case .parked(let p): return p.id.uuidString
                }
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Backdrop(on: model.isOn)
            ScrollView {
                VStack(spacing: 12) {
                    Header(sheet: $sheet)
                    if model.connection == .noAnswer && model.snapshot != nil {
                        FaultBar { sheet = .fault }
                    }
                    switch model.connection {
                    case .notSetUp: SetupView()
                    case .away: AwayView()
                    case .noAnswer where model.snapshot == nil: NoAnswerView(openSettings: { sheet = .settings })
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
                case .schedule(let src): ScheduleSheet(source: src)
                case .fault: FaultSheet(sheet: $sheet)
                }
            }
            .environmentObject(model)
            .environment(\.layoutDirection, .rightToLeft)
            .presentationDetents(kind.id == "menu" ? [.height(520)] : kind.id == "fault" ? [.height(300)] : [.medium, .large])
            .presentationCornerRadius(36)
            .presentationBackground(.regularMaterial)
            .presentationDragIndicator(.visible)
        }
        .onChange(of: phase) { _, p in
            if p == .active { model.start() } else { model.stop() }
        }
        .onAppear { model.start() }
    }

    var showBar: Bool { model.connection == .ok || ((model.connection == .connecting || model.connection == .noAnswer) && model.snapshot != nil) }
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
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 4) {
            Text("Ember")
                .font(.system(size: 26, weight: .bold))
                .kerning(-0.8)
                .foregroundStyle(LinearGradient(colors: [Theme.fg, Theme.fg, Theme.accent], startPoint: .leading, endPoint: .trailing))
                .environment(\.layoutDirection, .leftToRight)
            Spacer()
            Button { Task { await model.refresh() } } label: {
                HStack(spacing: 7) {
                    Circle().fill(dotColor).frame(width: 10, height: 10)
                        .shadow(color: dotColor, radius: 4)
                        .opacity(model.connection == .connecting ? (pulse ? 1 : 0.35) : 1)
                        .animation(model.connection == .connecting ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: pulse)
                    if !dotOnly { Text(statusText).font(.system(size: 13)) }
                }
                .padding(.horizontal, dotOnly ? 6 : 12)
                .frame(height: 32)
                .background(dotOnly ? Color.clear : Theme.fill, in: Capsule())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(statusText)
            .onAppear { pulse = true }
            Button { sheet = .menu } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.muted)
                    .frame(width: 36, height: 36)
                    .background(Theme.fill, in: Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("תפריט")
        }
    }

    var dotOnly: Bool { model.connection == .ok || model.connection == .connecting }
    var dotColor: Color {
        switch model.connection {
        case .ok: return Theme.ok
        case .connecting: return Color(hex: 0xffcc00)
        case .away, .notSetUp: return Theme.warn
        case .noAnswer: return Theme.bad
        }
    }
    var statusText: String {
        switch model.connection {
        case .ok: return "מחובר"
        case .connecting: return "מתחבר..."
        case .away: return "מחוץ לבית"
        case .noAnswer: return "הדוד לא עונה"
        case .notSetUp: return "לא מוגדר"
        }
    }
}

struct FaultBar: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("הדוד לא עונה · לחץ לפרטים", systemImage: "exclamationmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0xff7a7a))
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(Color(red: 1, green: 0.31, blue: 0.31).opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }
}

struct FaultSheet: View {
    @EnvironmentObject var model: AppModel
    @Binding var sheet: ContentView.SheetKind?
    var body: some View {
        SheetFrame(title: "הדוד לא עונה") {
            Text("אתה מחובר ל-WiFi, אבל הדוד לא מגיב בכתובת \(model.config.host). ייתכן שהוא התנתק מה-WiFi או קיבל כתובת חדשה מהראוטר. מה שמוצג במסך הוא המצב האחרון שנקלט.")
                .font(.system(size: 14)).foregroundStyle(Theme.muted).lineSpacing(3)
            HStack(spacing: 8) {
                Button("בדוק הגדרות") { MenuSheet.switchTo(.settings, $sheet) }.buttonStyle(SecondaryStyle())
                Button("נסה שוב") { sheet = nil; Task { await model.refresh() } }.buttonStyle(PrimaryStyle())
            }
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
            DialView(onTimerTap: { sheet = .autoOff }).padding(.top, -6).padding(.bottom, -38)
            ControlRow()
            PowerButton()
            VStack(alignment: .leading, spacing: 6) {
                Text("זמן מהיר").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                Presets()
            }
            Details(open: $detailsOpen, sheet: $sheet)
        }
        .disabled(model.snapshot == nil && model.connection != .ok)
    }
}

/// Under the arc: − and + at the ends, a pill in the middle ("no timer" when off, "+15" when on).
struct ControlRow: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 8) {
            step("+", 5)
            Spacer(minLength: 0)
            if model.isOn {
                if !model.unlimited {
                    pill(selected: false) { model.addTime(15) } label: {
                        Image(systemName: "plus.circle").font(.system(size: 16))
                        Text("+15").font(.system(size: 13, weight: .medium, design: .rounded)).environment(\.layoutDirection, .leftToRight)
                        Text("דק׳").font(.system(size: 13))
                    }
                }
            } else {
                let on = model.chosen == 0
                pill(selected: on) { model.chosen = on ? 45 : 0; Haptics.tap() } label: {
                    Image(systemName: "infinity").font(.system(size: 15, weight: .semibold))
                    Text("ללא טיימר").font(.system(size: 13))
                }
            }
            Spacer(minLength: 0)
            step("−", -5)
        }
        .disabled(model.busy || model.connection != .ok)
    }

    func step(_ label: String, _ delta: Int) -> some View {
        let hidden = model.isOn ? model.unlimited : model.chosen == 0
        return Button { model.nudge(delta) } label: {
            Text(label).font(.system(size: 26, weight: .light)).foregroundStyle(Theme.fg)
                .frame(width: 52, height: 52)
                .background(Theme.fill, in: Circle())
        }
        .buttonStyle(PressStyle())
        .opacity(hidden ? 0 : 1)
        .disabled(hidden)
        .accessibilityLabel(delta > 0 ? "עוד 5 דקות" : "פחות 5 דקות")
    }

    func pill<L: View>(selected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            HStack(spacing: 6) { label() }
                .foregroundStyle(selected ? Theme.accentInk : Theme.fg)
                .padding(.leading, 10).padding(.trailing, 12).padding(.vertical, 8)
                .background(selected ? Theme.accentFill : Theme.fill, in: Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

/// Full width. Off: solid fill. On: copper, like Breeze's accent power button.
struct PowerButton: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Button { model.powerTapped() } label: {
            HStack(spacing: 10) {
                if model.busy { ProgressView().tint(model.isOn ? Theme.onAccent : Theme.fg) }
                else { Image(systemName: "power").font(.system(size: 19, weight: .bold)) }
                Text(title).font(.system(size: 17, weight: .semibold))
            }
            .frame(maxWidth: .infinity).padding(14)
            .foregroundStyle(model.isOn ? Theme.onAccent : Theme.fg)
            .background {
                if model.isOn { Capsule().fill(Theme.heat) } else { Capsule().fill(Theme.fill) }
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
                        Image(systemName: p.icon).font(.system(size: 18)).foregroundStyle(selected ? Theme.accentInk : Theme.muted)
                        Text(p.title).font(.system(size: 13, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                            .foregroundStyle(selected ? Theme.accentInk : Theme.fg)
                        Text("\(p.m) דק׳").font(.system(size: 11.5, design: .rounded)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 9).padding(.horizontal, 2)
                    .card(22, selected: selected)
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
                    Text("פרטים נוספים").font(.system(size: 16))
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
        .card(26)
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
        .padding(.horizontal, 12).padding(.vertical, 10)
        .card(16, inner: true)
    }
}

/// Breeze-style schedule rows: big time range, days below, switch on the side.
struct ScheduleList: View {
    @EnvironmentObject var model: AppModel
    @Binding var sheet: ContentView.SheetKind?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(model.schedules) { s in
                row(time: "\(Fmt.hm(s.startMinutes)) - \(Fmt.hm(s.endMinutes))", days: Fmt.days(s.weekdays), on: true,
                    open: { sheet = .schedule(.heater(s)) }, toggle: { model.park(s) })
            }
            ForEach(model.parked) { p in
                row(time: "\(Fmt.hm(p.startMinutes)) - \(Fmt.hm(p.endMinutes))", days: Fmt.days(p.weekdays) + " · מושבת", on: false,
                    open: { sheet = .schedule(.parked(p)) }, toggle: { model.unpark(p) })
            }
            if model.schedules.count < 8 {
                Button { sheet = .schedule(.new) } label: {
                    Text("+ תזמון חדש").font(.system(size: 15)).foregroundStyle(Theme.accentInk)
                        .frame(maxWidth: .infinity).padding(12)
                        .card(16, inner: true)
                }
                .buttonStyle(PressStyle())
            }
        }
    }

    func row(time: String, days: String, on: Bool, open: @escaping () -> Void, toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(time).font(.system(size: 21, design: .rounded)).monospacedDigit().environment(\.layoutDirection, .leftToRight)
                    Text(days).font(.system(size: 12.5)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(on ? 1 : 0.4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(get: { on }, set: { _ in toggle() }))
                .labelsHidden().tint(Theme.ok)
        }
        .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 10)
        .card(16, inner: true)
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
                    .frame(width: 32, height: 32)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(1)
                    Text(value).font(.system(size: 15, weight: .medium, design: .rounded)).lineLimit(1)
                        .foregroundStyle(model.isOn ? Theme.fg : Theme.muted)
                }
                Spacer(minLength: 0)
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
    @EnvironmentObject var model: AppModel
    @Binding var sheet: ContentView.SheetKind?

    var body: some View {
        SheetFrame(title: "תפריט") {
            VStack(spacing: 8) {
                row("calendar", "תזמונים", scheduleSub) { go(.schedules) }
                row("chart.bar", "צריכה וחיסכון", weekSub) { go(.stats) }
                row("timer", "כיבוי אוטומטי", "אחרי \(Fmt.hm((model.snapshot?.state.autoShutdownSeconds ?? 0) / 60)) שע׳") { go(.autoOff) }
                HStack(spacing: 12) {
                    Image(systemName: "bell").font(.system(size: 18)).foregroundStyle(Theme.accentInk).frame(width: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("התראות לטלפון").font(.system(size: 16, weight: .medium))
                        Text("כשהמים חמים").font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Toggle("", isOn: $model.notify).labelsHidden().tint(Theme.ok)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .card(16, inner: true)
                row("wifi", "החיבור", connSub) { go(.settings) }
            }
            Text("Ember \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
        }
    }

    var scheduleSub: String { model.schedules.isEmpty ? "אין" : "\(model.schedules.count) פעילים" }
    var weekSub: String {
        let since = Date().addingTimeInterval(-7 * 86_400)
        let week = Store.shared.sessions.filter { $0.end > since }
        let mins = Int(week.reduce(0) { $0 + $1.minutes })
        let cost = week.reduce(0) { $0 + $1.kWh } * model.config.tariff
        return "השבוע \(Fmt.hm(mins)) שע׳ · ₪\(Int(cost.rounded()))"
    }
    var connSub: String {
        switch model.connection {
        case .ok: return "מחובר · \(model.config.host)"
        case .connecting: return "מתחבר..."
        case .away: return "מחוץ לבית"
        case .noAnswer: return "הדוד לא עונה"
        case .notSetUp: return "לא מוגדר"
        }
    }

    func go(_ next: ContentView.SheetKind) { Self.switchTo(next, $sheet) }

    /// switch sheets after the current one has gone away
    static func switchTo(_ next: ContentView.SheetKind, _ sheet: Binding<ContentView.SheetKind?>) {
        sheet.wrappedValue = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { sheet.wrappedValue = next }
    }

    func row(_ icon: String, _ title: String, _ sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Theme.accentInk).frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 16, weight: .medium))
                    Text(sub).font(.system(size: 12.5)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .card(16, inner: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
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
            MenuSheet.switchTo(next, $sheet)
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
            .background(Theme.fill2, in: Capsule())
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
