import Foundation

// THE ARITHMETIC BEHIND GROUP CARDS, WITH NO UI AND NO NETWORK.
//
// Pure functions, so they compile and run on a Mac with plain swiftc
// (test/TogetherCoreTest.swift, run by test/together-core.test.js). Ported
// from Kyber in amber-ios (targets/kyber/KyberCore.swift), where the same
// logic was tested for one person; here every function takes the whole chat.

// MARK: - Time slots

enum Slots {
    /// Half-hour slots from 9am to 10pm. Mirrored on the server
    /// (cards.js SLOTS_PER_DAY), which refuses any slot past the last day.
    /// 9 to 10 is a guess at when friends plan to meet, never measured.
    static let startHour = 9
    static let perDay = 26

    static func start(day: Date, slot: Int, calendar: Calendar = .current) -> Date {
        let base = calendar.startOfDay(for: day)
        return base.addingTimeInterval(TimeInterval((startHour * 60 + slot * 30) * 60))
    }

    /// The slots on `day` that a person is free for, given their busy blocks.
    /// A slot that has already started is not offered.
    static func free(day: Date, busy: [DateInterval], now: Date, calendar: Calendar = .current) -> [Int] {
        (0..<perDay).filter { slot in
            let s = start(day: day, slot: slot, calendar: calendar)
            let e = s.addingTimeInterval(1800)
            guard s >= now else { return false }
            return !busy.contains { $0.start < e && $0.end > s }
        }
    }

    static func dayKey(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(fromKey key: String, calendar: Calendar = .current) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    static func clock(_ d: Date, meridiem: Bool = true, calendar: Calendar = .current) -> String {
        let h = calendar.component(.hour, from: d), m = calendar.component(.minute, from: d)
        let h12 = h % 12 == 0 ? 12 : h % 12
        let body = m == 0 ? "\(h12)" : String(format: "%d:%02d", h12, m)
        return meridiem ? body + (h < 12 ? "am" : "pm") : body
    }
}

/// A stretch of slots on one day that the most people can make.
struct BestTime: Equatable {
    let day: Int
    let first: Int
    let last: Int
    let count: Int
}

enum Overlap {
    /// How many people are free in each slot across all days.
    static func counts(_ answers: [[Int]], days: Int) -> [Int] {
        var c = Array(repeating: 0, count: days * Slots.perDay)
        for slots in answers { for s in Set(slots) where s >= 0 && s < c.count { c[s] += 1 } }
        return c
    }

    /// The longest runs at the highest head-count, best first. A run never
    /// crosses midnight, because "Sat 9pm to Sun 9am" is not one plan.
    static func best(_ answers: [[Int]], days: Int, limit: Int = 3) -> [BestTime] {
        let c = counts(answers, days: days)
        guard let top = c.max(), top > 0 else { return [] }
        var runs: [BestTime] = []
        for day in 0..<days {
            var start: Int?
            for k in 0...Slots.perDay {
                let hit = k < Slots.perDay && c[day * Slots.perDay + k] == top
                if hit, start == nil { start = k }
                if !hit, let s = start {
                    runs.append(BestTime(day: day, first: s, last: k - 1, count: top))
                    start = nil
                }
            }
        }
        return Array(runs.sorted { ($0.last - $0.first, -$0.day, -$0.first) > ($1.last - $1.first, -$1.day, -$1.first) }.prefix(limit))
    }

