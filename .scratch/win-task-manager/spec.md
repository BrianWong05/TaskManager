# Task Manager for macOS — Implementation Spec

**Version**: 1.0 (decision-complete) · **Date**: 2026-08-08 · **Source**: wayfinder map `.scratch/win-task-manager/map.md` (tickets 01–10)

A SwiftUI-native macOS application that looks and behaves like the Windows 11 Task Manager: monitors processes and system resources, terminates processes, and lives both in a main window and the menu bar. This spec is decision-complete — an implementing effort should need no further design decisions.

---

## 1. Product identity & build

| Item | Value |
|---|---|
| Display name | `Task Manager` (Dock, title bar, menu bar, About — deliberately identical to Windows) |
| Bundle id (app) | `com.brianwong.taskmanager` |
| Bundle id (daemon) | `com.brianwong.taskmanager.daemon` |
| Xcode project | `TaskManager` (single workspace; app target + daemon target) |
| Daemon plist | `com.brianwong.taskmanager.daemon.plist` in the app's `Contents/Library/LaunchDaemons/` |
| Minimum OS | macOS 13 (SMAppService) — developed and tested on macOS 26 |
| Language | Swift 6, SwiftUI; UI strings English-only |
| Sandboxing | **Off** (mandatory — elevation and system metrics are incompatible with App Sandbox). Not App Store distributed. |
| Signing | Xcode automatic signing with a **free personal-team** Apple ID (sufficient for SMAppService registration). Paid Developer ID is the documented upgrade path — architecture unchanged, only the certificate. |
| Icon | macOS-native style: semi-transparent/layered material with a gauge or performance-curve motif (Big Sur-era icon language). NOT a Win11 homage. |

**Signing reality & runbook** (must ship as a README section): personal-team signatures expire periodically (~7 days reported). On expiry the app still runs but the daemon registration becomes invalid → the app enters degraded mode (see §6.4) and Settings shows "Signature expired". Recovery: rebuild/re-sign from Xcode, then Settings → Background service → "Retry setup".

## 2. Architecture overview

Two processes:

1. **Task Manager app** (unprivileged): SwiftUI UI + `SamplerActor` data layer. Everything that works without root lives here and works *always* — even when the daemon is unavailable.
2. **Privileged daemon** (root, launchd): registered via SMAppService, exposes exactly three XPC methods (§6.2).

Module layout inside the app target:

```
TaskManager/
├── App/            # entry point, window + menu-bar scene management, settings store
├── UI/             # one folder per tab + shared Fluent-style components
├── Data/           # SamplerActor, collectors (protocol-backed), snapshots, ring buffers
├── Elevation/      # XPC client, registration flow, degradation state
└── Startup/        # launchd plist enumeration, BTM dump parsing, toggles
Daemon/             # separate target: XPC listener + the three operations
```

Every system-data collector sits behind a protocol so unit tests can inject mocks (§8).

## 3. UI specification

### 3.1 Visual language

- Theme: user-selectable **System / Light / Dark** (default System). System tracks macOS appearance.
- Fluent-ish "resembles" fidelity: 8px corner radii, light borders, layered surfaces (`#F3F3F3` page / `#FFFFFF` cards; dark-mode equivalents), system font stack.
- Accent: Windows 11 blue `#0067C0` (light) with dark-mode equivalent — active nav, chart strokes, selection.
- Every tab defines an empty state and an error state.

### 3.2 Main window shell

- Left vertical nav rail (icon + label), non-collapsible in v1: **Processes / Performance / Startup apps / Users / Settings**. Active item: accent bar + tinted background.
- macOS traffic lights left, centered title "Task Manager".
- Default size ~1000×640, min ~860×520, freely resizable. Size/position and selected tab persist across launches.
- Degradation status bar (§6.4) occupies the top of the content area when shown.

### 3.3 Processes tab

**Toolbar**: search field, live process count, "End task" button (acts on selection).

**List**: app-grouped.
- **App Group**: all processes whose executable path (via `proc_pidpath`) resolves into the same `.app` bundle. Row shows app icon + name + aggregated CPU/Memory; expandable to child processes.
- Processes without a bundle render flat under a "Background processes" section.

**Columns (seven, Win11 parity)**: Name / Status / CPU / Memory / Disk / Network / GPU.
- GPU column renders `–` for every process (per-process GPU is unavailable on macOS — see §7). System GPU % lives on the Performance tab.

**Search**: real-time, case-insensitive filter on process and app names. If any child of a group matches, the whole group stays visible and auto-expands. Empty result → empty-state message.

