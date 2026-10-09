import SwiftUI

// The team board's faces (Team.swift), in the app's own look: white blocks on
// the paper page, hairlines, ink pills for the one main action, SF Pro, never
// smaller than 13pt. Built for a thumb in a group chat: the one thing done most
// (move my task forward) is one tap on the dot at the left of its row, and
// everything else is one sheet away.

// MARK: - Home and the small sheet

/// On home, above the group cards: where the team stands, one tap from the board.
struct TeamEntry: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var team: TeamStore

    var body: some View {
        // Shown before the first load too: a new thread has no chat on the
        // server until something starts one, and the board is what starts it.
        if team.board?.available != false {
            Button { store.revealFrom = .zero; withAnimation(.reveal) { store.route = .team }; store.host?.expand() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checklist")
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(Circle().fill(Amber.ink))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Team board").font(Amber.font(16, .bold)).foregroundStyle(Amber.ink)
                        Text(team.summary).font(Amber.font(14)).foregroundStyle(Amber.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if !team.unsaid.isEmpty { Circle().fill(Amber.amber).frame(width: 10, height: 10).accessibilityLabel("Updates to tell the chat") }
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Amber.muted)
                }
                .padding(12)
                .block()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the Chewbacca team board")
        }
    }
}

/// The board as one pill in the keyboard-sized sheet.
struct TeamPill: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var team: TeamStore
    var body: some View {
        if team.board?.available != false {
            Button { store.route = .team; store.host?.expand() } label: {
                Label(team.board?.linked == true ? "Team: \(team.summary)" : "Team board", systemImage: "checklist")
                    .font(Amber.font(15, .bold)).foregroundStyle(.white).lineLimit(1)
                    .frame(maxWidth: 240)
                    .padding(.horizontal, 14).frame(height: 40)
                    .background(Capsule().fill(Amber.ink))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - The board

struct TeamView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var team: TeamStore
    @AppStorage("amber.team.tab") private var tab = "mine"
    @State private var showBacklog = false
    @State private var expanded: Set<String> = []

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = team.error { Text(error).font(Amber.font(15)).foregroundStyle(Amber.danger) }
                    if let board = team.board {
                        if !board.available {
                            Text("The team board isn't switched on for Amber yet.").font(Amber.font(17)).foregroundStyle(Amber.body)
                        } else if !board.linked {
                            LinkTeamView()
                        } else if board.me == nil {
                            WhoAreYouView()
                        } else {
                            header
                            tabs
                            switch tab {
                            case "team": everyone
                            case "done": done
                            default: mine
                            }
                        }
                    } else {
                        loading
                    }
                }
                .padding(20)
                .padding(.bottom, team.unsaid.isEmpty ? 20 : 84)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .refreshable { await team.load() }
            if !team.unsaid.isEmpty { tellBar }
        }
        .background(Amber.paper.ignoresSafeArea())
        .sheet(item: $team.editing) { t in TaskSheet(id: t.id).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $team.adding) { AddTaskSheet().presentationDetents([.medium, .large]) }
        .sheet(item: $team.proofFor) { t in ProofSheet(task: t).presentationDetents([.height(320)]) }
        .task {
            _ = await store.ensureSession()
            await team.load()
            // A teammate's change shows up while the board is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await team.load()
            }
        }
    }

    private var loading: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Amber.wash).frame(height: 64)
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Opening the board")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tab == "team" ? "Everyone" : tab == "done" ? "Shipped" : "Your week")
                    .font(Amber.font(28, .heavy)).headline().foregroundStyle(Amber.ink)
                Text(team.summary).font(Amber.font(16)).foregroundStyle(Amber.body)
            }
            Spacer()
            Button { team.adding = true } label: {
                Image(systemName: "plus").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Circle().fill(Amber.ink))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a task")
        }
    }

    private var tabs: some View {
        HStack(spacing: 6) {
            ForEach([("mine", "Mine"), ("team", "Everyone"), ("done", "Done")], id: \.0) { key, label in
                Button { withAnimation(.smooth(duration: 0.25)) { tab = key } } label: {
                    Text(label).font(Amber.font(15, .bold))
                        .foregroundStyle(tab == key ? .white : Amber.ink)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Capsule().fill(tab == key ? Amber.ink : Amber.sheet))
                        .overlay(Capsule().strokeBorder(tab == key ? .clear : Amber.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // Mine: the work in my hands, review first because someone is waiting on it.
    @ViewBuilder private var mine: some View {
        let open = team.open(of: team.me)
        let now = open.filter { $0.stage != .backlog }
        let later = open.filter { $0.stage == .backlog }
        if now.isEmpty {
            EmptyBoard(text: "Nothing on your plate. Add one, or pick something from Everyone.")
        } else {
            TaskList(tasks: now)
        }
        if !later.isEmpty {
            Button { withAnimation(.smooth) { showBacklog.toggle() } } label: {
                HStack {
                    Text("Backlog, \(later.count)").font(Amber.font(15, .bold)).foregroundStyle(Amber.muted)
                    Image(systemName: showBacklog ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(Amber.muted)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            if showBacklog { TaskList(tasks: later) }
        }
    }

    // Everyone: one section per teammate, so the chat sees who's on what.
    @ViewBuilder private var everyone: some View {
        ForEach(team.members) { m in
            let open = team.open(of: m.name).filter { $0.stage != .backlog }
            VStack(alignment: .leading, spacing: 8) {
                PersonHeader(member: m, tasks: open, isMe: m.name == team.me)
                if open.isEmpty {
                    Text("Nothing assigned").font(Amber.font(15)).foregroundStyle(Amber.muted).padding(.leading, 48)
                } else {
                    // Three each, so the whole team fits in a scroll or two;
                    // the rest are one tap away.
                    let all = expanded.contains(m.name)
                    TaskList(tasks: all ? open : Array(open.prefix(3)))
                    if open.count > 3 {
                        Button { withAnimation(.smooth) { if all { expanded.remove(m.name) } else { expanded.insert(m.name) } } } label: {
                            Text(all ? "Show fewer" : "Show all \(open.count)").font(Amber.font(15, .bold)).foregroundStyle(Amber.ink)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        let loose = team.tasks.filter { $0.owner.isEmpty && ($0.stage == .todo || $0.stage == .in_progress) }
        if !loose.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nobody's yet, \(loose.count)").font(Amber.font(17, .bold)).foregroundStyle(Amber.ink)
                TaskList(tasks: loose, showOwner: false)
            }
        }
    }

    @ViewBuilder private var done: some View {
        let shipped = team.tasks.filter { $0.stage == .done }.sorted { $0.updated > $1.updated }
        if shipped.isEmpty {
            EmptyBoard(text: "Nothing shipped in the last two weeks. Friday's proof lands here.")
        } else {
            TaskList(tasks: shipped, showOwner: true)
        }
    }

    private var tellBar: some View {
        Button { Task { await team.tell() } } label: {
            HStack(spacing: 10) {
                if team.working.contains("tell") { ProgressView().tint(.white) } else { Image(systemName: "arrow.up.message.fill") }
                Text("Tell the chat, \(team.unsaid.count) \(team.unsaid.count == 1 ? "update" : "updates")").lineLimit(1)
            }
        }
        .buttonStyle(BlockButton(primary: true, full: true))
        .padding(.horizontal, 20).padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct EmptyBoard: View {
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").font(.system(size: 18, weight: .semibold)).foregroundStyle(Amber.amber)
            Text(text).font(Amber.font(16)).foregroundStyle(Amber.body)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).block()
    }
}

struct PersonHeader: View {
    let member: TeamMember
    let tasks: [TeamTask]
    let isMe: Bool
    var body: some View {
        HStack(spacing: 10) {
            Text(member.initial).font(Amber.font(16, .heavy)).foregroundStyle(isMe ? .white : Amber.ink)
                .frame(width: 38, height: 38).background(Circle().fill(isMe ? Amber.bubble : Amber.amberSoft))
            VStack(alignment: .leading, spacing: 1) {
                Text(isMe ? "\(member.name) (you)" : member.name).font(Amber.font(17, .bold)).foregroundStyle(Amber.ink)
                Text(line).font(Amber.font(14)).foregroundStyle(Amber.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var line: String {
        let doing = tasks.filter { $0.stage == .in_progress }.count
        let review = tasks.filter { $0.stage == .in_review }.count
        let todo = tasks.filter { $0.stage == .todo }.count
        let parts = [doing > 0 ? "\(doing) doing" : nil, review > 0 ? "\(review) in review" : nil, todo > 0 ? "\(todo) to do" : nil].compactMap { $0 }
        return parts.isEmpty ? member.role : parts.joined(separator: ", ")
    }
}

struct TaskList: View {
    let tasks: [TeamTask]
    var showOwner = false
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { i, t in
                TaskRow(task: t, showOwner: showOwner)
                if i < tasks.count - 1 { Rectangle().fill(Amber.hairline).frame(height: 1).padding(.leading, 60) }
            }
        }
        .block()
    }
}

struct TaskRow: View {
    let task: TeamTask
    var showOwner = false
    @EnvironmentObject var team: TeamStore

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            StatusDot(stage: task.stage, busy: team.working.contains(task.id)) { team.advance(task) }
                .accessibilityLabel("\(task.stage.label). \(task.stage.next.map { "Tap to mark \($0.label)" } ?? "")")
            Button { team.editing = task } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(Amber.font(16, .bold)).foregroundStyle(task.stage == .done ? Amber.muted : Amber.ink)
                        .strikethrough(task.stage == .done, color: Amber.muted)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    meta
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12).padding(.trailing, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 6)
    }

    private var meta: some View {
        HStack(spacing: 6) {
            Text(task.id).font(Amber.font(13, .bold)).foregroundStyle(Amber.muted).monospacedDigit()
            if task.stage == .in_review { Tag(text: "Review", color: Amber.link) }
            if let d = task.dueDate {
                let late = TeamDates.overdue(task)
                Tag(text: late ? "Late, \(TeamDates.short(d))" : TeamDates.short(d), color: late ? Amber.danger : Amber.body)
            }
            if task.priority == "urgent" || task.priority == "high" { Tag(text: task.priority.capitalized, color: Amber.bubble) }
            if showOwner && !task.owner.isEmpty { Text(task.owner).font(Amber.font(13)).foregroundStyle(Amber.muted) }
        }
        .lineLimit(1)
    }
}

struct Tag: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(Amber.font(13, .bold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.1)))
    }
}

/// The left of every row: shows the stage, and one tap moves it forward.
struct StatusDot: View {
    let stage: TeamStage
    let busy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    switch stage {
                    case .todo, .backlog:
                        Circle().strokeBorder(Amber.muted, style: StrokeStyle(lineWidth: 2, dash: stage == .backlog ? [3, 3] : []))
                    case .in_progress:
                        Circle().strokeBorder(Amber.amber, lineWidth: 2)
                            .overlay(Circle().trim(from: 0, to: 0.5).fill(Amber.amber).rotationEffect(.degrees(-90)).padding(4))
                    case .in_review:
                        Circle().strokeBorder(Amber.link, lineWidth: 2)
                            .overlay(Circle().trim(from: 0, to: 0.75).fill(Amber.link).rotationEffect(.degrees(-90)).padding(4))
                    case .done:
                        Circle().fill(Amber.ink).overlay(Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white))
                    }
                }
            }
            .frame(width: 22, height: 22)
            .frame(width: 50, height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy || stage == .done)
        .sensoryFeedback(.selection, trigger: stage)
    }
}

// MARK: - First time in a chat

struct LinkTeamView: View {
    @EnvironmentObject var team: TeamStore
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Put the team board in this chat").font(Amber.font(28, .heavy)).headline().foregroundStyle(Amber.ink)
            Text("Everyone here sees who's on what, moves their own tasks, and tells the chat when something ships. It's the same board as the web and the terminal.")
                .font(Amber.font(17)).foregroundStyle(Amber.body)
            TextField("Team code", text: $code).font(Amber.font(19)).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focused).padding(14).block()
                .submitLabel(.go).onSubmit { Task { await team.link(code: code) } }
            Button { Task { await team.link(code: code) } } label: {
                HStack { if team.working.contains("link") { ProgressView().tint(.white) }; Text("Link this chat") }
            }
            .buttonStyle(BlockButton(primary: true, full: true))
            .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || team.working.contains("link"))
            Text("Only a chat with the code can see the board.").font(Amber.font(14)).foregroundStyle(Amber.muted)
        }
    }
}

