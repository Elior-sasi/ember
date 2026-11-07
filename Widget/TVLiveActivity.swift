import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The TV remote on the lock screen and in the Dynamic Island.
struct TVLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TVActivityAttributes.self) { ctx in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "tv").foregroundStyle(Theme.home)
                    Text(ctx.attributes.name).font(.headline)
                    Spacer()
                    if !ctx.state.app.isEmpty { Text(ctx.state.app).font(.caption).foregroundStyle(.secondary) }
                }
                HStack(spacing: 10) {
                    key(.volumeDown, "speaker.minus.fill", "הנמכה")
                    key(.playPause, "playpause.fill", "הפעלה או השהיה")
                    key(.volumeUp, "speaker.plus.fill", "הגברה")
                    key(.mute, "speaker.slash.fill", "השתקה")
                    key(.power, "power", "כיבוי", tint: Color(red: 0.24, green: 0.55, blue: 1))
                }
            }
            .padding(14)
            .activityBackgroundTint(Color.black.opacity(0.85))
            .environment(\.layoutDirection, .rightToLeft)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "tv").foregroundStyle(Theme.home).padding(.leading, 6) }
                DynamicIslandExpandedRegion(.trailing) { Text(ctx.attributes.name).font(.caption).lineLimit(1) }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        key(.volumeDown, "speaker.minus.fill", "הנמכה")
                        key(.playPause, "playpause.fill", "הפעלה או השהיה")
                        key(.volumeUp, "speaker.plus.fill", "הגברה")
                        key(.power, "power", "כיבוי", tint: Color(red: 0.24, green: 0.55, blue: 1))
                    }
                }
            } compactLeading: {
                Image(systemName: "tv").foregroundStyle(Theme.home)
            } compactTrailing: {
                Image(systemName: "playpause.fill")
            } minimal: {
                Image(systemName: "tv").foregroundStyle(Theme.home)
            }
        }
    }

    private func key(_ k: TVKey, _ icon: String, _ label: String, tint: Color = Color.white.opacity(0.14)) -> some View {
        Button(intent: TVKeyIntent(k)) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(tint, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(label)
    }
}

/// Control Center / lock screen control: TV on or off.
@available(iOS 18.0, *)
struct TVPowerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.elior.homeon.tvpower") {
            ControlWidgetButton(action: TVPowerIntent()) {
                Label("טלוויזיה", systemImage: "tv")
            }
        }
        .displayName("טלוויזיה")
        .description("הדלקה או כיבוי של Google TV")
    }
}
