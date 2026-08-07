# 05 — Elevation architecture decision

Type: grilling
Status: resolved
Parent: map.md
Blocked by: 02

## Question

Given the elevation mechanism research (ticket 02), grill and lock the app's elevation architecture for the spec:

1. Which mechanism to adopt (per-operation prompt vs privileged helper vs hybrid), and why — against the user's accepted trade-off (wants to see/kill other users' processes).
2. Elevation lifecycle: when elevation is requested (app launch? first elevated action?), how long the session lasts, how failure/cancellation degrades the UI.
3. Signing/distribution implications for a developer-built local app (ad-hoc signed): what the spec must prescribe so the app can actually run.
4. Security posture: least privilege scope of the elevated channel (only process enumeration + signals?), audit/logging requirements.

Invoke /grilling and /domain-modeling. Output: spec-ready architecture statements in the Answer section.

## Answer

Resolved 2026-08-08 via live grilling (2 rounds) on top of ticket 02's verified research. All decisions spec-ready.

### Mechanism & signing

1. **Mechanism**: SMAppService-registered root launchd daemon exposed over XPC. Rejected: SMJobBless (deprecated, Developer-ID-gated SecRequirement plists), AuthorizationExecuteWithPrivileges (deprecated since 10.7, removal landmine, no target-signature verification). osascript-per-prompt is recorded in the spec only as a documented alternative, not the default path.
2. **Signing route**: free Apple ID personal-team development signing now (sufficient for SMAppService registration, local use only); paid Developer ID is the later upgrade path — the architecture does not change, only the certificate. App is non-sandboxed and non-App Store.
3. **Signing reality (verified fact)**: personal-team signatures expire periodically (community-reported ~7 days). The spec must include a re-sign / re-register runbook, and the degradation design below must absorb signature expiry without app failure.

### Daemon scope (least privilege)

4. **Exactly three XPC methods, nothing else**: `processDetails(pid)` (cross-user `proc_pidinfo`-level detail), `terminate(pid, mode)` (SIGTERM/SIGKILL), `setStartupItem(label, enabled)` (system-scope `launchctl enable/disable`). No arbitrary shell/exec capability. Enumeration stays unprivileged (sysctl sees everything, ticket 02 verified).
5. **Caller validation**: the daemon accepts connections only from binaries carrying this app's Team-ID signature. **Audit log**: every privileged operation appends a local log line (timestamp, PID, operation, result).

### Lifecycle & degradation

6. **Registration**: guided on first launch — explain why a background service is needed, then trigger SMAppService registration and the system "Background Items Added" approval. If the user declines, the app continues degraded (item 7).
7. **Degraded mode** (daemon unregistered / disabled in Login Items / signature expired): the app still runs fully for what needs no root — complete process list with base fields (enumeration is unprivileged); cross-user detail, kill of other users' processes, and system-scope startup toggles are disabled with inline reasons; a dismissable status bar at the top of the window explains state and offers "Retry setup".

### Un-killable processes

8. **SIP / platform-protected processes** (kernel_task, launchd, etc.): shown normally in the list; End task / Force Quit are disabled for them with "Protected by the system"; a failed kill of any process surfaces an error dialog with the reason.

### Consequences for downstream tickets

- Data layer (ticket 06): collectors split into unprivileged (always on) and daemon-routed (cross-user detail/kill); degraded-mode data gaps feed the UI states defined here.
- Build section of the spec (ticket 07): Xcode automatic signing + personal Team ID, no sandbox, re-sign runbook.