struct WhoAreYouView: View {
    @EnvironmentObject var team: TeamStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Which one are you?").font(Amber.font(28, .heavy)).headline().foregroundStyle(Amber.ink)
            Text("So your moves show up under your name on the board.").font(Amber.font(17)).foregroundStyle(Amber.body)
            ForEach(team.members) { m in
                Button { Task { await team.setMe(m.name) } } label: {
                    HStack(spacing: 12) {
                        Text(m.initial).font(Amber.font(17, .heavy)).foregroundStyle(Amber.ink)
                            .frame(width: 40, height: 40).background(Circle().fill(Amber.amberSoft))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.name).font(Amber.font(17, .bold)).foregroundStyle(Amber.ink)
                            if !m.role.isEmpty { Text(m.role.capitalized).font(Amber.font(14)).foregroundStyle(Amber.muted) }
                        }
                        Spacer()
                        if team.working.contains("me") { ProgressView() }
                    }
                    .padding(12).block().contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Sheets

struct TaskSheet: View {
    let id: String
    @EnvironmentObject var team: TeamStore
    @Environment(\.dismiss) private var dismiss
    @State private var comment = ""
    @State private var proof = ""
    @State private var pickingDate = false
    @State private var date = Date()
    @State private var needProof = false
    @FocusState private var proofFocused: Bool

