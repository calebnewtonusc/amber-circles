import Foundation

// Compiled with ios/Messages/TogetherCore.swift and run by
// test/together-core.test.js. Exits 1 on any failed check.

var failures = 0
func check(_ ok: Bool, _ what: String, line: UInt = #line) {
    if !ok { failures += 1; print("FAIL line \(line): \(what)") }
}

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
}
let sat = at(10, 0), sun = at(11, 0)

// Free slots from a calendar: class 1-2:30, it is 11:10 now.
let mine = Slots.free(day: sat, busy: [DateInterval(start: at(10, 13), end: at(10, 14, 30))], now: at(10, 11, 10), calendar: cal)
check(!mine.contains(4), "11am already started")
check(mine.first == 5, "first offer is 11:30 (slot 5), got \(mine.first ?? -1)")
check(!mine.contains(8) && !mine.contains(10) && mine.contains(11), "1pm to 2:30 blocked, 2:30 free")
check(Slots.dayKey(sat, calendar: cal) == "2026-10-10" && Slots.date(fromKey: "2026-10-10", calendar: cal) == sat, "day keys round-trip")

// Group overlap: three people, one stretch all three can make.
let a = Array(14...20), b = Array(12...18), c = [16, 17, 18, 30, 31]
let best = Overlap.best([a, b, c], days: 2)
check(best.first == BestTime(day: 0, first: 16, last: 18, count: 3), "everyone free Sat slots 16-18, got \(best)")
check(Overlap.label(best[0], days: [sat, sun], calendar: cal) == "Sat 5–6:30pm", "label: \(Overlap.label(best[0], days: [sat, sun], calendar: cal))")
check(Overlap.counts([[0, 0, 0]], days: 1)[0] == 1, "one person counts once per slot")
check(Overlap.best([], days: 2).isEmpty, "nobody answered, no best time")
let crossing = Overlap.best([[24, 25, 26, 27]], days: 2)
check(crossing.count == 2, "a run never crosses midnight")

// Split to the cent.
let s = SplitMath.shares(totalCents: 10000, tipPercent: 0, people: 3)!
check(s.each == 3333 && s.extraCents == 1, "100 three ways leaves a cent")
let t = SplitMath.shares(totalCents: 8400, tipPercent: 18, people: 4)!
check(t.total == 9912 && t.each == 2478 && t.extraCents == 0, "84 + 18% four ways")
check(SplitMath.cents("$1,234.50") == 123450 && SplitMath.cents("abc") == nil && SplitMath.cents("0") == nil, "typed amounts")

// Two members know the same person: one card, known twice, ranked first.
let fused = NetworkFusion.fuse([
    (member: "Caleb", people: [(name: "Jake Lin", about: "Founder"), (name: "Priya Loran", about: nil)]),
    (member: "Gavin", people: [(name: "jake  lin", about: nil), (name: "Semyon K", about: "UT")]),
    (member: "Gavin", people: [(name: "Jake Lin", about: nil)]),
])
check(fused.first == Known(name: "Jake Lin", about: "Founder", knownBy: ["Caleb", "Gavin"]), "fused: \(fused)")
check(fused.count == 3 && fused[1].name == "Priya Loran", "order kept after the shared one: \(fused.map(\.name))")
check(NetworkFusion.fold("José  O'Neil") == "jose o neil", "folding: \(NetworkFusion.fold("José  O'Neil"))")

// The chat stream across chunk boundaries.
var parser = SSEParser()
check(parser.feed("event: people\ndata: {\"people\":[{\"na").isEmpty, "half a frame waits")
let frames = parser.feed("me\":\"Jake\"}]}\n\n: ping\n\n")
check(frames.count == 1 && frames[0].event == "people", "one frame, comment skipped")

if failures > 0 { print("\(failures) failed"); exit(1) }
print("together core: all checks passed")
