# 04 — UI structure & information architecture

Type: grilling
Status: resolved
Parent: map.md

## Question

Grill and lock the UI structure and information architecture of the app, so the spec can describe every screen unambiguously. Fidelity target: "resembles Windows 11 Task Manager" (layout & feel, not pixel-perfect).

Decide:
1. Main window shell: left vertical nav rail (Win11 style: icons + labels) vs top tab bar; window sizing, resize behavior, remembered layout.
2. Per-tab content skeleton: Processes (app-grouped vs flat process list, columns), Performance (which graph cards and layout), Startup (columns, status chips), Users, Settings.
3. Menu-bar mini monitor panel: exact composition (CPU/mem sparklines, top-N list N=?, actions, "Open Task Manager" entry), menu-bar icon (static vs live value).
4. Interaction spec: search field behavior, column sorting (multi-column?), heat coloring rules, context menu item list, keyboard shortcuts (Cmd+Q process?, Esc), empty/error states.
5. Visual language summary: color palette approach (Fluent-ish light/dark), typography, corner radius — at "resembles" fidelity, what's prescribed vs left to implementation.

Invoke /grilling and /domain-modeling. Output: the decision record in the Answer section, phrased as spec-ready statements.

## Assets

- UI exploration prototype: [assets/ui-prototype.html](../assets/ui-prototype.html) — 3 variants switchable via floating bar / `?variant=A|B|C` (A: Win11 Faithful · B: Classic Dense · C: Modern Hybrid), plus demo pages for Performance / Startup / Users / Settings. User picked Variant A wholesale.

## Answer

Resolved 2026-08-08 via live grilling (4 rounds) + prototype comparison. All decisions below are spec-ready.

### Main window shell (chosen: Variant A — "Win11 Faithful")

1. **Navigation**: left vertical nav rail with icon + label entries: Processes / Performance / Startup apps / Users / Settings. Rail stays expanded (no collapse in v1). Active item shows accent bar + tinted background.
2. **Title bar**: macOS traffic lights on the left, centered window title "Task Manager".
3. **Window**: default ~1000×640, min ~860×520, freely resizable; last size/position and selected tab remembered across launches.

### Processes tab

4. **View**: app-grouped — GUI processes aggregated into expandable **App Groups** keyed by bundle id (group shows aggregate CPU/memory); background processes listed flat below.
5. **Columns** (seven, Win11-parity): Name / Status / CPU / Memory / Disk / Network / GPU. Per-process GPU unavailable on macOS (ticket 01): the GPU column renders `–` for every process; system-level GPU % lives on the Performance tab only.
6. **Toolbar**: search field + process count; "End task" button acts on the selection.
7. **Search**: real-time filter, case-insensitive, matches process and app names; if any child process of a group matches, the whole group stays visible and auto-expands. Empty result → empty-state message.
8. **Sorting**: single-column sort; header click cycles column + direction with arrow indicator; default CPU descending; sort choice persisted across sessions.
9. **Heat coloring**: CPU and Memory columns only, three tiers of background tint (CPU: >5% / >15% / >40%; Memory: tiered by share of total system memory). Other columns uncolored.
10. **Context menu** (process row): End task / Force Quit / Show in Finder / Show Details / Copy (name + PID + path). Show in Finder disabled for processes without a backing app bundle. **App Group row** additionally gets "End all in group".
11. **Termination semantics**: two independent actions — **End task** = graceful SIGTERM, no confirmation; **Force Quit** = SIGKILL, always preceded by a confirmation dialog stating process name and PID. Elevated targets route through the elevation channel (ticket 05).
12. **Keyboard**: ⌘F focuses search; ⌘Q performs End task on the selection; Esc clears search / deselects.

### Performance tab

13. **Layout**: left resource list (CPU / Memory / Disk / Network / GPU), each entry = name + live value + sparkline; right pane = big chart for the selected resource (~60 s history, 1 s ticks, grid background) + headline current value + stat row (utilization, process count, cores/capacity, up time). Clicking the list switches resources.

### Menu-bar monitor

14. **Icon**: live CPU percentage text (e.g. "23%") updated on the same sampling cadence as the main window.
15. **Panel** (popover on icon click): CPU and Memory sparklines with current values, Top 5 processes by CPU (click jumps to the main window and selects the process), and an "Open Task Manager" button.

### Startup / Users tabs

16. **Startup**: columns Name / Location / Status / toggle action, per the capability boundary in ticket 03 (launchd items toggleable; BTM login items read-only with a "Open System Settings" fallback affordance).
17. **Users**: one row per user (current user highlighted): user name, process count, aggregate CPU and memory; rows requiring elevation show a "requires elevation" chip until elevated.

### Visual language

18. **Theme**: follows macOS light/dark automatically. Fluent-ish feel at "resembles" fidelity: 8px corner radii, light borders, layered surfaces (#F3F3F3 / #FFFFFF), Segoe-style system font stack.
19. **Accent**: Windows 11 blue `#0067C0` (light mode) with dark-mode equivalent, used for active nav, chart strokes, selection.
20. **Empty/error states**: every tab defines one; data unavailable without elevation renders an inline elevation prompt rather than a blank.

Open threads graduated from this resolution: Settings tab options list (→ ticket 08); Show Details inspector content (fog).
