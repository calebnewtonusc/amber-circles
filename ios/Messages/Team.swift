import Messages
import SwiftUI

// THE TEAM BOARD: the Chewbacca board (calebnewtonusc/Chewbacca, team/tasks),
// inside the team's group chat. The server (team.js) reads and writes the same
// task files as the web board and the `team` CLI, so a status tapped here is
// the status everywhere. A chat sees it once someone links it with the team's
// code; each person picks their own name once, so the board's activity says
// who did what.

struct TeamTask: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let status: String
    let owner: String
    let priority: String
    let due: String
    let done_when: String
    let proof: String
    let labels: [String]
    let updated: String
    let notes: String
    let activity: [String]

    var stage: TeamStage { TeamStage(rawValue: status) ?? .todo }
    var dueDate: Date? { TeamDates.parse(due) }
}

struct TeamMember: Decodable, Identifiable, Equatable {
    let name: String
    let role: String
    var id: String { name }
    var initial: String { String(name.prefix(1)).uppercased() }
}

struct TeamBoard: Decodable, Equatable {
    let available: Bool
    let linked: Bool
    var me: String?
    var members: [TeamMember]?
    var tasks: [TeamTask]?
    var counts: [String: Int]?
    var today: String?
}

/// The statuses a phone works with. The board has more (inbox, ideas,
/// canceled); those are triage, done on the web board.
enum TeamStage: String, CaseIterable, Identifiable {
    case todo, in_progress, in_review, done, backlog
    var id: String { rawValue }

    var label: String {
        switch self {
        case .todo: return "To do"
        case .in_progress: return "Doing"
        case .in_review: return "Review"
        case .done: return "Done"
        case .backlog: return "Backlog"
        }
    }

    /// What one tap on the status dot does. Done needs proof, so review asks.
    var next: TeamStage? {
        switch self {
        case .backlog, .todo: return .in_progress
        case .in_progress: return .in_review
        case .in_review: return .done
        case .done: return nil
        }
    }

    /// The verb the chat reads: "Jake started CHW-12".
    var verb: String {
        switch self {
        case .todo: return "queued"
        case .in_progress: return "started"
        case .in_review: return "sent for review"
        case .done: return "finished"
        case .backlog: return "parked"
        }
    }

    var order: Int { [.in_review: 0, .in_progress: 1, .todo: 2, .backlog: 3, .done: 4][self] ?? 5 }
}

enum TeamDates {
    private static let key: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(_ s: String) -> Date? { s.isEmpty ? nil : key.date(from: s) }
    static func string(_ d: Date) -> String { key.string(from: d) }

    /// "Today", "Tomorrow", "Fri", "Oct 20": the shortest thing that is exact.
    static func short(_ d: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: d)).day ?? 99
        if days > 0 && days < 7 { return d.formatted(.dateTime.weekday(.abbreviated)) }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }

    static func overdue(_ t: TeamTask, now: Date = Date()) -> Bool {
        guard t.stage != .done, let d = t.dueDate else { return false }
        return Calendar.current.startOfDay(for: d) < Calendar.current.startOfDay(for: now)
    }

    /// The quick picks under a task: none, today, tomorrow, this Friday, next Monday.
    static func quick(now: Date = Date()) -> [(String, Date?)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        func nextWeekday(_ w: Int) -> Date {
            cal.nextDate(after: today, matching: DateComponents(weekday: w), matchingPolicy: .nextTime) ?? today
        }
        return [("None", nil), ("Today", today), ("Tomorrow", cal.date(byAdding: .day, value: 1, to: today)),
                ("Fri", nextWeekday(6)), ("Mon", nextWeekday(2))]
    }
}

@MainActor
final class TeamStore: ObservableObject {
    @Published var board: TeamBoard?
    @Published var error: String?
    @Published var working: Set<String> = []
    /// What this person changed since they last told the chat, newest last.
    @Published var unsaid: [String] = []
    @Published var editing: TeamTask?
    @Published var adding = false
    @Published var proofFor: TeamTask?
    weak var chat: ChatStore?

    private var token: String? { chat?.session?.token }
    private var chatId: String? { chat?.session?.chat }

    var me: String? { board?.me }
    var tasks: [TeamTask] { board?.tasks ?? [] }
    var members: [TeamMember] { board?.members ?? [] }
    func task(_ id: String) -> TeamTask? { tasks.first { $0.id == id } }

    func open(of name: String?) -> [TeamTask] {
        tasks.filter { $0.owner == (name ?? "") && $0.stage != .done }
            .sorted { ($0.stage.order, $0.dueDate ?? .distantFuture) < ($1.stage.order, $1.dueDate ?? .distantFuture) }
    }

