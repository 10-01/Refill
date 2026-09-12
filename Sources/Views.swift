import AppKit
import CoreText
import ServiceManagement
import SwiftUI

enum FontRegistry {
    static func registerBundledFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

enum UsageFormat {
    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func refresh(_ date: Date?) -> String {
        guard let date else { return "not refreshed" }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 10 { return "refreshed now" }
        if seconds < 60 { return "refreshed \(seconds)s ago" }
        if seconds < 3_600 { return "refreshed \(seconds / 60)m ago" }
        return "refreshed \(seconds / 3_600)h ago"
    }

    static func reset(_ date: Date?) -> String {
        guard let date else { return "reset unknown" }
        let seconds = Int(date.timeIntervalSinceNow)
        if seconds <= 0 { return "reset now" }
        if seconds >= 172_800 { return "reset \(seconds / 86_400)d" }
        if seconds >= 3_600 {
            let hours = seconds / 3_600
            let minutes = (seconds % 3_600) / 60
            return minutes > 0 ? "reset \(hours)h \(minutes)m" : "reset \(hours)h"
        }
        return "reset \(max(1, seconds / 60))m"
    }

    static func path(_ path: String?) -> String {
        guard let path else { return "Default login" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + String(path.dropFirst(home.count)) : path
    }
}

/// Counts popover opens. Each open is a navigation, and rows arrive once per navigation.
final class PopoverPresentation: ObservableObject {
    @Published var generation = 0
}

/// Off for proof renders, so screenshots show the end state instead of a frame mid-arrival.
private struct OtisMotionKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var otisMotion: Bool {
        get { self[OtisMotionKey.self] }
        set { self[OtisMotionKey.self] = newValue }
    }
}

/// Arrival. A row of a screen that just opened comes in 8px up and fading, over `Otis.move`,
/// `Otis.stagger` after the row before it. Runs once per navigation, never on scroll.
private struct Arrive: ViewModifier {
    let index: Int
    let generation: Int
    @Environment(\.otisMotion) private var motion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || !animates ? 1 : 0)
            .offset(y: shown || !animates ? 0 : 8)
            .onAppear { arrive() }
            .onChange(of: generation) { _ in arrive() }
    }

    private var animates: Bool { motion && generation > 0 && Otis.motionAllowed }

    private func arrive() {
        guard animates else { return }
        shown = false
        let delay = Otis.stagger * Double(min(index, 8))
        withAnimation(Otis.move.delay(delay)) { shown = true }
    }
}

extension View {
    func arrive(index: Int, generation: Int) -> some View {
        modifier(Arrive(index: index, generation: generation))
    }
}

