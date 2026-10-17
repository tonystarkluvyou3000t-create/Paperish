# Shared execution contract for every phase

You are the implementation model working on **Pip the Pizza Boy**, an existing Godot 4 project. Implement the supplied numbered phase; do not merely describe a plan. The pack's author audited the repository and deliberately left implementation to you.

## Scope and workflow
- Start with the phase's prerequisites and latest handoff. Inspect current files and `git status --short`. Preserve unrelated user work; never reset or clean the checkout.
- Read local AGENTS.md instructions, including `C:\Users\Zaida\.codex\RTK.md` where applicable. Address the user naturally as bro. Do not call yourself done while a required part of the phase is missing.
- One phase per assignment. Follow its milestones in order. Finish a small working slice, check it, then extend it. A reduced context window is a reason to write a handoff, not a reason to silently cut scope.
- Use existing Godot/GDScript and Python generation. No engine replacement, npm frontend, external service, paid assets, or plugin installation is needed.
- Keep the charming cream/teal/red/gold voxel style. Use original procedural assets or clearly licensed assets with attribution.
- Proposed new paths and types in these prompts are design guidance, not claims that files already exist. Inspect before creating. Prefer small focused services to speculative frameworks.
- Do not duplicate state in HUD, player and game. One authoritative owner per subsystem; UI observes it. Use typed signals and stable IDs across subsystem boundaries.
- Avoid magic numbers scattered through scripts. Put meaningful balance values in named configuration data.
- Determinism means fixed seed and event order for a scenario, not a claim of cross-platform bit-identical physics.

## Existing project contracts
Read `README.md`, `scripts/game.gd`, `scripts/player.gd`, `scripts/vehicle.gd`, `scripts/camera_rig.gd`, `scripts/hud.gd`, `scenes/game.tscn`, `tools/build_art.py`, `tools/build_town.py`, `tools/townkit.py`, and `tools/capture.gd` as relevant.

- `project.godot` launches `scenes/game.tscn`.
- The initial game discovers customers as direct Node3D children of `Town/Houses`, then looks up `Door` and `Park`. House metadata includes `address`, `label`, `number`, and `north`.
- Pickup initially lives at `Town/PizzaShop/PickupPoint`. Spawn markers are `Town/PlayerSpawn` and `Town/VanSpawn`, with yaw metadata.
- Pip's named limb pivots live under `Visual`. Vehicle wheels have names beginning `octagonal_tyre`, `wheel_hub`, and `hub_center`. Preserve or intentionally migrate these contracts and their consumers together.
- World forward for the existing van is local **+Z**. Godot cameras look along **-Z**. Do not introduce a 180-degree convention error when adding traffic.
- Python generators are the source of truth for generated art/world scenes. A runtime overlay can add behavior; permanent geometry changes must survive regeneration. Do not hand-edit generated files as the only source change.
- `tools/setup_project.gd` rewrites input and window defaults. New bindings/defaults must survive running it. User remaps must be loaded after project defaults.
- `tools/build_art.py` also rewrites the standalone `scenes/pizza_corner.tscn` presentation scene. Preserve it or deliberately update its role.
- Existing collision defaults: environment layer 1, player layer 2, van layer 4; player mask 5, van mask 1. These are bit masks, not ordinal layer numbers. Write a collision matrix before introducing NPC/traffic layers.
- `tools/capture.gd` is a developer autoload with teleport/autopilot/time-scale commands. Keep it inert without an explicit developer invocation, and exclude or gate it for release.

## Cross-phase ownership (establish in 03, evolve minimally)
- Session/flow service: title, playing, modal dialogue, paused, shift result, loading; explicit transition and input ownership.
- Order service: order ID, destination ID, preparation state, deadlines, settlement and failure; emits immutable event payloads.
- Cargo service: each package's ID/order ID, location, quality; one location at a time (counter/player/van/customer/discarded).
- World registry: district/address/POI IDs and marker lookup, no hard-coded eight-house indexing.
- Road service: directed lanes, pedestrian links, junction controls, traversability changes and route cost queries.
- Time service: simulation clock and day index; active delivery time is separate from save timestamps and UI animation time.
- Weather service: current/blended weather and gameplay modifiers; lighting composes time + weather rather than competing writes.
- Story service: flags, chapter, objective graph, dialogue conditions and one-time rewards.
- Progress service: money ledger, unlocks, upgrades and reputation; order settlement credits it once.
- Save service: versioned data snapshots using stable IDs; no serialized live Node pointers.
- UI/input coordinator: modal focus, mouse capture and action consumption; no gameplay leaking through menus.
Use Node/Resource classes or similarly simple Godot-native structures; exact class names are your choice. Document APIs as they become real.

## Timing and fairness rules
- Title, pause, settings, map, dialogue, shop ticket selection and free camera freeze gameplay clocks/AI by default. UI remains responsive. Use centralized pause reasons so closing one overlay cannot unpause another. Traffic and deadline time must freeze together.
- Preparation and queue delays are part of world fiction, but the customer's hot-food deadline begins on validated staff-to-player handoff. Route estimates must include safe travel, parking and final walk.
- Player-selected rush jobs may have tighter windows; normal jobs cannot become impossible because a mandatory scene or scripted road closure consumes their clock.
- Rejected interactions never advance an order or remove cargo. Every success/timeout/cancel/reward is idempotent.
- Difficulty should be telegraphed and recoverable. No unavoidable spawn-on-player obstacles, random instant losses, unavoidable pedestrian harm, or punishment with no explanation.
- Use separate random streams for orders, traffic, weather and decoration so changing tree placement does not change a regression's destination.

## Validation
Current engine: `.\godot-engine\Godot_v4.7.2-stable_win64_console.exe`. Verify local availability; do not claim an engine version from online assumptions.
```powershell
& '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe' --headless --audio-driver Dummy --path . --quit-after 180
& '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe' --headless --audio-driver Dummy --path . --script tools/check_town.gd
& '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe' --headless --audio-driver Dummy --path . --script tools/validate_art.gd
```
These baseline checks do not establish gameplay correctness. Extend them with meaningful regressions for behavior you change. Scan stdout/stderr as well as exit status. Existing check_town can falsely return zero on a bad load until phase 02 fixes it.

Use rendered captures for camera/UI/art. Headless screenshots cannot validate presentation. Do not use teleport/autopilot scenarios as proof of ordinary player navigation. Keep historical screenshots; write new evidence under a distinct run directory. Record exact commands, seeds, outcomes and untested limits. If unavailable, state a test was not run.

Use an isolated copy or explicit staging output to verify generators; do not overwrite user changes casually. Keep generated files synchronized with their source where the phase changes them. Do not add implementation-shaped tests for trivial edits; prioritize state invariants, real regressions and end-to-end behavior.

## Required handoff
Use HANDOFF_TEMPLATE.md. Include changed files, implemented APIs/schema, run commands and outcomes, outstanding defects, new controls, regeneration instructions, and the next phase's integration points. Never describe a stub, disabled feature, or unexecuted test as complete.
