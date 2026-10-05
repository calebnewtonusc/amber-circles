import Messages
import SwiftUI
import UIKit

final class MessagesViewController: MSMessagesAppViewController {
    private let store = ChatStore()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(Amber.paper)
        // Light always: in dark mode the text fields drew white text on the
        // white boxes (Caleb's phone, build 41).
        overrideUserInterfaceStyle = .light
        store.host = self
        let hosting = UIHostingController(rootView: RootView().environmentObject(store).environmentObject(store.together))
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        // Inside iMessage the keyboard does not reach SwiftUI's safe area, so
        // the message field sat under it (Caleb's phone, 2026-09-28). Measure
        // how much of this view the keyboard covers and lift by that.
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardMoved(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardMoved(_:)),
                                               name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardMoved(_ note: Notification) {
        var cover: CGFloat = 0
        if note.name != UIResponder.keyboardWillHideNotification,
           let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            let local = view.convert(end, from: nil)
            cover = max(0, view.bounds.maxY - local.minY - view.safeAreaInsets.bottom)
        }
        let seconds = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        withAnimation(.smooth(duration: seconds)) { store.keyboardInset = cover }
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        // Face ID on every open (Caleb: "face id each time it opens").
        // Only someone signed in has a Face ID lock; skipping sign-in means
        // there is nothing to unlock, so Amber is not left muted.
        store.unlocked = (store.personKey ?? "") == "" && store.personKey != nil
        store.expanded = presentationStyle == .expanded
        store.attach(conversation)
    }

    /// Leaving Amber clears home's chat too. iMessage can keep the extension
    /// alive and bring it back without calling willBecomeActive, so clearing
    /// only on open left the old chat up (Caleb's phone, 13:09, 2026-09-28).
    override func willResignActive(with conversation: MSConversation) {
        super.willResignActive(with: conversation)
        store.talk[""] = []
        store.speaker.stop()
    }

    override func didBecomeActive(with conversation: MSConversation) {
        super.didBecomeActive(with: conversation)
        store.talk[""] = []
    }

    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)
        store.attach(conversation)
    }

    /// Switch layouts as the sheet starts moving, on a curve close to the
    /// sheet's own, so the two travel together. Switching in didTransition
    /// waited for the sheet to finish and then snapped (Caleb, 2026-09-28).
    override func willTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.willTransition(to: presentationStyle)
        withAnimation(.smooth(duration: 0.38)) { store.expanded = presentationStyle == .expanded }
    }

    override func didTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.didTransition(to: presentationStyle)
        store.expanded = presentationStyle == .expanded
    }

    func expand() {
        if presentationStyle != .expanded { requestPresentationStyle(.expanded) }
    }

    /// An iMessage extension cannot hand a web link to Safari: iOS opens the
    /// containing app instead (Caleb's phone, build 39). So the link goes to
    /// the Amber app, which passes it straight on to Safari.
    func openInRealSafari(_ url: URL) {
        // Straight to Safari when the system lets an extension reach the
        // application object; the bounce through the Amber app below is only
        // the fallback (Caleb: "it should just go straight to safari").
        var responder: UIResponder? = self
        while let next = responder {
            if let application = next as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = next.next
        }
        var bridge = URLComponents()
        bridge.scheme = "amberapp"
        bridge.host = "open"
        bridge.queryItems = [URLQueryItem(name: "u", value: url.absoluteString)]
        if let link = bridge.url { extensionContext?.open(link) }
    }

    /// Publishing happens when the bubble is actually sent, not when it is
    /// put in the message box: until then nothing reaches the chat.
    override func didStartSending(_ message: MSMessage, conversation: MSConversation) {
        super.didStartSending(message, conversation: conversation)
        store.didSend(message.url)
    }
}

/// The picture on the bubble: the tool's name on a signage card, so a thread
/// full of them reads like a shelf of labelled folders.
enum BubbleArt {
    @MainActor
    static func render(title: String, by: String, tagline: String = "Let's build together", action: String = "Open") -> UIImage? {
        let card = VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image("AmberLogo").resizable().scaledToFit().frame(height: 30)
                Text(tagline).font(Amber.font(26, .bold)).foregroundStyle(Amber.muted)
            }
            Spacer(minLength: 0)
            Text(title).font(Amber.font(56, .heavy)).tracking(-1.6).foregroundStyle(Amber.ink)
                .lineLimit(2).minimumScaleFactor(0.6)
            HStack {
                Text("By \(by)").font(Amber.font(24)).foregroundStyle(Amber.body)
                Spacer()
                Text(action).font(Amber.font(24, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 26).padding(.vertical, 12)
                    .background(Capsule().fill(Amber.ink))
            }
        }
        .padding(40)
        .frame(width: 600, height: 400, alignment: .topLeading)
        .background(Color.white)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        return renderer.uiImage
    }
}
