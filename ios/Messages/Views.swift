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

    /// Slides between two places but keeps its own size: matching the frame
    /// forced a short chip's width onto a long one and cut its label off
    /// ("Sign-up sh...", 2026-09-28).
    @ViewBuilder
    func sharedSpot(_ id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace { self.matchedGeometryEffect(id: id, in: namespace, properties: .position) } else { self }
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

private struct RevealMask: ViewModifier, Animatable {
    let from: CGRect
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    // One white card with the row's outline grows and shrinks; the words
    // inside only show once it is nearly open, and leave first on the way
    // back. Clipping the words as the card shrank cut through the middle of
    // a message (Caleb's screenshot, 2026-09-27: "such a bad transition back").
    func body(content: Content) -> some View {
        let shape = RevealShape(from: from, progress: progress)
        content
            .opacity(Double(max(0, (progress - 0.6) / 0.4)))
            .background(shape.fill(Amber.sheet))
            .clipShape(shape)
            .overlay(shape.stroke(Amber.hairline, lineWidth: 1.5))
    }
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
    @EnvironmentObject var together: TogetherStore
    @Namespace private var titles
    /// The sheet's height. iMessage resizes the sheet outside SwiftUI, so the
    /// layout sat still and then snapped when the new size landed; changes
    /// to it now animate on the same curve (the "+" jump, 2026-09-28).
    @State private var height: CGFloat = 0

    var body: some View {
        ZStack {
            Amber.paper.ignoresSafeArea()
            // The top bar is fixed like the talk bar: screens change beneath
            // it and nothing animates over it (Caleb, 2026-09-27).
            VStack(spacing: 0) {
            if !store.firstRun && store.expanded { TopBar() }
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
                // In the keyboard-sized sheet Amber is a launcher; the full
                // app needs the full screen (Caleb, 2026-09-28).
                // One message field for both sizes: only what is above it
                // changes, and matching pieces morph into each other (Caleb,
                // 2026-09-28: "why is the message pill reanimating").
                VStack(spacing: 0) {
                    ZStack {
                        if store.expanded {
                            // Home never leaves. Rebuilt on the way back, every
                            // row popped in at once (Caleb, 2026-09-27).
                            HomeView().zIndex(0)
                            switch store.route {
                            case .home: EmptyView()
                            case .tool(let slug):
                                ToolView(slug: slug, speaker: store.speaker)
                                    .transition(.reveal(from: store.revealFrom)).zIndex(1)
                            case .draft(let key):
                                DraftView(key: key).transition(.reveal(from: store.revealFrom)).zIndex(1)
                            case .card(let id):
                                CardView(id: id).transition(.reveal(from: store.revealFrom)).zIndex(1)
                            case .team:
                                TeamView().transition(.reveal(from: store.revealFrom)).zIndex(1)
                            }
                        } else {
                            CompactView()
                        }
                    }
                    .coordinateSpace(.named("stage"))
                    TalkBar()
                }
                .transition(.blurReplace)
                .zIndex(5)
            }
            if store.firstRun { FirstRunHeader().zIndex(10) }
            }
            // Any tap above the keyboard puts it away (Caleb, 2026-09-28).
            .simultaneousGesture(TapGesture().onEnded {
                if store.keyboardInset > 0 { store.host?.view.endEditing(true) }
            })
            }
            .padding(.bottom, store.keyboardInset)
            .ignoresSafeArea(.keyboard)
        }
        .coordinateSpace(.named("root"))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .animation(.smooth(duration: 0.38), value: height)
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
        .sheet(item: $together.composing) { kind in ComposerView(kind: kind) }
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
    @Environment(\.titles) private var titles
    @State private var request = ""
    /// Where each row sits on screen, so opening it grows from that row.
    @State private var frames: [String: CGRect] = [:]
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Projects first, under the header, then one Activity for all of
            // them; the chat with Amber fills the rest (Caleb, 2026-09-27).
            VStack(alignment: .leading, spacing: 10) {
                ErrorLine()
                ScrollView { apps.padding(.vertical, 2) }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: 236)
                    .fixedSize(horizontal: false, vertical: true)
                // The Chewbacca board, for a chat linked to it (Team.swift).
                TeamEntry()
                // Amber's own features, made for the group.
                TogetherStrip()
                HomeActivityTray(frames: $frames)
            }
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 8)
            .animation(.reveal, value: store.drafts)
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Home is a chat too: what people asked Amber here, its
                    // answers, and a card for every project started from it.
                    VStack(alignment: .leading, spacing: 12) {
                        if (store.talk[""] ?? []).isEmpty && store.liveSpeech == nil
                            && (store.overview?.tools ?? []).isEmpty && store.drafts.isEmpty { StarterChips() }
                        ForEach(store.talk[""] ?? []) { turn in
                            if let key = turn.project {
                                ProjectCard(key: key).transition(.incoming(mine: false))
                            } else {
                                Bubble(text: turn.text, mine: turn.mine, who: turn.who, typing: turn.fresh)
                                    .transition(turn.settled ? .identity : .incoming(mine: turn.mine))
                            }
                        }
                        if let live = store.liveSpeech, store.route == .home { Bubble(text: live, mine: true, live: true) }
                        Color.clear.frame(height: 12).id("end")
                    }
                    .animation(.messageIn, value: store.talk[""]?.count ?? 0)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.reveal, value: store.drafts)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture { store.host?.view.endEditing(true) }
            .onChange(of: store.liveSpeech) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: store.talk[""]?.count ?? 0) { _, _ in
                DispatchQueue.main.async { withAnimation(.messageIn) { proxy.scrollTo("end", anchor: .bottom) } }
            }
            }
        }
        .background(Amber.paper.ignoresSafeArea())
        .task {
            await store.refresh()
            await store.loadBoard()
        }
        .task {
            // Presence and new comments, while this screen is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                await store.loadBoard()
                // A build cut off by closing iMessage is still finishing on
                // the server; keep looking for it.
                if store.drafts.contains(where: { $0.buildStarted != nil && store.changing[$0.id] == nil }) {
                    await store.refresh()
                }
            }
        }
    }

    private var apps: some View {
        VStack(spacing: 10) {
            // Projects from before each thread had its own Amber. Only one
            // thread can take them, and once taken they are gone from the rest.
            if store.legacySession != nil && store.session == nil {
                Button { store.claimLegacy() } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Bring your earlier projects here", systemImage: "tray.and.arrow.down")
                            .font(Amber.font(16, .bold)).foregroundStyle(Amber.ink)
                        Text("They were shared across all your chats. Now they will live only in this one.")
                            .font(Amber.font(14)).foregroundStyle(Amber.muted).multilineTextAlignment(.leading)
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Amber.sheet))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Amber.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            ForEach(store.drafts) { draft in
                Button { store.openedRow = draft.id; store.revealFrom = frames[draft.id] ?? .zero; withAnimation(.reveal) { store.route = .draft(draft.id) }; store.host?.expand() } label: {
                    DraftRow(draft: draft, building: store.changing[draft.id] != nil, doing: store.doing[draft.id])
                }
                .buttonStyle(.plain)
                .sharedTitle("proj-\(draft.id)", in: titles)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("stage")) } action: { frames[draft.id] = $0; store.rowFrames[draft.id] = $0 }
                .transition(.blurReplace)
            }
            ForEach(store.overview?.tools ?? []) { tool in
                Button { store.openedRow = tool.slug; store.revealFrom = frames[tool.slug] ?? .zero; withAnimation(.reveal) { store.route = .tool(tool.slug) }; store.host?.expand() } label: {
                    AppRow(tool: tool, unshared: store.unpublished.contains(tool.slug))
                }
                .buttonStyle(.plain)
                .sharedTitle("proj-\(tool.slug)", in: titles)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("stage")) } action: { frames[tool.slug] = $0; store.rowFrames[tool.slug] = $0 }
            }
            if store.loading && (store.overview?.tools ?? []).isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 60)
            } else if (store.overview?.tools ?? []).isEmpty && store.drafts.isEmpty {
                Text("No projects yet")
                    .font(Amber.font(17)).foregroundStyle(Amber.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// A blank project: its box opens out of the button, and Amber asks what
    /// it should be before building anything.
}

/// A new app being talked about, before it exists.
struct DraftRow: View {
    let draft: DraftApp
    let building: Bool
    let doing: String?
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Amber.wash)
                .frame(width: 48, height: 48)
                .overlay {
                    if building { ProgressView().controlSize(.small) } else {
                        Image(systemName: "sparkles").font(.system(size: 18, weight: .semibold)).foregroundStyle(Amber.ink)
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
                // The preview's place is held from the start, so when building
                // begins it appears where the space already was instead of
                // shoving the conversation down (the jump, 2026-09-27).
                if store.changing[key] == nil {
                    HStack(spacing: 10) {
                        Image(systemName: "eye").font(.system(size: 14, weight: .semibold)).foregroundStyle(Amber.muted)
                        Text("The preview shows up here while Amber builds").font(Amber.font(14)).foregroundStyle(Amber.muted)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).frame(height: 60)
                    .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Amber.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    .transition(.blurReplace)
                } else {
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
                                .transition(turn.settled ? .identity : .incoming(mine: turn.mine))
                        }
                        if let live = store.liveSpeech { Bubble(text: live, mine: true, live: true) }
                        Color.clear.frame(height: 12).id("end")
                    }
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .animation(.messageIn, value: store.talk[key]?.count ?? 0)
                }
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .onTapGesture { store.host?.view.endEditing(true) }
                // Stays on the newest message when the keyboard or the talk bar
                // takes room, instead of leaving it under the bar.
                .defaultScrollAnchor(.bottom)
                .onChange(of: store.liveSpeech) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: store.talk[key]?.count ?? 0) { _, _ in
                    // After the new bubble is laid out: scrolling in the same
                    // pass stopped short of it (Caleb, 2026-09-27).
                    DispatchQueue.main.async {
                        withAnimation(.messageIn) { proxy.scrollTo("end", anchor: .bottom) }
                    }
                }
            }
        }
        .background(Amber.sheet)
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
    @State private var activity: [ActivityItem] = []
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
                        // Sharing sits on top of the preview as a tab, the way
                        // Activity hangs under it: one unit, not three blocks
                        // stacked (Caleb, 2026-09-27: "visual hierarchy
                        // nightmare").
                        if let tool = store.tool(slug), store.unpublished.contains(slug) || tool.has_draft {
                            shareTab(tool)
                                .padding(.horizontal, previewing ? 20 : 30)
                                .zIndex(-1)
                                .transition(.blurReplace)
                        }
                        LivePanel(slug: slug, expanded: $previewing, pinsJSON: pinsJSON, onPin: handlePin)
                        ActivityTray(slug: slug, notes: notes, activity: activity) { await load() }
                            // Starts where the preview's flat bottom edge does:
                            // its corner radius, 30 as a pill and 20 open.
                            .padding(.horizontal, previewing ? 20 : 30)
                            .animation(.reveal, value: previewing)
                            .zIndex(-1)
                    }
                    .transition(.blurReplace)

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
                            Color.clear.frame(height: 12).id("end")
                        } else {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .onTapGesture { store.host?.view.endEditing(true) }
                // Stays on the newest message when the keyboard or the talk bar
                // takes room, instead of leaving it under the bar.
                .defaultScrollAnchor(.bottom)
                .onChange(of: store.liveSpeech) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: store.talk[slug]?.count ?? 0) { _, _ in
                    // After the new bubble is laid out: scrolling in the same
                    // pass stopped short of it (Caleb, 2026-09-27).
                    DispatchQueue.main.async {
                        withAnimation(.messageIn) { proxy.scrollTo("end", anchor: .bottom) }
                    }
                    Task { await load() }
                }
            }
        }
        // A project is the row's white card grown to fill the space between
        // the bars, and it stays white inside (Caleb, 2026-09-27).
        .background(Amber.sheet)
        .onChange(of: store.notesTick) { _, _ in Task { await load() } }
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
                    .transition(turn.settled ? .identity : .incoming(mine: turn.mine))
            }
            if let live = store.liveSpeech {
                Bubble(text: live, mine: true, live: true)
                    .transition(.opacity)
            }
            // What is being built shows once, in the preview's pill above.
            if tool.has_draft, store.changing[slug] == nil {
                Bubble(text: "Only you can see this change. Publish it online when it's right, or put it back.", mine: false) {
                    Button("Put it back") { Task { await store.discard(slug); await load() } }
                        .buttonStyle(BlockButton(full: true))
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

    /// Two acts in one slim strip: a bubble for the chat, or the change live
    /// on the site. With no change waiting, the right side says it is live.
    private func shareTab(_ tool: ToolItem) -> some View {
        HStack(spacing: 10) {
            // Real buttons, with edges and weight, so they read as tappable
            // (Caleb, 2026-09-28: "these aren't clearly buttons").
            Button { store.shareToChat(slug) } label: {
                Label("Send to chat", systemImage: "bubble.left.fill")
                    .font(Amber.font(14, .bold)).foregroundStyle(Amber.ink)
                    .padding(.horizontal, 14).frame(height: 36)
                    .background(Capsule().fill(Amber.sheet))
                    .overlay(Capsule().strokeBorder(Amber.hairline, lineWidth: 1))
                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 4)
            if tool.has_draft {
                Button { Task { await store.keep(slug); await load() } } label: {
                    Label("Publish online", systemImage: "globe")
                        .font(Amber.font(14, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 36)
                        .background(Capsule().fill(Amber.ink))
                }
                .buttonStyle(.plain)
                .disabled(store.changing[slug] != nil)
            } else {
                // A state, not an action, so it looks like one.
                HStack(spacing: 6) {
                    Circle().fill(Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)).frame(width: 7, height: 7)
                    Text("Live online").font(Amber.font(14)).foregroundStyle(Amber.muted)
                }
                .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 14)
        .background(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous).fill(Amber.wash))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous).strokeBorder(Amber.hairline, lineWidth: 1))
        .padding(.bottom, -6)
    }


    /// Open pinned comments, as the preview's pin layer draws them.
    private var pinsJSON: String {
        let open = notes.filter { $0.parent_id == nil && $0.resolved_at == nil && $0.anchor != nil }
        let names = Set(notes.compactMap(\.name))
        let list: [[String: Any]] = open.compactMap { note in
            guard let anchor = note.anchor else { return nil }
            let name = note.name ?? "Someone"
            return [
                "id": note.id, "selector": anchor.selector, "fx": anchor.fx, "fy": anchor.fy,
                "letter": PersonMark.letter(name, among: names), "color": PersonMark.hex(name),
                "name": name, "text": note.text,
                "replies": notes.filter { $0.parent_id == note.id }.map { ["name": $0.name ?? "Someone", "text": $0.text] },
            ]
        }
        let data = (try? JSONSerialization.data(withJSONObject: list)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    /// A double tap wakes Amber with the spot attached; the blob's own card
    /// replies and resolves; a pin whose element is gone resolves itself.
    private func handlePin(_ event: PinEvent) {
        guard let token = store.session?.token else { return }
        switch event {
        case .drop(let anchor):
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            store.pinTarget = PinDrop(slug: slug, anchor: anchor)
            store.host?.expand()
        case .resolve(let id):
            Task { await resolveNotes([id], token: token) }
        case .missing(let ids):
            Task { await resolveNotes(ids, token: token) }
        case .reply(let id, let text):
            Task {
                struct Made: Decodable { let id: String }
                let _: Made? = try? await API.call("api/tools/\(slug)/notes", method: "POST", body: ["text": text, "parent": id], chat: token)
                await load()
            }
        }
    }

    private func resolveNotes(_ ids: [String], token: String) async {
        struct Done: Decodable { let ok: Bool }
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask {
                    let _: Done? = try? await API.call("api/tools/\(slug)/notes/\(id)/resolve", method: "POST", body: ["resolved": true], chat: token)
                }
            }
        }
        await load()
    }

    private func load() async {
        guard let token = store.session?.token else { return }
        async let versionList: Versions = API.call("api/tools/\(slug)/versions", chat: token)
        async let noteList: Notes = API.call("api/tools/\(slug)/notes", chat: token)
        async let activityList: ActivityList = API.call("api/tools/\(slug)/activity", chat: token)
        do {
            versions = try await versionList.versions
            notes = try await noteList.notes
            activity = try await activityList.activity
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
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Amber.bubble.opacity(live ? 0.75 : 1)))
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

