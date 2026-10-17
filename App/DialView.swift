import SwiftUI

/// The big ring. Off: drag (or −/+) to choose minutes, 5-150.
/// On: shows time left, or time on for runs without a timer.
struct DialView: View {
    @EnvironmentObject var model: AppModel
    var onTimerTap: () -> Void = {}
    static let minM = 5, maxM = 150
    private let sweep = 0.75            // 270 degrees of the circle
    private let startAngle = 135.0      // bottom-left, clockwise
    @State private var breathe = false

    var noTimer: Bool { model.isOn ? model.unlimited : model.chosen == 0 }

    var fraction: Double {
        if noTimer { return 1 }
        if model.isOn { return Double(model.secondsLeft) / Double(model.totalSeconds) }
        return Double(model.chosen - Self.minM) / Double(Self.maxM - Self.minM)
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let r = size / 2 - 18
            ZStack {
                RadialGradient(colors: [Theme.accentSoft, .clear], center: .center, startRadius: 0, endRadius: size * 0.5)
                    .scaleEffect(breathe && model.isOn ? 1.06 : 1)
                    .opacity(model.isOn ? (breathe ? 1 : 0.75) : 0.2)
                    .animation(model.isOn ? .easeInOut(duration: 2.25).repeatForever(autoreverses: true) : .default, value: breathe)
                ticks(r: r)
                Circle().trim(from: 0, to: sweep)
                    .stroke(Theme.track, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(startAngle))
                    .frame(width: r * 2, height: r * 2)
                Circle().trim(from: 0, to: sweep * max(0.004, min(1, fraction)))
                    .stroke(AngularGradient(colors: [Color(hex: 0xffb36b), Theme.accent2], center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(270)),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(startAngle))
                    .frame(width: r * 2, height: r * 2)
                    .opacity(model.isOn ? 1 : 0.35)
                    .animation(.easeOut(duration: 0.25), value: fraction)
                if !model.isOn && !noTimer { knob(r: r) }
                center(size: size)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                guard !model.isOn else { return }
                choose(at: g.location, size: size)
            })
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 360)
        .environment(\.layoutDirection, .leftToRight)
        .onAppear { breathe = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.isOn ? "נשארו \(model.secondsLeft / 60) דקות" : "זמן חימום \(model.chosen) דקות")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: model.nudge(5)
            case .decrement: model.nudge(-5)
            @unknown default: break
            }
        }
    }

    private func center(size: CGFloat) -> some View {
        VStack(spacing: min(6, size * 0.015)) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(bigText).font(Theme.num(min(96, size * 0.28)))
                    .kerning(-2)
                    .contentTransition(.numericText())
                if !model.isOn && !noTimer {
                    Text("דק׳").font(.system(size: min(26, size * 0.08), weight: .light)).foregroundStyle(Theme.muted)
                }
            }
            .foregroundStyle(Theme.fg)
            Text(topLabel).font(.system(size: min(15, size * 0.048), weight: .semibold))
                .foregroundStyle(model.isOn ? Theme.accentInk : Theme.muted)
            secondLine.font(.system(size: min(13.5, size * 0.042)))
            if model.isOn, let end = model.snapshot?.endsAt {
                Button { onTimerTap() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "timer").font(.system(size: min(13, size * 0.04)))
                        Text(model.unlimited ? "כיבוי אוטומטי ב-" : "נכבה ב-")
                        Text(Fmt.time(end)).fontWeight(.semibold).monospacedDigit()
                    }
                    .font(.system(size: min(13, size * 0.04)))
                    .foregroundStyle(Theme.accentInk)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.16), in: Capsule())
                }
                .buttonStyle(PressStyle())
                .padding(.top, 2)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .multilineTextAlignment(.center)
    }

    @ViewBuilder private var secondLine: some View {
        if model.isOn {
            (Text("מחמם").foregroundColor(Theme.accentInk) + Text(" · \((model.snapshot?.state.powerWatts ?? 0).formatted()) וואט").foregroundColor(Theme.fg.opacity(0.85)))
        } else if let off = Store.shared.lastOff {
            Text("כבה \(Fmt.ago(off, now: model.now))").foregroundStyle(Theme.fg.opacity(0.85))
        } else {
            Text(" ")
        }
    }

    private var topLabel: String {
        if model.isOn { return model.unlimited ? "דולק ללא טיימר" : "נשאר" }
        return "כבוי"
    }
    private var bigText: String {
        if model.isOn { return Fmt.clock(model.unlimited ? model.secondsOn : model.secondsLeft) }
        return noTimer ? "∞" : "\(model.chosen)"
    }
    private func knob(r: CGFloat) -> some View {
        let deg: Double = startAngle + 270.0 * max(0.004, fraction)
        let a = CGFloat(deg * Double.pi / 180)
        let x: CGFloat = cos(a) * r
        let y: CGFloat = sin(a) * r
        return Circle().fill(.white.opacity(model.isOn ? 1 : 0.8))
            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
            .frame(width: 26, height: 26)
            .offset(x: x, y: y)
    }

    private func ticks(r: CGFloat) -> some View {
        let start = startAngle
        return Canvas { ctx, sz in
            let cx: CGFloat = sz.width / 2
            let cy: CGFloat = sz.height / 2
            let r1: CGFloat = r - 20
            let r2: CGFloat = r - 28
            for i in stride(from: 0, through: 29, by: 2) {
                let deg: Double = start + 270.0 * Double(i) / 29.0
                let a = CGFloat(deg * Double.pi / 180)
                let ca: CGFloat = cos(a)
                let sa: CGFloat = sin(a)
                var p = Path()
                p.move(to: CGPoint(x: cx + ca * r1, y: cy + sa * r1))
                p.addLine(to: CGPoint(x: cx + ca * r2, y: cy + sa * r2))
                ctx.stroke(p, with: .color(Theme.muted.opacity(0.45)), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }

    private func choose(at p: CGPoint, size: CGFloat) {
        let dx = p.x - size / 2, dy = p.y - size / 2
        // ignore the middle of the ring, and the bottom gap where the −/+ buttons sit
        if hypot(dx, dy) < size * 0.22 { return }
        var deg: Double = Double(atan2(dy, dx)) * 180.0 / Double.pi - startAngle
        while deg < 0 { deg += 360 }
        while deg >= 360 { deg -= 360 }
        if deg > 270 { return }
        let raw = Double(Self.minM) + Double(Self.maxM - Self.minM) * deg / 270
        let m = Int((raw / 5).rounded()) * 5
        if m != model.chosen {
            model.chosen = m
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}
