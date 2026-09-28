import SafariServices
import SwiftUI

private struct TitlesKey: EnvironmentKey { static let defaultValue: Namespace.ID? = nil }
extension EnvironmentValues {
    /// Shared so an app's name on its row flies up into the big title on its
    /// screen (Caleb, 2026-09-27: "when you click the title on the home page,
    /// that should animate into the big title on the project page").
    var titles: Namespace.ID? {
        get { self[TitlesKey.self] }
        set { self[TitlesKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder
    func sharedTitle(_ id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace { self.matchedGeometryEffect(id: id, in: namespace) } else { self }
    }
}

extension Animation {
    /// Every open and close. No bounce and nothing fades: Caleb, 2026-09-27,
    /// "it should be like a mask between 2 layers, simple as that. Idk why you
    /// keep flash banging the entire screen". The flash was the whole screen
    /// crossfading plus a matched-geometry card fading in on top of it.
    static let reveal = Animation.smooth(duration: 0.42)
}

/// A window cut into the layer on top, growing from the row that was tapped
/// until it is the whole screen. Both layers stay fully opaque the whole way.
struct RevealShape: Shape {
    var from: CGRect
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // With no row to grow from, grow from where the talk bar is.
        let start = from == .zero
            ? CGRect(x: rect.minX + 16, y: rect.maxY - 130, width: rect.width - 32, height: 60)
            : from
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * progress }
        let frame = CGRect(x: mix(start.minX, rect.minX), y: mix(start.minY, rect.minY),
                           width: mix(start.width, rect.width), height: mix(start.height, rect.height))
        return RoundedRectangle(cornerRadius: mix(12, 0), style: .continuous).path(in: frame)
    }
}

private struct RevealMask: ViewModifier {
    let from: CGRect
    let progress: CGFloat
    func body(content: Content) -> some View { content.clipShape(RevealShape(from: from, progress: progress)) }
}

extension AnyTransition {
    static func reveal(from: CGRect) -> AnyTransition {
        .modifier(active: RevealMask(from: from, progress: 0), identity: RevealMask(from: from, progress: 1))
    }
}

struct RootView: View {
    @EnvironmentObject var store: ChatStore
    @Namespace private var titles