/// The one bar under every screen, shaped like Messages: a field with the
/// microphone inside it. Hold the mic to talk, or type; you can switch
/// mid-conversation (Caleb, 2026-09-27: "always hold to talk, bc maybe mid
/// convo they might wanna switch to typing"). The bar sits on a faded
/// material instead of a hard edge.
struct TalkBar: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.titles) private var titles
    @State private var request = ""
    @FocusState private var focused: Bool

    /// The double-tapped spot, while this app is open.
    private var pin: PinDrop? {
        guard let pin = store.pinTarget, store.route == .tool(pin.slug) else { return nil }
        return pin
    }
    private var empty: Bool { request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let pin {
                HStack(spacing: 6) {
                    Image(systemName: "mappin").font(.system(size: 12, weight: .semibold)).foregroundStyle(Amber.muted)
                    Text("About \(pin.anchor.label)").font(Amber.font(13, .bold)).foregroundStyle(Amber.muted).lineLimit(1)
                    Spacer(minLength: 4)
                    Button { store.pinTarget = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(Amber.muted)
                            .frame(width: 44, height: 28)
                    }
                    .accessibilityLabel("Drop the pin")
                }
                .padding(.leading, 52)
                .transition(.blurReplace)
            }
            HStack(alignment: .bottom, spacing: 10) {
                EggSlot(rank: 5).frame(width: 28, height: 32).padding(.bottom, 8)
                HStack(alignment: .bottom, spacing: 4) {
                    TextField(store.liveSpeech != nil ? "Listening" : "Message Amber", text: $request, axis: .vertical)
                        .font(Amber.font(17)).foregroundStyle(Amber.ink).lineLimit(1...5).focused($focused)
                        .padding(.leading, 14).padding(.vertical, 11)
                        .onChange(of: focused) { _, isOn in if isOn { store.host?.expand() } }
                        .onSubmit { submit() }
                    if empty {
                        HoldToTalk(compact: true, onPress: { store.speaker.stop() }) { heard in send(heard) }
                            .padding(4)
                    } else {
                        Button { submit() } label: {
                            Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 36, height: 36).background(Circle().fill(Amber.ink))
                        }
                        .accessibilityLabel("Send")
                        .padding(4)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Amber.sheet))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Amber.hairline, lineWidth: 1))
                .sharedTitle("pill", in: titles)
                .animation(.messageIn, value: empty)
            }
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 10)
        .background(.bar)
        .animation(.reveal, value: store.pinTarget)
        .onChange(of: store.pinTarget) { _, pin in
            if pin != nil { focused = true }
        }
    }

    private func submit() {
        let text = request
        request = ""
        send(text)
    }

    /// A pin takes your words as a comment on that spot, unless they ask for
    /// a change ("make it bigger", "change this to blue"), which goes to Amber
    /// scoped to that one element.
    private func send(_ text: String) {
        if let pin {
            let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
            store.liveSpeech = nil
            guard !words.isEmpty else { return }
            store.pinTarget = nil
            let asksForChange = words.range(
                of: #"^(please\s+)?(make|change|move|add|remove|delete|put|turn|use|swap|replace|rename|fix|hide|show|center|align|resize|shrink|enlarge|bold|color|colour)\b|\b(make it|change it|should be|can you (make|change|move|add|remove))\b"#,
                options: [.regularExpression, .caseInsensitive]) != nil
            Task {
                if asksForChange {
                    await store.say(pin.slug, "Change only \(pin.anchor.label) (CSS selector \(pin.anchor.selector)) and leave everything else exactly as it is: \(words)",
                                    open: { store.host?.openInRealSafari($0) })
                } else {
                    await store.dropComment(pin, words)
                }
            }
            return
        }
        // An answer needs room: talking from the small sheet opens it up.
        store.host?.expand()
        Task {
            switch store.route {
            case .home: await store.homeSay(text)
            case .draft(let key): await store.say(key, text)
            case .tool(let slug): await store.say(slug, text, open: { store.host?.openInRealSafari($0) })
            case .card, .team: await store.homeSay(text)
            }
        }
    }
}

