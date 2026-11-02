import SwiftUI
import WebKit
import UIKit

/// HomeOn as an installed app: the HomeOn web app in a full-screen web view, plus the native parts
/// a web page can't do - the water heater (Switcher, home WiFi) and the router (Xiaomi, home WiFi).
struct HomeOnRoot: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var phase
    @State private var splash = true
    /// When the person actually sees the app. iOS may start ("prewarm") the app long before that,
    /// so the splash clock starts at the first time the app becomes active, not at launch.
    @State private var shownAt: Date?
    var body: some View {
        ZStack {
            HomeOnWebView()
                .ignoresSafeArea()
                .background(Color.black)
            if splash {
                SplashView(active: shownAt != nil)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear { if phase == .active { shown() } }
        .onChange(of: phase) { _, p in if p == .active { shown() } }
        .onChange(of: model.webReady) { _, ready in if ready { hideWhenSeen() } }
        .fullScreenCover(isPresented: $model.showHeater) {
                ContentView()
                    .environmentObject(model)
                    .environment(\.layoutDirection, .rightToLeft)
                    .environment(\.locale, Locale(identifier: "he_IL"))
                    .tint(Theme.accent)
            }
            .fullScreenCover(isPresented: $model.showRouter) {
                RouterScreen().environmentObject(model)
            }
    }

    private func shown() {
        guard shownAt == nil else { return }
        shownAt = Date()
        if model.webReady { hideWhenSeen() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) {   // never stay stuck on the splash
            withAnimation(.easeOut(duration: 0.45)) { splash = false }
        }
    }
    private func hideWhenSeen() {
        guard let t = shownAt else { return }   // not seen yet: shown() will call again
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, 2.6 - Date().timeIntervalSince(t))) {
            withAnimation(.easeOut(duration: 0.45)) { splash = false }
        }
    }
}

/// Starts exactly like the system launch screen (the house on black), then comes alive:
/// the roof settles, two tiles light up, the signal waves pulse, and the name appears while HomeOn loads.
struct SplashView: View {
    /// true once the app is really on screen
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var calm
    @State private var played = false
    @State private var roof = false
    @State private var tile1 = false
    @State private var tile2 = false
    @State private var wave1 = false
    @State private var wave2 = false
    @State private var name = false
    @State private var pulse = false

    private let blue = Color(red: 0.353, green: 0.627, blue: 1)
    private let orange = Color(red: 1, green: 0.541, blue: 0.2)
    private let gold = Color(red: 1, green: 0.765, blue: 0.353)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // the logo sits exactly in the middle, like the system launch screen; the name hangs below it
            ZStack {
                                        // two soft glows, blue and orange, each lighting up with its tile
                    Circle().fill(RadialGradient(colors: [Color(red: 0.24, green: 0.545, blue: 1).opacity(0.26), .clear], center: .center, startRadius: 0, endRadius: 85))
                        .frame(width: 180, height: 180).offset(x: -26, y: 6)
                        .opacity(tile1 ? 1 : 0)
                    Circle().fill(RadialGradient(colors: [orange.opacity(0.26), .clear], center: .center, startRadius: 0, endRadius: 85))
                        .frame(width: 180, height: 180).offset(x: 26, y: 20)
                        .opacity(tile2 ? 1 : 0)
                    Image("LaunchLogo").resizable().frame(width: 120, height: 120)
                        .scaleEffect(x: 1, y: roof ? 1 : 0.97, anchor: .bottom)
                    GeometryReader { g in
                        let k = g.size.width / 512
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 16 * k).fill(blue)
                                .frame(width: 80 * k, height: 64 * k).offset(x: 166 * k, y: 264 * k)
                                .opacity(tile1 ? 1 : 0).shadow(color: blue.opacity(0.8), radius: tile1 ? 6 : 0)
                            RoundedRectangle(cornerRadius: 16 * k).fill(orange)
                                .frame(width: 80 * k, height: 62 * k).offset(x: 266 * k, y: 342 * k)
                                .opacity(tile2 ? 1 : 0).shadow(color: orange.opacity(0.8), radius: tile2 ? 6 : 0)
                            Wave(r: 58 * k, cx: 368 * k, cy: 162 * k).stroke(LinearGradient(colors: [gold, orange], startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: 26 * k, lineCap: .round))
                                .opacity(wave1 ? (pulse ? 0.55 : 1) : 0)
                            Wave(r: 112 * k, cx: 368 * k, cy: 162 * k).stroke(LinearGradient(colors: [gold, orange], startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: 26 * k, lineCap: .round))
                                .opacity(wave2 ? (pulse ? 1 : 0.55) : 0)
                        }
                    }
                    .frame(width: 120, height: 120)
                }
                // the logo is a picture, not text: never mirror it for Hebrew
                .environment(\.layoutDirection, .leftToRight)
            Text("HomeOn")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(name ? 1 : 0)
                    .offset(y: 60 + 18 + 20 + (name || calm ? 0 : 8))
        }
        .accessibilityHidden(true)
        .onAppear { if active { play() } }
        .onChange(of: active) { _, a in if a { play() } }
    }

    private func play() {
        guard !played else { return }
        played = true
        if calm { roof = true; tile1 = true; tile2 = true; wave1 = true; wave2 = true; name = true; return }
        // starts a moment after launch, so the system launch screen has gone and the whole show is seen
        let t0 = 0.3
        withAnimation(.spring(response: 0.45, dampingFraction: 0.45).delay(t0)) { roof = true }
        withAnimation(.easeOut(duration: 0.35).delay(t0 + 0.35)) { tile1 = true }
        withAnimation(.easeOut(duration: 0.35).delay(t0 + 0.65)) { tile2 = true }
        withAnimation(.easeOut(duration: 0.3).delay(t0 + 0.95)) { wave1 = true }
        withAnimation(.easeOut(duration: 0.3).delay(t0 + 1.2)) { wave2 = true }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(t0 + 1.4)) { name = true }
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true).delay(t0 + 1.5)) { pulse = true }
    }
}

