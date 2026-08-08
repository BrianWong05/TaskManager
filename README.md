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

## Manual acceptance checklist (spec §8)

Privileged paths cannot be unit-tested; run these against a **signed** build (select your team first — ad-hoc builds always run degraded):

1. Fresh install: first launch shows the guided setup sheet; approving registers the daemon (verify in System Settings ▸ Login Items).
2. Decline setup: the app runs degraded — full process list visible, cross-user controls disabled with reasons, status bar present.
3. Kill own process: End task terminates gracefully (no confirmation); Force Quit confirms then kills.
4. Kill another user's/root process (daemon active): succeeds; `/Library/Application Support/TaskManager/audit.log` gains a line.
5. SIP process (e.g. launchd): controls greyed, "Protected by the system".
6. Disable the daemon in Login Items while running: the app transitions to degraded mode without crashing (within ~10 s).
7. Signature-expiry simulation — forcing the state is easier than waiting for it (see below): the status bar reads **"signature expired"** (distinct from "not set up"), then Settings ▸ Retry setup restores full function.
8. nettop failure simulation (see below): Network column shows `–`, then the "system-wide network only" notice after 3 failures; restoring returns data on the next sub-tick.
9. Startup tab: user LaunchAgents toggle without prompts; system daemons toggle through the daemon; BTM items read-only with "Open System Settings".
10. Mini monitor toggle off hides the icon/panel; self-impact stays under budget (CPU <8 %, RAM <150 MB) with the window open.

> The CPU figure was revised from 2 % to 8 % after measurement — spec §4.2 holds the canonical numbers and reasoning.
>
> CPU percentages here are on Activity Monitor's scale (100 % = one busy core), so compare against Activity Monitor or `top` — **not** against htop, which is commonly configured to divide by core count and will read ~14× lower on a 14-core machine.

### How to trigger items 7 and 8

Both items were originally written with steps that do not work on a current
system. These methods do.

**Item 7 — signature expiry.** Waiting for the signature to lapse may never
happen: an Apple Development certificate is valid for about a year, and with no
entitlements requiring a provisioning profile there is no 7-day profile to
expire. What matters is the *state* — registered but not answering — so force it
directly:

```bash
sudo launchctl bootout system/com.brianwong.taskmanager.daemon
```

`SMAppService` still reports `.enabled` while the mach service is gone, which is
exactly the signature-expiry symptom. Within ~10 s the status bar should read
"Background service signature expired". Then click **Retry setup**: the daemon
relaunches and cross-user detail returns, in the same app session.

**Item 8 — nettop failure.** `sudo mv /usr/bin/nettop …` fails on macOS with SIP
enabled ("Operation not permitted") — `/usr/bin` is protected. Kill nettop as
the app spawns it instead:

```bash
while :; do pkill -x nettop; sleep 0.25; done
```

Leave it running ~20 s (the notice needs 3 consecutive failed sub-ticks), then
stop it with Ctrl-C. Per-process Network returns on the next successful sub-tick;
the Performance tab keeps showing system-wide network throughout, which is what
the notice points at.
