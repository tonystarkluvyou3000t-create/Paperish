# Developer scenarios and regression checks

Run from the repository root with a Godot 4 executable on PATH. This cloud
instance uses Godot 4.6.3; source `/workspace/.paperish-env/activate.sh` here to
place writable Godot state outside the checkout. No external test framework or
Python package is required.

```sh
# Fast headless suite: engine/resource/physics checks, repeated seeded scenarios,
# negative fixtures, exit-status/stderr/report/cleanup checks.
python3 tools/run_checks.py

# Rendered one-delivery smoke on a desktop/X display; screenshots are required.
godot --audio-driver Dummy --path . -- --capture-plan=res://tools/plans/playfast.json

# A single headless two-delivery scenario, overriding the seed and output base.
godot --headless --audio-driver Dummy --path . -- --capture-plan=res://tools/plans/playtest.json --scenario-seed=20261018 --capture-output=/tmp/paperish-evidence
```

`run_checks.py` accepts `--godot`, `--seed` and `--output`. It preserves engine
exit codes, captures stdout/stderr, rejects script/engine errors even if Godot
exits zero, verifies fresh result files and compares logical replay records.
Phase 01's five deliberate world-contract error diagnostics are counted and
allowed only for that negative fixture suite. Outer subprocess timeouts are
failures, not skipped checks. The standalone runner also has a wall-clock budget.

A capture is not a correctness assertion: `views.json` remains visual-only.
`playfast.json` asserts one delivery, cargo removal, no strikes, a single payout
and next-ticket creation; `playtest.json` checks two transitions. `core.json`
checks pause, ownership, repeated forced destination, result and restart.
`camera.json` checks on-foot orbit, chase zoom travel and the free camera
freezing deadlines and the van while its controls move only the free camera.
`tools/phase01_checks.gd` supplies real-input, fast/blocked/unsupported exit,
collision, duplicate settlement/strike and terminal motion fixtures.
`tools/phase04_checks.gd` covers camera bindings, drag/zoom clamps, the collision
boom, modal gating, the free-camera freeze and restarts. `run_checks.py`
regenerates settings through `tools/setup_project.gd` before those camera checks
and replays `plans/camera.json` twice alongside the other correctness plans.

The delivery scenarios use explicit teleport setup at pickup/parking/doors.
They exercise actual E input and the legal entry/exit and delivery transitions,
but **do not prove human driving, autopilot navigation or route reachability**.
Autopilot remains available for separate navigation experiments. Presentation,
player navigation and audible sound require their own checks.

## Results and evidence

No developer plan argument means the Capture autoload is inert. With an explicit
plan, all steps are validated before execution. Unknown fields/actions/steps,
invalid types, failed assertions and wait timeouts fail with exit status 1.

Each invocation makes a unique `<name>-<pid>-<ticks>/` below the output base;
`CAPTURE_RESULT <absolute path>` identifies its `result.json`. Default base is
`user://test-runs`. Legacy plans with `dir` use `<dir>/runs/`. CLI
`--capture-output` takes precedence. Historical shots are never overwritten.
Suite evidence defaults to ignored `.godot/test-runs/suite-<unique>/` and contains
per-command logs, temporary negative fixtures, scenario evidence and summary.json.

The result records effective seed, success, failure step/message, assertion count,
logical state records, image paths and cleanup state. Logical records omit clock
and physical coordinates so fixed seed/event-order comparisons make no claim of
cross-platform bit-identical physics. A successful visual-only plan can have zero
assertions; `run_checks.py` requires assertions for its correctness scenarios.

Screenshot steps await rendering and image save before continuing or quitting.
Headless mode prints `SKIP visual capture` and does not wait for rendering. On
success and failure, teardown releases every held action, resets time scale to
1 and tree pause to false, cancels controller hooks, frees the main scene and
allows Dummy audio's mix thread to finish. The report verifies released controls.

## Plan format

A JSON object has `name` (safe identifier), `steps` (nonempty array), optional
nonnegative integer `seed`, optional string `dir`, and optional total wall-clock
`timeout` in seconds (default 120, maximum 600). CLI `--scenario-seed=N` overrides
the plan seed. Default scenario seed is 20261018; normal play randomizes an
independent order RNG. Restart restores a configured seed. Global decorative or
footstep random draws do not change seeded order destinations or quantities.

Steps execute sequentially. Optional `at` is a nonnegative, monotonic minimum
elapsed simulation time for compatibility with old visual plans; it does not
replace waits. Between steps the runner allows physics and deferred state to
settle. Wait timeout budgets use wall time even while the game is paused.
A plan must end with `quit`; nothing may follow it.

```json
{
  "name": "example",
  "seed": 20261018,
  "steps": [
    {"do": "order", "index": 0},
    {"do": "press", "action": "confirm"},
    {"do": "wait", "timeout": 3, "expect": {"mode": "to_shop", "order_id": 1}},
    {"do": "remember", "name": "initial"},
    {"do": "assert", "label": "order exists", "expect": {"timer": {"op": "gt", "value": 0}}},
    {"do": "shot", "name": "started"},
    {"do": "quit"}
  ]
}
```

