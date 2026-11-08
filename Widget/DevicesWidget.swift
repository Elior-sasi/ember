import AppIntents
import SwiftUI
import WidgetKit

/// Home screen buttons: tap a device to turn it on or off, without opening the app.
struct DevicesEntry: TimelineEntry {
    let date: Date
    let devices: [HomeDevice]
    let linked: Bool
}

struct DevicesProvider: TimelineProvider {
    func placeholder(in context: Context) -> DevicesEntry {
        DevicesEntry(date: .now, devices: [HomeDevice(id: "1", name: "מזגן", pcode: "switch", on: true),
                                           HomeDevice(id: "2", name: "טוסטר", pcode: "switch", on: false)], linked: true)
    }
    func getSnapshot(in context: Context, completion: @escaping (DevicesEntry) -> Void) {
        completion(DevicesEntry(date: .now, devices: HomeLink.widgetDevices, linked: !HomeLink.key.isEmpty))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DevicesEntry>) -> Void) {
        SharedPrefs.shared.reload()
        Task {
            let ids = HomeLink.widgetDevices.map(\.id)
            await HomeLink.refresh(ids)
            let e = DevicesEntry(date: .now, devices: HomeLink.widgetDevices, linked: !HomeLink.key.isEmpty)
            completion(Timeline(entries: [e], policy: .after(.now.addingTimeInterval(15 * 60))))
        }
    }
}

struct DevicesWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: DevicesEntry
    private let blue = Color(red: 0.24, green: 0.55, blue: 1)

    var body: some View {
        Group {
            if !entry.linked || entry.devices.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "house.fill").font(.title2).foregroundStyle(Theme.accent)
                    Text(entry.linked ? "בחר מכשירים בהגדרות HomeOn" : "פתח את HomeOn פעם אחת")
                        .font(.footnote.weight(.semibold)).multilineTextAlignment(.center)
                    if !entry.linked {
                        Text("\(Store.groupWorks ? "group" : "keychain \(SharedPrefs.accessGroup) \(SharedPrefs.status)")\n\(Store.groupInfo)")
                            .font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(6).multilineTextAlignment(.center)
                    }
                }
            } else {
                let cols = family == .systemSmall ? 2 : 3
                let limit = family == .systemSmall ? 4 : (family == .systemLarge ? 12 : 6)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: cols), spacing: 8) {
                    ForEach(entry.devices.prefix(limit)) { d in tile(d) }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .containerBackground(for: .widget) { Color.black }
    }

    private func tile(_ d: HomeDevice) -> some View {
        let on = d.on == true
        return Button(intent: DeviceToggleIntent(d.id)) {
            VStack(spacing: 4) {
                Image(systemName: d.online ? "power" : "wifi.slash")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(on ? .white : Color.white.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .background(on ? blue : Color.white.opacity(0.12), in: Circle())
                Text(d.name).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(on ? Theme.accent.opacity(0.28) : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(d.name), \(d.online ? (on ? "דולק" : "כבוי") : "מנותק")")
        .accessibilityHint(on ? "מכבה" : "מדליק")
    }
}

struct DevicesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HomeOnDevices", provider: DevicesProvider()) { e in
            DevicesWidgetView(entry: e)
        }
        .configurationDisplayName("מכשירים")
        .description("הדלקה וכיבוי בלחיצה, ישר ממסך הבית.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// The washing machine countdown on the lock screen and in the Dynamic Island.
struct WashLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WashActivityAttributes.self) { ctx in
            HStack(spacing: 12) {
                Image(systemName: ctx.state.done ? "checkmark.circle.fill" : "washer.fill")
                    .font(.title).foregroundStyle(ctx.state.done ? .green : Theme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ctx.attributes.name).font(.headline)
                    Text(ctx.state.done ? "סיימה, אפשר לפרוק" : ctx.state.phase).font(.subheadline).foregroundStyle(.secondary)
                    if !ctx.state.done {
                        ProgressView(timerInterval: ctx.state.start...ctx.state.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                            .tint(Theme.accent)
                    }
                }
                Spacer()
                if !ctx.state.done {
                    Text(timerInterval: ctx.state.start...ctx.state.end, countsDown: true)
                        .font(.title2.monospacedDigit().weight(.bold)).frame(maxWidth: 90)
                        .accessibilityLabel("זמן שנותר")
                }
            }
            .padding(14)
            .activityBackgroundTint(Color.black.opacity(0.85))
            .environment(\.layoutDirection, .rightToLeft)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "washer.fill").foregroundStyle(Theme.accent).padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if ctx.state.done { Text("סיימה").font(.headline) }
                    else { Text(timerInterval: ctx.state.start...ctx.state.end, countsDown: true).font(.headline.monospacedDigit()).frame(maxWidth: 70) }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(ctx.attributes.name) · \(ctx.state.done ? "אפשר לפרוק" : ctx.state.phase)").font(.caption)
                }
            } compactLeading: {
                Image(systemName: "washer.fill").foregroundStyle(Theme.accent)
            } compactTrailing: {
                if ctx.state.done { Image(systemName: "checkmark").foregroundStyle(.green) }
                else { Text(timerInterval: ctx.state.start...ctx.state.end, countsDown: true).monospacedDigit().frame(maxWidth: 44) }
            } minimal: {
                Image(systemName: "washer.fill").foregroundStyle(Theme.accent)
            }
        }
    }
}
