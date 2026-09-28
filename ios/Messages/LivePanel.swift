import SwiftUI
import UIKit
import WebKit

/// The window onto the app, at the top of the conversation. Collapsed it is a
/// button that says what is being built right now; tapped, the button itself
/// grows into a window and you see through it to the live app underneath,
/// while the chat moves down below it. Caleb, 2026-09-27: "the effect of
/// seeing through one layer to another", and "the preview button at the top
/// should animate in ... like genUI ... a little close button appears at the
/// top to shrink the window back down".
struct LivePanel: View {
    @EnvironmentObject var store: ChatStore
    /// The tool being shown, or nil while a brand new one is being built.
    let slug: String?
    /// Which build this shows: a draft's key while a new app is made.
    var buildKey: String? = nil
    @Binding var expanded: Bool
    var height: CGFloat = 440
    /// The chat's pins, as the page's pin layer reads them.
    var pinsJSON: String? = nil
    var onPin: ((PinEvent) -> Void)? = nil

    private var key: String { buildKey ?? slug ?? "__new" }
    private var building: Bool { store.changing[key] != nil }
    private var liveHTML: String? { store.liveHTML[key] }

    var body: some View {
        ZStack(alignment: .top) {
            // Always loaded, hidden by the button's own shape until it grows
            // (Caleb: "the back layer should already be loaded but hidden"),
            // so opening is a reveal, never a wait.
            WebFrame(url: building ? nil : slug.flatMap { store.openURL($0, draft: store.tool($0)?.has_draft == true) },
                     html: building ? liveHTML : nil,
                     pinsJSON: building ? nil : pinsJSON,
                     onPin: building ? nil : onPin)
                .id(slug.map { "\($0)-\(store.tool($0)?.version ?? 0)-\(store.tool($0)?.has_draft == true)" } ?? "new")
                .frame(height: height)
                .allowsHitTesting(expanded)
            // Collapsed it is a button that says what is happening; opened,
            // the header gets out of the way and only a small X is left in the
            // corner (Caleb: "there should just be the little X in the corner").
            if expanded {
                HStack(spacing: 8) {

                    Spacer()
                    if let slug, !building {
                        cornerButton("safari", label: "Open in Safari") {
                            if let url = store.openURL(slug, draft: store.tool(slug)?.has_draft == true) { store.host?.openInRealSafari(url) }
                        }
                    }
                    cornerButton("xmark", label: "Close preview") { close() }
                }
                .padding(10)
                // What is being built right now sits at the bottom, so it never
                // covers the app's own title (Caleb's screenshot, 2026-09-27).
                // Hints and progress sit at the bottom, never over the app's
                // own title.
                if !building, onPin != nil {
                    VStack {
                        Spacer()
                        Text("Double tap anything to comment").font(Amber.font(13, .bold)).foregroundStyle(Amber.ink)
                            .padding(.horizontal, 12).frame(height: 30)
                            .background(Capsule().fill(.ultraThinMaterial))
                            .overlay(Capsule().strokeBorder(Amber.hairline, lineWidth: 1))
                            .padding(12)
                    }
                    .frame(height: height)
                    .allowsHitTesting(false)
                }
                if building {
                    VStack {
                        Spacer()
                        Text(status).font(Amber.font(13, .bold)).foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 12).frame(height: 30)
                            .background(Capsule().fill(Amber.amber))
                            .contentTransition(.opacity)
                            .animation(.reveal, value: status)
                            .padding(12)
                    }
                    .frame(height: height)
                    .allowsHitTesting(false)
                }
            } else {
                // Opaque, so the loaded app underneath stays hidden until the
                // mask grows; nothing about the app itself ever fades.
                header.background(Amber.sheet)
            }
        }
        .frame(height: expanded ? height : 60, alignment: .top)
        .background(RoundedRectangle(cornerRadius: expanded ? 20 : 30, style: .continuous).fill(Amber.sheet))
        .clipShape(RoundedRectangle(cornerRadius: expanded ? 20 : 30, style: .continuous))
        .overlay(edge)
        .shadow(color: Color.black.opacity(0.06), radius: 12, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { if !expanded { open() } }
        .animation(.reveal, value: expanded)
    }

