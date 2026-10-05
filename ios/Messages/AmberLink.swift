import Foundation
import Security

// EACH PERSON IN THE CHAT, AS THEMSELVES IN AMBER.
//
// The Amber app (amberintelligence/amber-ios) keeps its session in a keychain
// group shared across this Apple team, `4DMVHH99R2.com.joinrytual.amber.shared`
// (its lib/secureStorage.ts and lib/sessionStore.ts). This extension declares
// the same group in project.yml, so anyone with Amber on their phone is
// already signed in here: no second login, and nobody's Amber account is ever
// reachable from anyone else's phone. Everything Amber knows about a person is
// read on that person's phone, and only the answer goes to the chat's card.
//
// The item layout is expo-secure-store's: service "app:no-auth", account and
// generic both the key's UTF-8 bytes. Refresh tokens are single-use and the
// Amber app refreshes too, so this follows the same rules Kyber did: one
// refresh at a time (an actor), update and never create (a missing item means
// the person signed out), stamp the save time, and if a refresh loses a race,
// use the session the other side just stored.

enum AmberKeychain {
    static let sessionKey = "medha_session_token_v1"
    static let refreshKey = "medha_refresh_token_v1"
    static let phoneKey = "medha_session_phone_v1"
    static let savedAtKey = "medha_session_saved_at_v1"
    static let group = "4DMVHH99R2.com.joinrytual.amber.shared"

    private static func query(_ key: String) -> [String: Any] {
        let account = Data(key.utf8)
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app:no-auth",
            kSecAttrAccount as String: account,
            kSecAttrGeneric as String: account,
            kSecAttrAccessGroup as String: group,
        ]
    }

    static func get(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = kCFBooleanTrue
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func update(_ key: String, _ value: String) -> Bool {
        SecItemUpdate(query(key) as CFDictionary, [kSecValueData as String: Data(value.utf8)] as CFDictionary) == errSecSuccess
    }

    static var signedIn: Bool { Self.get(sessionKey) != nil }
}

enum AmberError: LocalizedError {
    case notLinked, signedOut, server(Int), offline
    var errorDescription: String? {
        switch self {
        case .notLinked: return "Get Amber on this phone and sign in, and Amber fills this in for you."
        case .signedOut: return "Open the Amber app to sign back in."
        case .server: return "Amber is having a moment. Try again shortly."
        case .offline: return "You look offline. Check your connection and try again."
        }
    }
}

actor AmberClient {
    static let shared = AmberClient()
    nonisolated let base = URL(string: "https://medha-id-production.up.railway.app")!
    private var refreshing: Task<String, Error>?

    func token() async throws -> String {
        guard let current = AmberKeychain.get(AmberKeychain.sessionKey) else { throw AmberError.notLinked }
        if !AmberJWT.needsRefresh(current) { return current }
        if let refreshing { return try await refreshing.value }
        let task = Task<String, Error> { try await self.refresh() }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    private func refresh() async throws -> String {
        guard let sent = AmberKeychain.get(AmberKeychain.refreshKey) else { throw AmberError.signedOut }
        var req = URLRequest(url: base.appendingPathComponent("v1/auth/refresh"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["refreshToken": sent])
        req.timeoutInterval = 10
        let data: Data, res: URLResponse
        do { (data, res) = try await URLSession.shared.data(for: req) } catch { throw AmberError.offline }
        let status = (res as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            // The Amber app may have rotated it first; its session is then stored.
            if let now = AmberKeychain.get(AmberKeychain.refreshKey), now != sent,
               let access = AmberKeychain.get(AmberKeychain.sessionKey), !AmberJWT.needsRefresh(access) { return access }
            throw AmberError.signedOut
        }
        guard status == 200, let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = body["token"] as? String else { throw AmberError.server(status) }
        guard AmberKeychain.update(AmberKeychain.sessionKey, token) else { throw AmberError.signedOut }
        if let rotated = body["refreshToken"] as? String { AmberKeychain.update(AmberKeychain.refreshKey, rotated) }
        AmberKeychain.update(AmberKeychain.savedAtKey, String(Int(Date().timeIntervalSince1970 * 1000)))
        return token
    }

    func json(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        let token = try await token()
        guard let url = URL(string: path, relativeTo: base) else { throw AmberError.server(0) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        req.setValue("application/json", forHTTPHeaderField: "accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data, res: URLResponse
        do { (data, res) = try await URLSession.shared.data(for: req) } catch { throw AmberError.offline }
        let status = (res as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw AmberError.signedOut }
        guard (200..<300).contains(status) else { throw AmberError.server(status) }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// Asks Amber (POST /v1/chat, the app's own Ask) and gathers what came
    /// back: the people it named and the places it found.
    func ask(_ message: String) async throws -> (people: [[String: Any]], places: [[String: Any]], answer: String) {
        let token = try await token()
        var req = URLRequest(url: base.appendingPathComponent("v1/chat"))
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("text/event-stream", forHTTPHeaderField: "accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["message": message, "timezone": TimeZone.current.identifier])
        let bytes: URLSession.AsyncBytes, res: URLResponse
        do { (bytes, res) = try await URLSession.shared.bytes(for: req) } catch { throw AmberError.offline }
        let status = (res as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw AmberError.signedOut }
        guard status == 200 else { throw AmberError.server(status) }
        var parser = SSEParser()
        var people: [[String: Any]] = [], places: [[String: Any]] = [], answer = ""
        var pending = Data()
        for try await byte in bytes {
            pending.append(byte)
            guard byte == 0x0A, let chunk = String(data: pending, encoding: .utf8) else { continue }
            pending.removeAll(keepingCapacity: true)
            for f in parser.feed(chunk) {
                switch f.event {
                case "people": people = (f.data["people"] as? [[String: Any]]) ?? people
                case "places": places = (f.data["places"] as? [[String: Any]]) ?? places
                case "token": answer += (f.data["text"] as? String) ?? ""
                case "error": throw AmberError.server(0)
                case "complete": return (people, places, answer)
                default: break
                }
            }
        }
        return (people, places, answer)
    }
}
