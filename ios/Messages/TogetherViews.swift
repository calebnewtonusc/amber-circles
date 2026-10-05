import SwiftUI

// The faces of group cards (Together.swift), in the app's own look
// (Shared/Theme.swift): white blocks on the paper page, hairlines, ink pills
// for the one main action, SF Pro, never smaller than 13pt.

// MARK: - Home and the small sheet

/// Under the projects on home: start a card, and the chat's open cards.
struct TogetherStrip: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var together: TogetherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CardKind.allCases) { kind in
                        Button { together.composing = kind; store.host?.expand() } label: {
                            Label(kind.short, systemImage: kind.symbol)
                                .font(Amber.font(15, .bold)).foregroundStyle(Amber.ink)
                                .lineLimit(1).fixedSize()
                                .padding(.horizontal, 14).frame(height: 40)
                                .background(Capsule().fill(Amber.sheet))
                                .overlay(Capsule().strokeBorder(Amber.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(kind.amberDoes)
                    }
                }
            }
            .scrollClipDisabled()
            ForEach(together.cards.filter { $0.closed_at == nil }.prefix(3)) { card in
                Button { store.revealFrom = .zero; withAnimation(.reveal) { store.route = .card(card.id) }; store.host?.expand() } label: {
                    CardRow(card: card, people: store.overview?.people.count ?? 0)
                }
                .buttonStyle(.plain)
                .transition(.blurReplace)
            }
        }
        .task { await together.load() }
    }
}

struct CardRow: View {
    let card: Card
    let people: Int
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: card.cardKind.symbol)
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(Amber.ink)
                .frame(width: 40, height: 40).background(Circle().fill(Amber.amberSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title).font(Amber.font(16, .bold)).foregroundStyle(Amber.ink).lineLimit(1)
                Text(card.status(people: people)).font(Amber.font(14)).foregroundStyle(Amber.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Amber.muted)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Amber.sheet))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Amber.hairline, lineWidth: 1))
    }
}

