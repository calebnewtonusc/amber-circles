import SafariServices
import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: ChatStore

    var body: some View {
        ZStack {
            Amber.paper.ignoresSafeArea()
            if store.name.isEmpty {
                NameView()
            } else if let building = store.building {
                BuildingView(state: building)
            } else {
                switch store.route {
                case .home: HomeView()
                case .tool(let slug): ToolView(slug: slug)
                }
            }
        }
        .tint(Amber.ink)
    }
}

// MARK: - first open

struct NameView: View {
    @EnvironmentObject var store: ChatStore
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Brand()
                Text("What should the chat call you?").font(Amber.font(30, .heavy)).foregroundStyle(Amber.ink)
                Text("People here will see this name next to what you make.")
                    .font(Amber.font(18)).foregroundStyle(Amber.body)
                TextField("Your first name", text: $text)
                    .font(Amber.font(22)).padding(14).frame(minHeight: 60).block()
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { store.saveName(text) }
                    .onChange(of: focused) { _, isOn in if isOn { store.host?.expand() } }
                Button("That's me") { store.saveName(text) }
                    .buttonStyle(BlockButton(primary: true, full: true))
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)
        }
    }
}

struct Brand: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Amber.amber).overlay(Circle().strokeBorder(Amber.ink, lineWidth: 2))
                .frame(width: 18, height: 18)
            Text("Amber").font(Amber.font(20, .heavy)).foregroundStyle(Amber.ink)
        }
    }
}

struct ErrorLine: View {
    @EnvironmentObject var store: ChatStore
    var body: some View {
        if let error = store.error {
            HStack(alignment: .top) {
                Text(error).font(Amber.font(17, .bold)).foregroundStyle(Amber.danger)
                Spacer()
                Button("OK") { store.error = nil }.font(Amber.font(17, .bold))
            }
        }
    }
}

// MARK: - the Drive for this chat

struct HomeView: View {
    @EnvironmentObject var store: ChatStore
    @State private var request = ""
    @FocusState private var focused: Bool

    private let ideas = [
        "A prayer list for our Bible class",
        "Who is bringing what to Sunday dinner",
        "Rides to church this week",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Brand()
                Text(store.session == nil ? "Let's build together" : "Made in this chat")
                    .font(Amber.font(32, .heavy)).foregroundStyle(Amber.ink)
                if store.session == nil {
                    Text("Say what this chat needs. Claude makes it, and everyone here can open it and change it. Nobody makes an account.")
                        .font(Amber.font(18)).foregroundStyle(Amber.body)
                }
                ErrorLine()
                if let tools = store.overview?.tools, !tools.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                        ForEach(tools) { tool in
                            Button { store.route = .tool(tool.slug); store.host?.expand() } label: { Tile(tool: tool) }
                                .buttonStyle(.plain)
                        }
                    }
                } else if store.loading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(store.session == nil ? "What should we make?" : "Make something new")
                        .font(Amber.font(20, .bold)).foregroundStyle(Amber.ink)
                    Composer(placeholder: "A sign-up sheet for Sunday dinner", text: $request, focused: $focused)
                        .onChange(of: focused) { _, isOn in if isOn { store.host?.expand() } }
                    Text("Tap the mic on your keyboard to say it instead.")
                        .font(Amber.font(16)).foregroundStyle(Amber.muted)
                    if request.isEmpty {
                        ForEach(ideas, id: \.self) { idea in
                            Button { request = idea } label: {
                                Text(idea).font(Amber.font(18, .bold)).foregroundStyle(Amber.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                    .background(Amber.sheet)
                                    .overlay(Rectangle().strokeBorder(Amber.ink.opacity(0.18), lineWidth: 2))
                            }
                        }
                    }
                    Button("Make it") {
                        focused = false
                        let text = request
                        request = ""
                        Task { await store.make(text) }
                    }
                    .buttonStyle(BlockButton(primary: true, full: true))
                    .disabled(request.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let people = store.overview?.people, !people.isEmpty {
                    Text("In this chat: " + people.map(\.name).joined(separator: ", "))
                        .font(Amber.font(16)).foregroundStyle(Amber.muted)
                }
            }
            .padding(20)
        }
        .refreshable { await store.refresh() }
    }
}

