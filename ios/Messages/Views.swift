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
    static let reveal = Animation.smooth(duration: 0.5)
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

extension Animation {
    /// New messages only: a quick spring with a little give, the way a text
    /// lands in Messages (Caleb, 2026-09-27: "animate from the bottom like
    /// texts usually do when they come in").
    static let messageIn = Animation.spring(response: 0.38, dampingFraction: 0.78)
}

extension AnyTransition {
    /// A message rises from the bottom and grows out of its own corner.
    static func incoming(mine: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.6, anchor: mine ? .bottomTrailing : .bottomLeading)
                .combined(with: .offset(y: 24))
                .combined(with: .opacity),
            removal: .identity)
    }

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
            // The top bar is fixed like the talk bar: screens change beneath
            // it and nothing animates over it (Caleb, 2026-09-27).
            VStack(spacing: 0) {
            if !store.firstRun { TopBar() }
            ZStack {
            // Between steps the amber pill is one object that slides and scales
            // to its next place, and the words around it blur across. The mask
            // tried first chewed the old screen away from the bottom (Caleb,
            // 2026-09-27: "ur transitions are so ass").
            if store.personKey == nil {
                SignInView().transition(.blurReplace).zIndex(1)
            } else if !store.unlocked && !(store.personKey ?? "").isEmpty {
                LockView().transition(.blurReplace).zIndex(2)
            } else if store.name.isEmpty {
                NameView().transition(.blurReplace).zIndex(3)
            } else if let building = store.building {
                BuildingView(state: building).transition(.blurReplace).zIndex(4)
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
                .transition(.blurReplace).zIndex(5)
            }
            if store.firstRun { FirstRunHeader().zIndex(10) }
            }
            }
        }
        .coordinateSpace(.named("root"))
        // One headline for the whole app. First run and the top bar only say
        // where it goes, so on the way in the question travels from the
        // middle to the top while it deletes, then types the new words there.
        .overlayPreferenceValue(HeadlineKey.self) { slots in
            GeometryReader { proxy in
                if let slot = slots.max(by: { $0.rank < $1.rank }) {
                    let frame = proxy[slot.anchor]
                    RetypingText(target: slot.text, size: slot.size, wraps: slot.wraps)
                        .frame(width: frame.width, height: frame.height, alignment: .leading)
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)
                }
            }
        }
        // The one egg. Screens only say where it should be; it is drawn here,
        // above all of them, so it moves and scales between places instead of
        // fading out on one screen and in on the next (Caleb, 2026-09-27).
        .overlayPreferenceValue(EggSlotKey.self) { slots in
            GeometryReader { proxy in
                if let slot = slots.max(by: { $0.rank < $1.rank }) {
                    let frame = proxy[slot.anchor]
                    Image("AmberLogo").resizable().scaledToFit()
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        // No animation of its own: it rides whatever moved the
                        // screen. With one keyed to its frame it trailed half a
                        // second behind the text whenever the window was dragged.
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
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
    @Environment(\.titles) private var titles
    @State private var text = ""
    /// Set the moment it starts leaving, so the keyboard closing underneath
    /// cannot drag the whole screen down while it blurs away.
    @State private var leaving = false
    @State private var opened = false
    @State private var hint = ""

    /// The button becomes the talk bar's pill on the way to home. The
    /// keyboard goes first: closing it moves the talk bar, and the egg and
    /// pill chased that moving target and landed late (seen frame by frame,
    /// 2026-09-27). Its close takes about a quarter second.
    private func next() {
        leaving = true
        store.host?.view.endEditing(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(.reveal) { store.saveName(text) }
        }
    }
    @FocusState private var focused: Bool

    var body: some View {
        TallAware(frozen: leaving) { tall in
            VStack(alignment: .leading, spacing: tall ? 28 : 18) {
                // Same spot on every step, so the egg and title never move between
                // them (Caleb, 2026-09-27). Centering moved them, because each
                // step has a different amount under its title.
                if tall { Color.clear.frame(height: Onboarding.headerTop) }
                // Room for the egg and headline, drawn once above both steps.
                Color.clear.frame(height: Onboarding.headerHeight)
                TextField(hint, text: $text)
                    .font(Amber.font(22)).padding(14).frame(minHeight: 60).block()
                    .mask(alignment: .leading) {
                        GeometryReader { box in
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .frame(width: opened ? box.size.width : 0)
                        }
                    }
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { next() }
                    .onChange(of: focused) { _, isOn in if isOn { store.host?.expand() } }
                Button("That's me") { next() }
                    .buttonStyle(BlockButton(primary: true, full: true))
                    .sharedTitle("pill", in: titles)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
            }
            .padding(20)
        }
        .ignoresSafeArea(leaving ? .keyboard : [])
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.reveal) { opened = true }
            try? await Task.sleep(for: .milliseconds(450))
            for letter in "Your first name" {
                hint.append(letter)
                try? await Task.sleep(for: .milliseconds(28))
            }
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
                .transition(.blurReplace)
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
            Button { startNew() } label: { NewProjectRow() }
                .buttonStyle(.plain)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("stage")) } action: { frames["__new"] = $0 }
            ForEach(store.drafts) { draft in
                Button { store.revealFrom = frames[draft.id] ?? .zero; withAnimation(.reveal) { store.route = .draft(draft.id) }; store.host?.expand() } label: {
                    DraftRow(draft: draft, building: store.changing[draft.id] != nil, doing: store.doing[draft.id])
                }
                .buttonStyle(.plain)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("stage")) } action: { frames[draft.id] = $0 }
                .transition(.blurReplace)
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
            } else if (store.overview?.tools ?? []).isEmpty && store.drafts.isEmpty {
                Text("No projects made yet. Time to build!")
                    .font(Amber.font(17)).foregroundStyle(Amber.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// A blank project: its box opens out of the button, and Amber asks what
    /// it should be before building anything.
    private func startNew() {
        let draft = store.newDraft(title: "New project")
        store.revealFrom = frames["__new"] ?? .zero
        withAnimation(.reveal) { store.route = .draft(draft.id) }
        store.host?.expand()
        store.greet(draft.id, "What are we making? Tell me who it's for and what it needs to do.")
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
                if store.changing[key] != nil {
                    LivePanel(slug: nil, buildKey: key, expanded: $watching)
                        .transition(.blurReplace)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
            .animation(.reveal, value: store.changing[key] != nil)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(store.talk[key] ?? []) { turn in
                            Bubble(text: turn.text, mine: turn.mine, who: turn.who, typing: turn.fresh)
                                .transition(.incoming(mine: turn.mine))
                        }
                        if let live = store.liveSpeech { Bubble(text: live, mine: true, live: true) }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .animation(.messageIn, value: store.talk[key]?.count ?? 0)
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
    let tool: ToolItem
    var unshared = false
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Amber.wash)
                .frame(width: 48, height: 48)
                .overlay(Text(String(tool.title.prefix(1))).font(Amber.font(22, .heavy)).foregroundStyle(Amber.ink))
            VStack(alignment: .leading, spacing: 3) {
                Text(tool.title).font(Amber.font(18, .heavy)).foregroundStyle(Amber.ink).fixedSize(horizontal: false, vertical: true)
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
                if store.tool(slug) != nil {
                    VStack(spacing: 0) {
                        LivePanel(slug: slug, expanded: $previewing)
                        CommentsTray(slug: slug, notes: notes) { await load() }
                            .padding(.horizontal, 12)
                            .zIndex(-1)
                    }
                    .transition(.blurReplace)
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
                    .transition(.incoming(mine: turn.mine))
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
        .animation(.messageIn, value: store.talk[slug]?.count ?? 0)
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
    @Environment(\.titles) private var titles
    @State private var request = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The logo sits with the thing it names, not repeated at the top.
            HStack(spacing: 12) {
                EggSlot(rank: 5).frame(width: 30, height: 34)
                HoldToTalk(label: "Hold to talk to Amber", onPress: { store.speaker.stop() }) { heard in send(heard) }
                    .sharedTitle("pill", in: titles)
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

/// Tells its content whether iMessage has given it the full screen, and
/// moves between the two layouts on the same curve as everything else.
struct TallAware<Content: View>: View {
    var frozen = false
    @ViewBuilder let content: (Bool) -> Content
    @State private var tall = false
    var body: some View {
        content(tall)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onGeometryChange(for: Bool.self) { $0.size.height > 520 } action: { value in
                // Snaps, never glides: Caleb, 2026-09-27, "the sliding up
                // sliding down has gotta stop".
                if !frozen { tall = value }
            }
    }
}

struct EggSlotValue {
    let rank: Int
    let anchor: Anchor<CGRect>
}

/// Where the current screen wants the egg. The newest step outranks the one
/// it is replacing, so during a change the egg heads for the new place.
struct EggSlotKey: PreferenceKey {
    static let defaultValue: [EggSlotValue] = []
    static func reduce(value: inout [EggSlotValue], nextValue: () -> [EggSlotValue]) { value += nextValue() }
}

struct EggSlot: View {
    let rank: Int
    var body: some View {
        Color.clear
            .anchorPreference(key: EggSlotKey.self, value: .bounds) { [EggSlotValue(rank: rank, anchor: $0)] }
            .accessibilityHidden(true)
    }
}

/// The first row on home: start a project without having to say anything.
struct NewProjectRow: View {
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Amber.amber)
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: "plus").font(.system(size: 20, weight: .bold)).foregroundStyle(.white))
            Text("New project").font(Amber.font(18, .heavy)).foregroundStyle(Amber.ink)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Amber.sheet))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Amber.amber.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .contentShape(Rectangle())
    }
}

