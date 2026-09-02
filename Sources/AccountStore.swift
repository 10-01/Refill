import CryptoKit
import Darwin
import Foundation

enum AccountStore {
    private static let applicationSupportRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support", isDirectory: true)
    private static let legacyApplicationSupports = ["Leftbar", "Quota"].map {
        applicationSupportRoot.appendingPathComponent($0, isDirectory: true)
    }
    static let applicationSupport: URL = {
        let current = applicationSupportRoot.appendingPathComponent("Refill", isDirectory: true)
        if !FileManager.default.fileExists(atPath: current.path),
           let legacy = legacyApplicationSupports.first(where: {
               FileManager.default.fileExists(atPath: $0.path)
           }) {
            try? FileManager.default.moveItem(at: legacy, to: current)
        }
        return current
    }()
    static let registryURL = applicationSupport.appendingPathComponent("accounts.json")
    static let exportURL = applicationSupport.appendingPathComponent("refill.json")

    static func accounts() -> [AccountProfile] {
        guard let data = try? Data(contentsOf: registryURL),
              let profiles = try? JSONDecoder().decode([AccountProfile].self, from: data)
        else {
            let profiles = discoverAccounts()
            try? save(profiles)
            return profiles
        }
        var normalized: [String: AccountProfile] = [:]
        for profile in profiles {
            let migratedPath = profile.homePath.map(migrateLegacyPath)
            let path = migratedPath?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanPath = path?.isEmpty == true ? nil : path
            let clean = AccountProfile(
                id: stableID(provider: profile.provider, path: cleanPath),
                provider: profile.provider,
                name: profile.name,
                homePath: cleanPath,
                source: ["leftbar", "quota"].contains(profile.source) ? "refill" : profile.source
            )
            if normalized[clean.id] == nil || clean.source == "T3" { normalized[clean.id] = clean }
        }
        let result = sort(Array(normalized.values))
        if result != profiles { try? save(result) }
        return result
    }

