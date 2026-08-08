// Startup/StartupModels.swift
// Startup item models (spec §3.5) — the honest macOS capability boundary:
// launchd plists are enumerable everywhere, toggleable user-domain without
// elevation and system-domain through the daemon; BTM login items are
// read-only with a System Settings hand-off.

import Foundation

enum StartupSource: String, Sendable {
    case userAgents = "User LaunchAgents"
    case systemAgents = "System LaunchAgents"
    case systemDaemons = "System LaunchDaemons"
    case loginItems = "Login items"
}

/// What the user can do with this item (spec §3.5 matrix).
enum StartupToggleAbility: Equatable, Sendable {
    /// ~/Library/LaunchAgents — local `launchctl enable/disable user/…`.
    case userDomain
    /// /Library/* — requires the daemon's setStartupItem.
    case systemDomain
    /// BTM items: no per-item API exists; show state + System Settings.
    case readOnly
}

struct StartupItem: Identifiable, Sendable {
    let id: String
    let name: String
    let location: String
    let source: StartupSource
    /// launchd label used for enable/disable; nil for BTM entries.
    let label: String?
    var enabled: Bool
    let toggleAbility: StartupToggleAbility
}

/// One parsed launchd plist (pure — unit tested, spec §8).
struct LaunchdPlistInfo: Sendable {
    let label: String
    let programPath: String
    let runAtLoad: Bool
    let plistDisabledKey: Bool
}

enum LaunchdPlistParser {
    /// Interpret the meaningful keys of a launchd plist (spec §3.5).
    static func parse(_ plist: [String: Any], fallbackLabel: String) -> LaunchdPlistInfo? {
        let label = plist["Label"] as? String ?? fallbackLabel
        var program = plist["Program"] as? String ?? ""
        if program.isEmpty, let args = plist["ProgramArguments"] as? [String], let first = args.first {
            program = first
        }
        return LaunchdPlistInfo(
            label: label,
            programPath: program,
            runAtLoad: plist["RunAtLoad"] as? Bool ?? false,
            plistDisabledKey: plist["Disabled"] as? Bool ?? false
        )
    }
}

/// One parsed BTM record from `sfltool dumpbtm` (pure — unit tested).
struct BTMRecord: Sendable {
    let name: String
    let identifier: String
    /// true when the Disposition line starts with "disabled".
    let disabled: Bool
}

enum BTMParser {
    /// Defensively parse the unstructured `sfltool dumpbtm` text dump
    /// (undocumented format — never assume more than "Key: Value" lines
    /// separated by blank lines).
    static func parse(_ dump: String) -> [BTMRecord] {
        var records: [BTMRecord] = []
        var name: String?
        var identifier: String?
        var disabled: Bool?

        // sfltool dumps one section per UID, and a login item registered for
        // several users repeats verbatim in each — 166 records but only 91
        // distinct identifiers on a normal machine. Emitting the repeats gave
        // the list duplicate SwiftUI ids, which renders as misplaced rows and
        // large gaps while scrolling. One row per identifier.
        var seenIdentifiers = Set<String>()

        func flush() {
            if let name, !name.isEmpty {
                let key = identifier ?? name
                if seenIdentifiers.insert(key).inserted {
                    records.append(BTMRecord(name: name,
                                             identifier: key,
                                             disabled: disabled ?? false))
                }
            }
            name = nil
            identifier = nil
            disabled = nil
        }

        for rawLine in dump.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "Name":
                if name != nil { flush() } // new record without blank separator
                name = value
            case "Identifier", "Bundle Identifier":
                if identifier == nil { identifier = value }
            case "Disposition":
                // Values look like "[disabled, allowed, not notified]".
                disabled = value
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[ ]"))
                    .lowercased().hasPrefix("disabled")
            default:
                break
            }
        }
        flush()
        return records
    }
}
