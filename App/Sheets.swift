import SwiftUI
import SwitcherKit

struct SheetFrame<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(.system(size: 19, weight: .bold))
                content
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Theme.fg)
    }
}

// MARK: - auto shutdown

struct AutoOffSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var minutes = 120.0

    var body: some View {
        SheetFrame(title: "כיבוי אוטומטי") {
            Text("אם הדוד נשאר דולק בלי טיימר, הוא ייכבה לבד אחרי:").foregroundStyle(Theme.muted)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(Fmt.hm(Int(minutes))).font(Theme.num(46, .light))
                Text("שעות").foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
            Slider(value: $minutes, in: 60...1410, step: 30).tint(Theme.accent)
                .environment(\.layoutDirection, .leftToRight)
            HStack(spacing: 8) {
                Button("ביטול") { dismiss() }.buttonStyle(SecondaryStyle())
                Button("שמור") { model.setAutoShutdown(Int(minutes)); dismiss() }.buttonStyle(PrimaryStyle())
            }
        }
        .onAppear {
            let cur = (model.snapshot?.state.autoShutdownSeconds ?? 7200) / 60
            minutes = Double(min(max(cur, 60), 1410))
        }
    }
}

// MARK: - schedules

struct ScheduleEditor: View {
    @Binding var start: Date
    @Binding var end: Date
    @Binding var days: Set<Int>

    var body: some View {
        HStack(spacing: 10) {
            timeBox("מ-", $start)
            timeBox("עד", $end)
        }
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                let on = days.contains(i)
                Button {
                    if on { days.remove(i) } else { days.insert(i) }
                    Haptics.tap()
                } label: {
                    Text(Fmt.dayLetters[i]).font(.system(size: 14))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .foregroundStyle(on ? Theme.accent : Theme.fg)
                        .background(on ? Theme.accent.opacity(0.14) : Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Theme.accent : Theme.line))
                }
                .buttonStyle(.plain)
            }
        }
        Text("בלי ימים מסומנים, התזמון ירוץ פעם אחת.").font(.system(size: 13)).foregroundStyle(Theme.muted)
    }

    func timeBox(_ label: String, _ value: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.muted)
            DatePicker("", selection: value, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "he_IL"))
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
        }
    }

    static func date(_ minutes: Int) -> Date {
        Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(minutes * 60))
    }
    static func minutes(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

struct ScheduleSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let existing: HeaterSchedule?
    @State private var start = ScheduleEditor.date(390)
    @State private var end = ScheduleEditor.date(435)
    @State private var days: Set<Int> = [0, 1, 2, 3, 4]
    @State private var confirmDelete = false

    var body: some View {
        SheetFrame(title: existing == nil ? "תזמון חדש" : "עריכת תזמון") {
            ScheduleEditor(start: $start, end: $end, days: $days)
            HStack(spacing: 8) {
                Button("ביטול") { dismiss() }.buttonStyle(SecondaryStyle())
                Button("שמור") {
                    model.saveSchedule(replacing: existing?.slot, days: days,
                                       start: ScheduleEditor.minutes(start), end: ScheduleEditor.minutes(end))
                    dismiss()
                }
                .buttonStyle(PrimaryStyle())
            }
            if let existing {
                Button(confirmDelete ? "לחץ שוב כדי למחוק" : "מחק תזמון") {
                    if confirmDelete { model.deleteSchedule(existing); dismiss() } else { confirmDelete = true }
                }
                .foregroundStyle(Theme.bad).frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if let e = existing {
                start = ScheduleEditor.date(e.startMinutes); end = ScheduleEditor.date(e.endMinutes)
                days = WeekdayBits.indices(e.weekdays)
            }
        }
    }
}

/// A switched-off schedule lives only in the app, so editing it just changes the app's copy.
struct ParkedSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let item: ParkedSchedule
    @State private var start = Date()
    @State private var end = Date()
    @State private var days: Set<Int> = []

    var body: some View {
        SheetFrame(title: "תזמון מושבת") {
            ScheduleEditor(start: $start, end: $end, days: $days)
            HStack(spacing: 8) {
                Button("מחק") { model.deleteParked(item); dismiss() }.buttonStyle(SecondaryStyle())
                Button("שמור והפעל") {
                    var p = item
                    p.weekdays = WeekdayBits.mask(days)
                    p.startMinutes = ScheduleEditor.minutes(start); p.endMinutes = ScheduleEditor.minutes(end)
                    model.unpark(p)
                    dismiss()
                }
                .buttonStyle(PrimaryStyle())
            }
        }
        .onAppear {
            start = ScheduleEditor.date(item.startMinutes); end = ScheduleEditor.date(item.endMinutes)
            days = WeekdayBits.indices(item.weekdays)
        }
    }
}

