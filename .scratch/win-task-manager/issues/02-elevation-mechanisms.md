# 02 — Elevation mechanism research

Type: research
Status: resolved
Parent: map.md

## Question

On modern macOS (macOS 26, unsigned/ad-hoc signed developer app), what are the viable mechanisms to obtain elevated privileges, and which fits a Task Manager that must (a) see all processes including other users', and (b) terminate them?

Cover:
1. `osascript ... with administrator privileges` — what it can and can't do per-operation; UX cost; sandbox interaction.
2. `SMJobBless` privileged helper — signing/notarization requirements, whether it works for ad-hoc signed local builds, IPC design cost.
3. `SMAppService` (daemon registration) — capabilities vs SMJobBless on macOS 13+.
4. `AuthorizationExecuteWithPrivileges` — deprecated; still functional? risks.
5. What specifically requires root on macOS: enumerating other users' processes (sysctl KERN_PROC — is it actually limited without root?), signaling them, reading their rusage/memory.
6. App Store / sandbox implications of each route.

Deliverable: answer section with a comparison table (mechanism, signing requirement, granularity of elevation, UX friction, maintenance risk) and a recommended candidate for the grilling ticket that follows.

## Answer

Research method: web research (Apple docs, Developer Forums, Quinn "The Eskimo" SMAppService write-up, community reports) **plus live empirical verification on a macOS 26.5.2 (Tahoe) machine with an unsigned/ad-hoc test binary**. Items marked [VERIFIED] were directly tested on macOS 26.5.2.

### 1. What ACTUALLY requires root on macOS 26 [all VERIFIED empirically]

| Operation | Root required? | Evidence |
|---|---|---|
| Enumerate ALL pids (`sysctl KERN_PROC_ALL` / `proc_listallpids`) | **NO** | Ad-hoc signed probe returned all 957 processes including 140 root-owned and 103 other-user processes, with full `kinfo_proc` fields (pid, uid, ppid, start time, `p_comm` name, rss, flags). macOS has NO Linux-style hidepid restriction. |
| Basic per-process info for other users' processes | **NO (partial)** | `kinfo_proc` from sysctl gives name/uid/ppid/rusage-adjacent fields for every process without root. |
| Detailed per-process info (`proc_pidinfo PROC_PIDTBSDINFO`, `PROC_TASKINFO`, memory/CPU details) for other users' processes | **YES** | `proc_pidinfo(1, PROC_PIDTBSDINFO)` returned 0 / EPERM unprivileged; same call on own pid succeeded. This is why `ps` is SUID root. |
| `kill()` on another user's process | **YES** | `kill(1, 0)` returned EPERM unprivileged. Standard POSIX credential check; even root cannot kill SIP-protected/platform processes (separate constraint, not relevant to user processes). |

How Activity Monitor does it without SUID (verified via `codesign -d --entitlements`): it holds private entitlements (`com.apple.sysmond.client`, `com.apple.activitymonitor-helper`) and talks XPC to the root daemon `sysmond`; for killing it uses `com.apple.private.AuthorizationServices` with the right `com.apple.activitymonitor.kill` (per-kill auth prompt). **These are private entitlements, unavailable to third-party/ad-hoc apps.**

### 2. Elevation mechanisms evaluated

**a) `osascript ... with administrator privileges` [VERIFIED working]**
- Ran `do shell script "/usr/bin/id" with administrator privileges` from an ad-hoc context → child ran as `uid=0(root)`. Works regardless of app signing.
- Granularity: per-invocation shell command as root. Credential for `system.privilege.admin` is cached by securityd for ~5 min in the same login session, so rapid successive kills don't re-prompt.
- UX cost: generic "osascript wants to make changes" dialog (app name not shown); one prompt per burst of operations.
- Sandbox: incompatible with App Sandbox (can't be done from an App Store build). Fine for our non-sandboxed local build.

**b) `SMJobBless` privileged helper**
- Deprecated (docs list 10.6–13.0, superseded by SMAppService).
- Signing: the helper's `SMPrivilegedExecutables` and app's `SMAuthorizedClients` are SecRequirement strings, conventionally `anchor apple generic and identifier ... and certificate leaf = H<cert-hash>` — these REQUIRE an Apple-issued Developer ID certificate. An ad-hoc signed app has no anchor and does not satisfy these requirements; SMJobBless installs to `/Library/PrivilegedHelperTools` and validates both directions. **Effectively unusable for an ad-hoc signed local build.**
- Also requires XPC IPC design (Mach service, connection validation). High implementation cost for a deprecated API.

