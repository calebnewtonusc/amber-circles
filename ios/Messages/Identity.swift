import AuthenticationServices
import LocalAuthentication
import Security
import SwiftUI

/// The person's key from Sign in with Apple, kept in the Keychain so it
/// survives reinstalling and updates.
enum PersonKey {
    private static let service = "com.calebnewton.amber.person"

    static func load() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// First open: Sign in with Apple, so Amber knows it is you in every chat.
struct SignInView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.titles) private var titles
    @State private var problem: String?
    @State private var working = false
    @State private var skipFrame: CGRect = .zero
    @State private var appleFrame: CGRect = .zero

    var body: some View {
        // Compact, it sits at the top; expanded to full height, the same block
        // glides to the middle and loosens (Caleb, 2026-09-27).
        TallAware { tall in
        VStack(alignment: .leading, spacing: tall ? 28 : 18) {
            // Same spot on every step, so the egg and title never move between
                // them (Caleb, 2026-09-27). Centering moved them, because each
                // step has a different amount under its title.
                if tall { Color.clear.frame(height: Onboarding.headerTop) }
            HStack(alignment: .top, spacing: 14) {
                EggSlot(rank: 1).frame(width: 44, height: 50)
                Text("Let's build together").font(Amber.font(30, .heavy)).headline().foregroundStyle(Amber.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .sharedTitle("headline", in: titles)
            }
            .frame(maxWidth: .infinity)
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                Task { await finish(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 54)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { appleFrame = $0 }
            .clipShape(Capsule())
            .disabled(working)
            if let problem { Text(problem).font(Amber.font(16, .bold)).foregroundStyle(Amber.danger) }
            // Never a dead end: without sign-in Amber still works in this chat,
            // it just cannot remember you across chats.
            Button("Continue without signing in") {
                store.revealFrom = skipFrame
                withAnimation(.reveal) {
                    store.personKey = ""
                    store.unlocked = true
                }
            }
            .font(Amber.font(16, .bold)).foregroundStyle(Amber.muted)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { skipFrame = $0 }
            Spacer()
        }
        .padding(20)
        }
        .onAppear { store.host?.expand() }
    }

    private func finish(_ result: Result<ASAuthorization, Error>) async {
        guard case .success(let auth) = result,
              let credential = auth.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8) else {
            if case .failure(let error) = result, (error as? ASAuthorizationError)?.code != .canceled {
                problem = "That didn't go through. Try again."
            }
            return
        }
        working = true
        defer { working = false }
        let given = credential.fullName?.givenName ?? ""
        do {
            struct Signed: Decodable { let key: String; let name: String }
            let signed: Signed = try await API.call("api/people/signin", method: "POST", body: ["identityToken": token, "name": given])
            PersonKey.save(signed.key)
            store.revealFrom = appleFrame
            withAnimation(.reveal) {
                store.personKey = signed.key
                store.unlocked = true
                let name = signed.name.isEmpty ? given : signed.name
                if !name.isEmpty { store.saveName(name) }
            }
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// Every open: Face ID, because Amber remembers what you've told it.
struct LockView: View {
    @EnvironmentObject var store: ChatStore
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            EggSlot(rank: 2).frame(width: 56, height: 64)
            Text("Amber").font(Amber.font(26, .heavy)).foregroundStyle(Amber.ink)
            Button("Unlock with Face ID") { unlock() }
                .buttonStyle(BlockButton(primary: true))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear { unlock() }
    }

    private func unlock() {
        let context = LAContext()
        var error: NSError?
        // Face ID, or the passcode when Face ID is not set up.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            store.unlocked = true
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open Amber") { success, _ in
            Task { @MainActor in if success { store.revealFrom = .zero; withAnimation(.reveal) { store.unlocked = true } } }
        }
    }
}
