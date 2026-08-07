# Map: Win-style Task Manager for macOS

Status: resolved
Type: map

## Destination

A decision-complete implementation spec (`.scratch/win-task-manager/spec.md`) for a SwiftUI-native macOS task manager that looks and behaves like the Windows 11 Task Manager. Spec in English, ready for a separate implementation effort. When the spec is written and every decision it depends on is resolved, this map is done.

## Notes

- Domain: native macOS desktop app (SwiftUI, Xcode 26.2 / Swift 6.2 on macOS 26.5).
- Reference: Windows 11 Task Manager — tabbed navigation (Processes / Performance / Startup apps / Users / Settings), Fluent-ish look, "resembles, not pixel-perfect" fidelity.
- Scope decisions locked during charting (grilling rounds 1–4):
  - Deliverable of THIS effort is the spec document, not the app itself.
  - Full parity ambition: every Win11 tab covered; capabilities macOS can't provide must get an explicit documented fallback in the spec.
  - Elevation: required (see/kill other users' processes); mechanism deferred to research.
  - Performance graphs: full set (CPU / memory / disk / network / GPU), with researched fallbacks where unavailable.
  - Startup apps: display + enable/disable within macOS limits.
  - Window form: normal windowed app PLUS menu-bar mini monitor (live CPU/mem curves + top-N processes + open main window).
  - Interaction parity: context menu (end task / force quit / show in Finder / copy info), search filter, column sorting, CPU/memory heat coloring.
  - Language: UI English-only; spec document English.
- Skills to consult when working tickets: /grilling and /domain-modeling for grilling tickets; /research for research tickets; /prototype where a visual question needs a concrete artifact.

## Decisions so far

<!-- one line per resolved ticket: gist + link -->

- [macOS system metrics API survey](issues/01-macos-metrics-apis.md) — per-process CPU/RSS/disk-IO only for same-user processes without root (EPERM beyond); system-level GPU % readable via IOAccelerator without root but per-process GPU impossible; per-process network only via shelling to `nettop`; full-process sampling costs ~1.6ms at 950 procs.
- [Elevation mechanism research](issues/02-elevation-mechanisms.md) — process enumeration needs no root, but cross-user details/kill do; recommended: SMAppService root XPC daemon (needs Developer ID / Team-ID signing, ad-hoc blocked) with osascript-per-prompt as the ad-hoc fallback; SMJobBless deprecated.
- [Startup items management research](issues/03-startup-items.md) — launchd items fully enumerable (world-readable plists) and toggleable per-user without root, system scope via elevation; BTM/System-Settings login items read-only via `sfltool dumpbtm`, no per-item toggle — honest Startup-tab capability boundary.
- [UI structure & information architecture](issues/04-ui-structure.md) — Win11-faithful variant chosen via prototype comparison: left nav rail, app-grouped seven-column process list (GPU per-process degraded to `–`), left-list + big-chart Performance, live CPU% menu-bar icon with sparkline/Top-5 panel, End task (SIGTERM) vs Force Quit (SIGKILL + confirm) as separate actions, ⌘F/⌘Q/Esc shortcuts, system theme + Win11 blue accent.
- [Elevation architecture decision](issues/05-elevation-architecture.md) — SMAppService root XPC daemon on free personal-team signing (Developer ID is the later upgrade path); exactly three XPC methods (cross-user detail / terminate / startup toggle) with caller validation + audit log; first-launch guided registration; graceful degraded mode with dismissable status bar; SIP-protected processes shown but greyed out.
- [Data layer architecture](issues/06-data-layer.md) — 1s master tick (nettop on 5s), 60-sample ring buffers, PID+start-time identity, SamplerActor publishing immutable snapshots to @MainActor, bundle-path App Group aggregation, base-first + batched daemon fill, self-impact budget (CPU <2% / 150MB) and a locked metric-fallback table.
- [Settings tab options](issues/08-settings-tab.md) — exactly three options: Theme (System/Light/Dark, default System — overrides ticket 04), Start at login (off, SMAppService login item), Show menu-bar monitor (on); no refresh-rate knob; launch behavior by source (login-item = background-only); daemon status row with Retry setup at top.
- [App identity](issues/09-app-identity.md) — named `Task Manager` (deliberately identical to Windows); bundle ids `com.brianwong.taskmanager` / `.daemon`; macOS-native icon style (gauge motif, not Win11 homage); Xcode project `TaskManager`.
- [Show Details inspector](issues/10-show-details-inspector.md) — right-side inspector panel (list stays visible); nine fields in two capability tiers (cross-user tier degrades to "Requires elevation"); open files explicitly excluded to protect the daemon's narrow surface; App Group shows aggregates + clickable child list; live-updating with "Process exited" last-frame notice.
- [Spec assembly](issues/07-spec-assembly.md) — destination reached: [spec.md](spec.md) written (decision-complete, English); Testing strategy resolved at its head (pure-logic unit tests via collector mock seam + 10-point manual acceptance checklist). No open tickets, no fog remains.

## Not yet specified

- **App identity**: ~~app name, bundle id, icon direction~~ resolved inside ticket 09.
- **Show Details inspector**: ~~what Show Details reveals~~ resolved inside ticket 10.
- **Menu-bar presence beyond the panel**: ~~icon as live mini-meter~~ resolved inside ticket 04 (live CPU% text).
- **Degradation UX**: ~~elevation-driven degradation~~ resolved inside ticket 05 (graceful degraded mode, status bar, greyed entries, SIP messaging); metric-level fallbacks (GPU etc.) now live in the Data layer architecture fallback table.
- **Performance constraints**: ~~sampling intervals, ring buffers, impact budget~~ resolved inside ticket 06 (cadence, ring buffers, budget).
- **Testing strategy**: ~~what the spec should prescribe for testing~~ resolved at the head of the Spec assembly session (unit tests on pure logic via collector mock seam; manual acceptance checklist for privileged paths).

## Out of scope

<!-- nothing ruled out yet -->