    var body: some View {
        ZStack {
            Amber.paper.ignoresSafeArea()
            if store.personKey == nil {
                SignInView()
            } else if !store.unlocked && !(store.personKey ?? "").isEmpty {
                LockView()
            } else if store.name.isEmpty {
                NameView()
            } else if let building = store.building {
                BuildingView(state: building)
            } else {
                // Home stays put underneath; an app is the layer on top,
                // revealed through a mask on the way in and the way out.
                // The talk bar sits under every screen and never moves;
                // only the space above it changes (Caleb: "it should be the
                // same amber/nav bar, that shouldn't have to reanimate").
                VStack(spacing: 0) {
                    ZStack {
                        switch store.route {
                        case .home: HomeView().transition(.identity).zIndex(0)
                        case .tool(let slug):
                            ToolView(slug: slug, speaker: store.speaker)
                                .transition(.reveal(from: store.revealFrom)).zIndex(1)
                        case .draft(let key):
                            DraftView(key: key).transition(.reveal(from: store.revealFrom)).zIndex(1)
                        }
                    }
                    .coordinateSpace(.named("stage"))
                    TalkBar()
                }
            }
        }
        .environment(\.titles, titles)
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
                Image("AmberLogo").resizable().scaledToFit().frame(width: 52, height: 60).accessibilityHidden(true)
                Text("What should the chat call you?").font(Amber.font(30, .heavy)).headline().foregroundStyle(Amber.ink)
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
    /// Where each row sits on screen, so opening it grows from that row.
    @State private var frames: [String: CGRect] = [:]
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(store.session == nil && store.drafts.isEmpty ? "Let's build together" : "Made in this chat")
                        .font(Amber.font(30, .heavy)).headline().foregroundStyle(Amber.ink)
                    ErrorLine()
                    apps
                    boardSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.reveal, value: store.drafts)
            }
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture { store.host?.view.endEditing(true) }
            if let caption = store.caption {
                HStack(alignment: .top, spacing: 10) {
                    Image("AmberLogo").resizable().scaledToFit().frame(width: 16, height: 18).padding(.top, 3)
                    TypedText(text: caption, animate: true)
                    Button { withAnimation(.reveal) { store.caption = nil } } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Amber.muted)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Amber.sheet))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Amber.hairline, lineWidth: 1))
                .padding(.horizontal, 16).padding(.bottom, 8)
                .transition(.scale(scale: 0.96, anchor: .bottom).combined(with: .opacity))
            }
            if let live = store.liveSpeech {
                Bubble(text: live, mine: true, live: true).padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .background(Amber.paper.ignoresSafeArea())
        .animation(.reveal, value: store.caption)
        .task {
            await store.refresh()
            await store.loadBoard()
        }
        .task {
            // Presence and new comments, while this screen is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                await store.loadBoard()
            }
        }
    }

    private var apps: some View {
        VStack(spacing: 10) {
            ForEach(store.drafts) { draft in
                Button { store.revealFrom = frames[draft.id] ?? .zero; withAnimation(.reveal) { store.route = .draft(draft.id) }; store.host?.expand() } label: {
                    DraftRow(draft: draft, building: store.changing[draft.id] != nil, doing: store.doing[draft.id])
                }
                .buttonStyle(.plain)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("stage")) } action: { frames[draft.id] = $0 }
                .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
            }
            ForEach(store.overview?.tools ?? []) { tool in
                Button { store.revealFrom = frames[tool.slug] ?? .zero; withAnimation(.reveal) { store.route = .tool(tool.slug) }; store.host?.expand() } label: {
                    AppRow(tool: tool, unshared: store.unpublished.contains(tool.slug))
                }
                .buttonStyle(.plain)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("stage")) } action: { frames[tool.slug] = $0 }
            }
            if store.loading && (store.overview?.tools ?? []).isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }

    /// Comments, to-dos and ideas from across the chat, under the apps.
    @ViewBuilder
    private var boardSection: some View {
        if let board = store.board, !(board.comments.isEmpty && board.ideas.isEmpty && board.building.isEmpty) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(board.building) { now in
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("\(now.who) is making \(now.what)").font(Amber.font(16, .bold)).foregroundStyle(Amber.ink).lineLimit(2)
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Amber.amberSoft))
                }
                ForEach(board.comments) { item in
                    Button {
                        if let slug = item.slug { store.revealFrom = frames[slug] ?? .zero; withAnimation(.reveal) { store.route = .tool(slug) } }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(item.name ?? "Someone") on \(item.title ?? "an app")").font(Amber.font(14, .bold)).foregroundStyle(Amber.muted)
                            Text(item.text).font(Amber.font(17)).foregroundStyle(Amber.ink).multilineTextAlignment(.leading)
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading).block()
                    }
                    .buttonStyle(.plain)
                }
                ForEach(board.ideas) { idea in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb").font(.system(size: 15, weight: .semibold)).foregroundStyle(Amber.amber)
                        Text(idea.description).font(Amber.font(17)).foregroundStyle(Amber.ink)
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).block()
                }
            }
        }
    }
}

