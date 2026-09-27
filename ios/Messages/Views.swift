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
                case .tool(let slug): ToolView(slug: slug, speaker: store.speaker)
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
                    HoldToTalk(label: "Hold and say what to make") { heard in
                        Task { await store.make(heard) }
                    }
                    Text("Or type it").font(Amber.font(16, .bold)).foregroundStyle(Amber.muted)
                    Composer(placeholder: "A sign-up sheet for Sunday dinner", text: $request, focused: $focused)
                        .onChange(of: focused) { _, isOn in if isOn { store.host?.expand() } }
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
    @State private var copied = false
    @ObservedObject private var speaker: Speaker

    init(slug: String, speaker: Speaker) {
        self.slug = slug
        self.speaker = speaker
    }
    @FocusState private var focused: Bool
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Button { store.route = .home } label: {
                            Label("Everything in this chat", systemImage: "chevron.left")
                                .font(Amber.font(17, .bold)).foregroundStyle(Amber.ink)
                        }
                        if let tool = store.tool(slug) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tool.title).font(Amber.font(30, .heavy)).foregroundStyle(Amber.ink)
                                if let by = tool.made_by { Text("Made by \(by)").font(Amber.font(16, .bold)).foregroundStyle(Amber.body) }
                            }
                            safariCard(tool)
                            ErrorLine()
                            conversation(tool)
                            DisclosureGroup("Comments from the chat (\(notes.count))") { thoughts }
                                .font(Amber.font(17, .bold)).foregroundStyle(Amber.ink).tint(Amber.ink)
                            Color.clear.frame(height: 1).id("end")
                        } else {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                        }
                    }
                    .padding(20)
                }
                .onChange(of: store.talk[slug]?.count ?? 0) { _, _ in
                    withAnimation { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
            dock
        }
        .task(id: slug) {
            await load()
            await store.loadTalk(slug)
            if (store.talk[slug] ?? []).isEmpty, let explanation, !explanation.isEmpty {
                store.greet(slug, explanation + " Tap the link at the top to try it in Safari, then come back and tell me what to change.")
            }
        }
    }

    /// The tool lives on the web. This card is how you get there and back:
    /// open it in Safari, play with it, come back and talk.
    private func safariCard(_ tool: ToolItem) -> some View {
        Button {
            if let url = store.openURL(slug, draft: tool.has_draft) { store.host?.openInSafari(url) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "safari").font(.system(size: 28, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.has_draft ? "Try your draft in Safari" : "Open it in Safari")
                        .font(Amber.font(20, .heavy))
                    Text(tool.has_draft ? "Only this chat sees it until someone keeps it." : "Play with it, then come back and tell me.")
                        .font(Amber.font(15)).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 18, weight: .bold))
            }
            .foregroundStyle(Amber.ink)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .block(fill: Amber.amber, lifted: true)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy the link") { UIPasteboard.general.url = store.link(for: slug) }
            Button("Send it to the chat") { store.send(tool, note: "Tap to open it together.") }
        }
    }

    /// The talk button lives at the bottom, where a thumb already is.
    private var dock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HoldToTalk(label: "Hold to talk to Amber", onPress: { speaker.stop() }) { heard in
                Task { await store.say(slug, heard, open: { store.host?.openInSafari($0) }); await load() }
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Or type it", text: $request, axis: .vertical)
                    .font(Amber.font(18)).lineLimit(1...3).focused($focused)
                    .padding(12).frame(minHeight: 48).block()
                Button("Send") {
                    focused = false
                    let text = request
                    request = ""
                    Task { await store.say(slug, text, open: { store.host?.openInSafari($0) }); await load() }
                }
                .buttonStyle(BlockButton())
                .disabled(request.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Toggle(isOn: $speaker.isOn) {
                Text("Amber talks back").font(Amber.font(15, .bold)).foregroundStyle(Amber.body)
            }
            .tint(Amber.present)
        }
        .padding(16)
        .background(Amber.paper)
        .overlay(Rectangle().fill(Amber.ink).frame(height: 2), alignment: .top)
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
            }
            if let started = store.changing[slug] {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Bubble(text: "Making that change. \(Int(context.date.timeIntervalSince(started))) seconds so far. You can keep talking to me.", mine: false)
                }
            }
            if tool.has_draft, store.changing[slug] == nil {
                Bubble(text: "Want to keep it?", mine: false) {
                    HStack(spacing: 10) {
                        Button("Keep this") { Task { await store.keep(slug); await load() } }
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

import WebKit

/// The tool itself, running live inside the editor, the way v0 shows the
/// thing next to the conversation. Tap to open it full screen.
struct LivePreview: View {
    let url: URL?
    let label: String
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(Amber.present).frame(width: 10, height: 10)
                Text(label).font(Amber.font(16, .bold)).foregroundStyle(Amber.ink)
                Spacer()
                Button("Full screen", action: open).font(Amber.font(16, .bold)).foregroundStyle(Amber.ink).underline()
            }
            WebFrame(url: url)
                .frame(height: 380)
                .overlay(Rectangle().strokeBorder(Amber.ink, lineWidth: 2))
                .background(Rectangle().fill(Amber.ink).offset(x: 4, y: 4))
        }
    }
}

struct WebFrame: UIViewRepresentable {
    let url: URL?
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.isOpaque = false
        view.backgroundColor = UIColor(Amber.paper)
        if let url { view.load(URLRequest(url: url)) }
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