/// Comments, tucked under the preview as part of it, so they never read as
/// messages in the conversation. They work like Google Docs: reply to one,
/// resolve it when it is handled (Caleb, 2026-09-27).
/// Under the preview: open comments and everything that happened to the app,
/// in order. Resolved comments leave it (Caleb, 2026-09-27).
struct ActivityTray: View {
    @EnvironmentObject var store: ChatStore
    let slug: String
    let notes: [Note]
    let activity: [ActivityItem]
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
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 13, weight: .semibold)).foregroundStyle(Amber.muted)
                    Text("Activity").font(Amber.font(15, .bold)).foregroundStyle(Amber.ink)
                    if !threads.isEmpty {
                        Text("\(threads.count) open \(threads.count == 1 ? "comment" : "comments")")
                            .font(Amber.font(14)).foregroundStyle(Amber.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(Amber.muted)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.horizontal, 14).padding(.top, 6)
                .frame(height: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(timeline) { entry in
                            switch entry {
                            case .comment(let thread): card(thread)
                            case .event(let item): eventRow(item)
                            }
                        }
                        composer
                    }
                    .padding(.horizontal, 10).padding(.bottom, 10)
                }
                .defaultScrollAnchor(.bottom)
                .frame(maxHeight: 300)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14, style: .continuous).fill(Amber.wash))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14, style: .continuous))
        .overlay(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14, style: .continuous).strokeBorder(Amber.hairline, lineWidth: 1))
    }

    private enum Entry: Identifiable {
        case comment(Note)
        case event(ActivityItem)
        var id: String { switch self { case .comment(let n): "n-\(n.id)"; case .event(let a): "a-\(a.id)" } }
        var at: String { switch self { case .comment(let n): n.created_at; case .event(let a): a.created_at } }
    }

    /// Comments and events in the order they happened, newest at the bottom.
    private var timeline: [Entry] {
        (threads.map(Entry.comment) + activity.map(Entry.event)).sorted { $0.at < $1.at }
    }

    private func eventRow(_ item: ActivityItem) -> some View {
        let who = item.name ?? "Someone"
        let (icon, line): (String, String) = switch item.kind {
        case "made": ("sparkles", "\(who) made it")
        case "edited": ("pencil", item.text.isEmpty ? "\(who) edited it" : "\(who) edited: \(item.text)")
        case "published": ("globe", "\(who) published version \(item.version ?? 0) to the site")
        case "shared": ("bubble.left.fill", "\(who) sent it to the chat")
        case "declined": ("arrow.uturn.backward", "\(who) put back: \(item.text)")
        default: ("circle", "\(who): \(item.text)")
        }
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(item.kind == "published" ? Amber.ink : Amber.muted)
                .frame(width: 18).padding(.top, 2)
            Text(line).font(Amber.font(14)).foregroundStyle(Amber.body).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text(timeAgo(item.created_at)).font(Amber.font(12)).foregroundStyle(Amber.muted)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
    }

    private func card(_ thread: Note) -> some View {
        let name = thread.name ?? "Someone"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(PersonMark.letter(name, among: Set(notes.compactMap(\.name))))
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(PersonMark.color(name))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(PersonMark.color(name).opacity(0.22)))
                    .overlay(Circle().strokeBorder(PersonMark.color(name), lineWidth: 1.5))
                Text(name).font(Amber.font(14, .bold)).foregroundStyle(Amber.ink)
                Text(timeAgo(thread.created_at)).font(Amber.font(13)).foregroundStyle(Amber.muted)
                Spacer()
                Button { Task { await resolve(thread) } } label: {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Amber.ink)
                        .frame(width: 32, height: 32).background(Circle().fill(Amber.wash))
                }
                .accessibilityLabel("Resolve")
            }
            if let anchor = thread.anchor {
                Text("On \(anchor.label)").font(Amber.font(13)).foregroundStyle(Amber.muted)
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
                    .font(Amber.font(14, .bold)).foregroundStyle(Amber.ink)
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
    @Environment(\.titles) private var titles
    @State private var editing = false
    @State private var newName = ""
    @FocusState private var nameFocused: Bool

    /// What a rename applies to: the open app or the draft being talked out.
    private var renameKey: String? {
        switch store.route {
        case .tool(let slug): slug
        case .draft(let key): key
        case .home, .card, .team: nil
        }
    }

    private func commitRename() {
        guard editing else { return }
        editing = false
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key = renameKey, !name.isEmpty, name != title else { return }
        Task { await store.rename(key, to: name) }
    }

    private var title: String {
        if store.building != nil { return "Making it" }
        switch store.route {
        case .home: return "Made in this chat"
        case .tool(let slug): return store.tool(slug)?.title ?? ""
        case .draft(let key): return store.drafts.first { $0.id == key }?.title ?? "New project"
        case .card(let id): return store.together.card(id)?.title ?? ""
        case .team: return "Team board"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            if store.route != .home {
                Button { store.goHome() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(Amber.ink)
                        .frame(width: 44, height: 44).background(Circle().fill(Amber.wash))
                }
                .accessibilityLabel("Everything in this chat")
                .transition(.blurReplace)
            }
            // Double-tap the name to change it (Caleb, 2026-09-27).
            ZStack(alignment: .leading) {
                HeadlineSlot(rank: 2, text: editing ? "" : title, size: 26)
                if editing {
                    TextField("Name", text: $newName)
                        .font(Amber.font(26, .heavy)).foregroundStyle(Amber.ink)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { commitRename() }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard renameKey != nil, !editing else { return }
                newName = title
                editing = true
                nameFocused = true
                store.host?.expand()
            }
            .onChange(of: nameFocused) { _, on in if !on { commitRename() } }
            if store.route == .home {
                Button { store.startNewProject() } label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(Amber.ink)
                        .frame(width: 44, height: 44).background(Circle().fill(Amber.wash))
                }
                .sharedSpot("new", in: titles)
                .accessibilityLabel("New project")
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("stage")) } action: { store.rowFrames["__plus"] = $0 }
                .transition(.blurReplace)
            }
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
                // Egg and words centred as one block, as wide as "Let's build
                // together". The name question wraps inside the same width,
                // so the egg holds still between the two steps.
                HStack(alignment: .center, spacing: 14) {
                    EggSlot(rank: 1).frame(width: 44, height: 50)
                    Text("Let's build together").font(Amber.font(30, .heavy)).headline()
                        .fixedSize()
                        .hidden()
                        .frame(height: Onboarding.headerHeight)
                        .overlay(HeadlineSlot(rank: 1, text: title, size: 30, wraps: true))
                }
                .frame(maxWidth: .infinity)
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

/// A project in the home chat. Tapping it grows it into the project; closing
/// the project shrinks it back into this card.
struct ProjectCard: View {
    @EnvironmentObject var store: ChatStore
    let key: String

    private var title: String {
        store.drafts.first { $0.id == key }?.title ?? store.tool(key)?.title ?? "Project"
    }
    private var building: Bool { store.changing[key] != nil }

    var body: some View {
        Button { store.openProject(key) } label: {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Amber.wash)
                    .frame(width: 44, height: 44)
                    .overlay {
                        if building { ProgressView().controlSize(.small) } else {
                            Image(systemName: store.tool(key) == nil ? "sparkles" : "square.grid.2x2")
                                .font(.system(size: 17, weight: .semibold)).foregroundStyle(Amber.ink)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Amber.font(17, .heavy)).foregroundStyle(Amber.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(building ? (store.doing[key] ?? "Building") : "Tap to open")
                        .font(Amber.font(14)).foregroundStyle(Amber.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Amber.muted)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Amber.sheet))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Amber.hairline, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 40)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("stage")) } action: { store.rowFrames["card-\(key)"] = $0 }
    }
}