/// A new app being talked about, before it exists.
struct DraftRow: View {
    let draft: DraftApp
    let building: Bool
    let doing: String?
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Amber.amberSoft)
                .frame(width: 48, height: 48)
                .overlay {
                    if building { ProgressView().controlSize(.small) } else {
                        Image(systemName: "sparkles").font(.system(size: 18, weight: .semibold)).foregroundStyle(Amber.amber)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(draft.title).font(Amber.font(18, .heavy)).foregroundStyle(Amber.ink).fixedSize(horizontal: false, vertical: true)
                Text(building ? (doing ?? "Building") : "Talking it through with Amber")
                    .font(Amber.font(15)).foregroundStyle(Amber.link).lineLimit(1)
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

/// The screen of a new app while it is being talked through: its own
/// conversation, and its preview once building starts.
struct DraftView: View {
    @EnvironmentObject var store: ChatStore
    let key: String
    @State private var request = ""
    @State private var watching = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button { store.host?.view.endEditing(true); withAnimation(.reveal) { store.route = .home } } label: {
                        Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).foregroundStyle(Amber.ink)
                            .frame(width: 36, height: 36).background(Circle().fill(Amber.wash))
                    }
                    .accessibilityLabel("Everything in this chat")
                    Text(store.drafts.first { $0.id == key }?.title ?? "New app")
                        .font(Amber.font(22, .heavy)).headline().foregroundStyle(Amber.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                if store.changing[key] != nil {
                    LivePanel(slug: nil, buildKey: key, expanded: $watching)
                        .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
            .animation(.reveal, value: store.changing[key] != nil)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(store.talk[key] ?? []) { turn in
                            Bubble(text: turn.text, mine: turn.mine, who: turn.who, typing: turn.fresh)
                                .transition(.scale(scale: 0.96, anchor: .bottom).combined(with: .opacity))
                        }
                        if let live = store.liveSpeech { Bubble(text: live, mine: true, live: true) }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 20).padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .onTapGesture { store.host?.view.endEditing(true) }
                .onChange(of: store.talk[key]?.count ?? 0) { _, _ in
                    withAnimation(.reveal) { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
        }
        .background(Amber.paper.ignoresSafeArea())
    }
}

/// One app the chat made, as a row you tap to talk to it, change it or
/// comment on it.
struct AppRow: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.titles) private var titles
    let tool: ToolItem
    var unshared = false
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Amber.wash)
                .frame(width: 48, height: 48)
                .overlay(Text(String(tool.title.prefix(1))).font(Amber.font(22, .heavy)).foregroundStyle(Amber.ink))
            VStack(alignment: .leading, spacing: 3) {
                // While its screen is open the name lives there, so moving
                // between the two is one title flying, not two fading.
                if store.route == .tool(tool.slug) {
                    Text(tool.title).font(Amber.font(18, .heavy)).fixedSize(horizontal: false, vertical: true).hidden()
                } else {
                    Text(tool.title).font(Amber.font(18, .heavy)).foregroundStyle(Amber.ink).fixedSize(horizontal: false, vertical: true)
                        .sharedTitle("title-\(tool.slug)", in: titles)
                }
                Text(unshared ? "Not shared with the chat yet" : tool.has_draft ? "A change is waiting" : "\(tool.made_by.map { "By \($0)" } ?? "Made here") · \(timeAgo(tool.updated_at))")
                    .font(Amber.font(15)).foregroundStyle(unshared || tool.has_draft ? Amber.link : Amber.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(Amber.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Amber.sheet))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Amber.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 2)
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
                Image("AmberLogo").resizable().scaledToFit().frame(width: 52, height: 60).accessibilityHidden(true)
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
    @Environment(\.titles) private var titles
    @EnvironmentObject var store: ChatStore
    let slug: String
    @State private var explanation: String?
    @State private var versions: [Version] = []
    @State private var notes: [Note] = []
    @State private var request = ""
    @State private var showing: URL?
    @State private var copied = false
    @State private var previewing = false
    @ObservedObject private var speaker: Speaker

    init(slug: String, speaker: Speaker) {
        self.slug = slug
        self.speaker = speaker
    }
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Pinned above the conversation, so when the preview grows the
            // chat moves down beneath it instead of scrolling away.
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button { store.host?.view.endEditing(true); withAnimation(.reveal) { store.route = .home } } label: {
                        Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).foregroundStyle(Amber.ink)
                            .frame(width: 36, height: 36).background(Circle().fill(Amber.wash))
                    }
                    .accessibilityLabel("Everything in this chat")
                    Text(store.tool(slug)?.title ?? "").font(Amber.font(22, .heavy)).headline().foregroundStyle(Amber.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .sharedTitle("title-\(slug)", in: titles)
                    Spacer(minLength: 0)
                }
                if store.tool(slug) != nil {
                    VStack(spacing: 0) {
                        LivePanel(slug: slug, expanded: $previewing)
                        CommentsTray(slug: slug, notes: notes) { await load() }
                            .padding(.horizontal, 12)
                            .zIndex(-1)
                    }
                    .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
                    if store.unpublished.contains(slug) {
                        Button("Publish to the chat") { store.publish(slug) }
                            .buttonStyle(BlockButton(primary: true, full: true))
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
            .animation(.reveal, value: store.tool(slug) != nil)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let tool = store.tool(slug) {
                            ErrorLine()
                            conversation(tool)
                            Color.clear.frame(height: 1).id("end")
                        } else {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .onTapGesture { store.host?.view.endEditing(true) }
                .onChange(of: store.talk[slug]?.count ?? 0) { _, _ in
                    withAnimation(.reveal) { proxy.scrollTo("end", anchor: .bottom) }
                    Task { await load() }
                }
            }
        }
        // Only the container edge: ignoring the keyboard's safe area too is
        // what left the talk bar hidden under the keyboard.
        .background(Amber.paper.ignoresSafeArea())
        .task(id: slug) {
            await load()
            await store.loadTalk(slug)
            // Opening an app: who made it the first time, what changed after
            // that. The plain explanation only when there is nothing newer.
            if let news = await store.catchUp(slug), !news.isEmpty {
                store.greet(slug, news)
            } else if (store.talk[slug] ?? []).isEmpty, let explanation, !explanation.isEmpty {
                store.greet(slug, explanation)
            }
        }
        .sheet(item: $showing) { url in SafariSheet(url: url).ignoresSafeArea() }
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
                Bubble(text: turn.text, mine: turn.mine, who: turn.who, typing: turn.fresh)
                    .transition(.scale(scale: 0.96, anchor: .bottom).combined(with: .opacity))
            }
            if let live = store.liveSpeech {
                Bubble(text: live, mine: true, live: true)
                    .transition(.opacity)
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

/// A message laid out the way iMessage lays out a group chat: yours on the
/// right in blue, everyone else on the left in grey with their name above.
/// Shirley, 2026-09-27: "make it look like imessage, like the name is above
/// what they texted".
struct Bubble<Extra: View>: View {
    let text: String
    let mine: Bool
    var who: String? = nil
    var typing = false
    var live = false
    @ViewBuilder var extra: () -> Extra

    init(text: String, mine: Bool, who: String? = nil, typing: Bool = false, live: Bool = false, @ViewBuilder extra: @escaping () -> Extra = { EmptyView() }) {
        self.text = text
        self.mine = mine
        self.who = who
        self.typing = typing
        self.live = live
        self.extra = extra
    }

    var body: some View {
        if mine {
            HStack {
                Spacer(minLength: 56)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(text.isEmpty && live ? " " : text).font(Amber.font(17)).foregroundStyle(.white)
                        .contentTransition(.interpolate)
                        .animation(.easeOut(duration: 0.12), value: text)
                    if live { Caret(color: .white) }
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Amber.iMessageBlue.opacity(live ? 0.75 : 1)))
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(who ?? "Amber").font(Amber.font(12)).foregroundStyle(Amber.muted).padding(.leading, 14)
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 12) {
                        TypedText(text: text, animate: typing, size: 17)
                        extra()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Amber.iMessageGrey))
                    Spacer(minLength: 40)
                }
            }
        }
    }
}

