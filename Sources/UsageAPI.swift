import Foundation

enum UsageAPI {
    static func parseDate(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        guard let string = value as? String else { return nil }
        if let seconds = Double(string) { return Date(timeIntervalSince1970: seconds) }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    private static func get(
        _ urlString: String,
        token: String,
        headers: [String: String] = [:]
    ) -> (Data?, Int, String?) {
        guard let url = URL(string: urlString) else { return (nil, 0, "Invalid endpoint") }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.timeoutInterval = 12

        var result: (Data?, Int, String?) = (nil, 0, "Timed out")
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            result = (data, (response as? HTTPURLResponse)?.statusCode ?? 0, error?.localizedDescription)
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 15)
        return result
    }

    static func fetchClaude(token: String) -> (ProviderUsage?, String) {
        let headers = ["anthropic-beta": "oauth-2025-04-20"]
        let (data, status, error) = get(
            "https://api.anthropic.com/api/oauth/usage",
            token: token,
            headers: headers
        )
        if status == 401 || status == 403 { return (nil, "Sign in again") }
        if let error, data == nil { return (nil, error) }
        guard status == 200,
              let data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return (nil, status == 0 ? "Offline" : "Service returned \(status)") }

        guard let usage = parseClaudeUsage(json) else { return (nil, "No quota windows returned") }
        return (usage, "")
    }

    static func parseClaudeUsage(_ json: [String: Any], fetchedAt: Date = Date()) -> ProviderUsage? {
        if let limits = json["limits"] as? [[String: Any]] {
            let windows = limits.compactMap { value -> (Int, UsageWindow)? in
                guard let kind = value["kind"] as? String,
                      let percent = (value["percent"] as? NSNumber)?.doubleValue
                else { return nil }

                let label: String
                let shortLabel: String
                let rank: Int
                let duration: Int
                switch kind {
                case "session":
                    label = "5 hours"
                    shortLabel = "5h"
                    rank = 0
                    duration = 300
                case "weekly_all":
                    label = "Weekly"
                    shortLabel = "W"
                    rank = 1
                    duration = 10_080
                case "weekly_scoped":
                    guard let scope = value["scope"] as? [String: Any],
                          let model = scope["model"] as? [String: Any],
                          let displayName = model["display_name"] as? String
                    else { return nil }
                    let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanName.isEmpty else { return nil }
                    label = cleanName
                    shortLabel = String(cleanName.prefix(1)).uppercased()
                    rank = 2
                    duration = 10_080
                default:
                    return nil
                }

                return (rank, UsageWindow(
                    label: label,
                    shortLabel: shortLabel,
                    usedPercent: max(0, min(100, percent)),
                    resetsAt: parseDate(value["resets_at"]),
                    durationMinutes: duration
                ))
            }.sorted {
                $0.0 == $1.0
                    ? $0.1.label.localizedCaseInsensitiveCompare($1.1.label) == .orderedAscending
                    : $0.0 < $1.0
            }.map(\.1)

            if !windows.isEmpty { return ProviderUsage(windows: windows, fetchedAt: fetchedAt) }
        }

        func legacyWindow(_ key: String, label: String, short: String, minutes: Int) -> UsageWindow? {
            guard let value = json[key] as? [String: Any],
                  let percent = (value["utilization"] as? NSNumber)?.doubleValue
            else { return nil }
            return UsageWindow(
                label: label,
                shortLabel: short,
                usedPercent: max(0, min(100, percent)),
                resetsAt: parseDate(value["resets_at"]),
                durationMinutes: minutes
            )
        }

        let windows = [
            legacyWindow("five_hour", label: "5 hours", short: "5h", minutes: 300),
            legacyWindow("seven_day", label: "Weekly", short: "W", minutes: 10_080),
            legacyWindow("seven_day_fable", label: "Fable", short: "F", minutes: 10_080),
            legacyWindow("seven_day_sonnet", label: "Sonnet", short: "S", minutes: 10_080),
            legacyWindow("seven_day_opus", label: "Opus", short: "O", minutes: 10_080),
        ].compactMap { $0 }

        return windows.isEmpty ? nil : ProviderUsage(windows: windows, fetchedAt: fetchedAt)
    }

    static func windowLabel(minutes: Int) -> (String, String) {
        if minutes == 300 { return ("5 hours", "5h") }
        if minutes == 10_080 { return ("Weekly", "W") }
        if minutes % 10_080 == 0 { return ("\(minutes / 10_080) weeks", "\(minutes / 10_080)w") }
        if minutes % 1_440 == 0 { return ("\(minutes / 1_440) days", "\(minutes / 1_440)d") }
        if minutes % 60 == 0 { return ("\(minutes / 60) hours", "\(minutes / 60)h") }
        return ("\(minutes) minutes", "\(minutes)m")
    }

    static func parseCodexRateLimits(_ object: [String: Any]) -> ProviderUsage? {
        let result = (object["result"] as? [String: Any]) ?? object
        var candidates: [[String: Any]] = []
        if let rateLimits = result["rateLimits"] as? [String: Any] {
            if let primary = rateLimits["primary"] as? [String: Any] { candidates.append(primary) }
            if let secondary = rateLimits["secondary"] as? [String: Any] { candidates.append(secondary) }
        }
        if let buckets = result["rateLimitsByLimitId"] as? [String: Any] {
            let preferred = (buckets["codex"] as? [String: Any])
                ?? buckets.values.compactMap { $0 as? [String: Any] }.first
            if let preferred {
                if let primary = preferred["primary"] as? [String: Any] { candidates.append(primary) }
                if let secondary = preferred["secondary"] as? [String: Any] { candidates.append(secondary) }
            }
        }

        var seen = Set<Int>()
        let windows = candidates.compactMap { value -> UsageWindow? in
            guard let duration = (value["windowDurationMins"] as? NSNumber)?.intValue,
                  let percent = (value["usedPercent"] as? NSNumber)?.doubleValue,
                  seen.insert(duration).inserted
            else { return nil }
            let labels = windowLabel(minutes: duration)
            return UsageWindow(
                label: labels.0,
                shortLabel: labels.1,
                usedPercent: percent,
                resetsAt: parseDate(value["resetsAt"]),
                durationMinutes: duration
            )
        }.sorted { ($0.durationMinutes ?? 0) < ($1.durationMinutes ?? 0) }

        return windows.isEmpty ? nil : ProviderUsage(windows: windows, fetchedAt: Date())
    }

    static func parseGrokTerminal(_ raw: String) -> ProviderUsage? {
        let stripped = raw.replacingOccurrences(
            of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
        guard let range = stripped.range(
            of: #"Weekly limit[^%]{0,240}([0-9]+(?:\.[0-9]+)?)%"#,
            options: .regularExpression
        ) else { return nil }
        let match = String(stripped[range])
        guard let percentRange = match.range(
            of: #"([0-9]+(?:\.[0-9]+)?)%"#,
            options: [.regularExpression, .backwards]
        ),
              let value = Double(match[percentRange].dropLast())
        else { return nil }
        let percent = value

        var reset: Date?
        if let resetRange = stripped.range(
            of: #"(?:Next reset|Resets):\s*[A-Za-z]+\s+[0-9]{1,2},\s*[0-9]{2}:[0-9]{2}"#,
            options: .regularExpression
        ) {
            let value = String(stripped[resetRange])
                .replacingOccurrences(of: "Next reset:", with: "")
                .replacingOccurrences(of: "Resets:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMMM d, HH:mm"
            if let partial = formatter.date(from: value) {
                let calendar = Calendar.current
                var parts = calendar.dateComponents([.month, .day, .hour, .minute], from: partial)
                parts.year = calendar.component(.year, from: Date())
                reset = calendar.date(from: parts)
                if let candidate = reset, candidate < Date().addingTimeInterval(-86_400) {
                    parts.year = (parts.year ?? 0) + 1
                    reset = calendar.date(from: parts)
                }
            }
        }

        return ProviderUsage(
            windows: [UsageWindow(
                label: "Weekly",
                shortLabel: "W",
                usedPercent: percent,
                resetsAt: reset,
                durationMinutes: 10_080
            )],
            fetchedAt: Date()
        )
    }
}

enum UsageCache {
    private static func key(_ id: String) -> String { "refill-cache-\(id)" }

    static func save(_ id: String, _ usage: ProviderUsage) {
        if let data = try? JSONEncoder().encode(usage) {
            UserDefaults.standard.set(data, forKey: key(id))
        }
    }

    static func load(_ id: String) -> ProviderUsage? {
        let data = UserDefaults.standard.data(forKey: key(id))
            ?? (UserDefaults.standard.persistentDomain(forName: "com.hstrauss.leftbar")?["leftbar-cache-\(id)"] as? Data)
            ?? (UserDefaults.standard.persistentDomain(forName: "com.hstrauss.quota")?["quota-cache-\(id)"] as? Data)
        guard let data else { return nil }
        return try? JSONDecoder().decode(ProviderUsage.self, from: data)
    }
}