struct Tile: View {
    let tool: ToolItem
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tool.title).font(Amber.font(20, .heavy)).foregroundStyle(Amber.ink)
                .multilineTextAlignment(.leading).lineLimit(3)
            if let by = tool.made_by { Text("By \(by)").font(Amber.font(16, .bold)).foregroundStyle(Amber.body) }
            Spacer(minLength: 0)
            if tool.has_draft {
                Text("Change waiting").font(Amber.font(15, .bold)).foregroundStyle(Amber.ink)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Amber.wash).overlay(Rectangle().strokeBorder(Amber.ink, lineWidth: 2))
            }
            Text("\(tool.entries) \(tool.entries == 1 ? "entry" : "entries") · \(timeAgo(tool.updated_at))")
                .font(Amber.font(15)).foregroundStyle(Amber.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .block(lifted: true)
    }
}

// MARK: - building

struct BuildingView: View {
    let state: BuildState
    private let stages = [("thinking", "Reading what you asked for"), ("writing", "Writing it"), ("checking", "Checking it works")]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 18) {
                Brand()
                Text("Making it").font(Amber.font(32, .heavy)).foregroundStyle(Amber.ink)
                Text("\u{201C}\(state.request)\u{201D}").font(Amber.font(19, .bold)).foregroundStyle(Amber.ink)
                    .padding(.leading, 12)
                    .overlay(Rectangle().fill(Amber.amber).frame(width: 6), alignment: .leading)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(stages, id: \.0) { key, label in
                        let index = stages.firstIndex { $0.0 == state.stage } ?? 0
                        let mine = stages.firstIndex { $0.0 == key } ?? 0
                        HStack(spacing: 12) {
                            Circle()
                                .fill(mine < index ? Amber.ink : mine == index ? Amber.wash : .clear)
                                .overlay(Circle().strokeBorder(mine <= index ? Amber.ink : Amber.muted,
                                                              style: StrokeStyle(lineWidth: 2, dash: mine <= index ? [] : [3])))
                                .frame(width: 24, height: 24)
                            Text(label).font(Amber.font(20, .bold))
                                .foregroundStyle(mine <= index ? Amber.ink : Amber.muted)
                            Spacer()
                            if mine == index, !state.detail.isEmpty {
                                Text(state.detail).font(Amber.font(15)).foregroundStyle(Amber.muted)
                            }
                        }
                    }
                }
                .padding(18).block()
                let seconds = Int(context.date.timeIntervalSince(state.started))
                Text("\(seconds) seconds so far. Usually about a minute.")
                    .font(Amber.font(16)).foregroundStyle(Amber.muted)
                Spacer()
            }
            .padding(20)
        }
    }
}

// MARK: - one tool: what it is, open it, talk to it

