import Foundation

enum Provider: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case grok

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .grok: return "Grok"
        }
    }

    var mark: String {
        switch self {
        case .claude: return "C"
        case .codex: return "O"
        case .grok: return "X"
        }
    }

    var logoResourceName: String { rawValue }

    var homeVariable: String {
        switch self {
        case .claude: return "CLAUDE_CONFIG_DIR"
        case .codex: return "CODEX_HOME"
        case .grok: return "GROK_HOME"
        }
    }

    var cliName: String { rawValue }
}

struct AccountProfile: Codable, Hashable, Identifiable {
    let id: String
    let provider: Provider
    var name: String
    let homePath: String?
    let source: String

    var isDefaultHome: Bool { homePath == nil }
}

struct UsageWindow: Codable, Equatable, Identifiable {
    var id: String { "\(label):\(durationMinutes ?? 0)" }
    let label: String
    let shortLabel: String
    let usedPercent: Double
    let resetsAt: Date?
    let durationMinutes: Int?

    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
    var isTight: Bool { usedPercent >= 85 }
}

struct ProviderUsage: Codable, Equatable {
    let windows: [UsageWindow]
    let fetchedAt: Date
}

enum UsageState: Equatable {
    case loading
    case fresh(ProviderUsage)
    case stale(ProviderUsage, String)
    case unavailable(String)

    var usage: ProviderUsage? {
        switch self {
        case .fresh(let usage), .stale(let usage, _): return usage
        case .loading, .unavailable: return nil
        }
    }

    var isStale: Bool {
        if case .stale = self { return true }
        return false
    }

    var reason: String? {
        switch self {
        case .stale(_, let reason), .unavailable(let reason): return reason
        case .loading, .fresh: return nil
        }
    }

    var requiresAuthentication: Bool {
        guard let reason = reason?.lowercased() else { return false }
        return reason.contains("sign in") || reason.contains("token") || reason.contains("authenticat")
    }
}
