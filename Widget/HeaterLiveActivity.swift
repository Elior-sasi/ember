import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

struct HeaterLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HeaterActivityAttributes.self) { ctx in
            LockScreenActivity(name: ctx.attributes.name, state: ctx.state)
                .activityBackgroundTint(Color(hex: 0x1c1712).opacity(0.94))
                .activitySystemActionForegroundColor(Theme.accent)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(ctx.attributes.name, systemImage: "flame.fill")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(ctx.state).font(Theme.num(26, .light)).foregroundStyle(Theme.accent)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        ProgressView(timerInterval: ctx.state.startedAt...max(ctx.state.endsAt, ctx.state.startedAt), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                            .tint(Theme.accent)
                        ActivityButtons(state: ctx.state)
                    }
                    .environment(\.layoutDirection, .rightToLeft)
                }
            } compactLeading: {
                Image(systemName: "flame.fill").foregroundStyle(Theme.accent)
            } compactTrailing: {
                countdown(ctx.state).font(Theme.num(14, .medium)).foregroundStyle(Theme.accent).frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "flame.fill").foregroundStyle(Theme.accent)
            }
            .keylineTint(Theme.accent)
        }
    }

    @ViewBuilder func countdown(_ s: HeaterActivityAttributes.ContentState) -> some View {
        if s.unlimited {
            Text(s.startedAt, style: .timer).monospacedDigit().multilineTextAlignment(.trailing)
        } else {
            Text(timerInterval: Date()...max(s.endsAt, Date()), countsDown: true).monospacedDigit().multilineTextAlignment(.trailing)
        }
    }
}

struct LockScreenActivity: View {
    let name: String
    let state: HeaterActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12).fill(Theme.heat)
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "flame.fill").foregroundStyle(Theme.onAccent))
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.unlimited ? "ה\(name) דולק ללא טיימר" : "ה\(name) דולק").font(.system(size: 15, weight: .semibold))
                    Text(state.unlimited ? "כיבוי אוטומטי ב-\(Fmt.time(state.endsAt))" : "נכבה ב-\(Fmt.time(state.endsAt))")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Group {
                    if state.unlimited { Text(state.startedAt, style: .timer) }
                    else { Text(timerInterval: Date()...max(state.endsAt, Date()), countsDown: true) }
                }
                .font(Theme.num(30, .light)).foregroundStyle(Theme.accent)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110, alignment: .trailing)
                .environment(\.layoutDirection, .leftToRight)
            }
            ProgressView(timerInterval: state.startedAt...max(state.endsAt, state.startedAt), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(Theme.accent)
            ActivityButtons(state: state)
        }
        .padding(16)
        .foregroundStyle(Theme.fg)
        .environment(\.layoutDirection, .rightToLeft)
    }
}

struct ActivityButtons: View {
    let state: HeaterActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: 8) {
            if !state.unlimited {
                Button(intent: AddHeaterTimeIntent(minutes: 15)) {
                    Text("+15 דק׳").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            Button(intent: TurnOffHeaterIntent()) {
                Text("כבה").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        .foregroundStyle(Theme.fg)
    }
}

@main
struct DudWidgets: WidgetBundle {
    var body: some Widget {
        HeaterWidget()
        HeaterLiveActivity()
    }
}