/// Home's Activity: what happened across every project in this chat, open
/// comments, ideas people mentioned, and who is building right now.
struct HomeActivityTray: View {
    @EnvironmentObject var store: ChatStore
    @Binding var frames: [String: CGRect]
    @State private var open = false

    private enum Entry: Identifiable {
        case event(BoardEvent)
        case comment(BoardItem)
        var id: String { switch self { case .event(let e): "e-\(e.id)"; case .comment(let c): "c-\(c.id)" } }
    }

    private var entries: [Entry] {
        (store.board?.activity ?? []).map(Entry.event) + (store.board?.comments ?? []).reversed().map(Entry.comment)
    }
    private var openComments: Int { store.board?.comments.count ?? 0 }
    private var building: [Board.Building] { store.board?.building ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.reveal) { open.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 13, weight: .semibold)).foregroundStyle(Amber.muted)
                    Text("Activity").font(Amber.font(15, .bold)).foregroundStyle(Amber.ink)
                    if let now = building.first {
                        ProgressView().controlSize(.mini)
                        Text("\(now.who) is making \(now.what)").font(Amber.font(13)).foregroundStyle(Amber.muted).lineLimit(1)
                    } else if openComments > 0 {
                        Text("\(openComments) open \(openComments == 1 ? "comment" : "comments")").font(Amber.font(14)).foregroundStyle(Amber.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(Amber.muted)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.horizontal, 14).frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if entries.isEmpty && (store.board?.ideas ?? []).isEmpty {
                            Text("Nothing yet. Edits, publishes and comments on any project show up here.")
                                .font(Amber.font(14)).foregroundStyle(Amber.muted).padding(.vertical, 6)
                        }
                        ForEach(store.board?.ideas ?? []) { idea in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "lightbulb").font(.system(size: 12, weight: .semibold)).foregroundStyle(Amber.muted).frame(width: 18)
                                Text(idea.description).font(Amber.font(14)).foregroundStyle(Amber.body)
                            }
                            .padding(.vertical, 4)
                        }
                        ForEach(entries) { entry in
                            switch entry {
                            case .event(let event): row(event)
                            case .comment(let comment): row(comment)
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 10)
                }
                .defaultScrollAnchor(.bottom)
                .frame(maxHeight: 240)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Amber.wash))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Amber.hairline, lineWidth: 1))
    }

    private func openProject(_ slug: String) {
        guard store.tool(slug) != nil else { return }
        store.openedRow = slug
        store.revealFrom = frames[slug] ?? .zero
        store.host?.expand()
        withAnimation(.reveal) { store.route = .tool(slug) }
    }

    private func row(_ event: BoardEvent) -> some View {
        let who = event.name ?? "Someone"
        let (icon, line): (String, String) = switch event.kind {
        case "made": ("sparkles", "\(who) made \(event.title)")
        case "edited": ("pencil", "\(who) edited \(event.title)\(event.text.isEmpty ? "" : ": \(event.text)")")
        case "published": ("globe", "\(who) published \(event.title) version \(event.version ?? 0)")
        case "shared": ("bubble.left.fill", "\(who) sent \(event.title) to the chat")
        case "declined": ("arrow.uturn.backward", "\(who) put back a change to \(event.title)")
        default: ("circle", "\(who): \(event.title)")
        }
        return Button { openProject(event.slug) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(event.kind == "published" ? Amber.ink : Amber.muted).frame(width: 18).padding(.top, 2)
                Text(line).font(Amber.font(14)).foregroundStyle(Amber.body).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(timeAgo(event.created_at)).font(Amber.font(12)).foregroundStyle(Amber.muted)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ comment: BoardItem) -> some View {
        let name = comment.name ?? "Someone"
        return Button { if let slug = comment.slug { openProject(slug) } } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(String(name.prefix(1)).uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(PersonMark.color(name))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(PersonMark.color(name).opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(name) on \(comment.title ?? "a project")").font(Amber.font(13, .bold)).foregroundStyle(Amber.muted)
                    Text(comment.text).font(Amber.font(15)).foregroundStyle(Amber.ink).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Amber.sheet))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


/// On an empty home, a few things to start with, one tap each.
struct StarterChips: View {
    @EnvironmentObject var store: ChatStore
    private let starters: [(String, String)] = [
        ("Sign-up sheet", "Make a sign-up sheet for our next event"),
        ("Packing list", "Make a shared packing list for our trip"),
    ]
    @Environment(\.titles) private var titles
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Start with one").font(Amber.font(13, .bold)).foregroundStyle(Amber.muted)
            ForEach(starters, id: \.0) { label, prompt in
                Button { Task { await store.homeSay(prompt) } } label: {
                    Text(label).font(Amber.font(15, .bold)).foregroundStyle(Amber.ink)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Capsule().fill(Amber.sheet))
                        .overlay(Capsule().strokeBorder(Amber.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .sharedSpot("starter-\(label)", in: titles)
            }
        }
        .transition(.blurReplace)
    }
}

/// Amber in the keyboard-sized sheet: a launcher. Your projects as pills to
/// jump into, quick starts, and the message field. Everything that needs room
/// (Activity, the conversation, the preview) waits for the full screen. Tall
/// tiles left most of the sheet empty (Caleb, 2026-09-28: "it looks visually
/// off"), so everything here is one pill high.
struct CompactView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.titles) private var titles

    private var tools: [ToolItem] { store.overview?.tools ?? [] }
    private var count: Int { tools.count + store.drafts.count }
    private let starters: [(String, String)] = [
        ("Sign-up sheet", "Make a sign-up sheet for our next event"),
        ("Packing list", "Make a shared packing list for our trip"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                // The same headline as full screen: it retypes into "Made in
                // this chat" as it moves up.
                Text("Amber").font(Amber.font(20, .heavy)).headline().fixedSize().hidden()
                    .overlay(HeadlineSlot(rank: 2, text: "Amber", size: 20))
                Text(count == 0 ? "Build something for this chat" : "\(count) \(count == 1 ? "project" : "projects") here")
                    .font(Amber.font(15)).foregroundStyle(Amber.muted).lineLimit(1)
                Spacer(minLength: 8)
                Button { store.host?.expand() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Amber.ink)
                        .frame(width: 34, height: 34).background(Circle().fill(Amber.wash))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Open Amber full screen")
            }
            .padding(.horizontal, 16).padding(.top, 4)
            row {
                Button {
                    store.host?.expand()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { store.startNewProject() }
                } label: {
                    // One line, always: it wrapped to two on a phone mid-morph.
                    Label("New project", systemImage: "plus")
                        .font(Amber.font(15, .bold)).foregroundStyle(.white)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(Capsule().fill(Amber.ink))
                }
                .buttonStyle(.plain)
                .sharedSpot("new", in: titles)
                // The team board, next to the one main action (Team.swift).
                TeamPill()
                ForEach(store.drafts) { draft in pill(draft.title) { open(.draft(draft.id)) }.sharedTitle("proj-\(draft.id)", in: titles) }
                ForEach(tools) { tool in pill(tool.title) { open(.tool(tool.slug)) }.sharedTitle("proj-\(tool.slug)", in: titles) }
            }
            // Amber's group cards, one pill high.
            CompactCards()
            row {
                ForEach(starters, id: \.0) { label, prompt in
                    Button {
                        store.host?.expand()
                        Task { await store.homeSay(prompt) }
                    } label: {
                        Text(label).font(Amber.font(15)).foregroundStyle(Amber.body)
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 14).frame(height: 40)
                            .overlay(Capsule().strokeBorder(Amber.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .sharedSpot("starter-\(label)", in: titles)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .background(Amber.paper.ignoresSafeArea())
        .task { await store.refresh() }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content() }.padding(.horizontal, 16)
        }
        .scrollClipDisabled()
    }

    private func open(_ route: Route) {
        store.revealFrom = .zero
        store.route = route
        store.host?.expand()
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(String(title.prefix(1)).uppercased()).font(Amber.font(13, .heavy)).foregroundStyle(Amber.ink)
                    .frame(width: 26, height: 26).background(Circle().fill(Amber.wash))
                Text(title).font(Amber.font(15, .bold)).foregroundStyle(Amber.ink).lineLimit(1)
                    .frame(maxWidth: 170, alignment: .leading)
            }
            .padding(.leading, 7).padding(.trailing, 14).frame(height: 40)
            .background(Capsule().fill(Amber.sheet))
            .overlay(Capsule().strokeBorder(Amber.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
}
