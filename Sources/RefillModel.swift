import Combine
import Foundation

final class RefillModel: ObservableObject {
    @Published var accounts: [AccountProfile]
    @Published var states: [String: UsageState]
    @Published var lastRefresh: Date?
    @Published var isRefreshing = false

    private var refreshQueued = false
    private let providerQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.hstrauss.refill.providers"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 3
        return queue
    }()

    init(accounts: [AccountProfile]? = nil, states: [String: UsageState]? = nil) {
        let profiles = accounts ?? AccountStore.accounts()
        self.accounts = profiles
        if let states {
            self.states = states
        } else {
            self.states = Dictionary(uniqueKeysWithValues: profiles.compactMap { profile in
                UsageCache.load(profile.id).map { (profile.id, UsageState.stale($0, "Cached")) }
            })
        }
    }

    var minimumRemaining: Double? {
        accounts.compactMap { states[$0.id]?.usage?.windows.map(\.remainingPercent).min() }.min()
    }

    var hasStaleData: Bool {
        states.values.contains { $0.isStale }
    }

    func refreshAll() {
        guard !isRefreshing else {
            refreshQueued = true
            return
        }
        isRefreshing = true
        let profiles = accounts
        for profile in profiles where states[profile.id] == nil {
            states[profile.id] = .loading
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var result: [String: UsageState] = [:]

        for profile in profiles {
            group.enter()
            providerQueue.addOperation {
                defer { group.leave() }
                let (usage, error) = ProviderClient.fetch(profile)
                let state: UsageState
                if let usage {
                    UsageCache.save(profile.id, usage)
                    state = .fresh(usage)
                } else if let cached = UsageCache.load(profile.id) {
                    state = .stale(cached, error)
                } else {
                    state = .unavailable(error)
                }
                lock.lock()
                result[profile.id] = state
                lock.unlock()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.states = result
            self.lastRefresh = Date()
            self.isRefreshing = false
            self.writeExport()
            if self.refreshQueued {
                self.refreshQueued = false
                self.refreshAll()
            }
        }
    }

    func rescan() throws {
        accounts = try AccountStore.rescan()
        hydrateCachedStates()
        refreshAll()
    }

    func remove(_ profile: AccountProfile) throws {
        accounts = try AccountStore.remove(profile)
        states.removeValue(forKey: profile.id)
        writeExport()
    }

    func rename(_ profile: AccountProfile, to name: String) throws {
        accounts = try AccountStore.rename(profile, to: name)
        writeExport()
    }

    func addCurrent(_ provider: Provider, name: String) throws {
        accounts = try AccountStore.addCurrent(provider, name: name)
        hydrateCachedStates()
        refreshAll()
    }

    func addIsolated(_ provider: Provider, name: String) throws -> AccountProfile {
        let result = try AccountStore.addIsolated(provider, name: name)
        accounts = result.1
        return result.0
    }

    private func hydrateCachedStates() {
        for profile in accounts where states[profile.id] == nil {
            if let cached = UsageCache.load(profile.id) {
                states[profile.id] = .stale(cached, "Cached")
            }
        }
    }

    func writeExport() {
        struct WindowExport: Encodable {
            let label: String
            let usedPercent: Double
            let remainingPercent: Double
            let resetsAt: Date?
        }
        struct AccountExport: Encodable {
            let id: String
            let provider: String
            let name: String
            let status: String
            let stale: Bool
            let message: String?
            let windows: [WindowExport]
        }
        struct RefillExport: Encodable {
            let generatedAt: Date
            let accounts: [AccountExport]
        }

        let exported = accounts.map { profile -> AccountExport in
            let state = states[profile.id]
            let status: String
            switch state {
            case .fresh: status = "fresh"
            case .stale: status = "stale"
            case .unavailable: status = "unavailable"
            case .loading: status = "loading"
            case nil: status = "pending"
            }
            return AccountExport(
                id: profile.id,
                provider: profile.provider.rawValue,
                name: profile.name,
                status: status,
                stale: state?.isStale ?? false,
                message: state?.reason,
                windows: state?.usage?.windows.map {
                    WindowExport(
                        label: $0.label,
                        usedPercent: $0.usedPercent,
                        remainingPercent: $0.remainingPercent,
                        resetsAt: $0.resetsAt
                    )
                } ?? []
            )
        }

        do {
            try FileManager.default.createDirectory(
                at: AccountStore.applicationSupport,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(RefillExport(generatedAt: Date(), accounts: exported))
                .write(to: AccountStore.exportURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: AccountStore.exportURL.path
            )
        } catch {
            // The menu remains useful even if the optional local export fails.
        }
    }

    static func preview() -> RefillModel {
        let now = Date()
        let profiles = [
            AccountProfile(id: "claude:one", provider: .claude, name: "Claude 1", homePath: nil, source: "T3"),
            AccountProfile(id: "claude:two", provider: .claude, name: "Claude 2", homePath: nil, source: "T3"),
            AccountProfile(id: "claude:three", provider: .claude, name: "Claude 3", homePath: nil, source: "T3"),
            AccountProfile(id: "codex:one", provider: .codex, name: "Codex 1", homePath: nil, source: "T3"),
            AccountProfile(id: "codex:two", provider: .codex, name: "Codex 2", homePath: nil, source: "T3"),
            AccountProfile(id: "grok:default", provider: .grok, name: "Grok", homePath: nil, source: "local"),
        ]
        func usage(_ values: [(String, Double, TimeInterval)]) -> ProviderUsage {
            ProviderUsage(windows: values.map {
                UsageWindow(
                    label: $0.0,
                    shortLabel: $0.0 == "5 hours" ? "5h" : String($0.0.prefix(1)),
                    usedPercent: $0.1,
                    resetsAt: now.addingTimeInterval($0.2),
                    durationMinutes: $0.0 == "5 hours" ? 300 : 10_080
                )
            }, fetchedAt: now)
        }
        let states: [String: UsageState] = [
            profiles[0].id: .fresh(usage([("5 hours", 38, 4_200), ("Weekly", 32, 345_600), ("Fable", 83, 345_600)])),
            profiles[1].id: .fresh(usage([("5 hours", 9, 11_400), ("Weekly", 63, 172_800), ("Fable", 12, 172_800)])),
            profiles[2].id: .fresh(usage([("5 hours", 71, 8_100), ("Weekly", 89, 86_400), ("Fable", 100, 86_400)])),
            profiles[3].id: .fresh(usage([("5 hours", 44, 7_200), ("Weekly", 22, 518_400)])),
            profiles[4].id: .stale(usage([("5 hours", 91, 3_600), ("Weekly", 48, 259_200)]), "Offline"),
            profiles[5].id: .fresh(usage([("Weekly", 35, 432_000)])),
        ]
        let model = RefillModel(accounts: profiles, states: states)
        model.lastRefresh = now.addingTimeInterval(-30)
        return model
    }
}
