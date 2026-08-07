# 06 — Data layer architecture

Type: grilling
Status: resolved
Parent: map.md
Blocked by: 01, 05

## Question

Given the metrics API survey (ticket 01) and the elevation architecture (ticket 05), grill and lock the data layer design for the spec:

1. Sampling architecture: sampler actor(s), tick intervals per data class (UI list refresh vs graph sampling vs menu-bar panel), and how the menu-bar panel shares state with the main window.
2. Process model: identity across PID reuse, app-grouping rules (bundle vs process), tree vs flat, delta computation for rates (CPU%, disk/network rate).
3. History stores: ring buffers for graphs — depth, resolution, downsample policy (Win11 shows ~60s windows at ~1s ticks).
4. Elevation boundary in the data layer: which collectors run unprivileged, which go through the elevated channel, and how missing data surfaces to the UI (degradation states).
5. Concurrency/threading model in Swift (actors, MainActor publish path) and the self-impact budget (max overhead the monitor may impose).
6. Fallback table: for every metric the research found unavailable (e.g. GPU), the prescribed substitute or explicit omission.

Invoke /grilling and /domain-modeling. Output: spec-ready architecture statements in the Answer section.

## Answer

Resolved 2026-08-08 via live grilling (2 rounds) on top of tickets 01 (measured API facts) and 05 (elevation architecture). All decisions spec-ready.

### Sampling architecture

1. **Cadence**: one 1s master tick drives process table, CPU, memory, disk I/O and system metrics; per-process network (nettop) runs on a 5s sub-tick (it spawns a process; 5s deltas are plenty for network rates). When the main window is hidden and the menu-bar panel collapsed, process-level sampling pauses; system-level sampling continues (feeds the menu-bar CPU% icon).
2. **History stores**: uniform ring buffers, 60 samples deep at 1s resolution per resource (CPU / memory / disk / network / GPU); ephemeral — cleared on restart, matching Win11 behavior.

### Process model

3. **Identity**: composite key of PID + start timestamp (`kinfo_proc` / `PROC_PIDTBSDINFO` start time). Protects against PID reuse; vanished processes are dropped from the list immediately.
4. **App Group algorithm**: derive the owning `.app` bundle from the executable path (`proc_pidpath`, free for all processes); processes sharing a bundle aggregate into one App Group row (name + app icon, group values = sum of children, expandable). Processes with no bundle render flat in a "Background processes" section.
5. **Rates**: CPU% = Δcpu_ns / Δwall_ns / core count; disk and network rates = deltas of cumulative counters between samples; icon and display-name resolution cached, refreshed only on process-table changes (never per tick).

### Concurrency & publication

6. **Model**: a dedicated `SamplerActor` performs all sampling serially off the main thread and publishes immutable `ProcessSnapshot` values to `@MainActor` in one hop per tick. Main window and menu-bar panel both render from the same snapshot. nettop runs as a lower-frequency task inside the same actor.

### Elevation boundary in the sampling flow

7. **Base-first + batch fill**: every tick first publishes a base snapshot (all PIDs with name/path/owner from unprivileged enumeration + same-user details). When the daemon (ticket 05) is available, the same tick sends one batched XPC round-trip (PID list) to fill cross-user details and publishes the merged snapshot; when unavailable, only the base snapshot publishes (degraded mode per ticket 05). Kills and startup toggles are actions, not sampling — they go through the daemon's other methods with the audit log.

### Resilience, budget & fallback table

8. **nettop resilience**: isolated in a single collector. On failure (missing binary, parse error, >3s timeout) the Network column shows `–`; after 3 consecutive failures degrade to system-wide network only + status-bar notice; no retry storm — the next 5s tick retries naturally. The collector is the one swappable seam if Apple changes nettop.
9. **Self-impact budget**: sampler CPU <2% average, app memory <150MB; if exceeded, automatically halve cadence to 2s and log it. (Headroom is large — measured full pass is ~1.6ms — so the budget is a regression guardrail, not a tight constraint.)
10. **Fallback table** (locks every "unavailable" finding from the metrics research into UI behavior): per-process GPU → column renders `–` (system GPU % lives on the Performance tab); cross-user CPU/memory/disk while unprivileged → "Requires elevation"; nettop failure → `–`; memory-pressure events → badge on the Performance memory card.
