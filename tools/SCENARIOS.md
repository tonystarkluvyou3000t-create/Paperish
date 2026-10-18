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
and next-ticket creation; `playtest.json` checks two transitions; `dialogue.json`
walks a conversation at the counter, one at the door and one declined branch,
asserting the prompt id, the conversation state and the settlement after each;
`shop-handoff.json` checks ticket readiness, Mona's counter conversation, the
receipt and collected state, with exterior, interior, dialogue and handoff
screenshots;
`core.json`
checks pause, ownership, repeated forced destination, result and restart.
`camera.json` checks on-foot orbit, chase zoom travel and the free camera
freezing deadlines and the van while its controls move only the free camera.
`menu.json` walks the title menu, options, controls, credits, the pause and
confirm dialogs, free roam and the results screen, with shots at 100 %, 125 %
and 150 % UI scale.
`tools/phase01_checks.gd` supplies real-input, fast/blocked/unsupported exit,
collision, duplicate settlement/strike and terminal motion fixtures.
`tools/phase04_checks.gd` covers camera bindings, drag/zoom clamps, the collision
boom, modal gating, the free-camera freeze and restarts. `run_checks.py`
regenerates settings through `tools/setup_project.gd` before those camera checks
and replays `plans/camera.json` twice alongside the other correctness plans.
`tools/phase05_checks.gd` covers menu stack/focus/back routing, options
application, rebinding (conflict, cancel, reset, critical-action protection),
free roam gating, results copy, HUD layout at 100–150 % scale and the settings
service. Because saved preferences only count as persisted when *another*
process loads them, `run_checks.py` also runs `tools/settings_probe.gd` three
times (`write`, `read`, `clean`) against `user://phase05-probe.cfg`; the real
`user://settings.cfg` is never touched by any check.
`tools/phase07_checks.gd` adds service, collision and world-rotation checks and
walks Pip from the authored spawn through the shop doorway and back using regular
movement input. Delivery capture plans still teleport to their interaction
points for transaction setup; they are not navigation evidence.

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
| session_mode, actor_mode, order_lifecycle | Independent flow (title/playing/paused/result), actor (foot/driving), and ticket lifecycle (idle/at_shop/on_route/closed) |
| ticket_state, preparation_remaining, ticket_customer | Shop ticket state (`none`, `preparing`, `ready`, `collected`), bounded prep seconds, and the destination's customer label |
| generation | Session generation; reset invalidates pending old-ticket work |
| order_id | Session-local monotonic ticket ID, reset to 0 at title restart |
| destination_id | Stable address string, empty before first order |
| cargo_count, order_pizzas | Carried boxes and active ticket quantity |
| deliveries, money, strikes | Authoritative settlement state |
| driving, paused, world_ready | Session booleans |
| timer, timer_max, tip | Remaining/max freshness seconds and derived tip; remaining stays zero until ticket receipt |
| pip_control, van_control | Authoritative movement ownership |
| speed, van_stopped | Signed van speed and entry/exit stop predicate |
| pip_autopilot, van_autopilot | Whether a developer controller is assigned |
| pickup_distance, door_distance, park_distance | Actor-to-counter approach / current door / van-to-park distance; unavailable destination distances are -1 |
| pip_x, pip_z, van_x, van_z | World coordinates for motion invariants |
| pip_motion, van_motion | Current velocity magnitudes |
| pip_visible, pip_collision | Player body restoration state |
| camera_mode | Camera rig mode: title, foot, chase or free |
| camera_hint | Free-camera controls line; empty whenever the follow camera owns the view |
| menu_screen, menu_focused | Open menu screen id (`title`, `options`, …; empty while playing) and the focused control's node name |
| play_mode, gameplay_visible | `shift` or `roam`, and whether gameplay (not a menu or the title) owns the screen |
| timer_visible | Whether the freshness bar is shown; it starts on receipt and is false at title, shop prep, results and free roam |
| prompt_text, prompt_id | The single interaction query: what the HUD prompt says and which target id it came from (empty when nothing is in reach) |
| dialogue_id, dialogue_node, dialogue_state | Open conversation id, current node id, and its state (`revealing`, `choices` or `line`); all empty while nobody is talking |
| dialogue_choices, dialogue_busy, dialogue_flags | Offered choice count, the target that owns the session, and how many story flags are set |

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
| talk | No required fields; optional nonnegative `pick` (default 0) and `expect`. Drives the open conversation the way a player would - reveal, advance, then pick - until it closes, then asserts `expect` and adds a logical record. Fails if the conversation never ends. |
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
van_left, shop_front, counter or customer; door/park require an existing ticket,
counter resolves to the generated counter access marker (the customer target needs a
waiting customer, i.e. an active ticket). For order-range or missing-target
runtime errors the process fails cleanly. No arbitrary field
mutation, code execution or arbitrary method dispatch is supported by JSON.

## Performance probe

`tools/perf_probe.gd` is a rendered measurement, not a plan: it starts a shift on
a fixed seed, walks the street route with the real follow camera and reports
frame times and renderer counters. Timings need a real window.

```powershell
# Reference run: 1080p HIGH on the RTX 3050, 900 warmup frames then 1800 samples.
& '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe' --audio-driver Dummy --path . `
  --script res://tools/perf_probe.gd -- --perf-quality=high --perf-res=1920x1080 `
  --perf-frames=1800 --perf-warm=900 --perf-output=res://.godot/perf-high.json

# Harness only (the suite runs this): no window, no numbers, route still walked.
godot --headless --audio-driver Dummy --path . --script tools/perf_probe.gd
```

Warm up before reading the percentiles: uncached Vulkan pipelines make the first
~900 frames report 14–17 ms tails that disappear once the shader cache is warm.
Report `median`, `p95`, `p99`, `hitches`, `draw_calls` and `nodes` together, and
name the adapter, resolution and quality tier — the probe prints all of them and
`--perf-output=` writes the same numbers as JSON.

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
