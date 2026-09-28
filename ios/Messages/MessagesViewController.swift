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
        let hosting = UIHostingController(rootView: RootView().environmentObject(store))
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        // Face ID on every open (Caleb: "face id each time it opens").
        store.unlocked = false
        store.expanded = presentationStyle == .expanded
        store.attach(conversation)
    }

    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)
        store.attach(conversation)
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
    static func render(title: String, by: String) -> UIImage? {
        let card = VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image("AmberLogo").resizable().scaledToFit().frame(height: 30)
                Text("Let's build together").font(Amber.font(26, .bold)).foregroundStyle(Amber.muted)
            }
            Spacer(minLength: 0)
            Text(title).font(Amber.font(56, .heavy)).tracking(-1.6).foregroundStyle(Amber.ink)
                .lineLimit(2).minimumScaleFactor(0.6)
            HStack {
                Text("By \(by)").font(Amber.font(24)).foregroundStyle(Amber.body)
                Spacer()
                Text("Open").font(Amber.font(24, .bold)).foregroundStyle(.white)
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