**Sorting**: single-column; header click cycles column + direction (arrow indicator); default CPU descending; choice persists across sessions.

**Heat coloring**: CPU and Memory columns only, three tiers of background tint — CPU thresholds >5% / >15% / >40%; Memory tiered by share of total system memory.

**Context menu** (process row): End task / Force Quit / Show in Finder / Show Details / Copy (name + PID + path). "Show in Finder" disabled for processes without a backing bundle. App Group rows additionally get "End all in group".

**Termination semantics**:
- **End task** = SIGTERM, no confirmation.
- **Force Quit** = SIGKILL, always preceded by a confirmation dialog stating name and PID.
- Targets requiring elevation route through the daemon (§6); failures show an error dialog with reason.
- **SIP / platform-protected processes** (kernel_task, launchd, …): listed normally; End task / Force Quit disabled with "Protected by the system".

**Keyboard**: ⌘F focuses search · ⌘Q performs End task on selection · Esc clears search / deselects.

**Inspector (Show Details)**: right-side panel sliding over the content; list stays visible, selection kept in sync; Esc or re-invoking closes it.
- Single process — nine fields in two capability tiers:
  - Free for all: Name, PID, PPID, User, Path, Start time, CPU%.
  - Same-user or daemon-filled: Memory RSS, Command line, disk I/O. Cross-user while unprivileged → rows show "Requires elevation".
  - Open files / thread count / environment are deliberately **not** included (would widen the daemon surface).
- App Group — aggregate header (total CPU / memory / process count) + child list (Name / PID / CPU / Memory); clicking a child switches the inspector to it.
- Values live-update from snapshots; if the inspected process exits, keep last frame + "Process exited" notice.

### 3.4 Performance tab

- Left resource list: **CPU / Memory / Disk / Network / GPU** — each entry: name + live value + sparkline. Click switches.
- Right pane: big chart of the selected resource (~60 s window, 1 s ticks, grid background), headline current value, stat row (utilization, process count, cores/capacity, up time).
- Memory card additionally shows a badge when a memory-pressure event (warn/critical) fires.
- Charts fed by ephemeral ring buffers (§5.2).

### 3.5 Startup apps tab

