// TaskManagerTests/StartupParseTests.swift
// Launchd plist interpretation and BTM dump parsing with recorded fixtures
// (spec §8) — no real launchctl/sfltool in tests.

import Testing
@testable import TaskManager

private let btmFixture = """
Background task management dump

Name: BlueStacks Service
        Developer Name: BlueStack Systems
        Type: app (0x2)
        Disposition: [enabled, allowed, notified]
        Identifier: com.bluestacks.bluestacks
        Bundle Identifier: com.bluestacks.bluestacks

Name: Spotify Helper
        Type: agent (0x8)
        Disposition: [disabled, allowed, not notified]
        Identifier: com.spotify.helper
        URL: file:///Applications/Spotify.app/

Name: Legacy Daemon
        Disposition: [enabled, disallowed, not notified]
        Identifier: com.example.legacy
"""

@Suite struct BTMParserTests {
    @Test func parsesRecordedDump() {
        let records = BTMParser.parse(btmFixture)
        #expect(records.count == 3)
        #expect(records[0].name == "BlueStacks Service")
        #expect(records[0].disabled == false)
        #expect(records[1].name == "Spotify Helper")
        #expect(records[1].disabled == true)
        #expect(records[2].identifier == "com.example.legacy")
    }

    @Test func emptyAndGarbageInputYieldNothing() {
        #expect(BTMParser.parse("").isEmpty)
        #expect(BTMParser.parse("random noise\nno keys here").isEmpty)
    }

    @Test func missingDispositionDefaultsEnabled() {
        let records = BTMParser.parse("Name: Thing\nIdentifier: com.thing\n\n")
        #expect(records.first?.disabled == false)
    }
}

@Suite struct LaunchdPlistParserTests {
    @Test func interpretsMeaningfulKeys() {
        let plist: [String: Any] = [
            "Label": "com.example.agent",
            "ProgramArguments": ["/usr/local/bin/agent", "--daemon"],
            "RunAtLoad": true,
            "Disabled": false,
        ]
        let info = LaunchdPlistParser.parse(plist, fallbackLabel: "unused")
        #expect(info?.label == "com.example.agent")
        #expect(info?.programPath == "/usr/local/bin/agent")
        #expect(info?.runAtLoad == true)
        #expect(info?.plistDisabledKey == false)
    }

    @Test func fallsBackToFileNameLabelAndProgramKey() {
        let plist: [String: Any] = [
            "Program": "/opt/tool/run",
            "Disabled": true,
        ]
        let info = LaunchdPlistParser.parse(plist, fallbackLabel: "com.fallback.label")
        #expect(info?.label == "com.fallback.label")
        #expect(info?.programPath == "/opt/tool/run")
        #expect(info?.plistDisabledKey == true)
    }

    @Test func absentOptionalsDefaultFalse() {
        let info = LaunchdPlistParser.parse(["Label": "x"], fallbackLabel: "f")
        #expect(info?.runAtLoad == false)
        #expect(info?.plistDisabledKey == false)
        #expect(info?.programPath == "")
    }
}

@Suite struct BTMDeduplicationTests {
    /// sfltool emits one section per UID, repeating items registered for
    /// several users. Duplicate ids made SwiftUI misrender the list, so the
    /// parser keeps one record per identifier.
    @Test func repeatedIdentifiersAcrossUIDSectionsCollapseToOne() {
        let dump = """
        ========================
         Records for UID 501
        ========================
                     Name: Microsoft AutoUpdate
               Identifier: Microsoft AutoUpdate
              Disposition: [enabled, allowed, notified]

        ========================
         Records for UID -2
        ========================
                     Name: Microsoft AutoUpdate
               Identifier: Microsoft AutoUpdate
              Disposition: [enabled, allowed, notified]

                     Name: Other Item
               Identifier: com.example.other
              Disposition: [disabled, allowed, not notified]
        """
        let records = BTMParser.parse(dump)
        #expect(records.count == 2)
        #expect(records.map(\.identifier) == ["Microsoft AutoUpdate", "com.example.other"])
        #expect(Set(records.map(\.identifier)).count == records.count)
    }
}
