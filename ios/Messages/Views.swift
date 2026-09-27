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
                    .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))
                case .tool(let slug): ToolView(slug: slug, speaker: store.speaker)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
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
                Text("What should the chat call you?").font(Amber.font(30, .heavy)).headline().foregroundStyle(Amber.ink)
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
            Image("AmberLogo").resizable().scaledToFit().frame(height: 26)
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

    @State private var watching = false

    var body: some View {
        VStack(spacing: 0) {
            if store.changing["__new"] != nil {
                LivePanel(slug: nil, expanded: $watching)
                    .padding(.horizontal, 16).padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Brand()
                        Text(store.session == nil ? "Let's build together" : "Made in this chat")
                            .font(Amber.font(30, .heavy)).headline().foregroundStyle(Amber.ink)
                        if store.session == nil {
                            Text("Tell Amber what this chat needs. It builds it, everyone here can open it and change it, and it remembers what each of you said.")
                                .font(Amber.font(18)).foregroundStyle(Amber.body)
                        }
                        ErrorLine()
                        if let tools = store.overview?.tools, !tools.isEmpty {
                            VStack(spacing: 10) {
                                ForEach(tools) { tool in
                                    Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { store.route = .tool(tool.slug) }; store.host?.expand() } label: {
                                        AppRow(tool: tool, unshared: store.unpublished.contains(tool.slug))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else if store.loading {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                        }
                        ForEach(store.talk[""] ?? []) { turn in
                            Bubble(text: turn.text, mine: turn.mine)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        if let people = store.overview?.people, !people.isEmpty {
                            Text("In this chat: " + people.map(\.name).joined(separator: ", "))
                                .font(Amber.font(15)).foregroundStyle(Amber.muted)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(20)
                }
                .onChange(of: store.talk[""]?.count ?? 0) { _, _ in
                    withAnimation { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                HoldToTalk(label: "Hold to talk to Amber", onPress: { store.speaker.stop() }) { heard in
                    Task { await store.say("", heard) }
                }
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Or type what the chat needs", text: $request, axis: .vertical)
                        .font(Amber.font(18)).lineLimit(1...3).focused($focused)
                        .padding(12).frame(minHeight: 48).block()
                        .onChange(of: focused) { _, isOn in if isOn { store.host?.expand() } }
                    Button("Send") {
                        focused = false
                        let text = request
                        request = ""
                        Task { await store.say("", text) }
                    }
                    .buttonStyle(BlockButton(primary: true))
                    .disabled(request.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(16)
            .background(Amber.paper)
            .overlay(Rectangle().fill(Amber.hairline).frame(height: 1), alignment: .top)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: store.changing["__new"] != nil)
        .onChange(of: store.changing["__new"] != nil) { _, building in if !building { watching = false } }
        .task {
            await store.refresh()
            await store.loadTalk("")
        }
    }
}

/// One app the chat made, as a row you tap to talk to it, change it or
/// comment on it.
struct AppRow: View {
    let tool: ToolItem
    var unshared = false
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Amber.wash)
                .frame(width: 48, height: 48)
                .overlay(Text(String(tool.title.prefix(1))).font(Amber.font(22, .heavy)).foregroundStyle(Amber.ink))
            VStack(alignment: .leading, spacing: 3) {
                Text(tool.title).font(Amber.font(18, .heavy)).foregroundStyle(Amber.ink).lineLimit(1)
                Text(unshared ? "Not shared with the chat yet" : tool.has_draft ? "A change is waiting" : "\(tool.made_by.map { "By \($0)" } ?? "Made here") · \(timeAgo(tool.updated_at))")
                    .font(Amber.font(15)).foregroundStyle(unshared || tool.has_draft ? Amber.link : Amber.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(Amber.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .block(lifted: true)
        .contentShape(Rectangle())
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
                    .background(Capsule().fill(Amber.wash))
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
                Text("Making it").font(Amber.font(32, .heavy)).headline().foregroundStyle(Amber.ink)
                Text("\u{201C}\(state.request)\u{201D}").font(Amber.font(19, .bold)).foregroundStyle(Amber.ink)
                    .padding(.leading, 12)
                    .overlay(Capsule().fill(Amber.hairline).frame(width: 3), alignment: .leading)
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
    @State private var copied = false
    @State private var previewing = false
    @ObservedObject private var speaker: Speaker

    init(slug: String, speaker: Speaker) {
        self.slug = slug
        self.speaker = speaker
    }
    @FocusState private var focused: Bool
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Pinned above the conversation, so when the preview grows the
            // chat moves down beneath it instead of scrolling away.
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { store.route = .home } } label: {
                        Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).foregroundStyle(Amber.ink)
                            .frame(width: 36, height: 36).background(Circle().fill(Amber.wash))
                    }
                    .accessibilityLabel("Everything in this chat")
                    VStack(alignment: .leading, spacing: 0) {
                        Text(store.tool(slug)?.title ?? "").font(Amber.font(22, .heavy)).headline().foregroundStyle(Amber.ink).lineLimit(1)
                        if let by = store.tool(slug)?.made_by { Text("Made by \(by)").font(Amber.font(14)).foregroundStyle(Amber.muted) }
                    }
                    Spacer(minLength: 0)
                }
                if store.tool(slug) != nil {
                    LivePanel(slug: slug, expanded: $previewing)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    if store.unpublished.contains(slug) {
                        Button("Publish to the chat") { store.publish(slug) }
                            .buttonStyle(BlockButton(primary: true, full: true))
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: store.tool(slug) != nil)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let tool = store.tool(slug) {
                            ErrorLine()
                            conversation(tool)
                            DisclosureGroup("Comments from the chat (\(notes.count))") { thoughts }
                                .font(Amber.font(17, .bold)).foregroundStyle(Amber.ink).tint(Amber.ink)
                            Color.clear.frame(height: 1).id("end")
                        } else {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 8)
                }
                .onChange(of: store.talk[slug]?.count ?? 0) { _, _ in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
            dock
        }
        .task(id: slug) {
            await load()
            await store.loadTalk(slug)
            if (store.talk[slug] ?? []).isEmpty, let explanation, !explanation.isEmpty {
                store.greet(slug, explanation)
            }
        }
        .sheet(item: $showing) { url in SafariSheet(url: url).ignoresSafeArea() }
    }

    /// The talk button lives at the bottom, where a thumb already is.
    private var dock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HoldToTalk(label: "Hold to talk to Amber", onPress: { speaker.stop() }) { heard in
                Task { await store.say(slug, heard, open: { store.host?.openInRealSafari($0) }); await load() }
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Or type it", text: $request, axis: .vertical)
                    .font(Amber.font(18)).lineLimit(1...3).focused($focused)
                    .padding(12).frame(minHeight: 48).block()
                Button("Send") {
                    focused = false
                    let text = request
                    request = ""
                    Task { await store.say(slug, text, open: { store.host?.openInRealSafari($0) }); await load() }
                }
                .buttonStyle(BlockButton())
                .disabled(request.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .background(Amber.paper)
        .overlay(Rectangle().fill(Amber.hairline).frame(height: 1), alignment: .top)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(Amber.font(22, .heavy)).foregroundStyle(Amber.ink)
            content()
        }
    }

    /// Only the conversation: what people said, what Amber said back, and
    /// the waiting change's two buttons after the last word.
    @ViewBuilder
    private func conversation(_ tool: ToolItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(store.talk[slug] ?? []) { turn in
                Bubble(text: turn.text, mine: turn.mine)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let started = store.changing[slug] {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Bubble(text: "Making that change. \(Int(context.date.timeIntervalSince(started))) seconds so far. You can keep talking to me.", mine: false)
                }
            }
            if tool.has_draft, store.changing[slug] == nil {
                Bubble(text: "Publish it so the chat gets it, or put it back.", mine: false) {
                    HStack(spacing: 10) {
                        Button("Publish changes") { store.publishChanges(slug) }
                            .buttonStyle(BlockButton(primary: true, full: true))
                        Button("Put it back") { Task { await store.discard(slug); await load() } }
                            .buttonStyle(BlockButton(full: true))
                    }
                }
            }
            if versions.count > 1 {
                DisclosureGroup("Earlier versions (\(versions.count))") {
                    ForEach(versions) { version in
                        HStack {
                            Text(version.request?.isEmpty == false ? version.request! : "The first version")
                                .font(Amber.font(16)).foregroundStyle(Amber.body).lineLimit(2)
                            Spacer()
                            if version.current {
                                Text("Live").font(Amber.font(15, .bold)).foregroundStyle(Amber.present)
                            } else {
                                Button("Go back") { Task { await restore(version.version) } }
                                    .font(Amber.font(16, .bold)).foregroundStyle(Amber.ink).underline()
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .font(Amber.font(17, .bold)).foregroundStyle(Amber.ink).tint(Amber.ink)
            }
        }
    }

    private var thoughts: some View {
        VStack(alignment: .leading, spacing: 10) {
            if notes.isEmpty {
                Text("Nothing yet. Leave a thought and anyone can turn it into a change later.")
                    .font(Amber.font(17)).foregroundStyle(Amber.muted)
            }
            if notes.count > 1, store.tool(slug)?.has_draft == false {
                Button("Turn these into one change") {
                    let all = notes.map(\.text).joined(separator: "; ")
                    Task { await store.say(slug, "Make these changes the chat asked for: \(all)"); await load() }
                }
                .buttonStyle(BlockButton(full: true))
            }
            ForEach(notes) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name ?? "Someone").font(Amber.font(15, .bold)).foregroundStyle(Amber.muted)
                    Text(item.text).font(Amber.font(18)).foregroundStyle(Amber.ink)
                    if store.tool(slug)?.has_draft == false {
                        Button("Make this change") { Task { await store.say(slug, item.text); await load() } }
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
        if mine {
            HStack {
                Spacer(minLength: 48)
                Text(text).font(Amber.font(18)).foregroundStyle(Amber.ink)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Amber.wash))
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(Amber.amber).frame(width: 10, height: 10).padding(.top, 8)
                VStack(alignment: .leading, spacing: 12) {
                    Text(text).font(Amber.font(18)).foregroundStyle(Amber.ink).lineSpacing(3)
                    extra()
                }
                Spacer(minLength: 16)
            }
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
