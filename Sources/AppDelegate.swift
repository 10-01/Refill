import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = RefillModel()
    private let presentation = PopoverPresentation()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var modelObserver: AnyCancellable?
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontRegistry.registerBundledFonts()
        configureStatusItem()
        configurePopover()

        modelObserver = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }
        updateStatusItem()
        model.refreshAll()

        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            self?.model.refreshAll()
        }
        timer.tolerance = 25
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self?.model.refreshAll() }
        }

        if !UserDefaults.standard.bool(forKey: "did-open-refill-once") {
            UserDefaults.standard.set(true, forKey: "did-open-refill-once")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.showPopover()
            }
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: Otis.popoverWidth, height: 620)
        popover.contentViewController = NSHostingController(rootView: PopoverView(
            model: model,
            presentation: presentation,
            openSettings: { [weak self] in self?.showSettings() },
            reauthenticate: { [weak self] account in self?.reauthenticate(account) },
            quit: { NSApp.terminate(nil) }
        ))
    }

    @objc private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        if let last = model.lastRefresh, Date().timeIntervalSince(last) > 30 {
            model.refreshAll()
        }
        presentation.generation += 1
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let remaining = model.minimumRemaining
        button.attributedTitle = StatusTitle.make(remaining: remaining, stale: model.hasStaleData)
        if let remaining {
            button.toolTip = "Refill: \(UsageFormat.percent(remaining)) left on the tightest window"
        } else {
            button.toolTip = model.isRefreshing ? "Refill is refreshing" : "Refill has no usage yet"
        }
    }

    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 526),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Refill settings"
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.contentViewController = NSHostingController(rootView: settingsRootView())
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func settingsRootView() -> SettingsView {
        SettingsView(
            model: model,
            launchAtLogin: SMAppService.mainApp.status == .enabled,
            toggleLaunchAtLogin: { [weak self] in self?.toggleLaunchAtLogin() },
            rescan: { [weak self] in self?.rescanAccounts() },
            addCurrent: { [weak self] provider in self?.addCurrent(provider) },
            addAnother: { [weak self] provider in self?.addAnother(provider) },
            reauthenticate: { [weak self] account in self?.reauthenticate(account) },
            rename: { [weak self] account in self?.rename(account) },
            remove: { [weak self] account in self?.remove(account) },
            openDataFolder: { NSWorkspace.shared.open(AccountStore.applicationSupport) }
        )
    }

    private func rescanAccounts() {
        do { try model.rescan() }
        catch { showError("Accounts were not rescanned", error.localizedDescription) }
    }

    private func addCurrent(_ provider: Provider) {
        let probe = AccountProfile(
            id: "probe",
            provider: provider,
            name: provider.title,
            homePath: nil,
            source: "local"
        )
        guard AccountStore.isSignedIn(probe) else {
            showError("No \(provider.title) login found", "Sign in with the \(provider.title) CLI, then try again.")
            return
        }
        guard let name = askForName(
            title: "Add current \(provider.title) login",
            detail: "Choose a short name for this account.",
            initial: provider.title
        ) else { return }
        do { try model.addCurrent(provider, name: name) }
        catch { showError("Account was not added", error.localizedDescription) }
    }

    private func addAnother(_ provider: Provider) {
        guard let name = askForName(
            title: "Add another \(provider.title) account",
            detail: "Refill will open an isolated sign-in in Terminal.",
            initial: ""
        ) else { return }
        do {
            let profile = try model.addIsolated(provider, name: name)
            launchSignIn(profile)
            scheduleRefreshAfterSignIn()
        } catch {
            showError("Account was not added", error.localizedDescription)
        }
    }

    private func launchSignIn(_ profile: AccountProfile) {
        guard let executable = AccountStore.executable(profile.provider.cliName)
        else {
            showError("CLI not found", "Install the \(profile.provider.title) CLI, then try again.")
            return
        }
        let command = AccountStore.signInCommand(for: profile, executable: executable)
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        _ = AccountStore.run(
            "/usr/bin/osascript",
            ["-e", "tell application \"Terminal\" to do script \"\(escaped)\""],
            timeout: 8
        )
    }

    private func reauthenticate(_ profile: AccountProfile) {
        launchSignIn(profile)
        scheduleRefreshAfterSignIn()
    }

    private func scheduleRefreshAfterSignIn() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.model.refreshAll() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.model.refreshAll() }
    }

    private func rename(_ profile: AccountProfile) {
        guard let name = askForName(
            title: "Rename account",
            detail: "This changes only the label shown in Refill.",
            initial: profile.name
        ) else { return }
        do { try model.rename(profile, to: name) }
        catch { showError("Account was not renamed", error.localizedDescription) }
    }

    private func remove(_ profile: AccountProfile) {
        let alert = NSAlert()
        alert.messageText = "Remove \(profile.name)?"
        alert.informativeText = "Refill will forget this account. The CLI login files stay on this Mac."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try model.remove(profile) }
        catch { showError("Account was not removed", error.localizedDescription) }
    }

    private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            settingsWindow?.contentViewController = NSHostingController(rootView: settingsRootView())
        } catch {
            showError("Launch at login was not changed", error.localizedDescription)
        }
    }

    private func askForName(title: String, detail: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initial
        field.placeholderString = "Account name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 48 else {
            showError("Enter an account name", "Use 1 to 48 characters.")
            return nil
        }
        return name
    }

    private func showError(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

enum StatusTitle {
    static func make(remaining: Double?, stale: Bool) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor(hex: "#ff7a3a").setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            return true
        }
        attachment.bounds = NSRect(x: 0, y: -1, width: 8, height: 8)
        let title = NSMutableAttributedString(attachment: attachment)
        let value = remaining.map { "  \(UsageFormat.percent($0))" } ?? "  Refill"
        let color: NSColor
        if stale {
            color = NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "#a09e96") : NSColor(hex: "#6b6862")
            }
        } else if let remaining, remaining <= 15 {
            color = NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "#ff7a3a") : NSColor(hex: "#c2440a")
            }
        } else {
            color = NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "#f0eee5") : NSColor(hex: "#1a1814")
            }
        }
        title.append(NSAttributedString(string: value, attributes: [
            .font: NSFont(name: "Geist Mono", size: 11) ?? NSFont(name: "GeistMono-Regular", size: 11)!,
            .foregroundColor: color,
        ]))
        return title
    }
}

