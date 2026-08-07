# 01 — macOS system metrics API survey

Type: research
Status: resolved
Parent: map.md

## Question

What macOS system APIs are available to a SwiftUI app (macOS 26, Xcode 26.2) for collecting the data the Windows 11 Task Manager shows, and what are their access requirements?

Cover:
1. **System-wide + per-process CPU** usage (host_statistics / host_processor_info / libproc pid_rusage / proc_pidinfo).
2. **Memory**: system pressure, wired/active/compressed breakdown, per-process RSS/footprint.
3. **Disk I/O**: system-wide and per-process read/write bytes (IOKit, fs_usage-class APIs) — what's actually obtainable without root.
4. **Network**: system-wide and per-process bytes sent/received (Network Extension entitlements? nettop-style data? getifaddrs deltas?).
5. **GPU utilization**: is there any public API (IOAccelerator family, powermetrics requires root, private APIs)? What's the best honest fallback for the spec (e.g. omit, or show GPU-rendering-per-process via Metal/AVFoundation proxies)?
6. **Process metadata**: name, icon, user owner, PID/PPID, start time, command line, executable path — which calls provide them, and which require elevation to see other users' processes.
7. Sampling cost and rate limits: how cheap are these calls at ~1s intervals for hundreds of processes?

Deliverable: the answer section of this ticket with a fact table per metric (API, entitlement/root requirement, granularity, cost), plus citations to Apple docs / known open-source usage (e.g. Stats app, htop, osquery).

## Answer

> Target verified against: macOS 26, uid 501 (non-root), ad-hoc-signed non-sandboxed binary, compiled with Xcode toolchain on this machine. All "measured" figures below are empirical results from test programs run during this research, not just documentation claims.

### TL;DR — what is impossible or requires elevation

| Capability | Verdict without root |
|---|---|
| Per-process CPU / RSS / disk I/O for **same-user** processes | ✅ works (`proc_pidinfo` / `proc_pid_rusage`) |
| Per-process CPU / memory / disk I/O for **other users' (incl. root daemons)** processes | ❌ `EPERM` — needs root or a privileged helper (this was the boundary measured: 707 of 950 processes readable as uid 501) |
| Process **name/path/pid/ppid/uid** for **all** processes | ✅ `proc_pidpath` works even for root processes; `PROC_PIDTBSDINFO` for full metadata only same-user |
| Per-process **phys_footprint** (Activity Monitor–style) | ⚠️ only `pti_resident_size` via `PROC_PIDTASKALLINFO` (same-user). True footprint needs task port → `task_for_pid` → root/debug entitlement |
| Per-process **network bytes** | ⚠️ no public C API; only via shelling out to `/usr/bin/nettop` (works without root — measured) or private `NetworkStatistics` framework |
| System-wide **GPU utilization** | ✅ IORegistry `IOAccelerator` → `PerformanceStatistics` (works without root — measured); no entitlement |
| **Per-process GPU** utilization | ❌ no public API; Activity Monitor gets it via private `sysmond` XPC |
| `powermetrics` (GPU power/ANE/memory bandwidth) | ❌ requires `sudo` |
| System CPU/memory/disk/network totals | ✅ all available without root |

### 1. CPU

