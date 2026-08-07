# 09 — App identity

Type: grilling
Status: resolved
Parent: map.md

## Question

Graduated from the map's fog. Grill and lock the app's identity for the spec: display name (it must read as a Windows-style "Task Manager" while being a Mac app — keep the name, invent a new one?), bundle identifier, Xcode project/target naming, and icon direction (Fluent-ish gauge? Windows-taskbar homage? plain macOS style?). These strings land verbatim in the spec's build section and Info.plist prescriptions.

Invoke /grilling and /domain-modeling. Output: the exact name/bundle-id/icon-direction statements in the Answer section.

## Answer

Resolved 2026-08-08 via live grilling (1 round). Spec-ready identity:

1. **Display name**: `Task Manager` — used verbatim as the app name in Dock, window title bar, menu-bar accessibility label, and About panel. Deliberately identical to the Windows tool; no conflict with any macOS system utility (the native monitor is "Activity Monitor").
2. **Bundle identifiers**: app `com.brianwong.taskmanager`; privileged daemon `com.brianwong.taskmanager.daemon`. Both strings are the identities used in SMAppService registration, the daemon's launchd plist, and the XPC caller-validation requirement (ticket 05).
3. **Icon direction** (design brief, not pixel spec): macOS-native style — semi-transparent / layered material treatment with a gauge or performance-curve motif, consistent with Big Sur-era icon language. Explicitly NOT a Win11 blue-square homage; the Windows identity lives inside the window, not on the icon.
4. **Derived naming** (prescribed, no decision needed): Xcode project `TaskManager`; app target display name `Task Manager`; daemon launchd plist `com.brianwong.taskmanager.daemon.plist` under `Contents/Library/LaunchDaemons/`.