struct PopoverView: View {
    @ObservedObject var model: RefillModel
    @ObservedObject var presentation: PopoverPresentation
    let openSettings: () -> Void
    let reauthenticate: (AccountProfile) -> Void
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 8) {
                    ForEach(Array(Provider.allCases.enumerated()), id: \.element) { index, provider in
                        ProviderSection(
                            provider: provider,
                            accounts: model.accounts.filter { $0.provider == provider },
                            states: model.states,
                            reauthenticate: reauthenticate
                        )
                        .arrive(index: index, generation: presentation.generation)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            footer
        }
        .frame(width: Otis.popoverWidth, height: 620)
        .background(Otis.chrome)
        .foregroundStyle(Otis.ink)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Refill")
                .font(Otis.sans(15, weight: .semibold))
            Spacer()
            if model.isRefreshing {
                Text("refreshing")
                    .font(Otis.mono(11))
                    .foregroundStyle(Otis.ink2)
            } else {
                Text(UsageFormat.refresh(model.lastRefresh))
                    .font(Otis.mono(11))
                    .foregroundStyle(Otis.ink2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(Otis.chrome)
    }

    private var footer: some View {
        HStack {
            Button("Settings") { openSettings() }
                .keyboardShortcut(",", modifiers: .command)
            Spacer()
            Button(model.isRefreshing ? "Refreshing" : "Refresh") { model.refreshAll() }
                .disabled(model.isRefreshing)
                .keyboardShortcut("r", modifiers: .command)
            Spacer()
            Button("Quit") { quit() }
        }
        .buttonStyle(OtisFooterButtonStyle())
        .font(Otis.mono(11))
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .foregroundStyle(Otis.ink2)
        .background(Otis.chrome)
    }
}

struct ProviderSection: View {
    let provider: Provider
    let accounts: [AccountProfile]
    let states: [String: UsageState]
    let reauthenticate: (AccountProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(provider.title)
                .font(Otis.sans(11, weight: .semibold))
                .foregroundStyle(Otis.ink2)
                .padding(.bottom, 8)

            if accounts.isEmpty {
                Text("No accounts found")
                    .font(Otis.working)
                    .foregroundStyle(Otis.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 {
                        Rectangle().fill(Otis.sheetLine).frame(height: Otis.hairline)
                            .padding(.vertical, 10)
                    }
                    AccountUsageView(
                        profile: profile,
                        state: states[profile.id],
                        reauthenticate: reauthenticate
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Otis.sheet)
        .clipShape(RoundedRectangle(cornerRadius: Otis.radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: Otis.radiusMd)
                .stroke(Otis.sheetLine, lineWidth: Otis.hairline)
        )
    }
}

struct ProviderLogoView: View {
    let provider: Provider

    var body: some View {
        Group {
            if let image = ProviderLogoStore.image(for: provider) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                Text(provider.mark)
                    .font(Otis.mono(10, weight: .medium))
            }
        }
        .foregroundStyle(Otis.ink2)
        .frame(width: 13, height: 13)
        .accessibilityHidden(true)
    }
}

private enum ProviderLogoStore {
    static let images: [Provider: NSImage] = Dictionary(uniqueKeysWithValues: Provider.allCases.compactMap { provider in
        guard let url = Bundle.main.url(
            forResource: provider.logoResourceName,
            withExtension: "svg",
            subdirectory: "ProviderLogos"
        ), let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return (provider, image)
    })

    static func image(for provider: Provider) -> NSImage? { images[provider] }
}

struct AccountUsageView: View {
    let profile: AccountProfile
    let state: UsageState?
    let reauthenticate: (AccountProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text(profile.name)
                    .font(Otis.sans(13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if state?.isStale == true {
                    Text("Stale")
                        .font(Otis.mono(11))
                        .foregroundStyle(Otis.ink2)
                }
                if state?.requiresAuthentication == true {
                    Button("Reauthenticate") { reauthenticate(profile) }
                        .buttonStyle(OtisFooterButtonStyle())
                        .font(Otis.sans(11, weight: .medium))
                        .foregroundStyle(Otis.ink)
                }
            }

            if let windows = state?.usage?.windows, !windows.isEmpty {
                ForEach(windows) { window in
                    UsageWindowView(window: window, stale: state?.isStale == true)
                }
            } else {
                HStack(spacing: 7) {
                    LiveDot(live: stateLoading)
                    Text(stateLoading ? "Refreshing quota" : (state?.reason ?? "Waiting for first refresh"))
                        .font(Otis.sans(11))
                        .foregroundStyle(Otis.ink2)
                        .lineLimit(1)
                        .help(state?.reason ?? "")
                }
                .frame(height: 18)
            }
        }
    }

    private var stateLoading: Bool {
        if case .loading = state { return true }
        return false
    }

}

/// The 6px orange dot that pulses at 1.6s while data is live. The only loop Otis allows.
struct LiveDot: View {
    let live: Bool
    @Environment(\.otisMotion) private var motion
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(live ? Otis.accent : Otis.ink2)
            .frame(width: 6, height: 6)
            .opacity(dim ? 0.3 : 1)
            .onAppear { pulse() }
            .onChange(of: live) { _ in pulse() }
    }

    private func pulse() {
        guard live, motion, Otis.motionAllowed else {
            withAnimation(nil) { dim = false }
            return
        }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true }
    }
}

struct UsageWindowView: View {
    let window: UsageWindow
    let stale: Bool
    @Environment(\.otisMotion) private var motion
    @State private var painted = false

    private var attention: Bool { !stale && window.isTight }
    private var drawn: Bool { painted || !motion || !Otis.motionAllowed }

    var body: some View {
        HStack(spacing: 8) {
            Text(window.label)
                .font(Otis.working)
                .foregroundStyle(Otis.ink2)
                .frame(width: 62, alignment: .leading)
                .lineLimit(1)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Otis.sheetLine)
                    Capsule()
                        .fill(Otis.meterFill(attention: attention, stale: stale))
                        .frame(width: drawn ? max(3, proxy.size.width * CGFloat(window.remainingPercent) / 100) : 3)
                        .animation(Otis.bar, value: window.remainingPercent)
                        .animation(Otis.bar, value: drawn)
                }
            }
            .frame(height: 4)
            .onAppear { painted = true }

            Text(UsageFormat.percent(window.remainingPercent))
                .font(Otis.mono(11, weight: attention ? .medium : .regular))
                .foregroundStyle(Otis.meterText(attention: attention, stale: stale))
                .frame(width: 36, alignment: .trailing)
                .lineLimit(1)

            Text(resetLabel)
                .font(Otis.mono(11))
                .foregroundStyle(attention ? Otis.accentText : Otis.ink2)
                .frame(width: 50, alignment: .trailing)
                .lineLimit(1)
        }
        .frame(height: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.label), \(UsageFormat.percent(window.remainingPercent)) left, \(UsageFormat.reset(window.resetsAt))")
    }

    private var resetLabel: String {
        let value = UsageFormat.reset(window.resetsAt).replacingOccurrences(of: "reset ", with: "")
        return value == "unknown" ? "" : value
    }
}

