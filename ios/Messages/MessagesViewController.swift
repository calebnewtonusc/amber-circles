import Messages
import SwiftUI
import UIKit

final class MessagesViewController: MSMessagesAppViewController {
    private let store = ChatStore()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(Amber.paper)
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

    func openInSafari(_ url: URL) {
        extensionContext?.open(url)
    }
}

/// The picture on the bubble: the tool's name on a signage card, so a thread
/// full of them reads like a shelf of labelled folders.
enum BubbleArt {
    @MainActor
    static func render(title: String, by: String) -> UIImage? {
        let card = VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle().fill(Amber.amber).overlay(Circle().strokeBorder(Amber.ink, lineWidth: 3))
                    .frame(width: 28, height: 28)
                Text("Made in this chat").font(Amber.font(24, .bold)).foregroundStyle(Amber.ink)
            }
            Spacer(minLength: 0)
            Text(title).font(Amber.font(58, .heavy)).foregroundStyle(Amber.ink)
                .lineLimit(2).minimumScaleFactor(0.6)
            Text("By \(by). Tap to open it together.").font(Amber.font(24)).foregroundStyle(Amber.body)
            HStack {
                Text("Open").font(Amber.font(26, .bold)).foregroundStyle(Amber.ink)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(Amber.amber)
                    .overlay(Rectangle().strokeBorder(Amber.ink, lineWidth: 3))
            }
        }
        .padding(36)
        .frame(width: 600, height: 400, alignment: .topLeading)
        .background(Amber.paper)
        .overlay(Rectangle().strokeBorder(Amber.ink, lineWidth: 6))
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        return renderer.uiImage
    }
}