/// The blinking bar at the end of what you are saying right now.
struct Caret: View {
    var color = Amber.amber
    @State private var on = true
    var body: some View {
        RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2, height: 20)
            .opacity(on ? 1 : 0.15)
            .onAppear { withAnimation(.easeInOut(duration: 0.5).repeatForever()) { on = false } }
    }
}

/// Amber's reply, typed out letter by letter the first time it appears.
struct TypedText: View {
    let text: String
    let animate: Bool
    var size: CGFloat = 18
    @State private var start = Date()
    var body: some View {
        if animate {
            TimelineView(.animation) { context in
                let shown = min(text.count, Int(context.date.timeIntervalSince(start) * 55))
                Text(String(text.prefix(shown))).font(Amber.font(size)).foregroundStyle(Amber.ink).lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Text(text).font(Amber.font(size)).lineSpacing(3).hidden())
            }
        } else {
            Text(text).font(Amber.font(size)).foregroundStyle(Amber.ink).lineSpacing(3)
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

/// The one talk bar, under every screen. What it does depends on where you
/// are: at home it starts something new, inside an app it talks to that app.
struct TalkBar: View {
    @EnvironmentObject var store: ChatStore
    @State private var request = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The logo sits with the thing it names, not repeated at the top.
            HStack(spacing: 12) {
                Image("AmberLogo").resizable().scaledToFit().frame(width: 30, height: 34)
                    .accessibilityHidden(true)
                HoldToTalk(label: "Hold to talk to Amber", onPress: { store.speaker.stop() }) { heard in send(heard) }
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(store.route == .home ? "Or type what the chat needs" : "Or type it", text: $request, axis: .vertical)
                    .font(Amber.font(18)).foregroundStyle(Amber.ink).lineLimit(1...3).focused($focused)
                    .padding(12).frame(minHeight: 48).block()
                    .onChange(of: focused) { _, isOn in if isOn { store.host?.expand() } }
                Button("Send") {
                    focused = false
                    let text = request
                    request = ""
                    send(text)
                }
                .buttonStyle(BlockButton(primary: true))
                .disabled(request.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .background(Amber.paper)
        .overlay(Rectangle().fill(Amber.hairline).frame(height: 1), alignment: .top)
    }

    private func send(_ text: String) {
        Task {
            switch store.route {
            case .home: await store.homeSay(text)
            case .draft(let key): await store.say(key, text)
            case .tool(let slug): await store.say(slug, text, open: { store.host?.openInRealSafari($0) })
            }
        }
    }
}

/// Comments, tucked under the preview as part of it, so they never read as
/// messages in the conversation. They work like Google Docs: reply to one,
/// resolve it when it is handled (Caleb, 2026-09-27).
struct CommentsTray: View {
    @EnvironmentObject var store: ChatStore
    let slug: String
    let notes: [Note]
    let reload: () async -> Void
    @State private var open = false
    @State private var text = ""
    @State private var replyingTo: Note?
    @FocusState private var focused: Bool

    private var threads: [Note] { notes.filter { $0.parent_id == nil && $0.resolved_at == nil } }
    private func replies(_ id: String) -> [Note] { notes.filter { $0.parent_id == id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.reveal) { open.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble").font(.system(size: 13, weight: .semibold)).foregroundStyle(Amber.amber)
                    Text(threads.isEmpty ? "Comment" : "\(threads.count) \(threads.count == 1 ? "comment" : "comments")")
                        .font(Amber.font(15, .bold)).foregroundStyle(Amber.ink)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.top, 6)
                .frame(height: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(threads) { thread in card(thread) }
                        composer
                    }
                    .padding(.horizontal, 10).padding(.bottom, 10)
                }
                .frame(maxHeight: 300)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14, style: .continuous).fill(Amber.wash))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14, style: .continuous))
        .overlay(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14, style: .continuous).strokeBorder(Amber.hairline, lineWidth: 1))
    }

    private func card(_ thread: Note) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(thread.name ?? "Someone").font(Amber.font(14, .bold)).foregroundStyle(Amber.ink)
                Text(timeAgo(thread.created_at)).font(Amber.font(13)).foregroundStyle(Amber.muted)
                Spacer()
                Button { Task { await resolve(thread) } } label: {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Amber.amber)
                        .frame(width: 32, height: 32).background(Circle().fill(Amber.amberSoft))
                }
                .accessibilityLabel("Resolve")
            }
            Text(thread.text).font(Amber.font(16)).foregroundStyle(Amber.ink).fixedSize(horizontal: false, vertical: true)
            ForEach(replies(thread.id)) { reply in
                VStack(alignment: .leading, spacing: 2) {
                    Text(reply.name ?? "Someone").font(Amber.font(13, .bold)).foregroundStyle(Amber.muted)
                    Text(reply.text).font(Amber.font(15)).foregroundStyle(Amber.ink).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 10)
                .overlay(Rectangle().fill(Amber.hairline).frame(width: 2), alignment: .leading)
            }
            HStack(spacing: 16) {
                Button("Reply") { replyingTo = thread; focused = true }
                    .font(Amber.font(14, .bold)).foregroundStyle(Amber.amber)
                if store.tool(slug)?.has_draft == false {
                    Button("Make this change") { Task { await store.say(slug, thread.text) } }
                        .font(Amber.font(14, .bold)).foregroundStyle(Amber.ink)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Amber.sheet))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let replyingTo {
                HStack(spacing: 6) {
                    Text("Replying to \(replyingTo.name ?? "a comment")").font(Amber.font(13, .bold)).foregroundStyle(Amber.muted)
                    Button { self.replyingTo = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Amber.muted)
                    }
                    .accessibilityLabel("Cancel reply")
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(replyingTo == nil ? "Add a comment" : "Reply", text: $text, axis: .vertical)
                    .font(Amber.font(16)).foregroundStyle(Amber.ink).lineLimit(1...4).focused($focused)
                    .padding(10).frame(minHeight: 44).block()
                    .onChange(of: focused) { _, isOn in if isOn { store.host?.expand() } }
                Button("Post") { Task { await post() } }
                    .buttonStyle(BlockButton(primary: true))
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func post() async {
        guard let token = store.session?.token else { return }
        var body: [String: Any] = ["text": text]
        if let replyingTo { body["parent"] = replyingTo.id }
        text = ""
        replyingTo = nil
        focused = false
        do {
            struct Made: Decodable { let id: String }
            let _: Made = try await API.call("api/tools/\(slug)/notes", method: "POST", body: body, chat: token)
            await reload()
        } catch { store.error = error.localizedDescription }
    }

    private func resolve(_ thread: Note) async {
        guard let token = store.session?.token else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        do {
            struct Done: Decodable { let ok: Bool }
            let _: Done = try await API.call("api/tools/\(slug)/notes/\(thread.id)/resolve", method: "POST", body: ["resolved": true], chat: token)
            await reload()
        } catch { store.error = error.localizedDescription }
    }
}