    private var task: TeamTask? { team.editing?.id == id ? team.editing : team.task(id) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let t = task {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(t.id).font(Amber.font(14, .bold)).foregroundStyle(Amber.muted)
                            Text(t.title).font(Amber.font(24, .heavy)).headline().foregroundStyle(Amber.ink)
                            if !t.done_when.isEmpty {
                                Text("Done when: \(t.done_when)").font(Amber.font(16)).foregroundStyle(Amber.body)
                            }
                        }
                        if let error = team.error { Text(error).font(Amber.font(15)).foregroundStyle(Amber.danger) }
                        section("Status") {
                            Chips(options: [TeamStage.todo, .in_progress, .in_review, .done, .backlog].map { ($0.rawValue, $0.label) }, selected: t.status) { raw in
                                guard let s = TeamStage(rawValue: raw), s != t.stage else { return }
                                // A second sheet can't open over this one, so done asks
                                // for its proof right here.
                                if s == .done && t.proof.isEmpty && proof.isEmpty { needProof = true; proofFocused = true; return }
                                var body: [String: Any] = ["status": raw]
                                if s == .done && !proof.isEmpty { body["proof"] = proof }
                                Task { await team.update(t, body, said: "\(s.verb) \(t.id) \(t.title)") }
                            }
                        }
                        section("Owner") {
                            Chips(options: team.members.map { ($0.name, $0.name) } + [("", "Nobody")], selected: t.owner) { name in
                                guard name != t.owner else { return }
                                Task { await team.update(t, ["owner": name], said: name.isEmpty ? "unassigned \(t.id)" : "gave \(t.id) \(t.title) to \(name)") }
                            }
                        }
                        section("Due") {
                            Chips(options: TeamDates.quick().map { ($0.1.map(TeamDates.string) ?? "", $0.0) } + [("pick", t.dueDate.map { TeamDates.short($0) } ?? "Pick")],
                                  selected: TeamDates.quick().contains { ($0.1.map(TeamDates.string) ?? "") == t.due } ? t.due : "pick") { key in
                                if key == "pick" { date = t.dueDate ?? Date(); pickingDate = true; return }
                                guard key != t.due else { return }
                                Task { await team.update(t, ["due": key], said: key.isEmpty ? nil : "set \(t.id) due \(TeamDates.parse(key).map { TeamDates.short($0) } ?? key)") }
                            }
                            if pickingDate {
                                DatePicker("Due", selection: $date, displayedComponents: .date).datePickerStyle(.graphical).tint(Amber.amber)
                                Button("Set \(TeamDates.short(date))") {
                                    pickingDate = false
                                    Task { await team.update(t, ["due": TeamDates.string(date)], said: "set \(t.id) due \(TeamDates.short(date))") }
                                }
                                .buttonStyle(BlockButton(full: true))
                            }
                        }
                        section(needProof ? "Proof, to mark it done" : "Proof") {
                            if let url = URL(string: t.proof), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                                Link(destination: url) {
                                    Label(t.proof, systemImage: "link").font(Amber.font(15)).foregroundStyle(Amber.link).lineLimit(1)
                                }
                            }
                            HStack(spacing: 8) {
                                TextField(t.proof.isEmpty ? "Link to the commit, video or page" : "Replace the link", text: $proof)
                                    .font(Amber.font(16)).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .focused($proofFocused)
                                    .padding(12).block()
                                Button(needProof ? "Done" : "Save") {
                                    Task {
                                        var body: [String: Any] = ["proof": proof]
                                        if needProof { body["status"] = "done" }
                                        if await team.update(t, body, said: needProof ? "finished \(t.id) \(t.title)" : nil) { proof = ""; needProof = false }
                                    }
                                }
                                    .buttonStyle(BlockButton()).disabled(proof.isEmpty)
                            }
                        }
                        section("Comment") {
                            HStack(alignment: .bottom, spacing: 8) {
                                TextField("Say something on this task", text: $comment, axis: .vertical)
                                    .font(Amber.font(16)).lineLimit(1...4).padding(12).block()
                                Button("Post") { Task { if await team.update(t, ["comment": comment]) { comment = "" } } }
                                    .buttonStyle(BlockButton(primary: true)).disabled(comment.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        section("In the code?") {
                            if let r = team.checks[t.id] {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(r.short, systemImage: r.symbol).font(Amber.font(16, .bold)).foregroundStyle(r.color)
                                    Text(r.reason).font(Amber.font(15)).foregroundStyle(Amber.body)
                                    ForEach(r.evidence, id: \.label) { e in
                                        if let s = e.url, let url = URL(string: s), url.scheme == "https" {
                                            Link(destination: url) { Text(e.label).font(Amber.font(14)).foregroundStyle(Amber.link).lineLimit(1) }
                                        } else {
                                            Text(e.label).font(Amber.font(14)).foregroundStyle(Amber.muted)
                                        }
                                    }
                                }
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading).block()
                            }
                            Button { Task { await team.check(t) } } label: {
                                HStack {
                                    if team.working.contains("check-\(t.id)") { ProgressView() }
                                    Text(team.working.contains("check-\(t.id)") ? "Reading the commits" : (team.checks[t.id] == nil ? "Check it's really in the code" : "Check again"))
                                }
                            }
                            .buttonStyle(BlockButton(full: true))
                            .disabled(team.working.contains("check-\(t.id)"))
                        }
                        if !t.activity.isEmpty {
                            section("Activity") {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(t.activity.reversed().enumerated()), id: \.offset) { _, line in
                                        Text(line).font(Amber.font(14)).foregroundStyle(Amber.body)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .background(Amber.paper.ignoresSafeArea())
            .navigationTitle("Task").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        }
        .onAppear { team.error = nil }
    }

    private func section<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(Amber.font(15, .bold)).foregroundStyle(Amber.ink)
            content()
        }
    }
}

