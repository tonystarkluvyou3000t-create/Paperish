# Phase 23 — Balance pacing and optimize performance
Read rules and 22 handoff. All systems now exist; measure their combined behavior and fix the actual bottlenecks/pacing problems.

## Result
The island is fun to traverse, normal orders are achievable, harder choices reward skill, and busy/night/rain scenes run within measured budgets on the available machine.

## Milestone A — Evidence and balance
Add opt-in local debug telemetry for route estimate vs actual time, accepted/settled/expired orders, food quality causes, collision incidents, money flow, event overlaps, NPC/traffic counts and frame/physics cost. No external analytics service or private-data collection.

Use a fixed scenario matrix covering each district, short/long/batch routes, day/night, clear/rain/fog and three difficulty presets. Compare cautious safe driving, competent shortcuts and reckless play. Adjust route budgets using measured parking, cargo and conversation costs. Normal mandatory jobs must be achievable without speeding through pedestrians. Tips should reward improvement without making late-but-successful jobs worthless.

Play campaign chapter progression: tune early teaching, repetition, upgrade affordability, mission retry and finale. Use optional rush work to supply high difficulty. Avoid reducing difficulty solely by making everything slow/empty. Record actual campaign duration and missed target reasons.

## Milestone B — Performance
Profile renderer and physics on real rendered gameplay, not headless FPS. Capture at least median and high-percentile frame times for a repeatable busy market/rain/night route; name hardware/resolution/quality. Proposed target: near 60 FPS at 1280×720 on the available machine if feasible; do not claim broad hardware support from one test.

Find hot spots: generated MeshInstance counts, shadows/lights, particles, navigation requests, traffic sensing, per-frame allocations and UI rebuilding. Apply targeted fixes such as batching static detail, staggered AI, cached route queries, capped particles and light visibility. Preserve collision/navigation correctness and authored character identity.

Implement quality/density presets that actually change costly systems. Keep essential road/address readability. No pop-in spawns close to player to gain performance.

## Milestone C — Soak and fairness
Run a 20–30 minute seeded simulation or equivalent accelerated logic soak plus a real-time rendered session. Check memory/node counts, queues, pending dialogue, stale registry IDs, duplicate listeners and accumulated event effects. Repeated pause/free-camera/weather cycles must not compound modifiers. Ensure recovery does not bypass story locks.

## Acceptance
Document before/after frame metrics, settings and route. Normal district jobs pass under fair cautious play; challenging presets produce explainable losses. No traffic deadlock, impossible active order or unbounded population growth during soak. Full core/order/story/save suites pass after optimization. Update tuning data and document why each meaningful value changed.

Handoff: balance tables, scenario matrix/results, actual performance profile, unresolved hardware limits and final QA priorities. Avoid vague claims such as optimized or balanced without measurements.