    /// The boundary. While it builds, a soft amber light travels around the
    /// edge, so you can tell at a glance something is being made; when it is
    /// done it settles into a clean frame.
    @ViewBuilder
    private var edge: some View {
        let shape = RoundedRectangle(cornerRadius: expanded ? 20 : 30, style: .continuous)
        if building {
            TimelineView(.animation) { context in
                let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
                shape.strokeBorder(
                    AngularGradient(
                        colors: [Amber.amber.opacity(0.08), Amber.amber, Color(red: 1, green: 0.85, blue: 0.55), Amber.amber.opacity(0.08)],
                        center: .center, angle: .degrees(turn * 360)),
                    lineWidth: 2)
            }
        } else {
            shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Amber.wash).frame(width: 36, height: 36)
                if building {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "eye").font(.system(size: 15, weight: .semibold)).foregroundStyle(Amber.ink)
                }
            }
            Text(building ? status : "Preview").font(Amber.font(17, .heavy)).foregroundStyle(Amber.ink)
                .lineLimit(1).contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: status)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .frame(height: 60)
    }

    private func cornerButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(Amber.ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Amber.hairline, lineWidth: 1))
        }
        .accessibilityLabel(label)
    }

    private var status: String {
        if building { return store.doing[key] ?? "Starting" }
        if let slug, store.tool(slug)?.has_draft == true { return "Your change, not published yet" }
        if let slug, store.unpublished.contains(slug) { return "Only you have it until you publish" }
        return "Live for the chat"
    }

    private func open() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        store.host?.expand()
        expanded = true
    }

    private func close() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        expanded = false
    }
}

