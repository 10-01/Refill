import Foundation

private var failures = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures += 1
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    }
}

expect(Set(Provider.allCases.map(\.logoResourceName)).count == Provider.allCases.count,
       "Every provider should have a distinct logo resource")

let codex: [String: Any] = [
    "result": [
        "rateLimits": [
            "primary": ["usedPercent": 42.0, "windowDurationMins": 300, "resetsAt": 1_800_000_000],
            "secondary": ["usedPercent": 73.0, "windowDurationMins": 10_080, "resetsAt": 1_800_500_000],
        ],
    ],
]
let codexUsage = UsageAPI.parseCodexRateLimits(codex)
expect(codexUsage?.windows.count == 2, "Codex should expose both quota windows")
expect(codexUsage?.windows.first?.remainingPercent == 58, "Remaining quota should be derived from used quota")
expect(codexUsage?.windows.last?.label == "Weekly", "The 7-day Codex window should be labeled Weekly")

let claude: [String: Any] = [
    "limits": [
        ["kind": "session", "percent": 42.0, "resets_at": "2026-09-02T22:20:00Z"],
        ["kind": "weekly_all", "percent": 61.0, "resets_at": "2026-09-09T07:00:00Z"],
        [
            "kind": "weekly_scoped",
            "percent": 100.0,
            "resets_at": "2026-09-09T07:00:00Z",
            "scope": ["model": ["display_name": "Fable"]],
        ],
    ],
]
let claudeUsage = UsageAPI.parseClaudeUsage(claude)
expect(claudeUsage?.windows.count == 3, "Claude should expose session, weekly, and scoped model windows")
expect(claudeUsage?.windows.last?.label == "Fable", "Claude should label its scoped Fable window")
expect(claudeUsage?.windows.last?.remainingPercent == 0, "A fully used Fable limit should show zero left")
expect(claudeUsage?.windows.last?.resetsAt != nil, "Fable should include its reset time")

let legacyClaude: [String: Any] = [
    "five_hour": ["utilization": 10.0, "resets_at": "2026-09-02T22:20:00Z"],
    "seven_day": ["utilization": 20.0, "resets_at": "2026-09-09T07:00:00Z"],
    "seven_day_fable": ["utilization": 30.0, "resets_at": "2026-09-09T07:00:00Z"],
]
expect(UsageAPI.parseClaudeUsage(legacyClaude)?.windows.last?.label == "Fable",
       "Claude's legacy Fable field should remain supported")

let grok = "Weekly limit: 64%\nNext reset: September 7, 14:30\n"
let grokUsage = UsageAPI.parseGrokTerminal(grok)
expect(grokUsage?.windows.first?.usedPercent == 64, "Grok terminal output should parse")
expect(grokUsage?.windows.first?.remainingPercent == 36, "Grok remaining quota should be derived")

let currentGrok = "Weekly limit (SuperGrok Heavy)     5%     Resets: September 4, 06:22"
expect(UsageAPI.parseGrokTerminal(currentGrok)?.windows.first?.usedPercent == 5,
       "Current Grok usage dialog output should parse")
expect(UsageAPI.parseGrokTerminal(currentGrok)?.windows.first?.resetsAt != nil,
       "Current Grok reset time should parse")

let paintedGrok = "Weekly limit (SuperGrok Heavy)\u{001B}[8;57H5%\u{001B}[9;25H\u{001B}[2mResets: September 4, 06:22"
expect(UsageAPI.parseGrokTerminal(paintedGrok)?.windows.first?.resetsAt != nil,
       "Grok cursor-painted reset time should parse")

let tight = UsageWindow(
    label: "Weekly",
    shortLabel: "W",
    usedPercent: 91,
    resetsAt: nil,
    durationMinutes: 10_080
)
expect(tight.isTight, "A window at 91 percent used should be tight")
expect(tight.remainingPercent == 9, "Tight window remaining value should be exact")

let firstID = AccountStore.stableID(provider: .codex, path: "/tmp/example")
let secondID = AccountStore.stableID(provider: .codex, path: "/tmp/example")
let otherID = AccountStore.stableID(provider: .claude, path: "/tmp/example")
expect(firstID == secondID, "Account IDs should be stable")
expect(firstID != otherID, "Provider should contribute to account identity")

expect(UsageState.unavailable("Sign in to refresh").requiresAuthentication,
       "Sign-in errors should offer reauthentication")
expect(!UsageState.unavailable("Offline").requiresAuthentication,
       "Network errors should not offer reauthentication")

let defaultGrok = AccountProfile(
    id: "grok:test",
    provider: .grok,
    name: "Grok",
    homePath: nil,
    source: "test"
)
expect(AccountStore.signInCommand(for: defaultGrok, executable: "/usr/local/bin/grok")
    == "env -u GROK_HOME '/usr/local/bin/grok' login",
    "Default Grok reauthentication should unset GROK_HOME and run login")

let customClaude = AccountProfile(
    id: "claude:test",
    provider: .claude,
    name: "Work",
    homePath: "/tmp/Claude Home",
    source: "test"
)
expect(AccountStore.signInCommand(for: customClaude, executable: "/usr/local/bin/claude")
    == "env CLAUDE_CONFIG_DIR='/tmp/Claude Home' '/usr/local/bin/claude' auth login",
    "Custom Claude reauthentication should preserve its isolated home")

let timeoutStarted = Date()
let timeoutResult = AccountStore.run("/bin/sleep", ["5"], timeout: 0.05)
expect(timeoutResult.status != 0, "Timed-out child processes should not report success")
expect(Date().timeIntervalSince(timeoutStarted) < 2,
       "Timed-out child processes should be terminated promptly")

if failures == 0 {
    print("All Refill tests passed")
    exit(0)
}
exit(1)
