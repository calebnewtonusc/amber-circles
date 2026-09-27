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
    let speaker = Speaker()
    /// Changes being built right now, by tool, with when they started. The
    /// conversation stays open while they run (pipecat's async tools,
    /// processors/aggregators/async_tool_messages.py).
    @Published var changing: [String: Date] = [:]

    /// Amber opens a tool by saying what it is, out loud, once.
    func greet(_ slug: String, _ text: String) { reply(slug, text) }

    /// Amber's side of the conversation: shown, and said out loud.
    private func reply(_ slug: String, _ text: String) {
        talk[slug, default: []].append(Turn(text: text, mine: false))
        if let token = session?.token { Task { await speaker.say(text, token: token) } }
    }

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

    /// Loads the chat's conversation with Amber, all of it on the home screen
    /// ("" key) or only what was said about one tool.
    func loadTalk(_ slug: String) async {
        guard let session else { return }
        struct Row: Decodable { let role: String; let text: String; let name: String? }
        struct Rows: Decodable { let turns: [Row] }
        let path = slug.isEmpty ? "api/chats/\(session.chat)/agent" : "api/chats/\(session.chat)/agent?slug=\(slug)"
        guard let url = URL(string: path, relativeTo: API.base) else { return }
        var request = URLRequest(url: url)
        request.setValue(session.token, forHTTPHeaderField: "x-amber-chat")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let rows = try? JSONDecoder().decode(Rows.self, from: data) else { return }
        talk[slug] = rows.turns.compactMap { row in
            switch row.role {
            case "person": return Turn(text: row.name == nil || row.name == session.name ? row.text : "\(row.name!): \(row.text)", mine: true)
            case "amber": return Turn(text: row.text, mine: false)
            default: return nil
            }
        }
    }

    /// Say something to the chat's agent, on the home screen (slug "") or
    /// about one tool. The fast words never reach a model, the way
    /// Chewbacca's music does (docs/VOICE-DESIGN.md): keep it, put it back,
    /// open it.
    func say(_ slug: String, _ text: String, open: (URL) -> Void = { _ in }) async {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        error = nil
        talk[slug, default: []].append(Turn(text: words, mine: true))
        do {
            if session == nil {
                let started: Joined = try await API.call(
                    "api/chats", method: "POST", body: ["name": name, "participant": participant])
                store(Session(chat: started.chat, token: started.token, invite: started.invite ?? "", name: name))
            }
        } catch {
            self.error = error.localizedDescription
            return
        }
        guard let session else { return }
        let lower = words.lowercased()
        let hasDraft = !slug.isEmpty && tool(slug)?.has_draft == true
        if hasDraft, lower.range(of: #"^(keep (it|this|that)|looks good|ship it|yes keep)"#, options: .regularExpression) != nil {
            await keep(slug); reply(slug, "Kept. Everyone in the chat has it now."); return
        }
        if hasDraft, lower.range(of: #"^(put it back|undo|never ?mind|throw (it|that) (out|away))"#, options: .regularExpression) != nil {
            await discard(slug); reply(slug, "Put back. Nothing changed."); return
        }
        if !slug.isEmpty, lower.range(of: #"^(open|show me)( it| the (draft|app|site))?$"#, options: .regularExpression) != nil,
           let url = openURL(slug, draft: hasDraft) {
            reply(slug, "Opening it in Safari. Come back and tell me what you think.")
            open(url); return
        }
        // Chewbacca's filler rule: nothing said for two seconds, say something
        // shaped to the request, not "um".
        var answered = false
        let subject = slug.isEmpty ? "that" : (tool(slug)?.title ?? "it")
        let filler = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if !answered, let self, let token = self.session?.token {
                await self.speaker.say("Let me look at \(subject).", token: token)
            }
        }
        do {
            struct Action: Decodable { let type: String; let slug: String?; let request: String? }
            struct Reply: Decodable { let reply: String; let actions: [Action] }
            var body: [String: Any] = ["text": words]
            if !slug.isEmpty { body["slug"] = slug }
            let result: Reply = try await API.call(
                "api/chats/\(session.chat)/agent", method: "POST", body: body, chat: session.token)
            answered = true
            filler.cancel()
            self.reply(slug, result.reply)
            for action in result.actions {
                switch action.type {
                case "change":
                    if let target = action.slug, let request = action.request, changing[target] == nil {
                        Task { await self.changeInBackground(target, request, tell: slug) }
                    }
                case "make":
                    if let request = action.request { Task { await self.makeInBackground(request, tell: slug) } }
                case "open":
                    if let target = action.slug, let url = openURL(target, draft: tool(target)?.has_draft == true) { open(url) }
                default: break
                }
            }
        } catch {
            answered = true
            filler.cancel()
            self.error = error.localizedDescription
        }
    }

    /// A new tool, built while the conversation keeps going. When it is ready
    /// Amber says so and puts the bubble in the message field to send.
    private func makeInBackground(_ request: String, tell key: String) async {
        guard let session else { return }
        changing["__new"] = Date()
        defer { changing["__new"] = nil }
        do {
            let result = try await API.build(request: request, chat: session.chat, slug: nil, token: session.token) { _, _ in }
            await refresh()
            let title = tool(result.slug)?.title ?? "it"
            reply(key, "\(title) is ready. I put it in the message box so you can send it to the chat.")
            if let made = tool(result.slug) { send(made, note: "I made this for us. Tap to open it.") }
        } catch {
            reply(key, "That didn't get built. \(error.localizedDescription)")
        }
    }

    /// Builds a change without taking over the screen, then says when it is
    /// ready. A failure is always said out loud, never left silent.
    private func changeInBackground(_ slug: String, _ request: String, tell key: String? = nil) async {
        guard let session else { return }
        changing[slug] = Date()
        defer { changing[slug] = nil }
        do {
            _ = try await API.build(request: request, chat: session.chat, slug: slug, token: session.token) { _, _ in }
            await refresh()
            struct Summary: Decodable { let text: String }
            let summary: Summary? = try? await API.call("api/tools/\(slug)/draft-summary", chat: session.token)
            reply(key ?? slug, "It's updated. " + (summary?.text ?? "") + " Tap the link at the top to try it in Safari.")
        } catch {
            reply(key ?? slug, "That change didn't go through. \(error.localizedDescription)")
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
        // Game Pigeon's bubble says "Let's play 8-ball". Ours says what it is
        // for (Caleb, 2026-09-27: "instead of let's play 8-ball, it says
        // let's build together").
        layout.caption = "Let's build together"
        layout.subcaption = "\(tool.title). \(note)"
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