/// A web view for either a live URL or the half-written page while it is
/// being built. The half-written page is reloaded only when enough new has
/// arrived, so it grows in steps instead of flickering on every word.
struct WebFrame: UIViewRepresentable {
    let url: URL?
    var html: String? = nil
    var pinsJSON: String? = nil
    var onPin: ((PinEvent) -> Void)? = nil

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var lastLength = 0
        var loadedURL: URL?
        /// The streaming page is loaded once; after that, each new piece of
        /// the app is handed to it and eases in, instead of the whole page
        /// reloading and flashing.
        var shellReady = false
        var shellLoading = false
        var latestHTML: String?
        weak var view: WKWebView?
        /// The app's own frame, which is where the pin layer lives.
        var frame: WKFrameInfo?
        var pinsJSON: String?
        var pushed: String?
        var onPin: ((PinEvent) -> Void)?

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            if body["kind"] as? String == "ready" {
                frame = message.frameInfo
                pushed = nil
                push()
            } else if let event = PinEvent(body) {
                onPin?(event)
            }
        }

        func push() {
            guard let view, let frame, let json = pinsJSON, json != pushed else { return }
            pushed = json
            view.evaluateJavaScript("window.__amberSetPins && window.__amberSetPins(\(json))", in: frame, in: .page) { _ in }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { frame = nil }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if shellLoading { shellLoading = false; shellReady = true; stream() }
        }

        func stream() {
            guard shellReady, let view, let html = latestHTML,
                  let data = try? JSONEncoder().encode(html), let json = String(data: data, encoding: .utf8) else { return }
            view.evaluateJavaScript("window.__amberStream(\(json))") { _, _ in }
        }
    }

    /// A stand-in for Amber's data bridge (public/bridge.js), so a page that
    /// is still being written can draw its empty state instead of sitting on
    /// "Loading..." forever. It saves nothing; the real bridge takes over when
    /// the finished app opens.
    static let previewBridge = """
    <script>window.amber={me:async()=>({id:"preview",name:"You",isOwner:true}),circle:async()=>({name:"Preview"}),\
    people:async()=>[],list:async()=>[],add:async(c,d)=>({id:"p",data:d}),update:async()=>({}),remove:async()=>({}),\
    reachOut:async()=>({}),onChange:()=>{}};</script>
    """
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// The page a build streams into. It keeps what is already on screen and
    /// only adds or updates what changed, so each new piece eases in: rising,
    /// sharpening out of a blur (Caleb, 2026-09-27: "things should smoothly
    /// animate as they are added, some iron man genUI").
    static let streamShell = previewBridge + #"""
    <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
    <style id="__amberCSS"></style>
    <style>
    @keyframes __amberIn { from { opacity: 0; transform: translateY(14px) scale(.98); filter: blur(8px); } to { opacity: 1; transform: none; filter: none; } }
    .__amberNew { animation: __amberIn .6s cubic-bezier(.2,.9,.1,1) both; }
    </style></head><body></body>
    <script>
    window.__amberStream = function (src) {
      var doc = new DOMParser().parseFromString(src, 'text/html');
      document.getElementById('__amberCSS').textContent =
        Array.prototype.map.call(doc.querySelectorAll('style'), function (s) { return s.textContent; }).join(' ');
      doc.querySelectorAll('link[rel="stylesheet"]').forEach(function (l) {
        if (!document.querySelector('link[href="' + l.getAttribute('href') + '"]')) document.head.appendChild(l.cloneNode());
      });
      document.body.className = doc.body.className;
      morph(document.body, doc.body, 0);
      function morph(into, from, depth) {
        var have = into.children, want = Array.prototype.filter.call(from.children, function (c) { return c.tagName !== 'SCRIPT' && c.tagName !== 'STYLE' && c.tagName !== 'LINK'; });
        for (var i = 0; i < want.length; i++) {
          var next = want[i], now = have[i];
          if (!now || now.tagName !== next.tagName) {
            var made = document.importNode(next, true);
            made.querySelectorAll('script').forEach(function (s) { s.remove(); });
            made.classList.add('__amberNew');
                        if (now) into.replaceChild(made, now); else into.appendChild(made);
            continue;
          }
          var wasNew = now.classList.contains('__amberNew');
          Array.prototype.forEach.call(next.attributes, function (a) { now.setAttribute(a.name, a.value); });
          if (wasNew) now.classList.add('__amberNew');
          if (next.children.length === 0) { if (now.textContent !== next.textContent) now.textContent = next.textContent; }
          else morph(now, next, depth + 1);
        }
      }
    };
    </script></html>
    """#

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if onPin != nil {
            config.userContentController.add(WeakPinHandler(context.coordinator), name: "amber")
            config.userContentController.addUserScript(
                WKUserScript(source: PinScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        }
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        context.coordinator.view = view
        view.isOpaque = false
        view.backgroundColor = UIColor(Amber.paper)
        view.scrollView.contentInsetAdjustmentBehavior = .never
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onPin = onPin
        context.coordinator.pinsJSON = pinsJSON
        context.coordinator.push()
        if let html {
            let coordinator = context.coordinator
            // About a line of markup at a time: small enough that pieces
            // arrive one by one, and nothing reloads, so it costs little.
            guard html.count - coordinator.lastLength > 120 || coordinator.lastLength == 0 else { return }
            coordinator.lastLength = html.count
            coordinator.latestHTML = html
            if !coordinator.shellReady && !coordinator.shellLoading {
                coordinator.shellLoading = true
                view.loadHTMLString(Self.streamShell, baseURL: API.base)
            } else {
                coordinator.stream()
            }
        } else if let url, url != context.coordinator.loadedURL {
            context.coordinator.shellReady = false
            context.coordinator.loadedURL = url
            view.load(URLRequest(url: url))
        }
    }
}
