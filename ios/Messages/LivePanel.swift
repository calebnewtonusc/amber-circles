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

    private var key: String { buildKey ?? slug ?? "__new" }
    private var building: Bool { store.changing[key] != nil }
    private var liveHTML: String? { store.liveHTML[key] }

    var body: some View {
        ZStack(alignment: .top) {
            // Always loaded, hidden by the button's own shape until it grows
            // (Caleb: "the back layer should already be loaded but hidden"),
            // so opening is a reveal, never a wait.
            WebFrame(url: building ? nil : slug.flatMap { store.openURL($0, draft: store.tool($0)?.has_draft == true) },
                     html: building ? liveHTML : nil)
                .id(slug.map { "\($0)-\(store.tool($0)?.version ?? 0)-\(store.tool($0)?.has_draft == true)" } ?? "new")
                .frame(height: height)
                .opacity(expanded ? 1 : 0.001)
                .allowsHitTesting(expanded)
            // Collapsed it is a button that says what is happening; opened,
            // the header gets out of the way and only a small X is left in the
            // corner (Caleb: "there should just be the little X in the corner").
            if expanded {
                HStack(spacing: 8) {
                    if building {
                        Text(status).font(Amber.font(13, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 10).frame(height: 30)
                            .background(Capsule().fill(Amber.amber))
                            .transition(.opacity)
                    }
                    Spacer()
                    if let slug, !building {
                        cornerButton("safari", label: "Open in Safari") {
                            if let url = store.openURL(slug, draft: store.tool(slug)?.has_draft == true) { store.host?.openInRealSafari(url) }
                        }
                    }
                    cornerButton("xmark", label: "Close preview") { close() }
                }
                .padding(10)
            } else {
                header
            }
        }
        .frame(height: expanded ? height : 60, alignment: .top)
        .background(RoundedRectangle(cornerRadius: expanded ? 20 : 30, style: .continuous).fill(Amber.sheet))
        .clipShape(RoundedRectangle(cornerRadius: expanded ? 20 : 30, style: .continuous))
        .overlay(edge)
        .shadow(color: (building ? Amber.amber : Color.black).opacity(building ? 0.18 : 0.06), radius: building ? 18 : 12, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { if !expanded { open() } }
        .animation(.spring(response: 0.55, dampingFraction: 0.86, blendDuration: 0.2), value: expanded)
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
            VStack(alignment: .leading, spacing: 1) {
                Text("Preview").font(Amber.font(17, .heavy)).foregroundStyle(Amber.ink)
                Text(status).font(Amber.font(14)).foregroundStyle(building ? Amber.link : Amber.muted)
                    .lineLimit(1).contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: status)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.down").font(.system(size: 14, weight: .bold)).foregroundStyle(Amber.muted)
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

    final class Coordinator { var lastLength = 0; var loadedURL: URL? }

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

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.isOpaque = false
        view.backgroundColor = UIColor(Amber.paper)
        view.scrollView.contentInsetAdjustmentBehavior = .never
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        if let html {
            guard html.count - context.coordinator.lastLength > 600 || context.coordinator.lastLength == 0 else { return }
            context.coordinator.lastLength = html.count
            view.loadHTMLString(Self.previewBridge + html, baseURL: API.base)
        } else if let url, url != context.coordinator.loadedURL {
            context.coordinator.loadedURL = url
            view.load(URLRequest(url: url))
        }
    }
}
