import Messages
import SwiftUI

enum Route: Hashable {
    case home
    case tool(String)
    /// A new app being talked through, before it exists. Its key starts
    /// with "new-"; when the build lands it becomes .tool(slug).
    case draft(String)
}

/// A new app the chat is talking about but has not built yet.
struct DraftApp: Codable, Identifiable, Equatable {
    let id: String
    var started: Date
    var title: String
}

struct BoardItem: Decodable, Identifiable {
    var id: String { (slug ?? "") + text }
    let text: String
    let name: String?
    let slug: String?
    let title: String?
}

struct Board: Decodable {
    struct Idea: Decodable, Identifiable { var id: String { name }; let name: String; let description: String; let about: String? }
    struct Building: Decodable, Identifiable { var id: String { who + what }; let who: String; let what: String }
    let comments: [BoardItem]
    let ideas: [Idea]
    let building: [Building]
}

/// One line of the conversation with a tool: what someone said, or what
/// Amber said back.
struct Turn: Identifiable, Equatable, Codable {
    var id = UUID()
    let text: String
    let mine: Bool
    /// Said just now, so it types itself out instead of appearing whole.
    var fresh = false
}

/// What is on this phone and not yet in the cloud: the conversation, apps not
/// yet published, and where the person was. Saved on every change, so closing
/// iMessage by accident picks up like nothing happened (Caleb, 2026-09-27).
struct LocalState: Codable {
    var talk: [String: [Turn]] = [:]
    var unpublished: Set<String> = []
    var slug: String?
    var drafts: [DraftApp]? = []
    var draftKey: String?
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
    @Published var route: Route = .home { didSet { saveLocal() } }
    @Published var loading = false
    @Published var expanded = false
    /// The conversation with each tool, kept here so it survives the building
    /// screen replacing the tool's screen.
    @Published var talk: [String: [Turn]] = [:] { didSet { saveLocal() } }
    let speaker = Speaker()
    /// Changes being built right now, by tool, with when they started. The
    /// conversation stays open while they run (pipecat's async tools,
    /// processors/aggregators/async_tool_messages.py).
    @Published var changing: [String: Date] = [:]
    /// The half-written page and what is being added right now, per tool
    /// ("__new" for an app being made), for the live preview.
    @Published var liveHTML: [String: String] = [:]
    /// What the person is saying right now, while they hold the talk bar.
    @Published var liveSpeech: String?
    /// From Sign in with Apple; nil until they sign in.
    @Published var personKey: String? = PersonKey.load()
    /// Face ID passed for this open.
    @Published var unlocked = false
    /// New apps being talked through on this phone, shown as boxes in the list.
    @Published var drafts: [DraftApp] = [] { didSet { saveLocal() } }
    /// The last thing Amber said on the home screen, shown for a moment above
    /// the talk bar instead of piling up as a conversation.
    @Published var caption: String?
    @Published var board: Board?
    @Published var doing: [String: String] = [:]
    /// Tools built but not yet shared. Nothing goes into the message box
    /// until the person taps Publish (Caleb, 2026-09-27: "the text already
    /// tries to send without me clicking publish").
    @Published var unpublished: Set<String> = [] { didSet { saveLocal() } }

    /// Amber says what it is building as it goes, like a person narrating
    /// their work, but never more than once every few seconds and never over
    /// itself (Caleb: "it should literally feel like iron man genui").
    private var lastNarration = Date.distantPast
    private var lastNarrated = ""
    func narrate(_ doing: String) {
        guard doing != lastNarrated, Date().timeIntervalSince(lastNarration) > 5,
              !speaker.isSpeaking, let token = session?.token else { return }
        lastNarration = Date()
        lastNarrated = doing
        Task { await speaker.say(doing + ".", token: token) }
    }

    /// Amber opens a tool by saying what it is, out loud, once.
    func greet(_ slug: String, _ text: String) { reply(slug, text) }