Capability boundary (honest macOS equivalent of Win11's Startup tab):

| Source | Enumerate | Toggle |
|---|---|---|
| `~/Library/LaunchAgents` | ✅ | ✅ without elevation (`launchctl enable/disable user/<uid>/<label>`) |
| `/Library/LaunchAgents`, `/Library/LaunchDaemons` | ✅ | ✅ only through the daemon's `setStartupItem` (elevation) |
| BTM login items (System Settings list, incl. other apps' SMAppService registrations) | ✅ read-only via `sfltool dumpbtm` | ❌ no per-item API — show real state + "Open System Settings" fallback action |

Columns: Name / Location / Status (Enabled/Disabled) / toggle action. Header shows item count + enabled count. `sfltool resetbtm` is never exposed (destructive).

### 3.6 Users tab

One row per user: name, process count, aggregate CPU and memory. Current user highlighted. Rows whose detail requires elevation show a "requires elevation" chip until the daemon fills them.

### 3.7 Settings tab

Top: **Background service status row** — read-only daemon state (Registered / Not registered / Signature expired) + "Retry setup" and "Open Login Items" buttons. This is the stable re-entry point for the setup flow.

Options (exactly three, no others in v1):

| Option | Control | Default |
|---|---|---|
| Theme | Picker: System / Light / Dark | System |
| Start at login | Toggle (`SMAppService.mainApp` login item; independent of daemon) | Off |
| Show menu-bar monitor | Toggle (off hides status item + panel; main window unaffected) | On |

No refresh-rate knob — cadence is internal behavior (§5.1).

**Launch behavior** (no setting): login-item launches stay background-only (menu-bar presence, no window); manual launches open the main window.

### 3.8 Menu-bar monitor

- **Icon**: live CPU percentage text (e.g. "23%"), updated on the sampling cadence.
- **Panel** (popover on click): CPU and Memory sparklines with current values; Top 5 processes by CPU (click opens the main window and selects the process); "Open Task Manager" button.

## 4. Data model

### 4.1 Process identity & grouping

- Identity = **PID + start timestamp** composite key (start time from `kinfo_proc`/`PROC_PIDTBSDINFO`). Protects against PID reuse; vanished processes are dropped immediately.
- App Grouping = `.app` bundle extracted from `proc_pidpath` output; group metrics are sums of children. Icon/display-name resolution is cached and refreshed only on process-table changes — never per tick.
- Rates: CPU% = Δcpu_ns / Δwall_ns / core count; disk/network rates = deltas of cumulative counters between samples.

### 4.2 Sampling & history

- **1 s master tick**: process table, CPU, memory, disk I/O, system metrics.
- **5 s sub-tick**: per-process network (nettop spawn).
- Window hidden AND menu-bar monitor disabled/hidden → process-level sampling pauses; system-level sampling continues.
- **History**: uniform ring buffers, 60 samples × 1 s per resource (CPU / memory / disk / network / GPU). Ephemeral — cleared on restart (Win11 parity).
- **Self-impact budget**: sampler CPU <2% average, app memory <150MB. If exceeded: halve cadence to 2 s automatically and log it.

### 4.3 Concurrency

- Dedicated `SamplerActor` performs all sampling serially off the main thread; publishes immutable `ProcessSnapshot` values to `@MainActor` in one hop per tick. Main window and menu-bar panel render the same snapshot. The nettop task lives inside the same actor at lower frequency.

### 4.4 Elevation in the sampling flow

Base-first + batch fill:
1. Every tick publishes the **base snapshot**: all PIDs with name/path/owner (unprivileged enumeration sees everything) + same-user details.
2. If the daemon is available, the same tick sends one batched XPC round-trip (PID list) to fill cross-user details; the merged snapshot is published.
3. If unavailable, only the base snapshot publishes (degraded mode §6.4).

Kills and startup toggles are user actions through the daemon's other methods — never part of sampling.

### 4.5 Metric fallback table

| Metric | Behavior |
|---|---|
| Per-process GPU | Column shows `–`; system GPU % on Performance tab |
| Cross-user CPU/memory/disk, unprivileged | "Requires elevation" |
| Per-process network, nettop failing | `–`; after 3 consecutive failures → system-wide network only + status-bar notice; next 5 s tick retries naturally |
| Memory-pressure event | Badge on Performance memory card |
| Per-process phys_footprint | Not available without task ports — use `resident_size` (label the column "Memory", Activity-Monitor parity is out of scope) |

## 5. Metrics API selection (verified on macOS 26)

| Data | API | Notes |
|---|---|---|
| PID list | `proc_listpids(PROC_ALL_PIDS)` | sees ALL processes, unprivileged |
| Per-process CPU/RSS/name/uid/ppid/start | `proc_pidinfo(PROC_PIDTASKALLINFO)` | same-user only beyond EPERM; ~1.6 ms for 950 processes |
| Per-process disk I/O | `proc_pid_rusage(RUSAGE_INFO_CURRENT)` | cumulative counters → deltas; same-user only |
| Executable path | `proc_pidpath` | works for all processes incl. root's |
| Command line | `sysctl(KERN_PROCARGS2)` | same-user only |
| User name | `getpwuid(pbi_uid)` | |
| Icon | `NSWorkspace.icon(forFile:)` | cached |
| System CPU % / per-core | `host_statistics(HOST_CPU_LOAD_INFO)` / `host_processor_info` | tick deltas |
| Memory breakdown (wired/active/inactive/free/compressed) | `host_statistics64(HOST_VM_INFO64)` | |
| Swap | `sysctl vm.swapusage` | |
| Memory pressure | `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` | event-driven |
| System disk read/write | IOKit `IOBlockStorageDriver` "Statistics" | cumulative → deltas |
| System network in/out | `getifaddrs` `ifi_ibytes/ifi_obytes` deltas | |
| System GPU % | IORegistry `IOAccelerator` → "PerformanceStatistics" ("Device Utilization %") | unprivileged, Apple Silicon verified |
| Per-process network | `/usr/bin/nettop -P -L 1 -x -J bytes_in,bytes_out` shell-out | the one fragile dependency — isolated in a single swappable collector |

## 6. Elevation architecture

### 6.1 Mechanism

SMAppService-registered root launchd daemon over XPC. Rejected alternatives (recorded, not used): SMJobBless (deprecated), AuthorizationExecuteWithPrivileges (deprecated, removal risk), osascript-per-prompt (documented alternative only, not the default path).

### 6.2 Daemon surface — exactly three methods

```
processDetails(pids: [pid_t]) -> [ProcessDetail]   // cross-user proc_pidinfo-level data, batched
terminate(pid: pid_t, mode: graceful|force)         // SIGTERM / SIGKILL
setStartupItem(label: String, enabled: Bool)        // system-scope launchctl enable/disable
```

No arbitrary shell/exec capability. Caller validation: accept only connections from binaries carrying the `com.brianwong.taskmanager` Team-ID signature. Every privileged call appends an audit-log line (timestamp, PID, operation, result) to a local log file.

### 6.3 Registration lifecycle

- First launch: guided setup — explain why a background service is needed → `SMAppService.daemon(plistName:).register()` → system "Background Items Added" approval.
- User declines or disables later → degraded mode (§6.4).

### 6.4 Degraded mode

Triggered by: unregistered daemon, user disabling it in Login Items, or signature expiry. The app remains fully functional for everything unprivileged:
- Complete process list with base fields.
- Cross-user detail, cross-user kill, system-scope startup toggles: controls disabled with inline reasons.
- Dismissable status bar at the top of the window explains state and offers "Retry setup". Settings keeps the permanent status row (§3.7).

### 6.5 SIP-protected processes

Enumerated and shown; termination controls disabled with "Protected by the system"; any failed kill surfaces an error dialog with the reason.

## 7. Known platform limits (spec-level honesty)

1. Per-process GPU utilization has no public API (Activity Monitor uses private `sysmond`). → omitted per-process, system-level provided.
2. True `phys_footprint` needs task ports (root). → `resident_size` used instead.
3. BTM login items have no per-item toggle API. → read-only + System Settings hand-off.
4. Root enumeration needs no privilege, but cross-user *detail and signaling* do. → daemon.

## 8. Testing strategy

- **Unit tests** on pure logic: App Group aggregation, PID+start-time identity across simulated reuse, rate-delta computation, ring-buffer behavior, heat-tier classification, nettop CSV parsing (recorded fixtures), launchd plist interpretation.
- **Collector protocols** are the mock seam: SamplerActor tests inject mock collectors; no test touches real system calls.
- **No UI automation required** in v1; UI verified manually against §3.
- Privileged paths (daemon, registration, SIP) are covered by the manual acceptance checklist below — they cannot be unit-tested.

### Manual acceptance checklist

1. Fresh install: first launch shows guided setup; approving registers the daemon (verify in System Settings → Login Items).
2. Decline setup: app runs degraded — full list visible, cross-user controls disabled with reasons, status bar present.
3. Kill own process: End task terminates gracefully; Force Quit shows confirmation then kills.
4. Kill another user's/root process (with daemon): succeeds; audit log gains a line.
5. SIP process (e.g. launchd): controls greyed, "Protected by the system".
6. Disable daemon in Login Items while running: app transitions to degraded mode without crashing.
7. Signature-expiry simulation (re-sign/rebuild then retry): "Retry setup" restores full function.
8. nettop failure simulation (rename binary): Network column shows `–`, then system-only notice after 3 failures; restoring returns data next 5 s tick.
9. Startup tab: user LaunchAgents toggle without prompts; system daemons toggle via daemon; BTM items read-only with "Open System Settings".
10. Menu-bar monitor toggle off hides the icon/panel; self-impact stays under budget (CPU <2%, RAM <150MB) with the window open.

## 9. Milestones

1. **M0 — Skeleton**: Xcode project, app + daemon targets, signing setup, empty Win11-style shell (nav rail, five empty tabs), re-sign runbook README.
2. **M1 — Processes tab unprivileged**: SamplerActor + collectors (§5 unprivileged set), snapshot pipeline, grouped seven-column list, search/sort/heat coloring, End task/Force Quit for own-user processes, inspector.
3. **M2 — Performance + menu bar**: system collectors, ring buffers, Performance tab, menu-bar icon + panel.
4. **M3 — Elevation**: daemon target, XPC protocol, registration flow, batched detail fill, cross-user termination, degraded mode + status bar, audit log.
5. **M4 — Remaining tabs**: Startup (launchd + BTM), Users, Settings (three options + service status row), login item.
6. **M5 — Hardening**: nettop resilience, memory-pressure badge, unit-test suite, manual acceptance checklist pass, icon + polish.

## Appendix: source tickets

| Ticket | Content |
|---|---|
| 01 macOS system metrics API survey | §4–§5, §7 facts |
| 02 Elevation mechanism research | §6 mechanism choice facts |
| 03 Startup items management research | §3.5 capability boundary |
| 04 UI structure & information architecture | §3 (base) |
| 05 Elevation architecture decision | §6 |
| 06 Data layer architecture | §4, §5 cadence |
| 08 Settings tab options | §3.7 |
| 09 App identity | §1 |
| 10 Show Details inspector | §3.3 inspector |
