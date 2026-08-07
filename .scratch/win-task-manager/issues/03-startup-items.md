# 03 — Startup items management research

Type: research
Status: resolved
Parent: map.md

## Question

The spec needs a Startup apps tab that lists and toggles startup items like Windows 11 Task Manager. What can a third-party macOS app actually do?

Cover:
1. `SMAppService.mainApp/loginItem/daemon/userAgent` registration status query — can the app enumerate OTHER apps' `SMAppService` registrations (status only? `.enabled`?), or only its own?
2. Reading `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons` plists — enumerate, interpret `RunAtLoad`/`KeepAlive`, disable by moving/`launchctl disable` — what's possible without root, what needs elevation.
3. The legacy Login Items list (System Settings → General → Login Items) — is there a public API to enumerate/toggle it (sfltool? legacy LSSharedFileList is gone), and what does the user-facing fallback look like.
4. Per-item enable/disable semantics on macOS: `launchctl disable <target>` writes to a disabled.plist — scope, reversibility, root requirement.
5. Recommended scope for the spec: which columns/states are honestly implementable (name, path, status, user/system scope) vs which must be documented as unsupported.

Deliverable: answer section with capability matrix and a recommended Startup-tab capability statement for the spec.

## Answer

Researched 2026-08-08 against macOS 26.5.2 (build 25F84), the live local machine, Apple deployment docs (`depdca572563`), the `launchctl(1)` man page, and the `SMAppService` API docs. Context: ad-hoc signed, non-sandboxed local Swift 6.2 build.

### 1. SMAppService — can we enumerate OTHER apps' registrations?

**No.** `SMAppService` is scoped to *"helper executables that live inside an app's main bundle"* (Apple docs abstract). `mainApp`, `loginItem(_:)`, `agentService(_:)`, `daemonService(_:)` and `.status` only work for services registered **by the calling app itself**. There is no public API to list other apps' SMAppService registrations or their enabled/disabled state.

However, those registrations ARE visible indirectly: macOS 13+ funnels all SMAppService/launchd startup entries into **Background Task Management (BTM)**, and `/usr/bin/sfltool dumpbtm` prints them — verified live on this machine, **as a normal user (no sudo)**. Sample record fields:

```
Name: BlueStacks          Developer Name: ...
Type: app (0x2)           Type codes seen locally: agent (0x8), daemon (0x10),
                          login item (0x4), legacy agent (0x10008), legacy daemon (0x10010)
Disposition: [disabled, allowed, not notified] | [enabled, allowed, notified] | [enabled, disallowed, ...]
Identifier / URL / Bundle Identifier / Team Identifier / Executable Path
```

This is the only sanctioned programmatic view of the System Settings → Login Items list. Caveats: output is an unstructured text dump (must be parsed defensively, format is undocumented and may change), and the BTM backing store (`/var/db/com.apple.backgroundtaskmanagement/`) itself returns `Operation not permitted` even to a root shell without Full Disk Access — so **parse `sfltool dumpbtm` output, never read the store directly**.

### 2. LaunchAgents / LaunchDaemons plists

Verified locally:

