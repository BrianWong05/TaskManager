# Task Manager

A macOS task manager modeled on the Windows 11 Task Manager: monitors processes and system resources and lets the user terminate processes, from a main window and a menu-bar presence.

## Language

**App Group**:
The Processes-tab aggregate of all processes belonging to one application (keyed by bundle id), rendered as a single expandable row.
_Avoid_: app bundle row, grouped process

**Process**:
A single OS process; inside an App Group it is a child process.
_Avoid_: task, instance

**End task**:
The graceful termination action (SIGTERM), never confirmed.
_Avoid_: quit, terminate

**Force Quit**:
The hard-kill action (SIGKILL), always confirmed.
_Avoid_: kill, force end

**Startup item**:
An entry in the Startup apps tab — a launchd agent/daemon or login item that launches at login/boot.
_Avoid_: login item (means only the BTM-managed subset), autostart entry

**Mini monitor**:
The menu-bar presence: a live CPU-percentage icon plus its popover panel of sparklines and top processes.
_Avoid_: tray icon, widget

**Elevation**:
The act of obtaining root privileges for operations unavailable to the app otherwise (cross-user process detail, killing other users' processes, system-scope startup toggles).
_Avoid_: sudo, admin mode

**Heat coloring**:
The three-tier background tint applied to the CPU and Memory columns by usage.
_Avoid_: color coding, highlighting

**CPU graph mode**:
The CPU pane's chart selection — Overall utilization (one whole-CPU chart) or Logical processors (a per-core grid) — chosen by a segmented control and remembered across launches.
_Avoid_: per-core toggle, core view, graph type

**In use**:
The share of physical memory that cannot be reclaimed without swapping — App memory, Wired memory and Compressed together. The headline value of the Performance memory pane.
_Avoid_: memory used, used memory, active memory

**Memory composition**:
The three parts In use divides into: App memory (allocated by running applications), Wired memory (kernel-owned pages that can never be swapped), and Compressed (pages the kernel has compressed in place rather than swapped).
_Avoid_: memory breakdown, memory detail

**Cached files**:
File-backed and purgeable pages the kernel holds speculatively — a subset of Available, reclaimed on demand without swapping.
_Avoid_: cache, buffers, inactive memory

**Available**:
Physical memory that is not In use — everything the system can still hand to a new allocation, Cached files included.
_Avoid_: free memory, unused memory