    /// One line for the row on home and the bubble: where the team stands.
    var summary: String {
        guard board?.linked == true else { return "Put the Chewbacca board in this chat" }
        let active = tasks.filter { $0.stage == .in_progress || $0.stage == .in_review }.count
        let late = tasks.filter { TeamDates.overdue($0) }.count
        let mine = open(of: me).filter { $0.stage != .backlog }.count
        var parts: [String] = []
        if me != nil { parts.append("\(mine) yours") }
        parts.append("\(active) moving")
        if late > 0 { parts.append("\(late) late") }
        return parts.joined(separator: ", ")
    }

    private struct One: Decodable { let task: TeamTask }
    private struct Ok: Decodable { let ok: Bool }

    func load() async {
        guard let token, let chatId else { return }
        do {
            let fresh: TeamBoard = try await API.call("api/chats/\(chatId)/team", chat: token)
            error = nil
            if fresh != board { withAnimation(.smooth) { board = fresh } }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func link(code: String) async -> Bool {
        guard let session = await chat?.ensureSession() else { return false }
        return await run("link") {
            let _: Ok = try await API.call("api/chats/\(session.chat)/team/link", method: "POST", body: ["code": code], chat: session.token)
            await self.load()
        }
    }

    func setMe(_ name: String) async {
        guard let token, let chatId else { return }
        _ = await run("me") {
            let _: Ok = try await API.call("api/chats/\(chatId)/team/me", method: "POST", body: ["name": name], chat: token)
            await self.load()
        }
    }

    @discardableResult
    func add(title: String, owner: String, due: Date?) async -> Bool {
        guard let token, let chatId else { return false }
        var body: [String: Any] = ["title": title, "owner": owner]
        if let due { body["due"] = TeamDates.string(due) }
        return await run("add") {
            let made: One = try await API.call("api/chats/\(chatId)/team/tasks", method: "POST", body: body, chat: token)
            self.upsert(made.task)
            let who = owner == self.me ? "" : " for \(owner)"
            self.unsaid.append("added \(made.task.id) \(made.task.title)\(who)")
        }
    }

    /// One field or several, written now. `said` is what the chat hears about it.
    @discardableResult
    func update(_ t: TeamTask, _ body: [String: Any], said: String? = nil) async -> Bool {
        guard let token, let chatId else { return false }
        return await run(t.id) {
            let fresh: One = try await API.call("api/chats/\(chatId)/team/tasks/\(t.id)", method: "PATCH", body: body, chat: token)
            self.upsert(fresh.task)
            if self.editing?.id == fresh.task.id { self.editing = fresh.task }
            if let said { self.unsaid.append(said) }
        }
    }

    /// The dot's one tap: forward one stage. Into done it asks for proof first.
    func advance(_ t: TeamTask) {
        guard let next = t.stage.next else { return }
        if next == .done && t.proof.isEmpty { proofFor = t; return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { await update(t, ["status": next.rawValue], said: "\(next.verb) \(t.id) \(t.title)") }
    }

    private func upsert(_ t: TeamTask) {
        guard var b = board else { return }
        var list = b.tasks ?? []
        if let i = list.firstIndex(where: { $0.id == t.id }) { list[i] = t } else { list.append(t) }
        b.tasks = list
        withAnimation(.smooth) { board = b }
    }

    private func run(_ key: String, _ work: @escaping () async throws -> Void) async -> Bool {
        working.insert(key)
        defer { working.remove(key) }
        error = nil
        do { try await work(); return true } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    // MARK: The bubble

    func didSendBoard() { unsaid = [] }

    /// Puts one bubble in the message box: what you changed, or where the
    /// board stands. It is only sent when the person taps send.
    func tell() {
        guard let chat, let host = chat.host, let conversation = host.activeConversation,
              let url = chat.link(for: nil, board: true) else { return }
        let name = me ?? chat.name
        let said = unsaid.suffix(3)
        let layout = MSMessageTemplateLayout()
        layout.caption = said.isEmpty ? "Team board" : "\(name) \(said.first ?? "")"
        layout.subcaption = said.count > 1 ? "and \(said.dropFirst().joined(separator: ", "))" : summary
        layout.trailingSubcaption = "Chewbacca"
        let headline = said.isEmpty ? "This week" : "\(said.count + max(0, unsaid.count - 3)) \(unsaid.count == 1 ? "update" : "updates")"
        layout.image = BubbleArt.render(title: headline, by: name, tagline: "Team board", action: "Open board")
        // Its own session: reusing the open bubble's would fold this update
        // into a card's or a tool's bubble in the transcript.
        let message = MSMessage(session: MSSession())
        message.layout = layout
        message.url = url
        message.summaryText = said.isEmpty ? "\(name) shared the team board" : "\(name) \(said.joined(separator: ", "))"
        // `unsaid` clears when the bubble is actually sent (didSendBoard), not
        // when it is staged: a deleted draft keeps the updates.
        conversation.insert(message) { [weak self] problem in
            if let problem { Task { @MainActor in self?.error = problem.localizedDescription } }
        }
        host.requestPresentationStyle(.compact)
    }
}