    static func save(_ profiles: [AccountProfile]) throws {
        try FileManager.default.createDirectory(
            at: applicationSupport,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(sort(profiles)).write(to: registryURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: registryURL.path
        )
    }

    static func rescan() throws -> [AccountProfile] {
        var merged = Dictionary(uniqueKeysWithValues: accounts().map { ($0.id, $0) })
        for profile in discoverAccounts() where merged[profile.id] == nil {
            merged[profile.id] = profile
        }
        let result = sort(Array(merged.values))
        try save(result)
        return result
    }

    static func remove(_ profile: AccountProfile) throws -> [AccountProfile] {
        let result = accounts().filter { $0.id != profile.id }
        try save(result)
        return result
    }

    static func rename(_ profile: AccountProfile, to name: String) throws -> [AccountProfile] {
        var result = accounts()
        guard let index = result.firstIndex(where: { $0.id == profile.id }) else { return result }
        result[index].name = name
        try save(result)
        return sort(result)
    }

    static func addCurrent(_ provider: Provider, name: String) throws -> [AccountProfile] {
        var result = accounts()
        let profile = AccountProfile(
            id: stableID(provider: provider, path: nil),
            provider: provider,
            name: name,
            homePath: nil,
            source: "local"
        )
        if let index = result.firstIndex(where: { $0.id == profile.id }) { result[index] = profile }
        else { result.append(profile) }
        try save(result)
        return sort(result)
    }

    static func addIsolated(_ provider: Provider, name: String) throws -> (AccountProfile, [AccountProfile]) {
        let identifier = UUID().uuidString.lowercased()
        let home = applicationSupport
            .appendingPathComponent("Providers", isDirectory: true)
            .appendingPathComponent(provider.rawValue, isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
        try FileManager.default.createDirectory(
            at: home,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let profile = AccountProfile(
            id: stableID(provider: provider, path: home.path),
            provider: provider,
            name: name,
            homePath: home.path,
            source: "refill"
        )
        var result = accounts()
        result.append(profile)
        try save(result)
        return (profile, sort(result))
    }

    static func discoverAccounts() -> [AccountProfile] {
        var profiles = discoverT3Accounts()
        let providers = Set(profiles.map(\.provider))

        if !providers.contains(.claude), isSignedIn(AccountProfile(
            id: "probe", provider: .claude, name: "Claude", homePath: nil, source: "local"
        )) {
            profiles.append(AccountProfile(
                id: stableID(provider: .claude, path: nil),
                provider: .claude,
                name: "Claude",
                homePath: nil,
                source: "local"
            ))
        }
        if !profiles.contains(where: { $0.provider == .codex && $0.homePath == nil }),
           fileExists(provider: .codex, homePath: nil, name: "auth.json") {
            profiles.append(AccountProfile(
                id: stableID(provider: .codex, path: nil),
                provider: .codex,
                name: "Codex",
                homePath: nil,
                source: "local"
            ))
        }
        if fileExists(provider: .grok, homePath: nil, name: "auth.json") {
            profiles.append(AccountProfile(
                id: stableID(provider: .grok, path: nil),
                provider: .grok,
                name: "Grok",
                homePath: nil,
                source: "local"
            ))
        }

        var unique: [String: AccountProfile] = [:]
        profiles.forEach { unique[$0.id] = $0 }
        return sort(Array(unique.values))
    }

    private static func discoverT3Accounts() -> [AccountProfile] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settings = home.appendingPathComponent(".t3/userdata/settings.json")
        guard let data = try? Data(contentsOf: settings),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let instances = root["providerInstances"] as? [String: Any]
        else { return [] }

        var profiles: [AccountProfile] = []
        for (instanceID, rawValue) in instances {
            guard let value = rawValue as? [String: Any],
                  let driver = value["driver"] as? String
            else { continue }
            let provider: Provider
            switch driver {
            case "claudeAgent": provider = .claude
            case "codex": provider = .codex
            default: continue
            }
            if let enabled = value["enabled"] as? Bool, !enabled { continue }

            let config = value["config"] as? [String: Any] ?? [:]
            let rawPath = (config["homePath"] as? String)
                ?? (config["shadowHomePath"] as? String)
            let expandedPath = rawPath.map(expandTilde)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let path = expandedPath?.isEmpty == true ? nil : expandedPath
            let configuredName = value["displayName"] as? String
            let name = configuredName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? configuredName!
                : discoveredName(provider: provider, instanceID: instanceID)

            profiles.append(AccountProfile(
                id: stableID(provider: provider, path: path),
                provider: provider,
                name: name,
                homePath: path,
                source: "T3"
            ))
        }
        return profiles
    }

    private static func discoveredName(provider: Provider, instanceID: String) -> String {
        let cache = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".t3/caches/\(instanceID).json")
        if let data = try? Data(contentsOf: cache),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let auth = root["auth"] as? [String: Any],
           let email = auth["email"] as? String,
           let domain = email.split(separator: "@").last?.split(separator: ".").first {
            return "\(domain.capitalized) \(provider.title)"
        }
        return provider.title
    }

    static func sort(_ profiles: [AccountProfile]) -> [AccountProfile] {
        profiles.sorted {
            let left = Provider.allCases.firstIndex(of: $0.provider) ?? 0
            let right = Provider.allCases.firstIndex(of: $1.provider) ?? 0
            return left == right ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : left < right
        }
    }

    static func stableID(provider: Provider, path: String?) -> String {
        let value = "\(provider.rawValue)|\(path ?? "default")"
        let digest = SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(provider.rawValue):\(digest.prefix(12))"
    }

    private static func migrateLegacyPath(_ path: String) -> String {
        guard let legacy = legacyApplicationSupports.first(where: {
            path == $0.path || path.hasPrefix($0.path + "/")
        }) else { return path }
        return applicationSupport.path + String(path.dropFirst(legacy.path.count))
    }

    static func expandTilde(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return FileManager.default.homeDirectoryForCurrentUser.path + String(path.dropFirst())
    }

    static func defaultHome(_ provider: Provider) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch provider {
        case .claude: return home.appendingPathComponent(".claude")
        case .codex: return home.appendingPathComponent(".codex")
        case .grok: return home.appendingPathComponent(".grok")
        }
    }

    static func effectiveHome(_ profile: AccountProfile) -> URL {
        profile.homePath.map(URL.init(fileURLWithPath:)) ?? defaultHome(profile.provider)
    }

    static func fileExists(provider: Provider, homePath: String?, name: String) -> Bool {
        let home = homePath.map(URL.init(fileURLWithPath:)) ?? defaultHome(provider)
        return FileManager.default.fileExists(atPath: home.appendingPathComponent(name).path)
    }

