import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject var model: AppModel
    @State private var range: Period = .week

    enum Period: String, CaseIterable { case day = "היום", week = "שבוע", month = "חודש" }

    struct DayTotal: Identifiable {
        let day: Date
        let minutes: Double
        let kWh: Double
        var id: Date { day }
    }

    var body: some View {
        SheetFrame(title: "צריכה") {
            Picker("", selection: $range) {
                ForEach(Period.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            let days = totals(range)
            let minutes = days.reduce(0) { $0 + $1.minutes }
            let kWh = days.reduce(0) { $0 + $1.kWh }
            HStack(spacing: 8) {
                kpi(Fmt.hm(Int(minutes.rounded())), "שעות חימום")
                kpi(String(format: "%.1f", kWh), "קוט״ש")
                kpi("₪" + String(format: "%.0f", kWh * model.config.tariff), "עלות משוערת")
            }

            if range != .day {
                Chart(days) { d in
                    BarMark(x: .value("יום", d.day, unit: .day), y: .value("דקות", d.minutes))
                        .foregroundStyle(Calendar.current.isDateInToday(d.day) ? Theme.accent : Theme.accent.opacity(0.65))
                        .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { v in
                        AxisGridLine().foregroundStyle(Theme.line)
                        AxisValueLabel().foregroundStyle(Theme.muted)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 5)) { v in
                        AxisValueLabel(format: range == .week ? .dateTime.weekday(.narrow) : .dateTime.day())
                            .foregroundStyle(Theme.muted)
                    }
                }
                .frame(height: 160)
                .environment(\.locale, Locale(identifier: "he_IL"))
                Text("דקות חימום ביום").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }

            Text("נספרים רק חימומים שהאפליקציה ראתה: כאלה שהדלקת ממנה, מהווידג׳ט או מסירי, או שהיו דולקים כשפתחת אותה. העלות לפי \(String(format: "%.2f", model.config.tariff)) ₪ לקוט״ש, ואפשר לשנות בהגדרות.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(2)
        }
    }

    func kpi(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.num(20, .light)).environment(\.layoutDirection, .leftToRight)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glass(18)
    }

    func totals(_ r: Period) -> [DayTotal] {
        let cal = Calendar.current
        let count = r == .day ? 1 : (r == .week ? 7 : 30)
        let today = cal.startOfDay(for: Date())
        var all = Store.shared.sessions
        if let open = Store.shared.openSession { all.append(open) }
        return (0..<count).reversed().map { back in
            let day = cal.date(byAdding: .day, value: -back, to: today)!
            let next = cal.date(byAdding: .day, value: 1, to: day)!
            var mins = 0.0, kwh = 0.0
            for s in all {
                // the part of each run that falls inside this day
                let a = max(s.start, day), b = min(s.end, next)
                if b > a {
                    let part = b.timeIntervalSince(a)
                    mins += part / 60
                    kwh += Double(s.watts) * part / 3_600_000
                }
            }
            return DayTotal(day: day, minutes: mins, kWh: kwh)
        }
    }
}