`expect` is a nonempty object mapping diagnostic fields to either a scalar
(equality) or `{"op":"eq|ne|lt|lte|gt|gte", "value": scalar}`. Instead of
`value`, `saved: "snapshot.field"` reads a previous `remember` snapshot with a
compatible field type. Names and types are checked before execution; ordering
operators require numeric fields. Example: a paused timer must equal
`{"op":"eq", "saved":"initial.timer"}`. No expression evaluation or arbitrary
script/method names are allowed. Assert/wait accept an optional string `label`.

Diagnostics come from typed read-only `Game.get_snapshot()` values. The legacy
`get_diagnostics()` method returns an isolated dictionary copy. Service ownership,
transaction and lifetime rules are documented in [the architecture guide](../docs/ARCHITECTURE.md).

| Field | Type / meaning |
| --- | --- |
| mode | title, to_shop, to_house, complete or failed |
| session_mode, actor_mode, order_lifecycle | Independent flow (title/playing/paused/result), actor (foot/driving), ticket (idle/at_shop/on_route/closed) states |
| generation | Session generation; reset invalidates pending old-ticket work |
| order_id | Session-local monotonic ticket ID, reset to 0 at title restart |
| destination_id | Stable address string, empty before first order |
| cargo_count, order_pizzas | Carried boxes and active ticket quantity |
| deliveries, money, strikes | Authoritative settlement state |
| driving, paused, world_ready | Session booleans |
| timer, timer_max, tip | Remaining/max deadline seconds and derived tip |
| pip_control, van_control | Authoritative movement ownership |
| speed, van_stopped | Signed van speed and entry/exit stop predicate |
| pip_autopilot, van_autopilot | Whether a developer controller is assigned |
| pickup_distance, door_distance, park_distance | Actor-to-current-target distance; unavailable destination distances are -1 |
| pip_x, pip_z, van_x, van_z | World coordinates for motion invariants |
| pip_motion, van_motion | Current velocity magnitudes |
| pip_visible, pip_collision | Player body restoration state |
| camera_mode | Camera rig mode: title, foot, chase or free |
| camera_hint | Free-camera controls line; empty whenever the follow camera owns the view |

Supported steps (only the listed fields plus optional `at` are accepted):

| do | Required / optional fields and behavior |
| --- | --- |
| press / down / up | `action`: existing action with a physical keyboard or mouse binding; events enter Godot's input pipeline. A tap releases on the following frame. |
| mouse_motion | `dx`, `dy` pixel deltas; injected as a mouse-motion event so camera drag paths run without moving the OS cursor. |
| start / restart | Start once from title / reset to title using Game's flow API. |
| order | Exactly one stable string `destination_id` or legacy nonnegative `index`. Sets the **next** destination; inject before start/settlement/expiry creates that order. New correctness plans use stable IDs. |
| wait | `expect`, positive `timeout` up to 120 seconds; optional `label`. |
| assert | `expect`; optional `label`. Fails immediately. |
| remember | Safe `name`; snapshots primitive diagnostics. |
| state | Adds a logical diagnostic record. |
| place | `node`: pip or van; exactly one `target`/`pos`; optional `offset`, numeric `yaw` degrees. Teleports and clears that actor's velocity/autopilot (and van speed). |
| walk_to / drive_to | Exactly one `target`/`pos`; optional `offset`. Assigns a developer controller; never bypasses movement ownership. |
| shot | Safe `name`; saves PNG in the unique run directory or explicitly skips headless. |
| camera | `pos`, `look` vectors; optional `fov` in [1,179]. Freezes chase camera. |
| follow | Restores chase camera physics. |
| hud | Boolean `visible`. |
| time_scale | Numeric `v` in (0,8]. Reset at teardown. |
| expire | Developer fixture: set deadline zero and invoke guarded timeout. |
| retry_delivery | Developer fixture: retry the guarded settlement method to verify idempotence. |
| finish | Boolean `win`; developer terminal fixture. |
| quit | Last step only; finish report and teardown. |

Vectors are exactly three finite numbers. `target` is pickup, door, park, van,
van_left or shop_front; door/park require an existing ticket. For order-range or
missing-target runtime errors the process fails cleanly. No arbitrary field
mutation, code execution or arbitrary method dispatch is supported by JSON.

## Town validation and RNG check

```sh
godot --headless --audio-driver Dummy --path . --script tools/check_town.gd
godot --headless --audio-driver Dummy --path . --script tools/check_order_rng.gd
```

The town check requires PackedScene/Node3D roots, assembled root identity,
Island/Houses/Props/Shop/StreetDetails, pickup and spawn nodes, finite spawn yaw,
nonempty unique addresses, unique positive house numbers, labels, north booleans
and Door/Park markers. Missing/wrong resources fail nonzero. Negative fixtures
can use `-- --resource=/path/to/resource` or `-- --town-scene=/path/to/fixture`;
normal generated resources are never changed. The order-RNG check compares the
same seeded sequence with and without unrelated global random draws.
