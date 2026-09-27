import Messages
import SwiftUI

enum Route: Hashable {
    case home
    case tool(String)
}

/// One line of the conversation with a tool: what someone said, or what
/// Amber said back.
struct Turn: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let mine: Bool
}

struct BuildState: Equatable {
    var request: String
    var stage: String = "thinking"
    var detail: String = ""
    var started = Date()
}

/// One thread's state. A thread is identified the only way iMessage allows:
/// this device's participant id in it, which is stable per conversation.
@MainActor
final class ChatStore: ObservableObject {
    @Published var session: Session?
    @Published var overview: ChatOverview?
    @Published var name: String = UserDefaults.standard.string(forKey: "amber.name") ?? ""
    @Published var error: String?
    @Published var building: BuildState?
    @Published var route: Route = .home
    @Published var loading = false
    @Published var expanded = false
    /// The conversation with each tool, kept here so it survives the building
    /// screen replacing the tool's screen.
    @Published var talk: [String: [Turn]] = [:]

    weak var host: MessagesViewController?
    private var participant = ""
    private var pendingInvite: (chat: String, invite: String, slug: String?)?

    private var sessionKey: String { "amber.session.\(participant)" }

    func attach(_ conversation: MSConversation) {
        participant = conversation.localParticipantIdentifier.uuidString
        if let data = UserDefaults.standard.data(forKey: sessionKey),
           let saved = try? JSONDecoder().decode(Session.self, from: data) {
            session = saved
        } else {
            session = nil
            overview = nil
        }
        if let url = conversation.selectedMessage?.url, let link = Self.parse(url) {
            if session?.chat != link.chat {
                pendingInvite = link
            } else if let slug = link.slug {
                route = .tool(slug)
            }
        }
        Task { await joinIfNeeded(); await refresh() }
    }

    func saveName(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        name = trimmed
        UserDefaults.standard.set(trimmed, forKey: "amber.name")
        Task { await joinIfNeeded(); await refresh() }
    }

    private func store(_ value: Session) {
        session = value
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }

    /// Someone tapped a bubble from a chat this device has not joined yet.
    private func joinIfNeeded() async {
        guard let link = pendingInvite, !name.isEmpty else { return }
        pendingInvite = nil
        do {
            let joined: Joined = try await API.call(
                "api/chats/\(link.chat)/join", method: "POST",
                body: ["invite": link.invite, "name": name, "participant": participant])
            store(Session(chat: joined.chat, token: joined.token, invite: link.invite, name: name))
            if let slug = link.slug { route = .tool(slug) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refresh() async {
        guard let session else { return }
        loading = overview == nil
        defer { loading = false }
        do {
            overview = try await API.call("api/chats/\(session.chat)", chat: session.token)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func tool(_ slug: String) -> ToolItem? { overview?.tools.first { $0.slug == slug } }

    // MARK: making and changing

    func make(_ request: String) async {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        error = nil
        building = BuildState(request: text)
        do {
            if session == nil {
                let started: Joined = try await API.call(
                    "api/chats", method: "POST",
                    body: ["name": name, "participant": participant])
                store(Session(chat: started.chat, token: started.token, invite: started.invite ?? "", name: name))
            }
            guard let session else { return }
            let result = try await API.build(
                request: text, chat: session.chat, slug: nil, token: session.token
            ) { [weak self] stage, detail in
                self?.building?.stage = stage
                self?.building?.detail = detail
            }
            await refresh()
            building = nil
            route = .tool(result.slug)
            if let made = tool(result.slug) { send(made, note: "I made this for us. Tap to open it.") }
        } catch {
            building = nil
            self.error = error.localizedDescription
        }
    }

    func change(_ slug: String, _ request: String) async {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let session, !text.isEmpty else { return }
        error = nil
        building = BuildState(request: text)
        do {
            _ = try await API.build(request: text, chat: session.chat, slug: slug, token: session.token) {
                [weak self] stage, detail in
                self?.building?.stage = stage
                self?.building?.detail = detail
            }
            await refresh()
            building = nil
        } catch {
            building = nil
            self.error = error.localizedDescription
        }
    }

    /// Say something to a tool. A question is answered; a change is built,
    /// then described in plain words so the person knows what to look for.
    func say(_ slug: String, _ text: String) async {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let session, !words.isEmpty else { return }
        talk[slug, default: []].append(Turn(text: words, mine: true))
        do {
            struct Reply: Decodable { let kind: String; let reply: String; let request: String? }
            let reply: Reply = try await API.call(
                "api/tools/\(slug)/talk", method: "POST", body: ["text": words], chat: session.token)
            talk[slug, default: []].append(Turn(text: reply.reply, mine: false))
            guard reply.kind == "change" else { return }
            await change(slug, reply.request ?? words)
            if tool(slug)?.has_draft == true {
                struct Summary: Decodable { let text: String }
                if let summary: Summary = try? await API.call("api/tools/\(slug)/draft-summary", chat: session.token) {
                    talk[slug, default: []].append(Turn(text: summary.text, mine: false))
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func keep(_ slug: String) async {
        guard let session else { return }
        do {
            struct Kept: Decodable { let version: Int? }
            let _: Kept = try await API.call("api/tools/\(slug)/keep", method: "POST", chat: session.token)
            await refresh()
            if let kept = tool(slug) { send(kept, note: "I changed this. Tap to see it.") }
        } catch { self.error = error.localizedDescription }
    }

    func discard(_ slug: String) async {
        guard let session else { return }
        do {
            struct Done: Decodable { let ok: Bool? }
            let _: Done = try await API.call("api/tools/\(slug)/discard", method: "POST", chat: session.token)
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    // MARK: the bubble

    func link(for slug: String?) -> URL? {
        guard let session else { return nil }
        var components = URLComponents(url: API.base, resolvingAgainstBaseURL: false)
        components?.path = "/c/\(session.chat)"
        var fragment = "i=\(session.invite)"
        if let slug { fragment += "&t=\(slug)" }
        components?.fragment = fragment
        return components?.url
    }

    /// The tool, opened as this person. The token rides after #, so it never
    /// reaches a server log.
    func openURL(_ slug: String, draft: Bool = false) -> URL? {
        guard let session else { return nil }
        let query = draft ? "?draft=1" : ""
        return URL(string: "\(API.base.absoluteString)/t/\(slug)\(query)#m=\(session.token)")
    }

    /// Puts a bubble in the message field. The person still taps send, which
    /// is how iMessage apps are meant to behave and why nothing goes out alone.
    func send(_ tool: ToolItem, note: String) {
        guard let conversation = host?.activeConversation, let url = link(for: tool.slug) else { return }
        let layout = MSMessageTemplateLayout()
        layout.caption = tool.title
        layout.subcaption = note
        layout.trailingSubcaption = "Amber"
        layout.image = BubbleArt.render(title: tool.title, by: tool.made_by ?? name)
        let message = MSMessage(session: conversation.selectedMessage?.session ?? MSSession())
        message.layout = layout
        message.url = url
        message.summaryText = "\(name) shared \(tool.title)"
        conversation.insert(message) { [weak self] problem in
            if let problem { Task { @MainActor in self?.error = problem.localizedDescription } }
        }
        host?.requestPresentationStyle(.compact)
    }

    static func parse(_ url: URL) -> (chat: String, invite: String, slug: String?)? {
        let parts = url.path.split(separator: "/")
        guard parts.count == 2, parts[0] == "c" else { return nil }
        var values: [String: String] = [:]
        for pair in (url.fragment ?? "").split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { values[kv[0]] = kv[1] }
        }
        guard let invite = values["i"] else { return nil }
        return (String(parts[1]), invite, values["t"])
    }
}
