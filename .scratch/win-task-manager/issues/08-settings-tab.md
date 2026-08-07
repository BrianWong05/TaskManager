# 08 — Settings tab options

Type: grilling
Status: resolved
Parent: map.md

## Question

Graduated from the map's fog now that ticket 04 locked the UI structure. Grill and lock the Settings tab: the exact list of options, their controls and defaults, so the spec can enumerate them without ambiguity.

Candidate surface (from the ticket 04 prototype): Theme (System/Light/Dark vs follow-system-only), refresh rate preference, start at login, show menu-bar monitor, launch minimized. Decide each: keep/drop, control type, default value — and whether sampling cadence is user-configurable at all given the self-impact budget (ticket 06 will set the budget; this ticket decides whether the user gets a knob).

Invoke /grilling and /domain-modeling. Output: spec-ready options table in the Answer section.

## Answer

Resolved 2026-08-08 via live grilling (2 rounds). Spec-ready options table:

| Option | Control | Default | Notes |
|---|---|---|---|
| Theme | Picker: System / Light / Dark | System | **Overrides ticket 04's follow-system-only**: System tracks macOS appearance; Light/Dark force the app independently. |
| Start at login | Toggle | Off | Implemented with `SMAppService.mainApp` login item (works under ticket 05's signing route); independent of daemon registration. |
| Show menu-bar monitor | Toggle | On | Off hides the CPU% status item and its panel entirely; main window unaffected; system-level sampling continues at low cadence to serve the main window (ticket 06 pause policy). |

Additional locked decisions:

1. **Launch behavior — no "Launch minimized" setting**: behavior derives from launch source. Login-item launches stay background-only (menu-bar presence, no window); manual launches open the main window. Zero configuration.
2. **No refresh-rate knob**: the 1s master tick and automatic 2s halving (ticket 06 budget) are internal behavior; the spec states explicitly that refresh rate is not user-configurable.
3. **Background service status row** at the top of Settings: read-only state of the daemon — Registered / Not registered / Signature expired — with "Retry setup" and "Open Login Items" buttons. This is the stable re-entry point for the ticket 05 setup flow after its dismissable status bar has been dismissed (relevant because personal-team signatures expire periodically).

Settings tab therefore has exactly: the status row + three options above. No other settings in v1.
