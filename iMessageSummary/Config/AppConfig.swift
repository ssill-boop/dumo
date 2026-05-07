import Foundation

struct AppConfig {
    let anthropicAPIKey: String?
    let supabaseURL: URL?
    let supabaseAnonKey: String?
    let machineID: String

    var hasAnthropicKey: Bool { anthropicAPIKey != nil }
    var hasSupabase: Bool { supabaseURL != nil && supabaseAnonKey != nil }
    var isFullyConfigured: Bool { hasAnthropicKey && hasSupabase }

    static let envDirectoryName = ".imessage-summary"
    static let envFileName = ".env"

    static let envTemplate = """
    ANTHROPIC_API_KEY=
    SUPABASE_URL=
    SUPABASE_ANON_KEY=
    MACHINE_ID=
    """

    static var envDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(envDirectoryName, isDirectory: true)
    }

    static var envFileURL: URL {
        envDirectoryURL.appendingPathComponent(envFileName, isDirectory: false)
    }

    static func load() -> AppConfig {
        ensureEnvFileExists()
        let values = parseEnvFile(at: envFileURL)
        return AppConfig(
            anthropicAPIKey: nonEmpty(values["ANTHROPIC_API_KEY"]),
            supabaseURL: nonEmpty(values["SUPABASE_URL"]).flatMap(URL.init(string:)),
            supabaseAnonKey: nonEmpty(values["SUPABASE_ANON_KEY"]),
            machineID: nonEmpty(values["MACHINE_ID"]) ?? defaultMachineID()
        )
    }

    @discardableResult
    static func ensureEnvFileExists() -> Bool {
        let fm = FileManager.default
        let dir = envDirectoryURL
        if !fm.fileExists(atPath: dir.path) {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                return false
            }
        }
        let file = envFileURL
        if !fm.fileExists(atPath: file.path) {
            do {
                try envTemplate.write(to: file, atomically: true, encoding: .utf8)
            } catch {
                return false
            }
        }
        return true
    }

    static func parseEnvFile(at url: URL) -> [String: String] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }
        var result: [String: String] = [:]
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2 {
                let first = value.first!
                let last = value.last!
                if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                    value = String(value.dropFirst().dropLast())
                }
            }
            if !key.isEmpty {
                result[key] = value
            }
        }
        return result
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s = s, !s.isEmpty else { return nil }
        return s
    }

    private static func defaultMachineID() -> String {
        if let name = Host.current().localizedName, !name.isEmpty {
            return name
        }
        return "unknown-machine"
    }
}
