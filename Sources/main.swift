import AppKit
import Darwin
import Foundation

let arguments = CommandLine.arguments

if arguments.contains("--json") {
    if let data = try? Data(contentsOf: AccountStore.exportURL) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(0)
    }
    FileHandle.standardOutput.write(Data("{\"accounts\":[]}\n".utf8))
    exit(1)
}

if arguments.contains("--probe") {
    let accounts = AccountStore.accounts()
    var values: [[String: Any]] = []
    for account in accounts {
        let result = ProviderClient.fetch(account)
        values.append([
            "provider": account.provider.rawValue,
            "name": account.name,
            "ok": result.0 != nil,
            "windows": result.0?.windows.map {
                [
                    "label": $0.label,
                    "usedPercent": $0.usedPercent,
                    "remainingPercent": $0.remainingPercent,
                    "resetsAt": $0.resetsAt.map { ISO8601DateFormatter().string(from: $0) as Any } ?? NSNull(),
                ]
            } ?? [],
            "message": result.0 == nil ? result.1 : "",
        ])
    }
    let object: [String: Any] = ["accounts": values]
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(values.allSatisfy { $0["ok"] as? Bool == true } ? 0 : 2)
}

if let index = arguments.firstIndex(where: {
    [
        "--screenshot-light", "--screenshot-dark",
        "--screenshot-settings-light", "--screenshot-settings-dark",
        "--screenshot-reauth-light", "--screenshot-reauth-dark",
    ].contains($0)
}),
   arguments.indices.contains(index + 1) {
    _ = NSApplication.shared
    let dark = arguments[index].hasSuffix("dark")
    let settings = arguments[index].contains("settings")
    let reauthentication = arguments[index].contains("reauth")
    let appearance: NSAppearance.Name = dark ? .darkAqua : .aqua
    do {
        if settings {
            try ProofRenderer.renderSettings(to: arguments[index + 1], appearance: appearance)
        } else if reauthentication {
            try ProofRenderer.renderReauthentication(to: arguments[index + 1], appearance: appearance)
        } else {
            try ProofRenderer.render(to: arguments[index + 1], appearance: appearance)
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
