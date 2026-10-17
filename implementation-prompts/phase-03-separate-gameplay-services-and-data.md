# Phase 03 — Separate gameplay services and data
Read shared rules and handoffs 01–02. This is a behavior-preserving refactor, not permission to build future features prematurely.

## Result
Future orders, NPCs, weather and story can integrate through explicit services instead of making game.gd a giant mutable controller. Existing deliveries and regression commands remain functional.

## Inspect
game.gd currently owns shift, order, interaction, cash, audio and vehicle switching; hud.gd reads its fields every frame. Locate the test harness's direct private-method dependencies before moving anything.

## Milestone A — Define ownership
Write a short architecture document listing real owners for session flow, orders, interaction, cargo, world references, camera and presentation. Implement only the pieces needed by the current game; reserve names/data boundaries for later systems without creating empty managers. Prefer focused Node/Resource classes and exported references.

Define session states separately from order lifecycle and actor mode. TITLE/PAUSED/RESULT are not order destinations. Use a central modal/pause reason stack or set so dialogue and settings can coexist without one close action resuming the world underneath the other.

Introduce a typed read-only diagnostic snapshot for tests/HUD. State updates go through service methods; HUD cannot award money, mutate order fields or start a shift by changing variables.

## Milestone B — Extract incrementally
1. Move order selection, deadlines and settlement into an order owner; preserve existing $150/three-strike behavior for now.
2. Move actor switching and movement ownership into one controller.
3. Route sound/toast/marker updates through explicit events or small adapters. State events should include IDs and outcomes, not require consumers to inspect a half-updated object.
4. Give destinations stable string IDs independent of scene child ordering. Validate uniqueness. Keep legacy capture index lookup as a documented compatibility adapter until scenarios migrate.
5. Extract balance constants into named data: ranges, deadline floors, goal, movement thresholds and pay. Avoid a generic string-keyed global event bus.
6. Update HUD and capture harness after each extraction and run the fast suite before extracting the next concern.
7. Define transaction boundaries: a completed order emits one settlement event; a timeout cannot also settle it. Clear pending work when session generation changes.

## Milestone C — Data and migration notes
Publish actual signal/method signatures and owners in a small architecture document. List immutable configuration versus mutable run state and stable identifiers that later saves will use. Keep service lifetime/reset rules explicit across scene reloads. Do not serialize anything yet.

## Acceptance
Old playable loop behaves the same except phase 01 fixes. Core suite passes without private field writes except isolated test adapters. Repeated scene reload/start/result does not duplicate signal connections. HUD, markers and summary all report the same authoritative order. Opening two nested modals and closing one leaves the other paused. No empty service masquerades as an implemented feature.

Handoff must include a dependency diagram or concise ownership table, actual file/API names, stable destination ID format and test migration notes for phase 04 onward.
