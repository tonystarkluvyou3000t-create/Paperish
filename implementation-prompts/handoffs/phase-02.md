# Phase 02 — Deterministic regression checks
Status: VERIFIED

## Implemented behavior

Developer plans are validated before execution. Assertions, bounded conditional
waits, missing/malformed plans, unknown actions/steps/fields/types and invalid
destinations fail nonzero with a diagnostic and current step. Screenshots are
awaited or explicitly skipped in headless mode. Every invocation has a fresh
result/image directory. Both success and failure release held controls, reset
pause/time scale, cancel hooks, free the scene and allow audio cleanup.

Order generation uses its own RandomNumberGenerator. Plan seed / explicit
`--scenario-seed=N` sets it before the first order. Restart restores a configured
seed. The next forced destination is injected before ticket creation, including
repeated destinations. Session-local order IDs increment on each new ticket.

The new one/two-delivery plans exercise actual E input and legal van transitions,
assert cargo/payment/next-order state, retry settlement to prove idempotence,
and use waits instead of timing-dependent interactions. They use teleport setup,
so do not establish navigation or human driving. Existing historical shots and
visual-only plans remain intact.

Town validation now fails on missing/non-PackedScene resources, wrong roots,
missing world nodes/spawns/pickup, bad metadata/duplicate identities and missing
Door/Park markers. Negative fixtures stay outside normal resources.

## Files and ownership

- `scripts/game.gd`: isolated order RNG, seed API, ticket sequence and primitive
  diagnostic snapshot. Existing state owner is unchanged until Phase 03.
- `tools/capture.gd`: explicit developer scenario execution, schema validation,
  assertions/waits/snapshots, keyboard events, screenshots, reports and teardown.
- `tools/plans/core.json`, `playfast.json`, `playtest.json`: condition-based plans.
- `tools/check_town.gd`: resource/metadata/world contract validation.
- `tools/check_order_rng.gd`: seeded sequence unaffected by unrelated global draws.
- `tools/run_checks.py`: standard-library subprocess suite; scans stdout/stderr,
  verifies fresh reports/cleanup, repeats logical traces and tests negative cases.
- `tools/SCENARIOS.md`, README, `.gitignore`: workflow/schema, ignored unique shots.
- Phase 01's uncommitted work is preserved. No generated art/audio or historic
  screenshots changed. No external test framework/package was introduced.

## Contracts for the next phase

`Game.set_order_seed(value: int) -> void` configures the order RNG. Restart resets
the configured sequence and `active_order_id`; ordinary launch randomizes it.
`Game.get_diagnostics() -> Dictionary` returns fresh primitive data. Stable
`destination_id` is currently the unique address string, independent of child
ordering; scenario `order.index` remains a legacy registry-index adapter.

Diagnostic fields: mode, order_id, destination_id, cargo_count, order_pizzas,
deliveries, money, strikes, driving, paused, timer, timer_max, tip, pip_control,
van_control, van_stopped, speed, pip_autopilot, van_autopilot, pickup_distance,
door_distance, park_distance, pip_x/z, van_x/z, pip_motion, van_motion,
pip_visible, pip_collision, world_ready. Mode is title/to_shop/to_house/complete/failed.

Full plan schema is in `tools/SCENARIOS.md`: ordered steps; optional monotonic
legacy `at`; scalar equality or eq/ne/lt/lte/gt/gte comparison conditions; prior
remembered diagnostic references. Waits have wall-clock timeouts, including while
paused. Allowed commands are enumerated; JSON cannot execute arbitrary code.

Capture remains inert without `--capture-plan`. Developer expire/retry_delivery/
finish/place are explicit test adapters, not normal gameplay. Phase 01 fixtures
also intentionally use direct state injection. Phase 03 should consolidate these
adapters when extracting services. The normal HUD still reads Game fields;
a typed read-only snapshot and explicit service ownership are Phase 03 work.

Result JSON contains effective seed, success, failure step/message, assertion
count, logical records, image paths and cleanup state. `CAPTURE_RESULT` identifies
the exact file. Logical comparisons exclude floating clocks and physics positions.
Do not claim cross-platform bit-identical physics.