**c) `SMAppService` daemon registration (macOS 13+, Apple's current recommendation)**
- Helper lives inside the app bundle (`Contents/Library/LaunchDaemons/*.plist`), registered via `SMAppService.daemon(plistName:).register()`; user approves via "Background Items Added" notification + Login Items toggle; daemon runs as root via launchd. Much simpler than SMJobBless (no SecRequirement plists, no manual install).
- Signing: registration is signature-gated. Multiple independent reports (incl. a macOS 26 agent project) confirm **ad-hoc signed apps cannot register — SMAppService needs a real Team ID / Developer ID signature**. Xcode's automatic development signing also works, but pure ad-hoc does not. [Reported, not locally re-verified to avoid mutating this machine's BTM state.]
- Maintenance caveats: register/unregister churn can corrupt BTM state (requires `sfltool resetbtm`); launch constraint violations on upgrade (Mozilla VPN case); daemon updates need unregister/register dance.

**d) `AuthorizationExecuteWithPrivileges` [VERIFIED still functional on macOS 26.5.2]**
- Deprecated since 10.7, but the live test executed `/usr/bin/id` and got `euid=0(root)` on macOS 26.5.2 (build 25F84). It still works today.
- Risks: could be removed/broken in any OS release with no notice; executes any path as root with NO signature verification of the target binary (a known LPE vector, Apple deprecated it for exactly this reason); preauth dialog per call; not App Store legal.

**e) App Store / sandbox implications**
- All four routes are incompatible with a sandboxed App Store app performing cross-user kills (osascript/AEWP blocked in sandbox; SMAppService daemons from sandboxed apps must themselves be sandboxed, which cannot kill other users' processes). Not a constraint for us: local, non-sandboxed, non-App Store build. Our app simply must NOT enable App Sandbox.

### 3. Comparison table

| Mechanism | Signing requirement | Elevation granularity | UX friction | Maintenance risk |
|---|---|---|---|---|
| `osascript` + admin privileges | None (works ad-hoc) | Per-operation shell command; ~5 min credential cache | High: password prompt per burst; generic dialog | Low: stable, non-deprecated, but Apple discourages; no sandbox compatibility |
| `SMJobBless` | Developer ID + SecRequirement plists (anchor apple generic) | Persistent root daemon, per-RPC operations | Medium: one install-time auth prompt | High: deprecated; complex XPC setup; dead-end API |
| `SMAppService` daemon | **Developer ID / Team ID required — fails ad-hoc** | Persistent root daemon, per-RPC operations | Low-medium: one "Background Items Added" approval | Medium: modern & supported, but BTM state churn, launch-constraint upgrade issues, signing dependency |
| `AuthorizationExecuteWithPrivileges` | None (works ad-hoc) | Per-execution of a helper binary | High: auth dialog per call | Very high: deprecated since 10.7, security hole, removal risk any release |

### 4. Recommendation

**Recommended candidate: `SMAppService`-registered root launchd daemon (XPC), with an `osascript` admin-privileges fallback path.**

Rationale:
- Enumeration does not need root (sysctl/libproc see everything, verified on macOS 26), so the daemon's job is narrow: (a) fetch `proc_pidinfo`-level details for cross-user processes, (b) execute `kill()`. Small, auditable XPC surface.
- SMAppService is Apple's current, supported mechanism; SMJobBless is deprecated and AEWP is a removal landmine.
- The one hard constraint: **ad-hoc signing cannot register an SMAppService daemon** — the build needs at least a Development/Team-ID signature (a free Apple ID gives development signing on the local machine; Developer ID if distributed). This must be a decision input to the grilling ticket.
- Fallback for a truly ad-hoc/no-team build: unprivileged enumeration + `osascript ... with administrator privileges` for kill and cross-user detail fetches (works today, verified), accepting per-operation prompts.

Open items for grilling: team-ID availability (free Apple ID vs paid Developer ID); whether a persistent daemon (login-item approval) is acceptable UX vs per-kill prompting; handling of SIP-protected processes (un-killable even as root — UI must surface this).
