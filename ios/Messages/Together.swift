import Messages
import SwiftUI

// GROUP CARDS: Amber's own features, made for a group chat.
//
// A card is one shared question in this chat. Everyone answers it in their own
// row on the circles server (cards.js), so several people can tap at once and
// nobody's answer overwrites anybody else's. Where Amber can answer for you, it
// does it on your phone from your own account: your free time from your
// calendar, the people you know, a reminder saved where Amber keeps yours.
// Only the answer you send reaches the chat. Someone without Amber still taps
// their own answer in by hand, and sees what Amber would have done for them.

enum CardKind: String, CaseIterable, Identifiable {
    case free, split, pick, who, remind
    var id: String { rawValue }

    var name: String {
        switch self {
        case .free: return "When's everyone free"
        case .split: return "Split it"
        case .pick: return "Pick a spot"
        case .who: return "Who do we know"
        case .remind: return "Remind us"
        }
    }

    var short: String {
        switch self {
        case .free: return "Free time"
        case .split: return "Split"
        case .pick: return "Vote"
        case .who: return "Who knows"
        case .remind: return "Remind us"
        }
    }

    var symbol: String {
        switch self {
        case .free: return "calendar"
        case .split: return "dollarsign.circle"
        case .pick: return "checkmark.circle"
        case .who: return "person.2"
        case .remind: return "bell"
        }
    }

    /// What Amber does for you on this card, said where the button is.
    var amberDoes: String {
        switch self {
        case .free: return "Amber reads your calendar on your phone and fills in when you're free."
        case .split: return "Pay in one tap, and everyone sees who's paid."
        case .pick: return "Amber suggests real places, then everyone votes."
        case .who: return "Amber searches your own people, and you choose who to share."
        case .remind: return "Amber reminds you along with everyone else."
        }
    }
}

/// Any JSON value, for the parts of a card whose shape depends on its kind.
enum JSON: Decodable, Equatable {
    case string(String), number(Double), bool(Bool), array([JSON]), object([String: JSON]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSON].self)) }
    }

    subscript(_ key: String) -> JSON? { if case .object(let o) = self { return o[key] } else { return nil } }
    var string: String? { if case .string(let s) = self { return s } else { return nil } }
    var int: Int? { if case .number(let n) = self { return Int(n) } else { return nil } }
    var bool: Bool { if case .bool(let b) = self { return b } else { return false } }
    var array: [JSON] { if case .array(let a) = self { return a } else { return [] } }
}

struct CardEntry: Decodable, Identifiable, Equatable {
    let member_id: String
    let name: String
    let data: JSON
    var id: String { member_id }
}

struct Card: Decodable, Identifiable, Equatable {
    let id: String
    let kind: String
    let title: String
    let spec: JSON
    let made_by: String?
    let made_by_name: String?
    let closed_at: String?
    let entries: [CardEntry]

    var cardKind: CardKind { CardKind(rawValue: kind) ?? .pick }
    func entry(_ member: String?) -> CardEntry? { entries.first { $0.member_id == member } }

    var days: [Date] { spec["days"]?.array.compactMap { $0.string.flatMap { Slots.date(fromKey: $0) } } ?? [] }
    var options: [(name: String, detail: String?, url: String?)] {
        spec["options"]?.array.map { ($0["name"]?.string ?? "", $0["detail"]?.string, $0["url"]?.string) } ?? []
    }

