import LocalAuthentication
import SwiftUI

// The app itself only points at Messages: Amber lives in the thread, not here.
@main
struct AmberApp: App {
    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        Image("AmberLogo").resizable().scaledToFit().frame(height: 30)
                        Text("Amber").font(Amber.font(26, .heavy)).foregroundStyle(Amber.ink)
                    }
                    Text("Amber lives in Messages.").font(Amber.font(38, .heavy)).foregroundStyle(Amber.ink)
                    step(1, "Open any group chat, or a chat with one person.")
                    step(2, "Tap the plus next to the message box, then More, then Amber.")
                    step(3, "Say what the chat needs. Everyone in it can open it and change it.")
                    FaceIDSetup()
                }
                .padding(24)
            }
            .background(Amber.paper.ignoresSafeArea())
            // The iMessage extension cannot open Safari itself, so it opens
            // amberapp://open?u=<link> and this passes the link to Safari.
            .onOpenURL { url in
                guard url.scheme == "amberapp",
                      let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "u" })?.value,
                      let web = URL(string: target), web.scheme == "https" else { return }
                UIApplication.shared.open(web)
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)").font(Amber.font(28, .heavy)).foregroundStyle(Amber.ink)
                .frame(width: 44, height: 44).background(Circle().fill(Amber.wash))
            Text(text).font(Amber.font(20)).foregroundStyle(Amber.body)
        }
    }
}

/// iOS only asks "Allow Amber to use Face ID?" from the app itself, never from
/// inside Messages, so this is where it gets turned on once.
struct FaceIDSetup: View {
    @State private var state = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { enable() } label: {
                Label("Turn on Face ID for Amber", systemImage: "faceid")
                    .font(Amber.font(17, .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(Amber.ink))
            }
            .buttonStyle(.plain)
            if !state.isEmpty { Text(state).font(Amber.font(15)).foregroundStyle(Amber.muted) }
        }
        .padding(.top, 8)
    }

    private func enable() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            state = "Face ID is off for Amber. Turn it on in Settings, Amber, Face ID."
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock Amber with Face ID") { ok, _ in
            Task { @MainActor in state = ok ? "Face ID is on. Amber will use it in Messages." : "Face ID did not go through. Try again." }
        }
    }
}