/// A quarter circle from the top to the right, like the logo's signal waves.
struct Wave: Shape {
    var r: CGFloat, cx: CGFloat, cy: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        return p
    }
}

struct HomeOnWebView: UIViewRepresentable {
    @EnvironmentObject var model: AppModel
    static let home = URL(string: "https://elior-sasi.github.io/unplug/?app=1")!

    func makeCoordinator() -> Coordinator { Coordinator(model) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let ucc = cfg.userContentController
        ucc.addUserScript(WKUserScript(source: "window.HOMEON_APP=true;document.documentElement.classList.add(\"in-app\");", injectionTime: .atDocumentStart, forMainFrameOnly: false))
        ucc.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "homeon")

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.backgroundColor = .black
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.scrollView.bounces = false
        wv.allowsBackForwardNavigationGestures = false
        wv.allowsLinkPreview = false
        wv.customUserAgent = (wv.value(forKey: "userAgent") as? String ?? "") + " HomeOnApp/1"
        if #available(iOS 16.4, *) { wv.isInspectable = true }
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        context.coordinator.web = wv
        TVRemote.shared.onEvent = { [weak wv] json in wv?.evaluateJavaScript("window.tvEvent&&tvEvent(\(json))") }
        wv.load(URLRequest(url: Self.home, cachePolicy: .reloadRevalidatingCacheData))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate, WKUIDelegate {
        let model: AppModel
        weak var web: WKWebView?
        init(_ m: AppModel) { model = m }

        // MARK: bridge - window.webkit.messageHandlers.homeon.postMessage({action:...})
        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage,
                                   replyHandler: @escaping (Any?, String?) -> Void) {
            guard let body = message.body as? [String: Any], let action = body["action"] as? String else {
                replyHandler(nil, "bad request"); return
            }
            Task { @MainActor in
                do { replyHandler(try await self.handle(action, body), nil) }
                catch { replyHandler(nil, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription) }
            }
        }