    /// The line under the bubble and on the card row: where the group stands.
    func status(people: Int) -> String {
        switch cardKind {
        case .free:
            let best = Overlap.best(entries.map { $0.data["slots"]?.array.compactMap(\.int) ?? [] }, days: days.count, limit: 1)
            guard let b = best.first else { return entries.isEmpty ? "Nobody's answered yet" : "No time works for everyone yet" }
            return "\(Overlap.label(b, days: days)) works for \(b.count) of \(max(people, entries.count))"
        case .split:
            let inCount = entries.filter { $0.data["in"]?.bool ?? true }.count
            let paid = entries.filter { $0.data["paid"]?.bool ?? false }.count
            guard let total = spec["total"]?.int, let s = SplitMath.shares(totalCents: total, tipPercent: spec["tip"]?.int ?? 0, people: max(inCount, 1)) else { return "" }
            return "\(SplitMath.money(s.each)) each, \(paid) of \(max(inCount, 1)) paid"
        case .pick:
            let votes = Dictionary(grouping: entries.compactMap { $0.data["vote"]?.int }, by: { $0 }).mapValues(\.count)
            guard let top = votes.max(by: { $0.value < $1.value }), top.key < options.count else { return "Nobody's voted yet" }
            return "\(options[top.key].name) leads with \(top.value) \(top.value == 1 ? "vote" : "votes")"
        case .who:
            let fused = NetworkFusion.fuse(entries.map { e in (e.name, e.data["people"]?.array.map { ($0["name"]?.string ?? "", $0["about"]?.string) } ?? []) })
            let checked = entries.count
            return fused.isEmpty ? "\(checked) checked, nobody yet" : "\(fused.count) \(fused.count == 1 ? "person" : "people") known, \(checked) checked"
        case .remind:
            let inCount = entries.filter { $0.data["in"]?.bool ?? true }.count
            let when = spec["at"]?.string.flatMap(AmberJWT.iso).map { $0.formatted(date: .abbreviated, time: .shortened) } ?? ""
            return "\(when), \(inCount) in"
        }
    }
}

struct WhoCandidate: Identifiable, Equatable {
    let id: String
    let name: String
    let about: String?
}

@MainActor
final class TogetherStore: ObservableObject {
    @Published var cards: [Card] = []
    @Published var me: String?
    @Published var working: Set<String> = []
    @Published var error: String?
    @Published var composing: CardKind?
    @Published var amberLinked = AmberKeychain.signedIn
    weak var chat: ChatStore?

    private var token: String? { chat?.session?.token }
    private var chatId: String? { chat?.session?.chat }

    func card(_ id: String) -> Card? { cards.first { $0.id == id } }

    private struct CardsReply: Decodable { let me: String; let cards: [Card] }
    private struct OneCard: Decodable { let card: Card }

