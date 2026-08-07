# 07 — Spec assembly

Type: task
Status: resolved
Parent: map.md
Blocked by: 03, 04, 06, 08, 09, 10

## Question

Assemble the decision-complete implementation spec at `.scratch/win-task-manager/spec.md` (English), drawing from all resolved tickets (research facts + grilling decisions) and the map's Not-yet-specified patches that have since graduated. The spec must be complete enough that an implementation effort needs no further decisions: app identity, module layout, per-screen UI spec, data model, API selections with fallbacks, elevation design, milestones. Before assembly, graduate any remaining fog patches into tickets and resolve them.

## Answer

Resolved 2026-08-08. The last fog patch (**Testing strategy**) was resolved live at the head of this session: unit tests on pure logic only (aggregation / identity / rate deltas / ring buffers / heat tiers / nettop CSV parsing with fixtures) through the collector-protocol mock seam; no UI automation in v1; a 10-point manual acceptance checklist covers the untestable privileged/degradation paths.

Deliverable: **[spec.md](../spec.md)** — decision-complete, English, nine sections + source-ticket appendix: identity & build (incl. signing runbook), architecture & module layout, full per-screen UI spec, data model & sampling, verified API selection table, elevation architecture, honest platform-limit register, testing strategy + acceptance checklist, and six milestones (M0–M5). The map has no open tickets and no remaining fog; the destination is reached. Handoff: `/implement` against spec.md.
