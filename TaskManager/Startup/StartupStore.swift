// Startup/StartupStore.swift
// Enumeration + toggling of Startup items (spec §3.5). Enumeration is pure
// directory reads (no privilege); toggles route user-domain items through
// local launchctl and system-domain items through the daemon.

import Foundation
import Combine

@MainActor
final class StartupStore: ObservableObject {
    @Published private(set) var items: [StartupItem] = []
    @Published private(set) var isLoading = false
    @Published var toggleErrorMessage: String?

    private let elevation: ElevationManager

    init(elevation: ElevationManager) {
        self.elevation = elevation
    }

    // MARK: Enumeration

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        var collected: [StartupItem] = []

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        collected += await enumerateDirectory("\(home)/Library/LaunchAgents",
                                            source: .userAgents,
                                            domain: "user/\(getuid())",
                                            ability: .userDomain)
        collected += await enumerateDirectory("/Library/LaunchAgents",
                                            source: .systemAgents,
                                            domain: "system",
                                            ability: .systemDomain)
        collected += await enumerateDirectory("/Library/LaunchDaemons",
                                            source: .systemDaemons,
                                            domain: "system",
                                            ability: .systemDomain)

        let disabledFlags = await printDisabledFlags()
        for index in collected.indices {
            let item = collected[index]
            if let label = item.label, let flag = disabledFlags[label] {
                // launchctl flag wins over the plist's Disabled key.
                collected[index].enabled = !flag
            }
        }

        collected += await enumerateBTM()
        items = collected
    }

    private func enumerateDirectory(_ path: String, source: StartupSource,
                                    domain: String, ability: StartupToggleAbility) async -> [StartupItem] {
        var results: [StartupItem] = []
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.pathExtension == "plist" {
            guard let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(
                      from: data, options: [], format: nil) as? [String: Any] else { continue }
            let fallback = url.deletingPathExtension().lastPathComponent
            guard let info = LaunchdPlistParser.parse(plist, fallbackLabel: fallback) else { continue }
            results.append(StartupItem(
                id: "\(domain)/\(info.label)",
                name: info.label,
                location: "\(source.rawValue) · \(url.lastPathComponent)",
                source: source,
                label: info.label,
                enabled: !info.plistDisabledKey,
                toggleAbility: ability))
        }
        return results
    }

    /// `launchctl print-disabled <domain>` flag map (readable without root).
    private func printDisabledFlags() async -> [String: Bool] {
        var flags: [String: Bool] = [:]
        for domain in ["user/\(getuid())", "system"] {
            let output = await run("/bin/launchctl", ["print-disabled", domain])
            guard let output else { continue }
            for line in output.split(separator: "\n") {
                // Lines look like: "\t\"com.example.agent\" => disabled"
                let parts = line.split(separator: "=>")
                guard parts.count == 2 else { continue }
                let label = parts[0]
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                let state = parts[1].trimmingCharacters(in: .whitespaces)
                guard !label.isEmpty else { continue }
                flags[label] = state.lowercased().hasPrefix("disabled")
            }
        }
        return flags
    }

    /// BTM login items — read-only via `sfltool dumpbtm` (spec §3.5).
    private func enumerateBTM() async -> [StartupItem] {
        guard let output = await run("/usr/bin/sfltool", ["dumpbtm"]) else { return [] }
        return BTMParser.parse(output).map { record in
            StartupItem(
                id: "btm:\(record.identifier)",
                name: record.name,
                location: "Login items · managed in System Settings",
                source: .loginItems,
                label: nil,
                enabled: !record.disabled,
                toggleAbility: .readOnly)
        }
    }

    // MARK: Toggling

    func toggle(_ item: StartupItem) async {
        guard let label = item.label else { return }
        let enable = !item.enabled
        switch item.toggleAbility {
        case .userDomain:
            let verb = enable ? "enable" : "disable"
            let output = await run("/bin/launchctl", [verb, "user/\(getuid())/\(label)"],
                                   returnError: true)
            if let output, !output.isEmpty {
                toggleErrorMessage = output
            }
        case .systemDomain:
            guard elevation.isActive else {
                toggleErrorMessage = "Requires elevation — set up the background service in Settings, then retry."
                return
            }
            let result = await elevation.client.setStartupItem(label: label, enabled: enable)
            if !result.success {
                toggleErrorMessage = result.reason ?? "Toggle failed"
            }
        case .readOnly:
            return
        }
        await reload()
    }

    // MARK: Shell-out helper

    private func run(_ path: String, _ arguments: [String], returnError: Bool = false) async -> String? {
        // Blocking Process work happens off the main actor.
        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            do {
                try process.run()
            } catch {
                return nil
            }
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if returnError, process.terminationStatus != 0 {
                return String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return String(data: outData, encoding: .utf8)
        }.value
    }
}