enum Onboarding {
    /// Where the egg and title sit on every first-run step once iMessage
    /// gives Amber the full screen: about a third of the way down.
    static let headerTop: CGFloat = 200
    /// Two lines of the 30pt headline.
    static let headerHeight: CGFloat = 84
}

/// Deletes what it says, then types the new words, with an amber caret
/// while it works.
struct RetypingText: View {
    let target: String
    let size: CGFloat
    /// First-run headlines wrap to two lines; the top bar's shrinks to one.
    var wraps = false
    @State private var shown = ""
    @State private var working = false

    var body: some View {
        (Text(shown) + Text(working ? "|" : "").foregroundColor(Amber.amber))
            .font(Amber.font(size, .heavy)).headline().foregroundStyle(Amber.ink)
            .lineLimit(wraps ? 2 : 1).minimumScaleFactor(wraps ? 1 : 0.55)
            .fixedSize(horizontal: false, vertical: wraps)
            .accessibilityHidden(true)
            .task(id: target) { await retype() }
    }

    // About 35 letters a second typing, 80 deleting: reads as a person
    // typing, and a two-line title still lands in about a second.
    private func retype() async {
        working = true
        while !shown.isEmpty {
            shown.removeLast()
            try? await Task.sleep(for: .milliseconds(12))
            if Task.isCancelled { return }
        }
        try? await Task.sleep(for: .milliseconds(90))
        for letter in target {
            shown.append(letter)
            try? await Task.sleep(for: .milliseconds(28))
            if Task.isCancelled { return }
        }
        working = false
    }
}