struct SettingsView: View {
    @ObservedObject var model: RefillModel
    let launchAtLogin: Bool
    let toggleLaunchAtLogin: () -> Void
    let rescan: () -> Void
    let addCurrent: (Provider) -> Void
    let addAnother: (Provider) -> Void
    let reauthenticate: (AccountProfile) -> Void
    let rename: (AccountProfile) -> Void
    let remove: (AccountProfile) -> Void
    let openDataFolder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Otis.accent)
                    .frame(width: 11, height: 11)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Refill settings")
                        .font(Otis.sans(15, weight: .semibold))
                    Text("Accounts are read from their existing CLI homes.")
                        .font(Otis.sans(11))
                        .foregroundStyle(Otis.ink2)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 58)

            Rectangle().fill(Otis.line).frame(height: 1)

            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Text("ACCOUNTS")
                            .font(Otis.label)
                            .tracking(0.7)
                            .foregroundStyle(Otis.ink2)
                        Spacer()
                        Text("\(model.accounts.count) connected")
                            .font(Otis.mono(11))
                            .foregroundStyle(Otis.ink2)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 34)
                    .background(Otis.surface)

                    ForEach(Array(model.accounts.enumerated()), id: \.element.id) { index, account in
                        if index > 0 {
                            Rectangle().fill(Otis.line).frame(height: 1).padding(.leading, 18)
                        }
                        accountRow(account)
                    }
                }
            }

            Rectangle().fill(Otis.line).frame(height: 1)

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(Provider.allCases) { provider in
                            Button("Use current \(provider.title) login") { addCurrent(provider) }
                            Button("Sign in to another \(provider.title) account") { addAnother(provider) }
                        }
                    } label: {
                        Text("Add account")
                            .font(Otis.sans(11, weight: .medium))
                            .foregroundStyle(Otis.ink)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Otis.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: Otis.radius)
                            .stroke(Otis.line, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Otis.radius))

                    Button("Rescan T3") { rescan() }
                        .buttonStyle(OtisPanelButtonStyle())
                    Button(launchAtLogin ? "Launches at login" : "Launch at login") { toggleLaunchAtLogin() }
                        .buttonStyle(OtisPanelButtonStyle(active: launchAtLogin))
                    Spacer()
                }

                HStack {
                    Text("Refreshes every 5 minutes. No tokens are copied or exported.")
                        .font(Otis.sans(11))
                        .foregroundStyle(Otis.ink2)
                    Spacer()
                    Button("Open data folder") { openDataFolder() }
                        .buttonStyle(OtisFooterButtonStyle())
                        .font(Otis.mono(11))
                        .foregroundStyle(Otis.ink2)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(width: 540, height: 526)
        .background(Otis.paper)
        .foregroundStyle(Otis.ink)
    }

    private func accountRow(_ account: AccountProfile) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(Otis.sans(13, weight: .medium))
                Text("\(account.provider.title) · \(UsageFormat.path(account.homePath)) · \(account.source)")
                    .font(Otis.mono(11))
                    .foregroundStyle(Otis.ink2)
                    .lineLimit(1)
            }
            Spacer()
            Button("Reauthenticate") { reauthenticate(account) }
                .buttonStyle(OtisFooterButtonStyle())
                .font(Otis.mono(11))
                .foregroundStyle(Otis.ink2)
            Button("Rename") { rename(account) }
                .buttonStyle(OtisFooterButtonStyle())
                .font(Otis.mono(11))
                .foregroundStyle(Otis.ink2)
            Button("Remove") { remove(account) }
                .buttonStyle(OtisFooterButtonStyle())
                .font(Otis.mono(11))
                .foregroundStyle(Otis.bad)
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }
}

struct OtisFooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Otis.press, value: configuration.isPressed)
    }
}

struct OtisPanelButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Otis.sans(11, weight: .medium))
            .foregroundStyle(active ? Otis.paper : Otis.ink)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(active ? Otis.ink : Otis.surface)
            .overlay {
                RoundedRectangle(cornerRadius: Otis.radius)
                    .stroke(active ? Otis.ink : Otis.line, lineWidth: 1)
            }
            .animation(Otis.fast, value: active)
            .clipShape(RoundedRectangle(cornerRadius: Otis.radius))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Otis.press, value: configuration.isPressed)
    }
}