- `~/Library/LaunchAgents` (13 plists, user-owned), `/Library/LaunchAgents` (5, root:wheel), `/Library/LaunchDaemons` (12, root:wheel) — **all world-readable** (`-rw-r--r--`). No root and no TCC/FDA needed to *read*.
- Plists are XML or binary; parseable with `PropertyListSerialization`. Meaningful keys: `Label`, `ProgramArguments`/`Program`, `RunAtLoad`, `KeepAlive`, `StartInterval`, `Disabled`.
- Writing/deleting/moving plists in `/Library/*` requires root; `~/Library/LaunchAgents` is user-writable (but deleting other apps' files is a destructive act — out of scope for a task manager).

### 3. Toggling: `launchctl enable/disable`

Per `launchctl(1)`: `disable <domain-target/service-name>` marks a service disabled **persistently across boots**; `enable` reverses it. Only `system`, `user` and `user-login` domains may be targeted.

- **User-domain items** (`~/Library/LaunchAgents` → `user/<uid>/<label>` or `gui/<uid>/<label>`): **no root needed**. launchd mediates the write; state lands in `/var/db/com.apple.xpc.launchd/disabled.<uid>.plist` (verified present, root-owned but written by launchd on the user's behalf).
- **System-domain items** (`/Library/LaunchDaemons` → `system/<label>`, and `/Library/LaunchAgents` at boot): **root required**. In-app elevation options: a privileged helper registered via `SMAppService.daemonService` (the modern sanctioned path) or shelling out with an admin prompt (e.g. `osascript ... with administrator privileges`).
- Semantics: `disable` only sets the flag — it does **not** kill a running instance (pair with `bootout`), and apps can re-enable their own items on update. `/System/Library/*` services are SIP-protected: cannot be disabled. `launchctl print-disabled user/<uid>` / `system` (verified: readable without root) shows the current flag map.
- **Critical limitation**: `launchctl disable` does **not** govern BTM-managed items (modern SMAppService login items / "Allow in the background" toggles). Their state lives in BTM `Disposition`, and there is **no public API or CLI to toggle a single item** — `sfltool resetbtm` wipes *all* BTM data (destructive, testing-only). Per-item control is only available via System Settings UI, or MDM/declarative BTM profiles in managed environments.

### 4. System Settings → Login Items: public API?

**None.** `LSSharedFileList` is dead (deprecated 10.11, symbols removed). There is no public Swift API to enumerate or toggle the user "Open at Login" list or the "Allow in the Background" list on macOS 13–26. Honest fallbacks:

1. Show items parsed from `sfltool dumpbtm` (read-only, works unprivileged).
2. Deep-link the user into System Settings: `open "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"`.
3. Our *own* app's login item: fully supported via `SMAppService.mainApp.register()/unregister()/status` (status reflects user toggles in System Settings, e.g. `.notFound` after the user removes it).

### Capability matrix

| Capability | Feasibility | Mechanism | Privilege |
|---|---|---|---|
| List user LaunchAgents (`~/Library/LaunchAgents`) | ✅ full | directory read + plist parse | none |
| List system LaunchAgents / LaunchDaemons | ✅ full | directory read + plist parse | none (read-only) |
| Interpret `RunAtLoad`/`KeepAlive`/`Label`/program | ✅ full | `PropertyListSerialization` | none |
| Show enabled/disabled flag per launchd service | ✅ full | `launchctl print-disabled` | none |
| Show BTM/Login-Items entries (incl. other apps' SMAppService registrations) with enabled/disallowed state | ✅ via tool | parse `sfltool dumpbtm` | none |
| Toggle user-domain launchd agents | ✅ full | `launchctl enable/disable user/<uid>/<label>` | none |
| Toggle `/Library/LaunchDaemons` + system agents | ⚠️ elevated | `launchctl enable/disable system/<label>` via privileged helper / admin prompt | root |
| Show running/not-running state | ✅ full | `launchctl print` / process list cross-reference | none |
| Toggle BTM-managed items ("Allow in the Background", other apps' login items) | ❌ not possible | no public API; MDM-only; user must use System Settings | — |
| Enumerate other apps' SMAppService registrations via API | ❌ not possible | only visible inside BTM dump | — |
| Disable `/System/Library/*` services | ❌ not possible | SIP | — |
| Own app launch-at-login | ✅ full | `SMAppService.mainApp` | none |

### Recommended Startup-tab capability statement (for the spec)

> The Startup tab lists launch-time items from three read-only sources: (a) launchd plists in `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`; (b) the BTM registry via `sfltool dumpbtm` (captures SMAppService login items and "Allow in Background" entries that have no plist of their own); (c) the `launchctl print-disabled` flag map. Columns: Name/Label, Type (login item / user agent / system agent / daemon), Scope (user/system), Path, State (enabled / disabled / blocked-by-BTM), Running (if resolvable).
>
> Enable/disable is offered only for launchd-managed items: user-scope toggles run unprivileged via `launchctl enable/disable user/<uid>/…`; system-scope toggles request admin authorization via a privileged helper. Toggled state is persistent and reversible; it does not kill running processes (documented; optional `bootout` follow-up).
>
> BTM-managed items (System Settings → Login Items) are shown with their true enabled/disallowed state but are **not toggleable from this app** — the row's action opens System Settings at the Login Items pane instead. `/System/Library` items are listed as read-only. This is the honest macOS equivalent of Windows 11's Startup apps tab: full visibility, partial control.

### Implementation notes for the spec author

- Ad-hoc signing is fine: all of the above is `Process`-shelling to system tools plus plist file reads; nothing requires an entitlement or Developer ID. (Would break only if the app were sandboxed/App Store — it isn't.)
- Parse `sfltool dumpbtm` output defensively (undocumented format; observed fields: UUID, Name, Developer Name, Type, Flags, Disposition, Identifier, URL, Bundle Identifier, Team Identifier, Executable Path).
- Prefer `launchctl disable` over moving/deleting plists: flag-based, reversible, survives app updates; file deletion is destructive and leaves BTM "orphan" entries.
- Evidence trail: local verification performed 2026-08-08 on macOS 26.5.2 (no state modified; read-only commands only).