/// The fixed bar at the top: back when inside something, the egg during first
/// run, and the headline, which deletes and retypes whenever the screen changes.
struct TopBar: View {
    @EnvironmentObject var store: ChatStore

    private var title: String {
        if store.building != nil { return "Making it" }
        switch store.route {
        case .home: return "Made in this chat"
        case .tool(let slug): return store.tool(slug)?.title ?? ""
        case .draft(let key): return store.drafts.first { $0.id == key }?.title ?? "New project"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            if store.route != .home {
                Button { store.host?.view.endEditing(true); withAnimation(.reveal) { store.route = .home } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).foregroundStyle(Amber.ink)
                        .frame(width: 36, height: 36).background(Circle().fill(Amber.wash))
                }
                .accessibilityLabel("Everything in this chat")
            }
            HeadlineSlot(rank: 2, text: title, size: 26)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 44)
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 10)
        .background(Amber.paper)
        .zIndex(10)
    }
}

/// The egg and headline for sign-in and the name step. Drawn once above both,
/// at the same place, so going from one to the other the words delete and
/// retype and nothing else moves.
struct FirstRunHeader: View {
    @EnvironmentObject var store: ChatStore

    private var title: String {
        if store.personKey == nil { return "Let's build together" }
        if !store.unlocked && !(store.personKey ?? "").isEmpty { return "Welcome back" }
        return "What should the chat call you?"
    }

    var body: some View {
        TallAware { tall in
            VStack(alignment: .leading, spacing: tall ? 28 : 18) {
                if tall { Color.clear.frame(height: Onboarding.headerTop) }
                HStack(alignment: .center, spacing: 14) {
                    EggSlot(rank: 1).frame(width: 44, height: 50)
                    HeadlineSlot(rank: 1, text: title, size: 30, wraps: true)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: Onboarding.headerHeight)
                Spacer()
            }
            .padding(20)
        }
        .allowsHitTesting(false)
    }
}

struct HeadlineValue {
    let rank: Int
    let text: String
    let size: CGFloat
    let wraps: Bool
    let anchor: Anchor<CGRect>
}

struct HeadlineKey: PreferenceKey {
    static let defaultValue: [HeadlineValue] = []
    static func reduce(value: inout [HeadlineValue], nextValue: () -> [HeadlineValue]) { value += nextValue() }
}

/// Marks where the headline goes; its parent sets the size.
struct HeadlineSlot: View {
    let rank: Int
    let text: String
    let size: CGFloat
    var wraps = false
    var body: some View {
        Color.clear
            .anchorPreference(key: HeadlineKey.self, value: .bounds) {
                [HeadlineValue(rank: rank, text: text, size: size, wraps: wraps, anchor: $0)]
            }
            .accessibilityElement()
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isHeader)
    }
}