enum ProofRenderer {
    static func render(to path: String, appearance: NSAppearance.Name) throws {
        FontRegistry.registerBundledFonts()
        let model = RefillModel.preview()
        let claude = model.accounts.filter { $0.provider == .claude }
        let codex = model.accounts.filter { $0.provider == .codex }
        let grok = model.accounts.first { $0.provider == .grok }
        let selected = [claude.first, claude.dropFirst().first, codex.first, codex.last, grok].compactMap { $0 }
        let selectedIDs = Set(selected.map(\.id))
        model.accounts = selected
        model.states = model.states.filter { selectedIDs.contains($0.key) }
        let root = PopoverView(
            model: model,
            presentation: PopoverPresentation(),
            openSettings: {},
            reauthenticate: { _ in },
            quit: {}
        )
        try capture(root, size: NSSize(width: Otis.popoverWidth, height: 620), to: path, appearance: appearance)
    }

    static func renderSettings(to path: String, appearance: NSAppearance.Name) throws {
        FontRegistry.registerBundledFonts()
        let root = SettingsView(
            model: RefillModel.preview(),
            launchAtLogin: true,
            toggleLaunchAtLogin: {},
            rescan: {},
            addCurrent: { _ in },
            addAnother: { _ in },
            reauthenticate: { _ in },
            rename: { _ in },
            remove: { _ in },
            openDataFolder: {}
        )
        try capture(root, size: NSSize(width: 540, height: 526), to: path, appearance: appearance)
    }

    static func renderReauthentication(to path: String, appearance: NSAppearance.Name) throws {
        FontRegistry.registerBundledFonts()
        let model = RefillModel.preview()
        if let claude = model.accounts.first(where: { $0.provider == .claude }),
           let codex = model.accounts.first(where: { $0.provider == .codex }),
           let grok = model.accounts.first(where: { $0.provider == .grok }) {
            model.accounts = [claude, codex, grok]
            model.states = model.states.filter { [claude.id, codex.id, grok.id].contains($0.key) }
            model.states[grok.id] = .unavailable("Sign in to refresh")
        }
        let root = PopoverView(
            model: model,
            presentation: PopoverPresentation(),
            openSettings: {},
            reauthenticate: { _ in },
            quit: {}
        )
        try capture(root, size: NSSize(width: Otis.popoverWidth, height: 620), to: path, appearance: appearance)
    }

    private static func capture<Content: View>(
        _ root: Content,
        size: NSSize,
        to path: String,
        appearance: NSAppearance.Name
    ) throws {
        let host = NSHostingView(rootView: root.environment(\.otisMotion, false))
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: appearance)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.appearance = host.appearance
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw NSError(domain: "Refill", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render proof"])
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Refill", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode proof"])
        }
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        window.orderOut(nil)
    }
}