    /// "Sat 4–6pm". The end is the end of the last slot.
    static func label(_ b: BestTime, days: [Date], calendar: Calendar = .current) -> String {
        guard b.day < days.count else { return "" }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "EEE"
        let s = Slots.start(day: days[b.day], slot: b.first, calendar: calendar)
        let e = Slots.start(day: days[b.day], slot: b.last, calendar: calendar).addingTimeInterval(1800)
        let sameHalf = (calendar.component(.hour, from: s) < 12) == (calendar.component(.hour, from: e) < 12)
        return "\(f.string(from: s)) \(Slots.clock(s, meridiem: !sameHalf, calendar: calendar))–\(Slots.clock(e, calendar: calendar))"
    }
}

// MARK: - Split

enum SplitMath {
    /// Each person's share in cents, with the odd cents carried by the first
    /// few, so the shares always add up to the total. "$33.33 each" on $100
    /// leaves somebody a cent short and the group chat always notices.
    static func shares(totalCents: Int, tipPercent: Int, people: Int) -> (total: Int, each: Int, extraCents: Int)? {
        guard totalCents > 0, people > 0 else { return nil }
        let total = Int((Double(totalCents) * (1 + Double(tipPercent) / 100)).rounded())
        return (total, total / people, total % people)
    }

    static func money(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: Double(cents) / 100)) ?? "$\(cents / 100)"
    }

    /// "12.50" -> 1250. Nil for anything that is not an amount.
    static func cents(_ typed: String) -> Int? {
        let clean = typed.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: clean), value > 0 else { return nil }
        return NSDecimalNumber(decimal: value * 100).rounding(accordingToBehavior: nil).intValue
    }
}

// MARK: - Who do we know: the chat's networks, fused

/// One person somebody in the chat knows, with who knows them.
struct Known: Equatable {
    let name: String
    let about: String?
    let knownBy: [String]
}

enum NetworkFusion {
    /// Each member shares, from their own Amber, the people they know who fit
    /// the question. The same person shared by two members is one person
    /// known twice, which is the strongest intro in the chat, so they merge
    /// and rank first. Two people are the same when their names match after
    /// case, accents, punctuation and spacing are folded. Guessed rule: a
    /// middle name or nickname still splits one person in two, which errs
    /// toward showing two cards rather than wrongly merging two people.
    static func fuse(_ shares: [(member: String, people: [(name: String, about: String?)])]) -> [Known] {
        var order: [String] = []
        var name: [String: String] = [:]
        var about: [String: String] = [:]
        var by: [String: [String]] = [:]
        for share in shares {
            for p in share.people {
                let key = fold(p.name)
                guard !key.isEmpty else { continue }
                if name[key] == nil { order.append(key); name[key] = p.name }
                if about[key] == nil, let a = p.about, !a.isEmpty { about[key] = a }
                if !(by[key] ?? []).contains(share.member) { by[key, default: []].append(share.member) }
            }
        }
        return order.enumerated()
            .sorted { (by[$0.element]?.count ?? 0, -$0.offset) > (by[$1.element]?.count ?? 0, -$1.offset) }
            .map { Known(name: name[$0.element] ?? "", about: about[$0.element], knownBy: by[$0.element] ?? []) }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "en_US"))
            .components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

// MARK: - Amber's chat stream and session (from Kyber)

struct SSEFrame {
    let event: String
    let data: [String: Any]
}

struct SSEParser {
    private var buffer = ""

    mutating func feed(_ chunk: String) -> [SSEFrame] {
        buffer += chunk.replacingOccurrences(of: "\r\n", with: "\n")
        var frames: [SSEFrame] = []
        while let range = buffer.range(of: "\n\n") {
            let raw = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            var event = ""
            var data: [String] = []
            for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
                if line.hasPrefix(":") { continue }
                if line.hasPrefix("event:") { event = line.dropFirst(6).trimmingCharacters(in: .whitespaces) }
                else if line.hasPrefix("data:") { data.append(String(line.dropFirst(5))) }
            }
            guard !event.isEmpty else { continue }
            let joined = data.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
            let obj = joined.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            frames.append(SSEFrame(event: event, data: obj))
        }
        return frames
    }
}

enum AmberJWT {
    /// Same 60 s skew as the Amber app (lib/sessionRefresh.ts). An unreadable
    /// token fails open, so a format we do not know is still tried.
    static func needsRefresh(_ token: String, now: Date = Date()) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return false }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let d = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let exp = obj["exp"] as? Double else { return false }
        return exp - now.timeIntervalSince1970 <= 60
    }

    static func iso(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