## Validation evidence

Engine: Linux x86_64 Godot 4.6.3.stable.official.7d41c59c4, Python 3.12.14.
Commands from `/workspace/Paperish`, after sourcing the environment activation:

```sh
source /workspace/.paperish-env/activate.sh
python3 tools/run_checks.py --output /workspace/.paperish-env/phase02-suite
```

The final suite ran twice with seed **20261018**, each with **27 successful
command checks**. Each suite separately replays core, playfast and playtest twice
and compares their logical results. Core fixture suite: 137 assertions, zero
failures (five expected world-contract diagnostics). RNG isolation: twelve-ticket
sequence matches despite global random draws. Standard startup, town and ten-file
art checks pass. No unexpected engine/script errors or leaked resources remain.
One-delivery: 9 assertions, one payout of $22, cargo 0, next order ID 2/destination
4 Marinara Way. Two deliveries: 17 assertions, $44, cargo 0, next ID 3/destination
6 Marinara Way. Both have zero strikes. Ordinary launch without developer args
passes the standard 180-frame check.

Negative cases: inverted assertion, unknown action, unknown step, wrong type,
missing key, unknown diagnostic, never-satisfied wait, failure while paused with
held movement/time scale 2, out-of-range destination, malformed JSON, missing
plan, missing resource, non-PackedScene resource, broken town, duplicate address,
missing Door. Each exits nonzero, names its error, and applicable scenario reports
confirm cleanup. A failed test is never counted as passing gameplay.

Evidence:
- `/workspace/.paperish-env/logs/phase02-suite-final1.log`
- `/workspace/.paperish-env/logs/phase02-suite-final2.log`
- Both logs identify unique suite directories containing command logs, fixture
  inputs, reports and summary.json. Earlier failed diagnostic runs are retained.

Rendered acceptance also executed:

```sh
DISPLAY=:91 LIBGL_ALWAYS_SOFTWARE=1 godot --audio-driver Dummy --rendering-method gl_compatibility --path . -- --capture-plan=res://tools/plans/playfast.json --capture-output=/workspace/.paperish-env/phase02-rendered
```

An existing Xorg dummy driver provides display :91 (configuration at
`/workspace/.paperish-env/xorg-dummy.conf`, startup log `phase02-xorg.log`). No
package installation, network change or unverified download was needed. Godot
used Mesa llvmpipe. One V-Sync capability warning is expected on this driver;
no rendering/script error occurred. The smoke passed 9 assertions and wrote two
1280x720 PNGs, independently decoded and checked as nonempty images. The paid
image was visually inspected: $22 and DELIVERIES 1 match authoritative state.

Rendered report/images:
`/workspace/.paperish-env/phase02-rendered/playfast-3290-12814641/`.
Rendered log: `/workspace/.paperish-env/logs/phase02-rendered.log`.

`git diff --check` passes. No authoring generators changed in this phase, so
regenerating world geometry was unnecessary.

## Known defects / incomplete acceptance items

No required Phase 02 acceptance items remain. Manual driving, route reachability,
full-shift play and audible output are not validated by these teleport scenarios.
Legacy views/vanprobe plans remain useful captures/diagnostics, not correctness
tests. The next phase must preserve the scenario diagnostic/schema contract or
migrate every consumer together. The Windows 4.7.2 engine remains untested.

## Player controls and documentation

No player controls changed in Phase 02. Developer schema and commands are fully
documented in `tools/SCENARIOS.md`. Evidence is unique and historical shots are
preserved. Negative fixtures live only under the current suite evidence directory.

## Next phase entry point

Read Phase 03 and this handoff, then inspect Game, HUD, SessionInput, Capture,
phase01_checks and check_order_rng. Extract services incrementally and rerun
`python3 tools/run_checks.py` after each concern. Keep legacy fixture adapters
explicit while moving HUD/tests onto a typed read-only snapshot. Do not create
empty future managers or implement weather/story during the refactor.
