import SwiftUI

/// The big ring. Off: drag (or −/+) to choose minutes, 5-150.
/// On: shows time left, or time on for runs without a timer.
struct DialView: View {
    @EnvironmentObject var model: AppModel
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
            let r = size / 2 - 30
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
                    .opacity(noTimer && !model.isOn ? 0.5 : 1)
                    .animation(.easeOut(duration: 0.25), value: fraction)
                if !model.isOn && !noTimer { knob(r: r) }
                center(size: size)
                if !noTimer { steps(size: size) }
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
        .frame(maxWidth: 320)
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
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(bigText).font(Theme.num(min(92, size * 0.28)))
                    .kerning(-2)
                    .contentTransition(.numericText())
                if !model.isOn && !noTimer {
                    Text("דק׳").font(.system(size: min(24, size * 0.075), weight: .light)).foregroundStyle(Theme.muted)
                }
            }
            .foregroundStyle(Theme.fg)
            Text(topLabel).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accentInk)
            Text(bottomLabel).font(.system(size: 13)).foregroundStyle(Theme.muted)
        }
        .environment(\.layoutDirection, .rightToLeft)
        .multilineTextAlignment(.center)
        .allowsHitTesting(false)
    }

    private func steps(size: CGFloat) -> some View {
        HStack {
            stepButton("−", -5)
            Spacer()
            stepButton("+", 5)
        }
        .padding(.horizontal, size * 0.02)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, size * 0.06)
    }

    private func stepButton(_ label: String, _ delta: Int) -> some View {
        Button { model.nudge(delta) } label: {
            Text(label).font(.system(size: 26, weight: .light)).foregroundStyle(Theme.fg)
                .frame(width: 50, height: 50)
                .glass(25)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(delta > 0 ? "עוד 5 דקות" : "פחות 5 דקות")
    }

    private var topLabel: String {
        if model.isOn { return model.unlimited ? "דולק ללא טיימר" : "נשאר" }
        return noTimer ? "ללא טיימר" : "זמן חימום"
    }
    private var bigText: String {
        if model.isOn { return Fmt.clock(model.unlimited ? model.secondsOn : model.secondsLeft) }
        return noTimer ? "∞" : "\(model.chosen)"
    }
    private var bottomLabel: String {
        if model.isOn, let end = model.snapshot?.endsAt {
            return (model.unlimited ? "כיבוי אוטומטי ב-" : "נכבה ב-") + Fmt.time(end)
        }
        if noTimer {
            let auto = (model.snapshot?.state.autoShutdownSeconds ?? 7200) / 60
            return "ייכבה אוטומטית אחרי \(Fmt.hm(auto)) שע׳"
        }
        return "ייכבה ב-" + Fmt.time(model.now.addingTimeInterval(TimeInterval(model.chosen * 60)))
    }

    private func knob(r: CGFloat) -> some View {
        let a = (startAngle + 270 * max(0.004, fraction)) * .pi / 180
        return Circle().fill(.white)
            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
            .frame(width: 26, height: 26)
            .offset(x: cos(a) * r, y: sin(a) * r)
    }

    private func ticks(r: CGFloat) -> some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            for i in 0...29 {
                let a = (startAngle + 270 * Double(i) / 29) * .pi / 180
                let r1 = r + 18, r2 = r + (i % 6 == 0 ? 27 : 23)
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * r1, y: c.y + sin(a) * r1))
                p.addLine(to: CGPoint(x: c.x + cos(a) * r2, y: c.y + sin(a) * r2))
                ctx.stroke(p, with: .color(Theme.muted.opacity(0.45)), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }

    private func choose(at p: CGPoint, size: CGFloat) {
        let dx = p.x - size / 2, dy = p.y - size / 2
        // ignore the middle of the ring, and the bottom gap where the −/+ buttons sit
        if hypot(dx, dy) < size * 0.22 { return }
        var deg = Double(atan2(dy, dx)) * 180 / .pi - startAngle
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
