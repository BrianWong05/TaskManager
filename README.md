# Task Manager for macOS

A SwiftUI-native macOS application that looks and behaves like the Windows 11 Task Manager: monitors processes and system resources, terminates processes, and lives both in a main window and the menu bar.

- **App bundle id**: `com.brianwong.taskmanager`
- **Daemon bundle id**: `com.brianwong.taskmanager.daemon`
- **Minimum OS**: macOS 13 · developed on macOS 26 with Xcode 26
- **Sandboxing**: OFF (mandatory — Elevation and system metrics are incompatible with App Sandbox). Not App Store distributed.

The decision-complete implementation spec lives at `.scratch/win-task-manager/spec.md`; the glossary of canonical terms in `CONTEXT.md`.

## Project layout

```
TaskManager/
├── App/            # app target: entry point, window + menu-bar scenes, settings store
├── UI/             # one folder per tab + shared Fluent-style components
├── Data/           # SamplerActor, collectors (protocol-backed), snapshots, ring buffers
├── Elevation/      # XPC client, registration flow, degradation state
├── Startup/        # launchd plist enumeration, BTM dump parsing, toggles
└── Daemon/         # daemon target: XPC listener + the three privileged operations
Shared/             # XPC protocol, compiled into both targets
```

## Building

Open `TaskManager/TaskManager.xcodeproj` in Xcode, select your signing team on both targets (Signing & Capabilities → Team), then build the `TaskManager` scheme. Schemes: `TaskManager` (run the app) and `TaskManagerTests` (unit tests).

## Re-sign runbook (free personal-team signatures)

The app is signed with Xcode automatic signing under a **free personal Apple ID team**. These signatures expire periodically (~7 days reported). The paid Developer ID is the documented upgrade path — architecture unchanged, only the certificate.

**What expiry looks like**: the app itself still runs, but the daemon's registration becomes invalid (launchd rejects the stale signature). The app enters *degraded mode*: the full process list with base fields still works; cross-user detail, cross-user End task/Force Quit, and system-scope Startup toggles are disabled with inline reasons; a dismissable status bar at the top of the window explains the state; Settings shows **Signature expired** in the Background service row.

**Recovery steps**:

1. Open `TaskManager.xcodeproj` in Xcode.
2. Confirm your team is still selected on the `TaskManager` and `TaskManagerDaemon` targets (Signing & Capabilities).
3. Build and run once from Xcode (Product ▸ Run). This re-signs both binaries with a fresh signature.
4. In the running app: Settings ▸ Background service ▸ **Retry setup**. The app re-registers the daemon via `SMAppService` and the system confirms "Background Items Added".
5. The status bar clears and Elevation-dependent features are restored.

If "Retry setup" keeps failing, open System Settings ▸ General ▸ Login Items & Extensions, remove any stale `com.brianwong.taskmanager.daemon` entry, then retry from step 4.
