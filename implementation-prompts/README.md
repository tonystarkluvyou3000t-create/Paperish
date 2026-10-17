# Pip the Pizza Boy — phased implementation prompts

Prepared from the project in `C:\My work folder\Paperish` on 18 October 2026. This pack is planning/documentation only: the audit did not implement game changes.

## Start here
1. Read [PROJECT_AUDIT.md](PROJECT_AUDIT.md) for actual source findings and their confidence.
2. Read [IMPLEMENTATION_RULES.md](IMPLEMENTATION_RULES.md) for the shared execution contract.
3. Give the implementation model one numbered phase at a time. Attach the rules and audit, or give the model filesystem access to them.
4. Before each phase, read the previous phase handoff. The repository will have changed; locate current equivalents rather than assuming audit line numbers are still valid.
5. Complete and verify each milestone inside a phase before continuing. A phase may take several model turns. Do not attempt all 24 phases in one context window.
6. Record work using [HANDOFF_TEMPLATE.md](HANDOFF_TEMPLATE.md). A suggested location is `implementation-prompts/handoffs/phase-NN.md`; do not mark planned features implemented.
7. Do not skip the final integration phases. A bigger town with unplayable orders or deadlocked traffic is not finished.

## Product direction
Keep Pip's warm voxel identity, pizza shop, and on-foot/van delivery loop. Turn the tiny diorama into a lively, explorable island with fair, readable delivery challenges and a short authored story. Prefer satisfying choices and reliable interactions over adding unrelated survival systems.

The target is a connected town approximately **320 × 240 metres**, at least **five distinct districts**, **40 deliverable addresses**, **12 authored recurring characters**, functional pedestrians and moving traffic, a complete day/night cycle, meaningful weather, proper counter pickup and cargo handling, and a **three-chapter campaign of roughly 45–75 minutes** plus endless/free-roam modes. These are proposed implementation targets, not measurements of existing features. Validate performance and tune times with playtests.

## Execution order
| Phase | Prompt | Outcome / dependencies |
| --- | --- | --- |
| 01 | [Fix core shift, pause, and vehicle bugs](phase-01-fix-core-shift-pause-and-vehicle-bugs.md) | Reliable existing loop; no dependencies |
| 02 | [Make regression checks deterministic](phase-02-build-deterministic-regression-checks.md) | Real assertions; requires 01 |
| 03 | [Separate gameplay services and data](phase-03-separate-gameplay-services-and-data.md) | Explicit ownership/contracts; requires 01–02 |
| 04 | [Add player-controlled cameras](phase-04-add-player-controlled-cameras.md) | Orbit, zoom, chase, free camera; requires 03 |
| 05 | [Build menus and settings](phase-05-build-menus-and-settings.md) | Navigable UI and persistent preferences; requires 03–04 |
| 06 | [Unify interactions and dialogue](phase-06-unify-interactions-and-dialogue.md) | One validated interaction pipeline; requires 03–05 |
| 07 | [Build the pizza shop handoff](phase-07-build-the-pizza-shop-handoff.md) | Enterable shop and staff/counter pickup; requires 06 |
| 08 | [Implement orders and physical cargo](phase-08-implement-orders-and-physical-cargo.md) | Tickets, van storage, customer handoff; requires 07 |
| 09 | [Author world and road graphs](phase-09-author-world-and-road-graphs.md) | Reproducible layout and traversal data; requires 03, 08 |
| 10 | [Expand the island and districts](phase-10-expand-the-island-and-districts.md) | Large connected town; requires 09 |
| 11 | [Build map and route guidance](phase-11-build-map-and-route-guidance.md) | Road-aware navigation; requires 10 |
| 12 | [Populate pedestrian life](phase-12-populate-pedestrian-life.md) | Walking people and routines; requires 06, 10–11 |
| 13 | [Add traffic and road rules](phase-13-add-traffic-and-road-rules.md) | Moving cars, signals, crossings; requires 12 |
| 14 | [Create day-night lighting and schedules](phase-14-create-day-night-lighting-and-schedules.md) | Clock, lighting, opening hours; requires 12–13 |
| 15 | [Add weather with gameplay effects](phase-15-add-weather-with-gameplay-effects.md) | Rain, fog, transitions and grip; requires 14 |
| 16 | [Improve driving and delivery condition](phase-16-improve-driving-and-delivery-condition.md) | Readable handling, wear and food quality; requires 15 |
| 17 | [Create fair delivery hurdles](phase-17-create-fair-delivery-hurdles.md) | Detours, access and encounter pacing; requires 11–16 |
| 18 | [Write and implement the island story](phase-18-write-and-implement-the-island-story.md) | Complete branching three-chapter arc; requires 06–17 |
| 19 | [Add progression and side activities](phase-19-add-progression-and-side-activities.md) | Rewards, upgrades, exploration; requires 18 |
| 20 | [Enrich world art and animation](phase-20-enrich-world-art-and-animation.md) | District identity and feedback; requires 10–19 |
| 21 | [Polish sound, onboarding, and accessibility](phase-21-polish-sound-onboarding-and-accessibility.md) | Learnable, readable, audible systems; requires 20 |
| 22 | [Persist campaign and resume safely](phase-22-persist-campaign-and-resume-safely.md) | Versioned saves and recovery; requires 18–21 |
| 23 | [Balance pacing and optimize performance](phase-23-balance-pacing-and-optimize-performance.md) | Tested fun and measured budgets; requires 22 |
| 24 | [Verify and package the complete game](phase-24-verify-and-package-the-complete-game.md) | Integrated release candidate; requires 23 |

## Milestone gates
- **Foundation:** 01–06. Existing deliveries still work; bugs have regressions; UI and input ownership are reliable.
- **Delivery vertical slice:** 07–08. A real counter pickup, cargo loading, parking and customer conversation work end to end.
- **Living town:** 09–15. Expanded world, routes, people, cars, time and weather operate together.
- **Game depth:** 16–19. Difficulty, campaign, upgrades and optional exploration form a playable game.
- **Finish:** 20–24. Visual/audio polish, accessibility, saves, tuning and release verification.

If a phase cannot pass its acceptance gate, fix it before moving on. Ask for clarification only for an actual blocking choice; routine implementation decisions are already delegated to the implementation model.
