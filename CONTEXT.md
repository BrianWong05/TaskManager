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
