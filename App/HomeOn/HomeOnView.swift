import SwiftUI
import WebKit
import UIKit

/// HomeOn as an installed app: the HomeOn web app in a full-screen web view, plus the native parts
/// a web page can't do - the water heater (Switcher, home WiFi) and the router (Xiaomi, home WiFi).
struct HomeOnRoot: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HomeOnWebView()
            .ignoresSafeArea()
            .background(Color.black)
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
        ucc.addUserScript(WKUserScript(source: "window.HOMEON_APP=true;", injectionTime: .atDocumentStart, forMainFrameOnly: false))
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