    static func isSignedIn(_ profile: AccountProfile) -> Bool {
        switch profile.provider {
        case .claude:
            guard let claude = executable("claude") else { return false }
            var environment = providerEnvironment(profile)
            if profile.homePath == nil { environment.removeValue(forKey: "CLAUDE_CONFIG_DIR") }
            let result = run(claude, ["auth", "status", "--json"], environment: environment, timeout: 8)
            guard result.status == 0,
                  let data = result.output.data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return false }
            return value["loggedIn"] as? Bool == true
        case .codex, .grok:
            return fileExists(provider: profile.provider, homePath: profile.homePath, name: "auth.json")
        }
    }

    static func executable(_ name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates: [String]
        switch name {
        case "claude":
            candidates = ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        case "codex":
            candidates = [
                "\(home)/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                "\(home)/Applications/Codex.app/Contents/Resources/codex",
                "/Applications/Codex.app/Contents/Resources/codex",
            ]
        case "grok":
            candidates = ["\(home)/.grok/bin/grok", "\(home)/.local/bin/grok", "/opt/homebrew/bin/grok"]
        default:
            candidates = []
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func providerEnvironment(_ profile: AccountProfile) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        environment["PATH"] = "\(home)/.local/bin:\(home)/.grok/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        let variable = profile.provider.homeVariable
        if let path = profile.homePath {
            environment[variable] = path
        } else {
            environment.removeValue(forKey: variable)
        }
        environment["TERM"] = "xterm-256color"
        return environment
    }

    static func signInCommand(for profile: AccountProfile, executable: String) -> String {
        func quoted(_ value: String) -> String {
            "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        let arguments: String
        switch profile.provider {
        case .claude: arguments = "auth login"
        case .codex, .grok: arguments = "login"
        }
        let environment: String
        if let home = profile.homePath {
            environment = "env \(profile.provider.homeVariable)=\(quoted(home))"
        } else {
            environment = "env -u \(profile.provider.homeVariable)"
        }
        return "\(environment) \(quoted(executable)) \(arguments)"
    }

    static func claudeToken(for profile: AccountProfile) -> String? {
        let service: String
        if let path = profile.homePath {
            let digest = SHA256.hash(data: Data(path.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            service = "Claude Code-credentials-\(digest.prefix(8))"
        } else {
            service = "Claude Code-credentials"
        }
        let result = run(
            "/usr/bin/security",
            ["find-generic-password", "-w", "-s", service],
            timeout: 8
        )
        guard result.status == 0,
              let data = result.output.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { return nil }
        return token
    }

    @discardableResult
    static func run(
        _ path: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        input: Data? = nil,
        timeout: TimeInterval = 25
    ) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        if input != nil { process.standardInput = Pipe() }
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        if let input, let pipe = process.standardInput as? Pipe {
            try? pipe.fileHandleForWriting.write(contentsOf: input)
            try? pipe.fileHandleForWriting.close()
        }

        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }
        if completed.wait(timeout: .now() + timeout) == .timedOut {
            if process.isRunning { process.terminate() }
            if completed.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = completed.wait(timeout: .now() + 1)
            }
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let status = process.isRunning ? Int32(-1) : process.terminationStatus
        return (status, String(data: data, encoding: .utf8) ?? "")
    }
}

enum ProviderClient {
    static func fetch(_ profile: AccountProfile) -> (ProviderUsage?, String) {
        switch profile.provider {
        case .claude: return fetchClaude(profile)
        case .codex: return fetchCodex(profile)
        case .grok: return fetchGrok(profile)
        }
    }

    private static func fetchClaude(_ profile: AccountProfile) -> (ProviderUsage?, String) {
        guard let token = AccountStore.claudeToken(for: profile) else {
            return (nil, "Sign in to refresh")
        }
        return UsageAPI.fetchClaude(token: token)
    }

    static func fetchCodex(_ profile: AccountProfile, executable override: String? = nil) -> (ProviderUsage?, String) {
        guard AccountStore.isSignedIn(profile) else { return (nil, "Sign in to refresh") }
        guard let executable = override ?? AccountStore.executable("codex") else {
            return (nil, "Codex CLI not found")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--stdio"]
        process.environment = AccountStore.providerEnvironment(profile)
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        let lock = NSLock()
        var buffer = ""
        var usage: ProviderUsage?
        var failure = "Codex did not return usage"
        let finished = DispatchSemaphore(value: 0)

        func send(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object),
                  var line = String(data: data, encoding: .utf8)
            else { return }
            line += "\n"
            try? input.fileHandleForWriting.write(contentsOf: Data(line.utf8))
        }

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            lock.lock()
            buffer += chunk
            let lines = buffer.components(separatedBy: "\n")
            buffer = lines.last ?? ""
            lock.unlock()

            for line in lines.dropLast() {
                guard let data = line.data(using: .utf8),
                      let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = (message["id"] as? NSNumber)?.intValue
                else { continue }
                if id == 1 {
                    send(["jsonrpc": "2.0", "method": "initialized", "params": [:]])
                    send(["jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read", "params": [:]])
                } else if id == 2 {
                    usage = UsageAPI.parseCodexRateLimits(message)
                    if let error = message["error"] as? [String: Any],
                       let message = error["message"] as? String { failure = message }
                    finished.signal()
                }
            }
        }

        do { try process.run() } catch { return (nil, error.localizedDescription) }
        send([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": ["name": "refill", "title": "Refill", "version": "1"],
                "capabilities": [:],
            ],
        ])

        let result = finished.wait(timeout: .now() + 15)
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        return result == .success && usage != nil ? (usage, "") : (nil, failure)
    }

    private static func fetchGrok(_ profile: AccountProfile) -> (ProviderUsage?, String) {
        guard AccountStore.isSignedIn(profile) else { return (nil, "Sign in to refresh") }
        guard let executable = AccountStore.executable("grok") else { return (nil, "Grok CLI not found") }

        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        var size = winsize(ws_row: 24, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&masterFD, &slaveFD, nil, nil, &size) == 0 else {
            return (nil, "Could not open Grok")
        }
        let master = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)
        let slave = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--no-alt-screen"]
        process.environment = AccountStore.providerEnvironment(profile)
        process.standardInput = slave
        process.standardOutput = slave
        process.standardError = slave

        let lock = NSLock()
        var raw = ""
        var parsed: ProviderUsage?
        var answeredCursor = false
        var completionSent = false
        var firstParsedAt: Date?
        let finished = DispatchSemaphore(value: 0)

        master.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            var shouldFinish = false
            lock.lock()
            raw += chunk
            let shouldAnswer = !answeredCursor && raw.contains("\u{001B}[6n")
            if shouldAnswer { answeredCursor = true }
            if let latest = UsageAPI.parseGrokTerminal(raw) {
                parsed = latest
                if firstParsedAt == nil { firstParsedAt = Date() }
            }
            let hasReset = parsed?.windows.contains { $0.resetsAt != nil } == true
            if hasReset && !completionSent {
                completionSent = true
                shouldFinish = true
            }
            lock.unlock()

            if shouldAnswer {
                try? master.write(contentsOf: Data("\u{001B}[24;1R".utf8))
            }
            if shouldFinish { finished.signal() }
        }

        do { try process.run() } catch { return (nil, error.localizedDescription) }
        try? slave.close()

        // One cancelable timer drives both startup retries and the no-reset fallback.
        // This avoids retaining several delayed closures after Grok has already replied.
        let retryTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        retryTimer.schedule(deadline: .now() + 0.5, repeating: 4)
        retryTimer.setEventHandler {
            var shouldRequest = false
            var shouldFinish = false
            lock.lock()
            if !completionSent,
               let firstParsedAt,
               Date().timeIntervalSince(firstParsedAt) >= 4 {
                completionSent = true
                shouldFinish = parsed != nil
            } else if answeredCursor && parsed == nil && !completionSent {
                shouldRequest = true
            }
            lock.unlock()

            if shouldRequest {
                try? master.write(contentsOf: Data("\u{0015}/usage\r".utf8))
            }
            if shouldFinish { finished.signal() }
        }
        retryTimer.resume()

        let result = finished.wait(timeout: .now() + 42)
        retryTimer.cancel()
        retryTimer.setEventHandler(handler: nil)
        master.readabilityHandler = nil
        if process.isRunning { process.interrupt() }
        lock.lock()
        let finalUsage = parsed
        lock.unlock()
        return result == .success && finalUsage != nil ? (finalUsage, "") : (nil, "Grok usage is unavailable")
    }
}