/// A row of pills; the selected one is ink. Wraps onto a second line.
struct Chips: View {
    let options: [(key: String, label: String)]
    let selected: String
    let pick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.key) { o in
                    let on = o.key == selected
                    Button { pick(o.key) } label: {
                        Text(o.label).font(Amber.font(15, .bold)).foregroundStyle(on ? .white : Amber.ink)
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 14).frame(height: 40)
                            .background(Capsule().fill(on ? Amber.ink : Amber.sheet))
                            .overlay(Capsule().strokeBorder(on ? .clear : Amber.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }
}

struct AddTaskSheet: View {
    @EnvironmentObject var team: TeamStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var owner = ""
    @State private var due = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("What needs doing", text: $title, axis: .vertical)
                        .font(Amber.font(19)).lineLimit(1...3).focused($focused).padding(14).block()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Whose").font(Amber.font(15, .bold)).foregroundStyle(Amber.ink)
                        Chips(options: team.members.map { ($0.name, $0.name == team.me ? "Me" : $0.name) }, selected: owner) { owner = $0 }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Due").font(Amber.font(15, .bold)).foregroundStyle(Amber.ink)
                        Chips(options: TeamDates.quick().map { ($0.1.map(TeamDates.string) ?? "", $0.0) }, selected: due) { due = $0 }
                    }
                    if let error = team.error { Text(error).font(Amber.font(15)).foregroundStyle(Amber.danger) }
                    Button {
                        Task {
                            if await team.add(title: title.trimmingCharacters(in: .whitespacesAndNewlines), owner: owner, due: TeamDates.parse(due)) { dismiss() }
                        }
                    } label: {
                        HStack { if team.working.contains("add") { ProgressView().tint(.white) }; Text("Add to the board") }
                    }
                    .buttonStyle(BlockButton(primary: true, full: true))
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || team.working.contains("add"))
                }
                .padding(20)
            }
            .background(Amber.paper.ignoresSafeArea())
            .navigationTitle("New task").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onAppear { team.error = nil; owner = team.me ?? ""; focused = true }
    }
}

/// Done needs proof on this board, so the last tap asks for the link.
struct ProofSheet: View {
    let task: TeamTask
    @EnvironmentObject var team: TeamStore
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ship \(task.id)").font(Amber.font(24, .heavy)).headline().foregroundStyle(Amber.ink)
            Text("Done needs proof: the commit, the video or the page.").font(Amber.font(16)).foregroundStyle(Amber.body)
            TextField("https://", text: $link).font(Amber.font(17)).keyboardType(.URL)
                .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused).padding(14).block()
            if let error = team.error { Text(error).font(Amber.font(15)).foregroundStyle(Amber.danger) }
            Button {
                Task {
                    if await team.update(task, ["status": "done", "proof": link.trimmingCharacters(in: .whitespaces)], said: "finished \(task.id) \(task.title)") { dismiss() }
                }
            } label: {
                HStack { if team.working.contains(task.id) { ProgressView().tint(.white) }; Text("Mark done") }
            }
            .buttonStyle(BlockButton(primary: true, full: true))
            .disabled(!link.lowercased().hasPrefix("http"))
        }
        .padding(20)
        .background(Amber.paper.ignoresSafeArea())
        .onAppear { team.error = nil; focused = true }
    }
}