| Metric | API | Root/entitlement | Granularity | Cost @1s |
|---|---|---|---|---|
| System CPU % | `host_statistics(HOST_CPU_LOAD_INFO)` → tick deltas (`cpu_ticks[CPU_STATE_*]`) | none | whole system | single Mach call, µs |
| Per-core CPU % | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` | none | per logical core | one call for all cores (measured OK, 14 cores) |
| Per-process CPU % | `proc_pidinfo(pid, PROC_PIDTASKALLINFO)` → `pti_total_user` / `pti_total_system` (ns); % = Δcpu_ns / Δwall_ns / ncores | same-user only (EPERM otherwise, measured); root bypasses | per process | **measured: 1.6 ms total for 950 processes** |
| Per-process CPU (alt) | `proc_pid_rusage(pid, RUSAGE_INFO_V4)` → `ri_user_time`/`ri_system_time` | same-user only | per process | comparable |
| Thread-level | `task_threads` + `thread_info(THREAD_BASIC_INFO)` | needs task port (`task_for_pid` → root or debugger entitlement) | per thread | expensive; avoid — `PROC_PIDTASKALLINFO` is the right primitive |

Notes: `sysctl KERN_PROC` `p_pctcpu` is always 0 on macOS (kernel built without `PROC_HAS_SCHEDINFO`); Activity Monitor uses private `sysmond` — confirmed by the Apple Developer Forums thread cited below. htop and osquery both use the libproc/Mach route ([htop DarwinProcessList.c](https://github.com/htop-dev/htop/blob/main/darwin/DarwinProcessList.c), [osquery processes.cpp](https://github.com/osquery/osquery/blob/main/osquery/tables/system/darwin/processes.cpp)).

### 2. Memory

| Metric | API | Root/entitlement | Granularity | Cost @1s |
|---|---|---|---|---|
| Total RAM | `sysctlbyname("hw.memsize")` / `ProcessInfo.physicalMemory` | none | static | trivial |
| Wired / active / inactive / free / **compressed** / purgeable pages | `host_statistics64(HOST_VM_INFO64)` → `vm_statistics64_data_t` (`wire_count`, `active_count`, `inactive_count`, `free_count`, `compressor_page_count`, `purgeable_count`) × `vm_page_size` | none | system | single call (measured OK) |
| Memory pressure level | `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` dispatch source (public) or parse `memory_pressure` CLI | none | warn/critical events | event-driven |
| Swap usage | `sysctl vm.swapusage` (`xsw_usage`) | none | system | trivial |
| Per-process RSS | `PROC_PIDTASKALLINFO.pti_resident_size` | same-user only | per process | included in the 1.6 ms pass above |
| Per-process **phys_footprint** | `task_info(TASK_VM_INFO).phys_footprint` ([TN2434](https://developer.apple.com/library/archive/technotes/tn2434/_index_.html)) | needs task port → `task_for_pid` → root (or target signed with `get-task-allow` for your own apps) | per process | n/a without elevation |

Fallback decision input: without root, show `resident_size` for same-user processes and "—" for others. Activity Monitor's footprint column comes from privileged `sysmond`.

### 3. Disk I/O

| Metric | API | Root/entitlement | Granularity | Cost @1s |
|---|---|---|---|---|
| System-wide bytes read/written | IOKit: match `IOBlockStorageDriver` (or `IOMedia`), read `"Statistics"` dict → `"Bytes (Read)"`, `"Bytes (Write)"`, ops, latency | none | per volume; cumulative counters → delta | few IORegistry reads (measured OK via `ioreg`, matches Stats app's Disk module) |
| Per-process bytes read/written | `proc_pid_rusage(pid, RUSAGE_INFO_CURRENT)` → `ri_diskio_bytesread` / `ri_diskio_byteswritten` (cumulative lifetime counters) | same-user only (measured: `EPERM` on pid 1) | per process | one syscall per process |
| Real-time per-I/O stream | `fs_usage`/`iotop`-style kdebug (`kdebug_trace`) | ❌ root only | per operation | n/a for non-root app |

Caveat: `ri_diskio_*` are lifetime aggregates; rate = delta between samples. They count actual disk I/O (unbuffered), which is what Activity Monitor's "Bytes Read/Written" columns show ([SO #15786618](https://stackoverflow.com/questions/15786618/per-process-disk-read-write-statistics-in-mac-os-x)).

### 4. Network

| Metric | API | Root/entitlement | Granularity | Cost @1s |
|---|---|---|---|---|
| System-wide bytes in/out | `getifaddrs()` → `if_data.ifi_ibytes/ifi_obytes` deltas (or `netstat -ib`) | none | per interface | trivial |
| Per-process bytes in/out | shell out to `/usr/bin/nettop -P -L 1 -x -J bytes_in,bytes_out` (CSV; cumulative per-process counters) | **none — measured as uid 501, includes root daemons** | per process | ~1 process spawn/s, tens of ms; acceptable |
| Per-process bytes (in-app API) | private `NetworkStatistics.framework` (what nettop links against) | no entitlement but **private API** → fragile, not Mac-App-Store-safe | per process | n/a |
| Per-process bytes (proper API) | Network Extension (`NEFilterDataProvider` etc.) | ❌ requires `com.apple.developer.networking.networkextension` entitlement + Apple approval + user consent; intercepts traffic — wrong tool for a monitor | n/a | not recommended |

Decision input: per-process network is only realistically available by shelling out to `nettop` (or parsing its CSV). This is ad-hoc-signed/local, so shelling out is fine; flag it as the one fragile dependency.

### 5. GPU — honest assessment

| Metric | API | Root/entitlement | Granularity | Cost @1s |
|---|---|---|---|---|
| **System GPU utilization** | IORegistry: `IOServiceGetMatchingServices(kIOServicePlane, IOServiceMatching("IOAccelerator"))` → `"PerformanceStatistics"` dict → `"Device Utilization %"`, `"Renderer Utilization %"`, `"Tiler Utilization %"` (+ temp, clocks on Intel/AMD) | **none** — measured on Apple Silicon (`AGXAcceleratorG16X`, values 19–25%); same source used by the open-source [Stats app](https://github.com/exelban/stats/blob/master/Modules/GPU/reader.swift) | per GPU device | few IORegistry reads |
| ANE utilization / GPU power | IOReport private C API (`IOReportCopyChannelsInGroup("Energy Model")`) or `powermetrics` | IOReport: no root but private; `powermetrics`: ❌ root | system | n/a |
| **Per-process GPU** | none public. Activity Monitor uses private `sysmond` XPC (`libsysmon.dylib`); `task_for_pid`-based Metal counters only work for your own process | ❌ | — | — |
| FPS / display activity | IOReport `DCP`/`swap` channels (Stats app) | none, private-ish IOReport API | system | low |

Fallback for spec: show **system-wide GPU %** (fully feasible), per-process GPU column must be **omitted** (or reduced to a "uses GPU" boolean if you adopt sysmond-style data later with a root helper). Metal's `MTLCounterSampling` only profiles your own device.

### 6. Process metadata

| Field | API | Root/entitlement | Notes |
|---|---|---|---|
| PID list | `proc_listpids(PROC_ALL_PIDS)` | none | one call; measured 950 pids |
| Name, uid/gid, ppid, start time, flags | `proc_pidinfo(PROC_PIDTBSDINFO)` → `proc_bsdinfo` (`pbi_name`, `pbi_uid`, `pbi_ppid`, `pbi_start_tvsec/usec`, `pbi_status`) | same-user only for full struct (EPERM otherwise, measured) | also embedded in `PROC_PIDTASKALLINFO.pbsd` |
| Executable path | `proc_pidpath(pid, buf, PROC_PIDPATHINFO_SIZE)` | **none — works for all processes incl. root daemons** (measured 936/940) | |
| Command line + env | `sysctl(KERN_PROCARGS2)` | same-user only (EPERM otherwise, measured) | |
| User name | `getpwuid(pbi_uid)->pw_name` | none | |
| Icon | `NSWorkspace.shared.icon(forFile: path)` (AppKit interop from SwiftUI) | none | cache it — do not call per 1s tick |
| Parent/child tree | `pbi_ppid` | none (from readable processes) | |

Elevation note: to see other users' processes' CPU/memory/args you need a root helper (SMAppService privileged helper + XPC is the modern pattern) or run the app as root. `task_for_pid` is hard-gated (measured `KERN_FAILURE` on pid 1; requires root or `com.apple.security.cs.debugger` entitlement + approval).

### 7. Sampling cost summary (measured on this Mac, ~950 processes)

| Pass | Work per 1s tick | Measured cost |
|---|---|---|
| Process table + CPU/RSS for same-user processes | 1 × `proc_listpids` + N × `proc_pidinfo(PROC_PIDTASKALLINFO)` | **1.6 ms for 950 processes** |
| Same + disk I/O | + N × `proc_pid_rusage` | a few ms |
| nettop per-process network | 1 process spawn + CSV parse | tens of ms |
| System CPU/VM/disk/GPU | ~5 calls total | < 1 ms |

Conclusion: 1s interval sampling of hundreds of processes is comfortably cheap (htop/Stats run at this cadence). Recommend sampling on a background queue at 1s, with icon/name resolution cached and only re-fetched on process-table changes.

### Recommended API stack for the spec

1. `proc_listpids` + `PROC_PIDTASKALLINFO` (CPU %, RSS, name, uid, ppid, start) + `proc_pid_rusage` (disk I/O) — same-user coverage, all in one ~2 ms pass.
2. `proc_pidpath` for paths (all processes), `getpwuid` for users, `NSWorkspace.icon(forFile:)` cached for icons.
3. `host_statistics` / `host_processor_info` / `host_statistics64` / `sysctl vm.swapusage` for system CPU + memory breakdown; `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` for pressure.
4. IOKit `IOBlockStorageDriver` Statistics for system disk; `getifaddrs` deltas for system network.
5. IORegistry `IOAccelerator` PerformanceStatistics for system GPU %.
6. `nettop` CSV shellout for per-process network.
7. Gracefully degrade (show "—" / "requires elevation") for root-owned processes' CPU/memory/args; per-process GPU is out of scope without a privileged helper.

### Citations

- Apple Developer Forums — per-process CPU, sysmond is private, `p_pctcpu` always 0: https://forums.developer.apple.com/forums/thread/655349
- Apple TN2434 — memory footprint definition: https://developer.apple.com/library/archive/technotes/tn2434/_index_.html
- libproc / proc_pidinfo headers: `<libproc.h>`, `<sys/proc_info.h>` (macOS SDK); open-source users: [htop darwin](https://github.com/htop-dev/htop/blob/main/darwin/DarwinProcessList.c), [osquery darwin processes](https://github.com/osquery/osquery/blob/main/osquery/tables/system/darwin/processes.cpp)
- Per-process disk I/O via `proc_pid_rusage`: https://stackoverflow.com/questions/15786618/per-process-disk-read-write-statistics-in-mac-os-x
- GPU utilization via IOAccelerator PerformanceStatistics (no root): [Stats GPU reader](https://github.com/exelban/stats/blob/master/Modules/GPU/reader.swift); ANE/power residency approach: [pumas](https://github.com/graelo/pumas)
- nettop JSON/CSV usage: `man nettop`; backed by private NetworkStatistics.framework (`otool -L /usr/bin/nettop`)
- powermetrics requires root: `man powermetrics` ("This tool requires root privileges")
- Empirical verification: test programs compiled and executed during this research on macOS 26 (uid 501): permission boundary 707/950 same-user processes; `proc_pidpath` 936/940 all-user; `task_for_pid(1)` → `KERN_FAILURE`; `nettop`, `ioreg` IOAccelerator + IOBlockStorageDriver all OK without root.