struct ToolView: View {
    @EnvironmentObject var store: ChatStore
    let slug: String
    @State private var explanation: String?
    @State private var versions: [Version] = []
    @State private var notes: [Note] = []
    @State private var request = ""
    @State private var note = ""
    @State private var showing: URL?
    @FocusState private var focused: Bool
    @FocusState private var noteFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Button { store.route = .home } label: {
                    Label("Everything in this chat", systemImage: "chevron.left")
                        .font(Amber.font(17, .bold)).foregroundStyle(Amber.ink)
                }
                if let tool = store.tool(slug) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tool.title).font(Amber.font(34, .heavy)).foregroundStyle(Amber.ink)
                        if let by = tool.made_by { Text("Made by \(by)").font(Amber.font(17, .bold)).foregroundStyle(Amber.body) }
                    }
                    ErrorLine()
                    section("What it is") {
                        Text(explanation ?? "Reading it so it can explain itself…")
                            .font(Amber.font(19)).foregroundStyle(explanation == nil ? Amber.muted : Amber.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16).block()
                    }
                    HStack(spacing: 12) {
                        Button("Open it") { showing = store.openURL(slug) }
                            .buttonStyle(BlockButton(primary: true, full: true))
                        Button("Send to chat") { store.send(tool, note: "Tap to open it together.") }
                            .buttonStyle(BlockButton(full: true))
                    }
                    section("Talk to it") { conversation(tool) }
                    section("Thoughts from the chat") { thoughts }
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .padding(20)
        }
        .task(id: slug) { await load() }
        .sheet(item: $showing) { url in SafariSheet(url: url).ignoresSafeArea() }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(Amber.font(22, .heavy)).foregroundStyle(Amber.ink)
            content()
        }
    }

    /// Every change is a turn in a conversation: what someone asked, and what
    /// Amber did. A waiting change is the last turn, with its three buttons.
    @ViewBuilder
    private func conversation(_ tool: ToolItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(versions.reversed()) { version in
                Bubble(text: version.request?.isEmpty == false ? version.request! : "Made it", mine: true)
                Bubble(text: version.current ? "Done. This is what everyone sees now." : "Done. Version \(version.version).", mine: false) {
                    if !version.current {
                        Button("Go back to this") { Task { await restore(version.version) } }
                            .font(Amber.font(16, .bold)).foregroundStyle(Amber.ink).underline()
                    }
                }
            }
            if tool.has_draft {
                Bubble(text: tool.draft_request ?? "A change", mine: true)
                Bubble(text: "Here is that change. Only this chat's makers see it until someone keeps it.", mine: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        Button("Try it first") { showing = store.openURL(slug, draft: true) }
                            .buttonStyle(BlockButton(full: true))
                        HStack(spacing: 10) {
                            Button("Keep this") { Task { await store.keep(slug); await load() } }
                                .buttonStyle(BlockButton(primary: true, full: true))
                            Button("Put it back") { Task { await store.discard(slug); await load() } }
                                .buttonStyle(BlockButton(full: true))
                        }
                    }
                }
            } else {
                Composer(placeholder: "Make the writing bigger. Add a place for the date.", text: $request, focused: $focused)
                Button("Make the change") {
                    focused = false
                    let text = request
                    request = ""
                    Task { await store.change(slug, text); await load() }
                }
                .buttonStyle(BlockButton(primary: true, full: true))
                .disabled(request.trimmingCharacters(in: .whitespaces).isEmpty)
                Text("You'll try it first. Nothing changes for anyone until someone keeps it.")
                    .font(Amber.font(16)).foregroundStyle(Amber.muted)
            }
        }
    }

    private var thoughts: some View {
        VStack(alignment: .leading, spacing: 10) {
            if notes.isEmpty {
                Text("Nothing yet. Leave a thought and anyone can turn it into a change later.")
                    .font(Amber.font(17)).foregroundStyle(Amber.muted)
            }
            ForEach(notes) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name ?? "Someone").font(Amber.font(15, .bold)).foregroundStyle(Amber.muted)
                    Text(item.text).font(Amber.font(18)).foregroundStyle(Amber.ink)
                    if store.tool(slug)?.has_draft == false {
                        Button("Make this change") { Task { await store.change(slug, item.text); await load() } }
                            .font(Amber.font(16, .bold)).foregroundStyle(Amber.ink).underline()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).block()
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Leave a thought", text: $note, axis: .vertical)
                    .font(Amber.font(18)).lineLimit(1...4).focused($noteFocused)
                    .padding(12).frame(minHeight: 52).block()
                Button("Add") { Task { await addNote() } }
                    .buttonStyle(BlockButton())
                    .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func load() async {
        guard let token = store.session?.token else { return }
        async let versionList: Versions = API.call("api/tools/\(slug)/versions", chat: token)
        async let noteList: Notes = API.call("api/tools/\(slug)/notes", chat: token)
        do {
            versions = try await versionList.versions
            notes = try await noteList.notes
        } catch { store.error = error.localizedDescription }
        if explanation == nil {
            do {
                let result: Explanation = try await API.call("api/tools/\(slug)/explain", chat: token)
                explanation = result.text
            } catch {
                explanation = store.tool(slug)?.description ?? ""
            }
        }
    }

    private func addNote() async {
        guard let token = store.session?.token else { return }
        let text = note
        note = ""
        noteFocused = false
        do {
            struct Made: Decodable { let id: String }
            let _: Made = try await API.call("api/tools/\(slug)/notes", method: "POST", body: ["text": text], chat: token)
            await load()
        } catch { store.error = error.localizedDescription }
    }

    private func restore(_ version: Int) async {
        guard let token = store.session?.token else { return }
        do {
            struct Restored: Decodable { let version: Int? }
            let _: Restored = try await API.call("api/tools/\(slug)/restore", method: "POST", body: ["version": version], chat: token)
            await store.refresh()
            await load()
        } catch { store.error = error.localizedDescription }
    }
}

struct Bubble<Extra: View>: View {
    let text: String
    let mine: Bool
    @ViewBuilder var extra: () -> Extra

    init(text: String, mine: Bool, @ViewBuilder extra: @escaping () -> Extra = { EmptyView() }) {
        self.text = text
        self.mine = mine
        self.extra = extra
    }

    var body: some View {
        HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 10) {
                Text(text).font(Amber.font(18, mine ? .bold : .regular))
                    .foregroundStyle(mine ? Amber.sheet : Amber.ink)
                extra()
            }
            .padding(12)
            .background(mine ? Amber.ink : Amber.sheet)
            .overlay(Rectangle().strokeBorder(Amber.ink, lineWidth: 2))
            if !mine { Spacer(minLength: 40) }
        }
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

/// The tool itself, full screen, as this person. Safari's view keeps the
/// tool's own sandbox and fonts exactly as they are on the web.
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Amber.ink)
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