/// The same starts, one pill high, for the keyboard-sized sheet.
struct CompactCards: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var together: TogetherStore
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(together.cards.filter { $0.closed_at == nil }.prefix(4)) { card in
                    Button { store.revealFrom = .zero; store.route = .card(card.id); store.host?.expand() } label: {
                        Label(card.title, systemImage: card.cardKind.symbol)
                            .font(Amber.font(15, .bold)).foregroundStyle(.white).lineLimit(1)
                            .frame(maxWidth: 190)
                            .padding(.horizontal, 14).frame(height: 40)
                            .background(Capsule().fill(Amber.bubble))
                    }
                    .buttonStyle(.plain)
                }
                ForEach(CardKind.allCases) { kind in
                    Button { store.host?.expand(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { together.composing = kind } } label: {
                        Label(kind.short, systemImage: kind.symbol)
                            .font(Amber.font(15)).foregroundStyle(Amber.body).lineLimit(1).fixedSize()
                            .padding(.horizontal, 14).frame(height: 40)
                            .overlay(Capsule().strokeBorder(Amber.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
        .task { await together.load() }
    }
}

// MARK: - Starting a card

struct ComposerView: View {
    let kind: CardKind
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var together: TogetherStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var days: Set<String> = []
    @State private var amount = ""
    @State private var tip = 0
    @State private var venmo = UserDefaults.standard.string(forKey: "amber.venmo") ?? ""
    @State private var options: [(name: String, detail: String?, url: String?)] = []
    @State private var newOption = ""
    @State private var question = ""
    @State private var at = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date().addingTimeInterval(86_400)) ?? Date()
    @State private var sending = false

    private var upcoming: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: Date())) }
    }

    private var placeholder: String {
        switch kind {
        case .free: return "Dinner this week"
        case .split: return "Dinner at Sugarfish"
        case .pick: return "Where should we eat Friday"
        case .who: return "Intro to someone at Pixar"
        case .remind: return "Bring the speaker"
        }
    }

    private var ready: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch kind {
        case .free: return !days.isEmpty
        case .split: return SplitMath.cents(amount) != nil
        case .pick: return options.count >= 2
        case .who: return !question.trimmingCharacters(in: .whitespaces).isEmpty
        case .remind: return at > Date()
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(kind.amberDoes).font(Amber.font(15)).foregroundStyle(Amber.muted)
                    field("What's it for", text: $title, prompt: placeholder)
                    switch kind {
                    case .free: dayPicker
                    case .split: splitFields
                    case .pick: pickFields
                    case .who: field("Who are you looking for", text: $question, prompt: "Who do we know at Pixar?")
                    case .remind:
                        DatePicker("When", selection: $at, in: Date()...)
                            .font(Amber.font(17, .bold)).padding(14).block()
                    }
                    if let error = together.error { Text(error).font(Amber.font(15)).foregroundStyle(Amber.danger) }
                    Button { Task { await start() } } label: {
                        HStack { if sending { ProgressView().tint(.white) }; Text("Start and send to the chat") }
                    }
                    .buttonStyle(BlockButton(primary: true, full: true))
                    .disabled(!ready || sending).opacity(ready ? 1 : 0.4)
                }
                .padding(20)
            }
            .background(Amber.paper.ignoresSafeArea())
            .navigationTitle(kind.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onAppear {
            together.error = nil
            if kind == .free { days = Set(upcoming.prefix(3).map { Slots.dayKey($0) }) }
            if kind == .who { question = "" }
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Amber.font(15, .bold)).foregroundStyle(Amber.ink)
            TextField(prompt, text: text).font(Amber.font(17)).padding(14).block()
        }
    }

    private var dayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Which days").font(Amber.font(15, .bold)).foregroundStyle(Amber.ink)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(upcoming, id: \.self) { day in
                    let key = Slots.dayKey(day), on = days.contains(key)
                    Button {
                        if on { days.remove(key) } else if days.count < 5 { days.insert(key) }
                    } label: {
                        VStack(spacing: 2) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated))).font(Amber.font(13, .bold))
                            Text(day.formatted(.dateTime.day())).font(Amber.font(19, .heavy))
                        }
                        .foregroundStyle(on ? .white : Amber.ink)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Amber.ink : Amber.sheet))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Amber.hairline, lineWidth: on ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private var splitFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Total").font(Amber.font(15, .bold)).foregroundStyle(Amber.ink)
                TextField("$0.00", text: $amount).keyboardType(.decimalPad).font(Amber.font(28, .heavy)).padding(14).block()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Tip").font(Amber.font(15, .bold)).foregroundStyle(Amber.ink)
                Picker("Tip", selection: $tip) {
                    ForEach([0, 15, 18, 20], id: \.self) { Text($0 == 0 ? "None" : "\($0)%").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            field("Your Venmo, so people can pay you in one tap", text: $venmo, prompt: "@your-handle")
        }
    }

    private var pickFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Options").font(Amber.font(15, .bold)).foregroundStyle(Amber.ink)
                Spacer()
                Button {
                    Task {
                        let what = title.isEmpty ? placeholder : title
                        if let ideas = await together.ideasFromAmber(what) { options = Array((options + ideas).prefix(12)) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if together.working.contains("ideas") { ProgressView() } else { Image(systemName: "sparkles") }
                        Text("Ideas from Amber")
                    }
                }
                .buttonStyle(BlockButton())
                .disabled(!together.amberLinked || together.working.contains("ideas"))
            }
            if !together.amberLinked { Text(AmberError.notLinked.localizedDescription).font(Amber.font(14)).foregroundStyle(Amber.muted) }
            ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(o.name).font(Amber.font(16, .bold)).foregroundStyle(Amber.ink)
                        if let d = o.detail { Text(d).font(Amber.font(14)).foregroundStyle(Amber.muted) }
                    }
                    Spacer()
                    Button { options.remove(at: i) } label: { Image(systemName: "xmark").foregroundStyle(Amber.muted).frame(width: 44, height: 44) }
                        .accessibilityLabel("Remove \(o.name)")
                }
                .padding(.leading, 14).block()
            }
            HStack {
                TextField("Add an option", text: $newOption).font(Amber.font(17)).onSubmit(addOption)
                Button("Add", action: addOption).font(Amber.font(16, .bold)).disabled(newOption.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14).block()
        }
    }

    private func addOption() {
        let name = newOption.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, options.count < 12 else { return }
        options.append((String(name.prefix(80)), nil, nil))
        newOption = ""
    }

    private func start() async {
        sending = true
        defer { sending = false }
        var spec: [String: Any] = [:]
        switch kind {
        case .free: spec = ["days": days.sorted()]
        case .split:
            spec = ["total": SplitMath.cents(amount) ?? 0, "tip": tip]
            let handle = venmo.trimmingCharacters(in: .whitespaces)
            if !handle.isEmpty { spec["venmo"] = handle; UserDefaults.standard.set(handle, forKey: "amber.venmo") }
        case .pick:
            spec = ["options": options.map { o -> [String: String] in
                var d = ["name": o.name]
                if let x = o.detail { d["detail"] = x }
                if let u = o.url { d["url"] = u }
                return d
            }]
        case .who: spec = ["question": question]
        case .remind: spec = ["at": ISO8601DateFormatter().string(from: at)]
        }
        guard let card = await together.create(kind, title: title.trimmingCharacters(in: .whitespaces), spec: spec) else { return }
        // Whoever starts a split is in it.
        if kind == .split { await together.answer(card, ["in": true, "paid": true]) }
        dismiss()
        store.revealFrom = .zero
        store.route = .card(card.id)
        together.send(together.card(card.id) ?? card)
    }
}

