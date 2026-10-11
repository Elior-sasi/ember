import SwiftUI

/// The big ring. Off: drag to choose minutes (5-150, or no timer).
/// On: shows time left (or time on, for runs without a timer).
struct DialView: View {
    @EnvironmentObject var model: AppModel
    static let minM = 5, maxM = 150
    private let sweep = 0.75            // 270 degrees of the circle
    private let startAngle = 135.0      // bottom-left, clockwise

    var fraction: Double {
        if model.isOn { return Double(model.secondsLeft) / Double(model.totalSeconds) }
        if model.chosen == 0 { return 1 }
        return Double(model.chosen - Self.minM) / Double(Self.maxM - Self.minM)
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let lineW: CGFloat = 14
            let r = size / 2 - 30
            ZStack {
                RadialGradient(colors: [Theme.accent2.opacity(model.isOn ? 0.25 : 0), .clear], center: .center, startRadius: 0, endRadius: size * 0.42)
                    .animation(.easeInOut(duration: 0.6), value: model.isOn)
                ticks(r: r)
                Circle().trim(from: 0, to: sweep)
                    .stroke(Theme.line, style: StrokeStyle(lineWidth: lineW, lineCap: .round))
                    .rotationEffect(.degrees(startAngle))
                    .frame(width: r * 2, height: r * 2)
                Circle().trim(from: 0, to: sweep * max(0.004, min(1, fraction)))
                    .stroke(AngularGradient(colors: [Color(hex: 0xffb36b), Theme.accent2], center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(270)),
                            style: StrokeStyle(lineWidth: lineW, lineCap: .round))
                    .rotationEffect(.degrees(startAngle))
                    .frame(width: r * 2, height: r * 2)
                    .animation(.easeOut(duration: 0.25), value: fraction)
                if !model.isOn && model.chosen != 0 {
                    knob(r: r)
                }
                center
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
        .frame(maxWidth: 330)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement()
        .accessibilityLabel(model.isOn ? "נשארו \(model.secondsLeft / 60) דקות" : "זמן חימום \(model.chosen) דקות")
        .accessibilityAdjustableAction { dir in
            guard !model.isOn else { return }
            switch dir {
            case .increment: model.chosen = min(Self.maxM, max(Self.minM, model.chosen) + 5)
            case .decrement: model.chosen = max(Self.minM, model.chosen - 5)
            @unknown default: break
            }
        }
    }

    private var center: some View {
        VStack(spacing: 4) {
            Text(topLabel).font(.system(size: 14, weight: .medium)).foregroundStyle(model.isOn ? Theme.accent : Theme.muted)
            Text(bigText).font(Theme.num(model.isOn ? 64 : 76)).foregroundStyle(Theme.fg)
                .contentTransition(.numericText())
            Text(bottomLabel).font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .environment(\.layoutDirection, .rightToLeft)
        .multilineTextAlignment(.center)
    }

    private var topLabel: String {
        if model.isOn { return model.unlimited ? "ללא טיימר · דולק" : "נשאר" }
        return model.chosen == 0 ? "ללא טיימר" : "זמן חימום"
    }
    private var bigText: String {
        if model.isOn { return Fmt.clock(model.unlimited ? model.secondsOn : model.secondsLeft) }
        return model.chosen == 0 ? "∞" : "\(model.chosen)"
    }
    private var bottomLabel: String {
        if model.isOn {
            return model.unlimited ? "כיבוי אוטומטי בעוד \(Fmt.hm(model.secondsLeft / 60))" : "מחמם כבר \(model.secondsOn / 60) דק׳"
        }
        if model.chosen == 0 {
            let auto = (model.snapshot?.state.autoShutdownSeconds ?? 7200) / 60
            return "ייכבה אוטומטית אחרי \(Fmt.hm(auto)) שע׳"
        }
        return "דקות · גרור כדי לשנות"
    }

    private func knob(r: CGFloat) -> some View {
        let a = (startAngle + 270 * max(0.004, fraction)) * .pi / 180
        return Circle().fill(Theme.fg)
            .overlay(Circle().stroke(Theme.accent, lineWidth: 4))
            .frame(width: 24, height: 24)
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
                ctx.stroke(p, with: .color(Theme.muted.opacity(0.3)), lineWidth: 2)
            }
        }
    }

    private func choose(at p: CGPoint, size: CGFloat) {
        let dx = p.x - size / 2, dy = p.y - size / 2
        var deg = Double(atan2(dy, dx)) * 180 / .pi - startAngle
        while deg < 0 { deg += 360 }
        while deg >= 360 { deg -= 360 }
        if deg > 270 { deg = deg > 315 ? 0 : 270 }
        let raw = Double(Self.minM) + Double(Self.maxM - Self.minM) * deg / 270
        let m = Int((raw / 5).rounded()) * 5
        if m != model.chosen {
            model.chosen = m
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}
