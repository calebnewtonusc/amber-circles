import Foundation

// Everything the iMessage app knows comes from Amber's server. A chat member
// acts for the chat with their own token in x-amber-chat; nobody signs in.
enum API {
    static let base = URL(string: "https://web-production-058309.up.railway.app")!

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func call<T: Decodable>(
        _ path: String, method: String = "GET", body: [String: Any]? = nil, chat: String? = nil, person: String? = nil
    ) async throws -> T {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let chat { request.setValue(chat, forHTTPHeaderField: "x-amber-chat") }
        if let person { request.setValue(person, forHTTPHeaderField: "x-amber-person") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure(message: "You look offline. Check your connection and try again.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ServerError.self, from: data))?.error
            throw Failure(message: message ?? "That did not work (\(status)). Try again.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private struct ServerError: Decodable { let error: String }

    /// Streams a build. Stages arrive as "thinking", "writing", "checking" so
    /// the wait is named as it happens: a blank minute reads as broken.
    static func build(
        request text: String, chat: String, slug: String?, token: String,
        onStage: @escaping @MainActor (String, String, String?, String?) -> Void
    ) async throws -> BuildResult {
        var request = URLRequest(url: base.appendingPathComponent("api/build"))
        request.httpMethod = "POST"
        request.timeoutInterval = 400
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(token, forHTTPHeaderField: "x-amber-chat")
        var body: [String: Any] = ["request": text, "circle": chat]
        if let slug { body["slug"] = slug }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(status) {
            var raw = Data()
            for try await byte in bytes { raw.append(byte) }
            let message = (try? JSONDecoder().decode(ServerError.self, from: raw))?.error
            throw Failure(message: message ?? "That did not start. Try again.")
        }
        var event = ""
        for try await line in bytes.lines {
            if line.hasPrefix("event: ") {
                event = String(line.dropFirst(7))
            } else if line.hasPrefix("data: ") {
                let payload = Data(line.dropFirst(6).utf8)
                let json = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] ?? [:]
                switch event {
                case "progress":
                    let stage = json["stage"] as? String ?? ""
                    let chars = json["chars"] as? Int
                    await onStage(stage, chars.map { "\($0.formatted()) letters" } ?? "",
                                  json["html"] as? String, json["doing"] as? String)
                case "error":
                    throw Failure(message: json["message"] as? String ?? "Something went wrong. Try again.")
                case "done":
                    return BuildResult(slug: json["slug"] as? String ?? "", draft: json["draft"] as? Bool ?? false)
                default: break
                }
            }
        }
        throw Failure(message: "The connection dropped before it finished. Try again.")
    }
}

struct BuildResult { let slug: String; let draft: Bool }

struct Session: Codable, Equatable {
    var chat: String
    var token: String
    var invite: String
    var name: String
}

struct Person: Codable, Identifiable, Hashable { let id: String; let name: String }

struct ToolItem: Codable, Identifiable, Hashable {
    var id: String { slug }
    let slug: String
    let title: String
    let description: String?
    let version: Int
    let made_by: String?
    let updated_at: String
    let has_draft: Bool
    let draft_request: String?
    let entries: Int
    let notes: Int
}

struct ChatOverview: Codable {
    let chat: String
    let people: [Person]
    let tools: [ToolItem]
}

struct Note: Codable, Identifiable, Hashable {
    let id: String
    let text: String
    let created_at: String
    let name: String?
    /// Set on a reply: the comment it answers.
    var parent_id: String? = nil
    var resolved_at: String? = nil
}

struct Version: Codable, Identifiable, Hashable {
    var id: Int { version }
    let version: Int
    let request: String?
    let created_at: String
    let current: Bool
    let has_entries: Bool
    let entry_count: Int
}

struct Versions: Codable { let versions: [Version] }
struct Notes: Codable { let notes: [Note] }
struct Explanation: Codable { let text: String }
struct Joined: Codable {
    let chat: String
    let token: String
    let invite: String?
}

/// "3m ago", from the server's ISO timestamps.
func timeAgo(_ iso: String) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
    let seconds = max(1, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "just now" }
    if seconds < 3600 { return "\(seconds / 60)m ago" }
    if seconds < 86400 { return "\(seconds / 3600)h ago" }
    return "\(seconds / 86400)d ago"
}