// MARK: - One card

struct CardView: View {
    let id: String
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var together: TogetherStore
    @State private var candidates: [WhoCandidate]?
    @State private var chosen: Set<String> = []
    @State private var manualName = ""

    private var card: Card? { together.card(id) }
    private var mine: CardEntry? { card?.entry(together.me) }
    private var people: Int { store.overview?.people.count ?? 0 }

    var body: some View {
        ScrollView {
            if let card {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(card.cardKind.name, systemImage: card.cardKind.symbol).font(Amber.font(15, .bold)).foregroundStyle(Amber.muted)
                        Text(card.title).font(Amber.font(28, .heavy)).headline().foregroundStyle(Amber.ink)
                        Text(card.status(people: people)).font(Amber.font(17)).foregroundStyle(Amber.body)
                    }
                    if let error = together.error { Text(error).font(Amber.font(15)).foregroundStyle(Amber.danger) }
                    switch card.cardKind {
                    case .free: free(card)
                    case .split: split(card)
                    case .pick: pick(card)
                    case .who: who(card)
                    case .remind: remind(card)
                    }
                    HStack(spacing: 10) {
                        Button { together.send(card) } label: { Label("Send to the chat", systemImage: "arrow.up.message") }
                            .buttonStyle(BlockButton())
                        if card.made_by == together.me {
                            Button { Task { await together.close(card) } } label: { Text("Close") }.buttonStyle(BlockButton())
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Opening the card").font(Amber.font(15)).foregroundStyle(Amber.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .background(Amber.paper.ignoresSafeArea())
        .task {
            together.error = nil
            await together.load()
            // Everyone else's answers, while the card is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await together.load()
            }
        }
    }

    private func amberNote(_ kind: CardKind) -> some View {
        Text(together.amberLinked ? kind.amberDoes : AmberError.notLinked.localizedDescription)
            .font(Amber.font(14)).foregroundStyle(Amber.muted)
    }

    private func answers(_ card: Card, _ line: @escaping (CardEntry) -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Everyone").font(Amber.font(15, .bold)).foregroundStyle(Amber.ink)
            if card.entries.isEmpty { Text("Nobody yet. Send it to the chat.").font(Amber.font(15)).foregroundStyle(Amber.muted) }
            ForEach(card.entries) { e in
                HStack(alignment: .top, spacing: 10) {
                    Text(String(e.name.prefix(1)).uppercased()).font(Amber.font(13, .heavy)).foregroundStyle(Amber.ink)
                        .frame(width: 28, height: 28).background(Circle().fill(Amber.wash))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.member_id == together.me ? "You" : e.name).font(Amber.font(15, .bold)).foregroundStyle(Amber.ink)
                        Text(line(e)).font(Amber.font(14)).foregroundStyle(Amber.muted)
                    }
                }
            }
        }
    }

    // MARK: When's everyone free

    @ViewBuilder private func free(_ card: Card) -> some View {
        let days = card.days
        let answers = card.entries.map { $0.data["slots"]?.array.compactMap(\.int) ?? [] }
        let counts = Overlap.counts(answers, days: days.count)
        let myslots = Set(mine?.data["slots"]?.array.compactMap(\.int) ?? [])
        let top = max(counts.max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Overlap.best(answers, days: days.count), id: \.first) { b in
                Label("\(Overlap.label(b, days: days)), \(b.count) of \(max(people, card.entries.count))", systemImage: "checkmark.circle.fill")
                    .font(Amber.font(17, .bold)).foregroundStyle(Amber.ink)
            }
            Button {
                Task { if let slots = await together.freeFromAmber(card) { await together.answer(card, ["slots": slots, "amber": true]) } }
            } label: {
                HStack { if together.working.contains(card.id) { ProgressView().tint(.white) }; Text(mine == nil ? "Fill in my free time" : "Refresh my free time") }
            }
            .buttonStyle(BlockButton(primary: true, full: true))
            .disabled(!together.amberLinked || together.working.contains(card.id))
            amberNote(.free)
            Text("Or tap the half hours you can make").font(Amber.font(15, .bold)).foregroundStyle(Amber.ink)
            ForEach(Array(days.enumerated()), id: \.offset) { d, day in
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.formatted(.dateTime.weekday(.wide).month().day())).font(Amber.font(14, .bold)).foregroundStyle(Amber.body)
                    HStack(spacing: 2) {
                        ForEach(0..<Slots.perDay, id: \.self) { k in
                            let slot = d * Slots.perDay + k
                            let share = Double(counts[slot]) / Double(top)
                            Button {
                                var next = myslots
                                if next.contains(slot) { next.remove(slot) } else { next.insert(slot) }
                                Task { await together.answer(card, ["slots": next.sorted()]) }
                            } label: {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(counts[slot] == 0 ? Amber.wash : Amber.amber.opacity(0.25 + 0.75 * share))
                                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(myslots.contains(slot) ? Amber.ink : .clear, lineWidth: 1.5))
                                    .frame(height: 34)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(Slots.clock(Slots.start(day: day, slot: k))), \(counts[slot]) free\(myslots.contains(slot) ? ", including you" : "")")
                        }
                    }
                    HStack {
                        ForEach(["9am", "12pm", "3pm", "6pm", "9pm"], id: \.self) { Text($0).font(Amber.font(13)).foregroundStyle(Amber.muted).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                }
            }
            self.answers(card) { e in
                let n = e.data["slots"]?.array.count ?? 0
                return "\(n / 2)\(n % 2 == 1 ? "½" : "") hours free\(e.data["amber"]?.bool == true ? ", from Amber" : "")"
            }
        }
    }

    // MARK: Split

    @ViewBuilder private func split(_ card: Card) -> some View {
        let inCount = max(card.entries.filter { $0.data["in"]?.bool ?? true }.count, 1)
        let s = SplitMath.shares(totalCents: card.spec["total"]?.int ?? 0, tipPercent: card.spec["tip"]?.int ?? 0, people: inCount)
        let paid = mine?.data["paid"]?.bool ?? false
        VStack(alignment: .leading, spacing: 12) {
            if let s {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(SplitMath.money(s.each)) each").font(Amber.font(34, .heavy)).headline().foregroundStyle(Amber.ink)
                    Text("\(SplitMath.money(s.total)) total\(card.spec["tip"]?.int ?? 0 > 0 ? " with \(card.spec["tip"]?.int ?? 0)% tip" : ""), \(inCount) \(inCount == 1 ? "way" : "ways")\(s.extraCents > 0 ? ", one of you adds \(s.extraCents)¢" : "")")
                        .font(Amber.font(15)).foregroundStyle(Amber.muted)
                }
                if let handle = card.spec["venmo"]?.string, card.made_by != together.me, !paid,
                   let url = URL(string: "https://venmo.com/\(handle)?txn=pay&amount=\(String(format: "%.2f", Double(s.each) / 100))&note=\(card.title.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")") {
                    Button { store.host?.openInRealSafari(url) } label: { Label("Pay \(SplitMath.money(s.each)) on Venmo", systemImage: "arrow.up.right") }
                        .buttonStyle(BlockButton(primary: true, full: true))
                }
            }
            HStack(spacing: 10) {
                Button { Task { await together.answer(card, ["in": true, "paid": !paid]) } } label: {
                    Label(paid ? "Paid" : "I paid", systemImage: paid ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(BlockButton(primary: !paid))
                if mine == nil || mine?.data["in"]?.bool == true {
                    Button { Task { await together.answer(card, ["in": mine == nil, "paid": false]) } } label: { Text(mine == nil ? "I'm in" : "Count me out") }
                        .buttonStyle(BlockButton())
                }
            }
            answers(card) { e in
                guard e.data["in"]?.bool ?? true else { return "Out" }
                return e.data["paid"]?.bool == true ? "Paid" : "Hasn't paid yet"
            }
        }
    }

    // MARK: Vote

    @ViewBuilder private func pick(_ card: Card) -> some View {
        let votes = card.entries.compactMap { $0.data["vote"]?.int }
        let my = mine?.data["vote"]?.int
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(card.options.enumerated()), id: \.offset) { i, o in
                let n = votes.filter { $0 == i }.count
                Button { Task { await together.answer(card, ["vote": i]) } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: my == i ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22)).foregroundStyle(my == i ? Amber.amber : Amber.muted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(o.name).font(Amber.font(17, .bold)).foregroundStyle(Amber.ink)
                            if let d = o.detail { Text(d).font(Amber.font(14)).foregroundStyle(Amber.muted) }
                        }
                        Spacer()
                        Text("\(n)").font(Amber.font(20, .heavy)).foregroundStyle(Amber.ink).monospacedDigit()
                    }
                    .padding(14)
                    .background(
                        GeometryReader { g in
                            Amber.amberSoft.frame(width: g.size.width * (votes.isEmpty ? 0 : Double(n) / Double(votes.count)))
                        }
                    )
                    .block()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(o.name), \(n) votes\(my == i ? ", your vote" : "")")
            }
            answers(card) { e in
                let v = e.data["vote"]?.int ?? -1
                return v >= 0 && v < card.options.count ? card.options[v].name : ""
            }
        }
    }

    // MARK: Who do we know

    @ViewBuilder private func who(_ card: Card) -> some View {
        let fused = NetworkFusion.fuse(card.entries.map { e in
            (e.member_id == together.me ? "You" : e.name, e.data["people"]?.array.map { ($0["name"]?.string ?? "", $0["about"]?.string) } ?? [])
        })
        VStack(alignment: .leading, spacing: 12) {
            ForEach(fused, id: \.name) { k in
                HStack(spacing: 12) {
                    Text(String(k.name.prefix(1)).uppercased()).font(Amber.font(15, .heavy)).foregroundStyle(Amber.ink)
                        .frame(width: 40, height: 40).background(Circle().fill(Amber.amberSoft))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(k.name).font(Amber.font(17, .bold)).foregroundStyle(Amber.ink)
                        if let a = k.about { Text(a).font(Amber.font(14)).foregroundStyle(Amber.body) }
                        Text("Known by \(ListFormatter.localizedString(byJoining: k.knownBy))").font(Amber.font(14, .bold))
                            .foregroundStyle(k.knownBy.count > 1 ? Amber.bubble : Amber.muted)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading).block()
            }
            if let candidates {
                Text(candidates.isEmpty ? "Amber didn't find anyone in your people for this." : "Pick who to share. Nobody else is sent.")
                    .font(Amber.font(15, .bold)).foregroundStyle(Amber.ink)
                ForEach(candidates) { c in
                    Button { if chosen.contains(c.id) { chosen.remove(c.id) } else { chosen.insert(c.id) } } label: {
                        HStack {
                            Image(systemName: chosen.contains(c.id) ? "checkmark.square.fill" : "square").font(.system(size: 20))
                                .foregroundStyle(chosen.contains(c.id) ? Amber.amber : Amber.muted)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.name).font(Amber.font(16, .bold)).foregroundStyle(Amber.ink)
                                if let a = c.about { Text(a).font(Amber.font(14)).foregroundStyle(Amber.muted) }
                            }
                            Spacer()
                        }
                        .padding(12).block()
                    }
                    .buttonStyle(.plain)
                }
                if !candidates.isEmpty {
                    Button { Task { await share(card, candidates.filter { chosen.contains($0.id) }, amber: true) } } label: { Text("Share \(chosen.count) with the chat") }
                        .buttonStyle(BlockButton(primary: true, full: true)).disabled(chosen.isEmpty)
                }
            } else {
                Button { Task { candidates = await together.peopleFromAmber(card); chosen = [] } } label: {
                    HStack { if together.working.contains(card.id) { ProgressView().tint(.white) }; Text("Check my people") }
                }
                .buttonStyle(BlockButton(primary: true, full: true))
                .disabled(!together.amberLinked || together.working.contains(card.id))
                amberNote(.who)
            }
            HStack {
                TextField("Or add someone you know", text: $manualName).font(Amber.font(17))
                Button("Add") {
                    let name = manualName.trimmingCharacters(in: .whitespaces)
                    manualName = ""
                    Task { await share(card, [WhoCandidate(id: name, name: name, about: nil)], amber: false) }
                }
                .font(Amber.font(16, .bold)).disabled(manualName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14).block()
        }
    }

    /// Adds to what you already shared on this card instead of replacing it.
    private func share(_ card: Card, _ picked: [WhoCandidate], amber: Bool) async {
        let already = mine?.data["people"]?.array.map { p -> [String: String] in
            var d = ["name": p["name"]?.string ?? ""]
            if let a = p["about"]?.string { d["about"] = a }
            return d
        } ?? []
        let added = picked.map { c -> [String: String] in
            var d = ["name": c.name]
            if let a = c.about { d["about"] = a }
            return d
        }
        var seen = Set<String>()
        let people = (already + added).filter { seen.insert(NetworkFusion.fold($0["name"] ?? "")).inserted }
        await together.answer(card, ["people": Array(people.prefix(10)), "amber": amber || (mine?.data["amber"]?.bool ?? false)])
        candidates = nil
    }

    // MARK: Remind us

    @ViewBuilder private func remind(_ card: Card) -> some View {
        let joined = mine?.data["in"]?.bool ?? false
        VStack(alignment: .leading, spacing: 12) {
            if let at = card.spec["at"]?.string.flatMap(AmberJWT.iso) {
                Label(at.formatted(date: .complete, time: .shortened), systemImage: "bell.fill").font(Amber.font(17, .bold)).foregroundStyle(Amber.ink)
            }
            Button {
                Task {
                    let saved = together.amberLinked ? await together.remindInAmber(card) : false
                    await together.answer(card, ["in": true, "saved": saved])
                }
            } label: {
                HStack { if together.working.contains(card.id) { ProgressView().tint(.white) }; Text(joined ? "You're in" : "Remind me too") }
            }
            .buttonStyle(BlockButton(primary: !joined, full: true))
            .disabled(joined || together.working.contains(card.id))
            amberNote(.remind)
            answers(card) { e in e.data["saved"]?.bool == true ? "In, saved in Amber" : "In" }
        }
    }
}