// MARK: - settings

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var draft = HeaterConfig()
    @State private var tariff = ""
    @State private var testing = false
    @State private var error: String?
    @State private var searching = false

    var body: some View {
        SheetFrame(title: "הגדרות") {
            Field(label: "שם", text: $draft.name, ltr: false)
            Field(label: "כתובת IP של הדוד", text: $draft.host, placeholder: "192.168.1.37", keyboard: .decimalPad)
            Field(label: "מזהה מכשיר", text: $draft.deviceID, placeholder: "a1b2c3", keyboard: .asciiCapable)
            Field(label: "מפתח (נמצא אוטומטית)", text: $draft.deviceKey, placeholder: "1a", keyboard: .asciiCapable)
            Button(searching ? "מחפש..." : "חפש את הדוד ברשת") { search() }
                .buttonStyle(SecondaryStyle()).disabled(searching)
            Hint()
            Field(label: "תעריף חשמל (₪ לקוט״ש)", text: $tariff, placeholder: "0.64", keyboard: .decimalPad)
            VStack(alignment: .leading, spacing: 6) {
                Text("כפתור הווידג׳ט מדליק ל-").font(.system(size: 13)).foregroundStyle(Theme.muted)
                Picker("", selection: $draft.widgetMinutes) {
                    ForEach([15, 30, 45, 60], id: \.self) { Text("\($0) דק׳").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if let error { Text(error).font(.system(size: 14)).foregroundStyle(Theme.bad) }
            HStack(spacing: 8) {
                Button("ביטול") { dismiss() }.buttonStyle(SecondaryStyle())
                Button(testing ? "בודק..." : "שמור") { save() }.buttonStyle(PrimaryStyle()).disabled(testing)
            }
        }
        .onAppear {
            draft = model.config
            tariff = String(format: "%.2f", model.config.tariff)
        }
    }

    private func search() {
        searching = true; error = nil
        Task {
            let found = await SwitcherListener.discover(seconds: 8)
            searching = false
            if let h = found.first {
                draft.host = h.ip; draft.deviceID = h.deviceID; draft.deviceKey = h.deviceKey
            } else {
                error = "לא נמצא דוד אוטומטית. אפשר להזין את הפרטים ידנית."
            }
        }
    }

    private func save() {
        error = nil
        var c = draft
        c.host = c.host.trimmingCharacters(in: .whitespaces)
        c.deviceID = c.deviceID.trimmingCharacters(in: .whitespaces).lowercased()
        c.deviceKey = c.deviceKey.trimmingCharacters(in: .whitespaces).lowercased()
        if c.name.trimmingCharacters(in: .whitespaces).isEmpty { c.name = "דוד" }
        if let t = Double(tariff.replacingOccurrences(of: ",", with: ".")), t > 0, t < 10 { c.tariff = t }
        let changedDevice = c.host != model.config.host || c.deviceID != model.config.deviceID || c.deviceKey != model.config.deviceKey
        guard changedDevice else { model.saveConfig(c); dismiss(); return }
        testing = true
        Task {
            defer { testing = false }
            if c.deviceKey.count != 2 {
                guard let k = await SwitcherClient.findKey(host: c.host, deviceID: c.deviceID) else {
                    error = "הדוד לא ענה בכתובת הזו."; return
                }
                c.deviceKey = k
            } else if (try? await c.client.state()) == nil {
                // maybe the key was wrong; try to find it
                guard let k = await SwitcherClient.findKey(host: c.host, deviceID: c.deviceID) else {
                    error = "הדוד לא ענה בכתובת הזו."; return
                }
                c.deviceKey = k
            }
            model.saveConfig(c)
            dismiss()
        }
    }
}