    /// Amber's side of the conversation: shown, and said out loud.
    private func reply(_ slug: String, _ text: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
            talk[slug, default: []].append(Turn(text: text, mine: false, fresh: true))
        }
        if let token = session?.token { Task { await speaker.say(text, token: token) } }
    }

    weak var host: MessagesViewController?
    private var participant = ""
    private var pendingInvite: (chat: String, invite: String, slug: String?)?

    private var sessionKey: String { "amber.session.\(participant)" }
    private var localKey: String { "amber.local.\(participant)" }
    private var restoring = false

    private func saveLocal() {
        guard !restoring, !participant.isEmpty else { return }
        var slug: String?
        var draftKey: String?
        if case .tool(let current) = route { slug = current }
        if case .draft(let key) = route { draftKey = key }
        let state = LocalState(talk: talk, unpublished: unpublished, slug: slug, drafts: drafts, draftKey: draftKey)
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: localKey) }
    }

    private func restoreLocal() {
        restoring = true
        defer { restoring = false }
        guard let data = UserDefaults.standard.data(forKey: localKey),
              let state = try? JSONDecoder().decode(LocalState.self, from: data) else {
            talk = [:]; unpublished = []; drafts = []; route = .home
            return
        }
        talk = state.talk
        unpublished = state.unpublished
        drafts = state.drafts ?? []
        route = state.slug.map { .tool($0) } ?? state.draftKey.map { .draft($0) } ?? .home
    }

    func attach(_ conversation: MSConversation) {
        participant = conversation.localParticipantIdentifier.uuidString
        restoreLocal()
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
            ) { [weak self] stage, detail, _, _ in
                self?.building?.stage = stage
                self?.building?.detail = detail
            }
            await refresh()
            building = nil
            route = .tool(result.slug)
            unpublished.insert(result.slug)
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
                [weak self] stage, detail, _, _ in
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
        guard let session, !slug.hasPrefix("new-") else { return }
        struct Row: Decodable { let role: String; let text: String; let name: String? }
        struct Rows: Decodable { let turns: [Row] }
        let path = slug.isEmpty ? "api/chats/\(session.chat)/agent" : "api/chats/\(session.chat)/agent?slug=\(slug)"
        guard let url = URL(string: path, relativeTo: API.base) else { return }
        var request = URLRequest(url: url)
        request.setValue(session.token, forHTTPHeaderField: "x-amber-chat")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let rows = try? JSONDecoder().decode(Rows.self, from: data) else { return }
        let fromServer: [Turn] = rows.turns.compactMap { row in
            switch row.role {
            case "person": return Turn(text: row.name == nil || row.name == session.name ? row.text : "\(row.name!): \(row.text)", mine: true)
            case "amber": return Turn(text: row.text, mine: false)
            default: return nil
            }
        }
        // The phone may hold newer lines than the server (a "ready" said while
        // offline, or a reply not yet logged); never let the older copy win.
        if fromServer.count >= (talk[slug]?.count ?? 0) { talk[slug] = fromServer }
    }

    /// Say something to the chat's agent, on the home screen (slug "") or
    /// about one tool. The fast words never reach a model, the way
    /// Chewbacca's music does (docs/VOICE-DESIGN.md): keep it, put it back,
    /// open it.
    func say(_ slug: String, _ text: String, open: (URL) -> Void = { _ in }) async {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        error = nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
            talk[slug, default: []].append(Turn(text: words, mine: true))
        }
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
            if !slug.isEmpty, !slug.hasPrefix("new-") { body["slug"] = slug }
            let result: Reply = try await API.call(
                "api/chats/\(session.chat)/agent", method: "POST", body: body, chat: session.token,
                person: (personKey ?? "").isEmpty ? nil : personKey)
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
                    // Only when they asked to see it: Safari opening by itself
                    // mid-conversation was jarring (simulator run, 2026-09-27).
                    guard words.range(of: #"\b(open|show|see|pull (it )?up|look at)\b"#, options: [.regularExpression, .caseInsensitive]) != nil else { break }
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
        // Every new app has a box from the first word; one started from the
        // home screen gets one now.
        let draftKey = key.hasPrefix("new-") ? key : newDraft(title: "New app").id
        let since = drafts.first { $0.id == draftKey }?.started ?? Date()
        if let index = drafts.firstIndex(where: { $0.id == draftKey }) {
            drafts[index].title = String(request.prefix(40))
        }
        changing[draftKey] = Date()
        defer { changing[draftKey] = nil }
        do {
            let result = try await API.build(request: request, chat: session.chat, slug: nil, token: session.token) { [weak self] _, _, html, doing in
                if let html { self?.liveHTML[draftKey] = html }
                if let doing { self?.doing[draftKey] = doing; self?.narrate(doing) }
            }
            liveHTML[draftKey] = nil
            doing[draftKey] = nil
            await refresh()
            // The talk that shaped it moves into it, on the server and here.
            struct Moved: Decodable { let moved: Int }
            let _: Moved? = try? await API.call(
                "api/chats/\(session.chat)/adopt", method: "POST",
                body: ["slug": result.slug, "since": ISO8601DateFormatter().string(from: since.addingTimeInterval(-2))],
                chat: session.token)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                talk[result.slug] = (talk[draftKey] ?? []) + (talk[result.slug] ?? [])
                talk[draftKey] = nil
                drafts.removeAll { $0.id == draftKey }
                unpublished.insert(result.slug)
                if route == .draft(draftKey) { route = .tool(result.slug) }
            }
            let title = tool(result.slug)?.title ?? "it"
            reply(result.slug, "\(title) is ready. Try it, then tap Publish when you want the chat to have it.")
        } catch {
            reply(draftKey, "That didn't get built. \(error.localizedDescription)")
        }
    }

    /// A new app box, shown in the list right away.
    @discardableResult
    func newDraft(title: String) -> DraftApp {
        let draft = DraftApp(id: "new-\(UUID().uuidString.prefix(8))", started: Date(), title: title)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { drafts.insert(draft, at: 0) }
        return draft
    }

    /// Talking on the home screen. Talk about making something opens a new
    /// app box and moves into it; anything else is answered in a caption.
    /// Caleb: "if I start talking abt making a new app, it should smoothly
    /// create a new app box and we migrate to there."
    func homeSay(_ text: String) async {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        let aboutNewApp = words.range(
            of: #"\b(make|build|create|start|need|want|set up|let'?s do)\b.*\b(app|list|tracker|sheet|page|site|website|tool|sign.?up|calendar|schedule|poll|board|game)\b"#,
            options: [.regularExpression, .caseInsensitive]) != nil
        if aboutNewApp {
            let draft = newDraft(title: "New app")
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { route = .draft(draft.id) }
            await say(draft.id, words)
            return
        }
        await say("", words)
        let answer = talk[""]?.last(where: { !$0.mine })?.text
        withAnimation(.easeOut(duration: 0.25)) { caption = answer }
    }

    func catchUp(_ slug: String) async -> String? {
        guard let session else { return nil }
        struct News: Decodable { let text: String }
        let news: News? = try? await API.call("api/chats/\(session.chat)/catchup", method: "POST", body: ["slug": slug], chat: session.token)
        return news?.text
    }

    func loadBoard() async {
        guard let session else { return }
        board = try? await API.call("api/chats/\(session.chat)/board", chat: session.token)
    }

    /// Builds a change without taking over the screen, then says when it is
    /// ready. A failure is always said out loud, never left silent.
    private func changeInBackground(_ slug: String, _ request: String, tell key: String? = nil) async {
        guard let session else { return }
        changing[slug] = Date()
        defer { changing[slug] = nil }
        do {
            _ = try await API.build(request: request, chat: session.chat, slug: slug, token: session.token) { [weak self] _, _, html, doing in
                if let html { self?.liveHTML[slug] = html }
                if let doing { self?.doing[slug] = doing; self?.narrate(doing) }
            }
            liveHTML[slug] = nil
            doing[slug] = nil
            await refresh()
            struct Summary: Decodable { let text: String }
            let summary: Summary? = try? await API.call("api/tools/\(slug)/draft-summary", chat: session.token)
            reply(key ?? slug, "It's updated. " + (summary?.text ?? ""))
        } catch {
            reply(key ?? slug, "That change didn't go through. \(error.localizedDescription)")
        }
    }

    func keep(_ slug: String, announce: Bool = true) async {
        guard let session else { return }
        do {
            struct Kept: Decodable { let version: Int? }
            let _: Kept = try await API.call("api/tools/\(slug)/keep", method: "POST", chat: session.token)
            await refresh()
            if announce, let kept = tool(slug) { send(kept, note: "I changed this. Tap to see it.") }
            unpublished.remove(slug)
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
        let query = draft ? "?embed=1&draft=1" : "?embed=1"
        return URL(string: "\(API.base.absoluteString)/t/\(slug)\(query)#m=\(session.token)")
    }

    /// Puts a bubble in the message field. The person still taps send, which
    /// is how iMessage apps are meant to behave and why nothing goes out alone.
    /// What a bubble in the message box will publish once it is sent.
    private var pendingSend: [String: Bool] = [:]  // slug -> is a change

    /// Puts the new app's bubble in the message box. It is published when the
    /// person sends it.
    func publish(_ slug: String) {
        guard let made = tool(slug) else { return }
        pendingSend[slug] = false
        send(made, note: "I made this for us. Tap to open it.")
    }

    /// Puts a bubble for the waiting change in the message box; the change
    /// goes live for everyone when the bubble is sent.
    func publishChanges(_ slug: String) {
        guard let changed = tool(slug) else { return }
        pendingSend[slug] = true
        send(changed, note: "I changed this. Tap to see it.")
    }

    func didSend(_ url: URL?) {
        guard let url, let link = Self.parse(url), let slug = link.slug, let isChange = pendingSend[slug] else { return }
        pendingSend[slug] = nil
        unpublished.remove(slug)
        if isChange { Task { await keep(slug, announce: false) } }
    }

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
