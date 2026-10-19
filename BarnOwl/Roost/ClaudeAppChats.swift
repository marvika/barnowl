import Foundation

/// Sessions started in the Claude app's Code tab: the app keeps a small
/// record for each, naming its own ID ("local_…") beside Claude Code's, and
/// the chat's title. With that ID, `claude://code/continue` opens the very
/// chat. Only the first few kilobytes of each record are read, for those
/// three fields.
enum ClaudeAppChats {
    struct Chat: Equatable, Sendable {
        let id: String
        let title: String?
    }

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    }

    /// The link that opens a chat in the Claude app.
    static func link(to chat: String) -> URL? {
        guard chat.range(of: #"^local_[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "claude://code/continue?session=\(chat)")
    }

    /// The record files, `<account>/<organisation>/local_<id>.json`.
    static func records(in folder: URL = folder) -> [URL] {
        let manager = FileManager.default
        var found: [URL] = []
        for account in (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            for organisation in (try? manager.contentsOfDirectory(at: account, includingPropertiesForKeys: nil)) ?? [] {
                for file in (try? manager.contentsOfDirectory(at: organisation, includingPropertiesForKeys: nil)) ?? []
                where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
                    found.append(file)
                }
            }
        }
        return found
    }

    /// Claude Code's session ID and the chat, from the start of a record.
    static func parse(head data: Data) -> (cliSession: String, chat: Chat)? {
        let text = String(decoding: data, as: UTF8.self)
        guard let id = string("sessionId", in: text), id.hasPrefix("local_"),
              let cli = string("cliSessionId", in: text) else { return nil }
        return (cli, Chat(id: id, title: string("title", in: text).flatMap { $0.isEmpty ? nil : $0 }))
    }

    static func head(of url: URL, bytes: Int = 4096) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: bytes)
    }

    /// A top-level string field, JSON escapes and all.
    private static func string(_ key: String, in text: String) -> String? {
        let pattern = #"""# + key + #""\s*:\s*("(?:[^"\\]|\\.)*")"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return try? JSONDecoder().decode(String.self, from: Data(text[range].utf8))
    }
}