    func load() async {
        amberLinked = AmberKeychain.signedIn
        guard let token, let chatId else { return }
        do {
            let reply: CardsReply = try await API.call("api/chats/\(chatId)/cards", chat: token)
            me = reply.me
            if reply.cards != cards { withAnimation(.smooth) { cards = reply.cards } }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func replace(_ card: Card) {
        if let i = cards.firstIndex(where: { $0.id == card.id }) { cards[i] = card } else { cards.insert(card, at: 0) }
    }

    func create(_ kind: CardKind, title: String, spec: [String: Any]) async -> Card? {
        guard let session = await chat?.ensureSession() else {
            error = chat?.error ?? "Couldn't start this chat. Try again."
            return nil
        }
        let token = session.token, chatId = session.chat
        do {
            let made: OneCard = try await API.call("api/chats/\(chatId)/cards", method: "POST",
                                                   body: ["kind": kind.rawValue, "title": title, "spec": spec], chat: token)
            replace(made.card)
            return made.card
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func answer(_ card: Card, _ data: [String: Any]) async {
        guard let token else { return }
        working.insert(card.id)
        defer { working.remove(card.id) }
        do {
            let fresh: OneCard = try await API.call("api/cards/\(card.id)/mine", method: "PUT", body: ["data": data], chat: token)
            withAnimation(.smooth) { replace(fresh.card) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func close(_ card: Card) async {
        guard let token else { return }
        struct Done: Decodable { let ok: Bool }
        let _: Done? = try? await API.call("api/cards/\(card.id)/close", method: "POST", body: [:], chat: token)
        cards.removeAll { $0.id == card.id }
        chat?.route = .home
    }

    // MARK: Amber, on this phone, for this person

    private func amber<T>(_ id: String, _ work: () async throws -> T) async -> T? {
        working.insert(id)
        defer { working.remove(id) }
        do { return try await work() } catch {
            self.error = error.localizedDescription
            amberLinked = AmberKeychain.signedIn
            return nil
        }
    }

    /// Your free half hours on the card's days, from your own Amber calendar.
    func freeFromAmber(_ card: Card) async -> [Int]? {
        let days = card.days
        guard let first = days.first, let last = days.last else { return nil }
        return await amber(card.id) {
            let iso = ISO8601DateFormatter()
            let end = Calendar.current.date(byAdding: .day, value: 1, to: last) ?? last
            let q = "from=\(iso.string(from: first).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")&to=\(iso.string(from: end).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"
            let agenda = try await AmberClient.shared.json("/v1/me/agenda?\(q)")
            // Only events block time. An event with no end counts as an hour,
            // guessed, never measured. All-day events do not block the evening.
            let busy: [DateInterval] = ((agenda["events"] as? [[String: Any]]) ?? []).compactMap { e in
                if (e["allDay"] as? Bool) == true { return nil }
                guard let s = (e["startsAt"] as? String).flatMap(AmberJWT.iso) else { return nil }
                let end = (e["endsAt"] as? String).flatMap(AmberJWT.iso) ?? s.addingTimeInterval(3600)
                return end > s ? DateInterval(start: s, end: end) : nil
            }
            return days.enumerated().flatMap { i, day in
                Slots.free(day: day, busy: busy, now: Date()).map { i * Slots.perDay + $0 }
            }
        }
    }

    /// Real places for a vote, from Amber's own search.
    func ideasFromAmber(_ what: String) async -> [(name: String, detail: String?, url: String?)]? {
        await amber("ideas") {
            let r = try await AmberClient.shared.ask("Suggest 5 specific places for this, with a short reason each: \(what)")
            return r.places.prefix(6).compactMap { p in
                guard let name = (p["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
                let detail = [p["cuisine"], p["category"], p["neighborhood"]].compactMap { $0 as? String }.first { !$0.isEmpty }
                return (String(name.prefix(80)), detail.map { String($0.prefix(120)) }, p["url"] as? String)
            }
        }
    }

    /// The people in your own Amber who fit the question. Nothing is shared
    /// until you pick who.
    func peopleFromAmber(_ card: Card) async -> [WhoCandidate]? {
        let question = card.spec["question"]?.string ?? card.title
        return await amber(card.id) {
            let r = try await AmberClient.shared.ask(question)
            return r.people.compactMap { p in
                guard let name = (p["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
                let title = (p["title"] as? String) ?? "", company = (p["company"] as? String) ?? ""
                let about = [title, company].filter { !$0.isEmpty }.joined(separator: " at ")
                return WhoCandidate(id: "\(p["contactId"] ?? p["id"] ?? name)", name: name, about: about.isEmpty ? nil : about)
            }
        }
    }

    /// Saves the card's reminder into your own Amber.
    func remindInAmber(_ card: Card) async -> Bool {
        guard let at = card.spec["at"]?.string else { return false }
        return await amber(card.id) {
            _ = try await AmberClient.shared.json("/v1/me/reminders/self", method: "POST", body: ["title": String(card.title.prefix(120)), "dueAt": at])
            return true
        } ?? false
    }

    // MARK: The bubble

    func send(_ card: Card) {
        guard let chat, let host = chat.host, let conversation = host.activeConversation,
              let url = chat.link(for: nil, card: card.id) else { return }
        let layout = MSMessageTemplateLayout()
        layout.caption = card.cardKind.name
        layout.subcaption = "\(card.title). \(card.status(people: chat.overview?.people.count ?? 0))"
        layout.trailingSubcaption = "Amber"
        layout.image = BubbleArt.render(title: card.title, by: card.made_by_name ?? chat.name, tagline: card.cardKind.name, action: "Answer")
        let message = MSMessage(session: conversation.selectedMessage?.session ?? MSSession())
        message.layout = layout
        message.url = url
        message.summaryText = "\(chat.name) answered \(card.title)"
        conversation.insert(message) { [weak self] problem in
            if let problem { Task { @MainActor in self?.error = problem.localizedDescription } }
        }
        host.requestPresentationStyle(.compact)
    }
}
