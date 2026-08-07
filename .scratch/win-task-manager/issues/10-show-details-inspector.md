# 10 — Show Details inspector

Type: grilling
Status: resolved
Parent: map.md

## Question

Graduated from the map's fog (surfaced by ticket 04's context menu). Grill and lock what the "Show Details" action presents: surface form (inspector side panel vs popover vs floating window), the exact field list per process (PID, PPID, user, path, start time, CPU time totals, memory RSS/footprint, command line, open files?) and per App Group (child process list with per-child metrics), which fields need elevation and how they degrade, and live-update vs static-snapshot behavior while open.

Invoke /grilling and /domain-modeling. Output: spec-ready inspector definition in the Answer section.

## Answer

Resolved 2026-08-08 via live grilling (1 round). Spec-ready definition:

1. **Surface**: inspector side panel sliding in on the right of the main window (Finder-style). The process list stays visible with its selection kept in sync; Esc or invoking Show Details again closes it. No separate Details view and no floating window.
2. **Fields for a single process — two groups, nine fields** (per the ticket 01 capability matrix):
   - *Free for every process*: Name, PID, PPID, User, Path, Start time, CPU%.
   - *Same-user only, or filled via the daemon when elevated* (ticket 05): Memory RSS, Command line, disk I/O counters. While unprivileged and cross-user, these rows show "Requires elevation" inline.
   - Explicitly **excluded**: open files, thread count, environment — would require extending the daemon's three-method surface, violating the least-privilege lock in ticket 05.
3. **App Group details**: aggregate header (total CPU, total memory, process count) plus the child-process list (Name / PID / CPU / Memory per row); clicking a child switches the inspector to that process.
4. **Update behavior**: values refresh live with the 1s snapshots (ticket 06). When the inspected process exits, the panel keeps its last frame and shows a "Process exited" notice; Esc dismisses.
