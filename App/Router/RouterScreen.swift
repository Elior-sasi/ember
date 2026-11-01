import SwiftUI
import WebKit

/// The Halo router screen, inside Ember. Opens from the menu or from ember://router (HomeOn's router tile).
struct RouterScreen: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        RouterWebView(onClose: { model.showRouter = false })
            .ignoresSafeArea()
            .background(Color.black)
            .environment(\.layoutDirection, .leftToRight)
    }
}

struct RouterWebView: UIViewRepresentable {
    var onClose: () -> Void

    func makeCoordinator() -> Closer { Closer(onClose) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let ucc = cfg.userContentController
        let saved = HaloStore.all()
        let json = (try? JSONSerialization.data(withJSONObject: saved)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        ucc.addUserScript(WKUserScript(source: "window.__haloStore = \(json);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // A back button in Halo's own header, so the router feels like part of the app.
        let back = """
        addEventListener('DOMContentLoaded',function(){var r=document.querySelector('header.top');if(!r)return;
        var b=document.createElement('button');b.className='menu-btn';b.setAttribute('aria-label','חזרה');
        b.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="m9 6 6 6-6 6"/></svg>';
        b.style.cssText='width:44px;height:44px;border-radius:50%;flex:none';b.onclick=function(){window.webkit.messageHandlers.emberClose.postMessage('close')};r.insertBefore(b,r.firstChild)});
        """
        ucc.addUserScript(WKUserScript(source: back, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        ucc.addScriptMessageHandler(Bridge(), contentWorld: .page, name: "halo")
        ucc.add(context.coordinator, name: "emberClose")

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.backgroundColor = .black
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.allowsBackForwardNavigationGestures = false
        if #available(iOS 16.4, *) { wv.isInspectable = true }
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "router-web") {
            wv.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Closer) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "emberClose")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "halo", contentWorld: .page)
    }

    final class Closer: NSObject, WKScriptMessageHandler {
        let onClose: () -> Void
        init(_ f: @escaping () -> Void) { onClose = f }
        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
            DispatchQueue.main.async { self.onClose() }
        }
    }
}

/// Small key-value store for the router page (nicknames, schedules...), kept in UserDefaults.
enum HaloStore {
    private static let key = "halo.store"
    static func all() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }
    static func set(_ k: String, _ v: String) {
        var d = all()
        d[k] = v
        UserDefaults.standard.set(d, forKey: key)
    }
}