        @MainActor private func handle(_ action: String, _ body: [String: Any]) async throws -> String {
            switch action {
            case "openHeater":
                model.showHeater = true
                return #"{"ok":true}"#
            case "openRouter":
                model.showRouter = true
                return #"{"ok":true}"#
            case "heater":   // on / off / add / toggle / state, straight to the heater on the home WiFi
                let cmd = body["cmd"] as? String ?? "state"
                let m = body["m"] as? Int ?? 0
                let s: Snapshot
                switch cmd {
                case "on": s = try await HeaterController.turnOn(minutes: m)
                case "off": s = try await HeaterController.turnOff()
                case "add": s = try await HeaterController.addTime(minutes: m == 0 ? 15 : m)
                case "toggle":
                    let now = try await HeaterController.refresh()
                    s = now.state.isOn ? try await HeaterController.turnOff() : try await HeaterController.turnOn(minutes: model.chosen)
                default: s = try await HeaterController.refresh()
                }
                model.applyExternal(s)
                return #"{"ok":true,"on":\#(s.state.isOn),"left":\#(s.state.secondsLeft)}"#
            case "tv":   // Google TV remote on the home WiFi
                let tv = TVRemote.shared
                switch body["cmd"] as? String ?? "" {
                case "discover":
                    let list = await tv.discover()
                    let data = try JSONSerialization.data(withJSONObject: ["ok": true, "tvs": list])
                    return String(data: data, encoding: .utf8) ?? "{}"
                case "pair":
                    try await tv.pairStart(host: body["host"] as? String ?? "")
                    return #"{"ok":true}"#
                case "code":
                    try await tv.pairFinish(code: body["code"] as? String ?? "")
                    return #"{"ok":true}"#
                case "key":
                    try await tv.key(body["k"] as? Int ?? 0)
                    return #"{"ok":true}"#
                case "app":
                    try await tv.app(body["url"] as? String ?? "")
                    return #"{"ok":true}"#
                case "forget":
                    tv.host = nil
                    return #"{"ok":true}"#
                case "text":
                    try await tv.text(body["text"] as? String ?? "")
                    return #"{"ok":true}"#
                case "listen":
                    TVDictation.shared.onPartial = { [weak self] t in
                        let d = (try? JSONSerialization.data(withJSONObject: ["heard": t])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                        self?.web?.evaluateJavaScript("window.tvEvent&&tvEvent(\(d))")
                    }
                    try await TVDictation.shared.start()
                    return #"{"ok":true}"#
                case "listenStop":
                    let t = await TVDictation.shared.stop()
                    let d = try JSONSerialization.data(withJSONObject: ["ok": true, "text": t])
                    return String(data: d, encoding: .utf8) ?? "{}"
                case "volkeys":
                    if body["on"] as? Bool == true { TVVolumeKeys.shared.start() } else { TVVolumeKeys.shared.stop() }
                    return #"{"ok":true}"#
                case "live":
                    await TVLive.set(body["on"] as? Bool == true, name: body["name"] as? String ?? "Google TV")
                    return #"{"ok":true,"live":\#(TVLive.isOn)}"#
                case "sleep":
                    tv.sleep(minutes: body["min"] as? Int ?? 0)
                    return tv.stateJSON
                default:
                    return await tv.state()
                }
            case "config", "geo", "activity", "notify":
                return try await HomeNative.handle(action, body) ?? "{}"
            case "haptic":
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                return #"{"ok":true}"#
            default:
                throw RouterError.bad("unknown action \(action)")
            }
        }

        // MARK: links - keep HomeOn (and Breeze inside it) here, everything else goes out
        func webView(_ webView: WKWebView, decidePolicyFor nav: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = nav.request.url else { return decisionHandler(.cancel) }
            let ours = url.host == "elior-sasi.github.io" || url.scheme == "about" || url.scheme == "blob" || url.scheme == "data"
            if ours || (nav.targetFrame != nil && !(nav.targetFrame!.isMainFrame) && (url.scheme == "https" || url.scheme == "http")) {
                return decisionHandler(.allow)
            }
            if url.scheme == "ember" {
                model.handleLink(url)
                return decisionHandler(.cancel)
            }
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for nav: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = nav.request.url { UIApplication.shared.open(url) }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.model.webReady = true }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { retry(webView) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { retry(webView) }
        private func retry(_ wv: WKWebView) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if wv.url == nil || wv.isLoading == false && (wv.title ?? "").isEmpty { wv.load(URLRequest(url: HomeOnWebView.home)) }
            }
        }

        // MARK: alert / confirm / prompt (HomeOn uses them)
        private var top: UIViewController? {
            var v = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
            while let p = v?.presentedViewController { v = p }
            return v
        }
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "אישור", style: .default) { _ in completionHandler() })
            if let t = top { t.present(a, animated: true) } else { completionHandler() }
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "ביטול", style: .cancel) { _ in completionHandler(false) })
            a.addAction(UIAlertAction(title: "אישור", style: .default) { _ in completionHandler(true) })
            if let t = top { t.present(a, animated: true) } else { completionHandler(false) }
        }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            a.addTextField { $0.text = defaultText; $0.textAlignment = .right }
            a.addAction(UIAlertAction(title: "ביטול", style: .cancel) { _ in completionHandler(nil) })
            a.addAction(UIAlertAction(title: "אישור", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
            if let t = top { t.present(a, animated: true) } else { completionHandler(nil) }
        }
        // camera/microphone for QR scan and voice commands
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(origin.host == "elior-sasi.github.io" ? .grant : .prompt)
        }
    }
}
