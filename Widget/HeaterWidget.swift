import WidgetKit
import SwiftUI
import AppIntents
import SwitcherKit

struct HeaterEntry: TimelineEntry {
    let date: Date
    let name: String
    let isOn: Bool
    let endsAt: Date?
    let startedAt: Date?
    let unlimited: Bool
    let widgetMinutes: Int
    let next: (schedule: HeaterSchedule, at: Date)?
    let configured: Bool
}

struct HeaterProvider: TimelineProvider {
    func placeholder(in context: Context) -> HeaterEntry {
        HeaterEntry(date: Date(), name: "דוד", isOn: true, endsAt: Date().addingTimeInterval(1800), startedAt: Date().addingTimeInterval(-600),
                    unlimited: false, widgetMinutes: 30, next: nil, configured: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (HeaterEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HeaterEntry>) -> Void) {
        let now = Date()
        var entries = [entry(at: now)]
        var refresh = now.addingTimeInterval(15 * 60)
        // when a run ends, show it as off without waiting for the app
        if let end = Store.shared.snapshot?.endsAt, end > now {
            entries.append(entry(at: end.addingTimeInterval(1)))
            refresh = min(refresh, end.addingTimeInterval(2))
        }
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    private func entry(at date: Date) -> HeaterEntry {
        let store = Store.shared
        let snap = store.snapshot
        let stillOn = (snap?.endsAt).map { $0 > date } ?? false
        return HeaterEntry(date: date, name: store.config.name, isOn: stillOn,
                           endsAt: stillOn ? snap?.endsAt : nil, startedAt: stillOn ? snap?.startedAt : nil,
                           unlimited: store.unlimitedRun, widgetMinutes: store.config.widgetMinutes,
                           next: Store.nextRun(store.cachedSchedules, now: date), configured: store.config.isComplete)
    }
}

struct HeaterWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: HeaterEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            default: small
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .containerBackground(for: .widget) { Theme.surface2 }
    }

    // MARK: home screen

    var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(entry.name).font(.system(size: 14, weight: .semibold))
                Spacer()
                Image(systemName: "flame.fill").foregroundStyle(entry.isOn ? Theme.accent : Theme.muted).font(.system(size: 13))
            }
            Text(entry.isOn ? (entry.unlimited ? "דולק ללא טיימר" : "נשאר") : "כבוי")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            Spacer(minLength: 2)
            bigNumber.font(Theme.num(30, .light)).foregroundStyle(entry.isOn ? Theme.accent : Theme.fg)
            Spacer(minLength: 4)
            toggleButton
        }
        .foregroundStyle(Theme.fg)
    }

    var medium: some View {
        HStack(spacing: 14) {
            small
            VStack(alignment: .leading, spacing: 8) {
                if entry.isOn, !entry.unlimited, let end = entry.endsAt {
                    Text("נכבה ב-\(Fmt.time(end))").font(.system(size: 13)).foregroundStyle(Theme.muted)
                    Button(intent: AddHeaterTimeIntent(minutes: 15)) {
                        Text("+15 דק׳").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                } else {
                    Text("תזמון הבא").font(.system(size: 13)).foregroundStyle(Theme.muted)
                    if let n = entry.next {
                        Text(Fmt.hm(n.schedule.startMinutes)).font(Theme.num(26, .light))
                        Text("\(Fmt.days(n.schedule.weekdays)) · עד \(Fmt.hm(n.schedule.endMinutes))").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    } else {
                        Text("אין").font(Theme.num(26, .light))
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Theme.fg)
    }

    @ViewBuilder var bigNumber: some View {
        if entry.isOn, let end = entry.endsAt {
            if entry.unlimited, let start = entry.startedAt {
                Text(start, style: .timer).environment(\.layoutDirection, .leftToRight)
            } else {
                Text(timerInterval: entry.date...max(end, entry.date), countsDown: true).environment(\.layoutDirection, .leftToRight)
            }
        } else {
            Text("\(entry.widgetMinutes)").environment(\.layoutDirection, .leftToRight)
        }
    }

    @ViewBuilder var toggleButton: some View {
        if entry.configured {
            Button(intent: ToggleHeaterIntent()) {
                Text(entry.isOn ? "כבה" : "הדלק ל-\(entry.widgetMinutes)")
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .foregroundStyle(entry.isOn ? Theme.fg : Theme.onAccent)
                    .background(entry.isOn ? AnyShapeStyle(Theme.surface) : AnyShapeStyle(Theme.heat), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        } else {
            Text("פתח את האפליקציה כדי להגדיר").font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
    }

    // MARK: lock screen

    var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.isOn, let end = entry.endsAt, let start = entry.startedAt {
                ProgressView(timerInterval: min(start, end)...end, countsDown: true) {
                    Image(systemName: "flame.fill")
                } currentValueLabel: {
                    Image(systemName: "flame.fill")
                }
                .progressViewStyle(.circular)
            } else {
                Image(systemName: "flame").font(.system(size: 20))
            }
        }
    }

    var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(entry.name, systemImage: entry.isOn ? "flame.fill" : "flame").font(.system(size: 13, weight: .semibold))
            if entry.isOn, let end = entry.endsAt {
                Text(timerInterval: entry.date...max(end, entry.date), countsDown: true).font(Theme.num(20, .regular))
                    .environment(\.layoutDirection, .leftToRight)
            } else if let n = entry.next {
                Text("כבוי · הבא ב-\(Fmt.hm(n.schedule.startMinutes))").font(.system(size: 13))
            } else {
                Text("כבוי").font(.system(size: 13))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HeaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HeaterWidget", provider: HeaterProvider()) { entry in
            HeaterWidgetView(entry: entry)
        }
        .configurationDisplayName("דוד")
        .description("מצב הדוד, והדלקה או כיבוי בלחיצה.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
