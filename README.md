# Pip the Pizza Boy

A small voxel pizza-delivery game for Godot 4. Check the ticket at Mona's counter
inside Pip's Pizza, receive the ready boxes, drive along Marinara Way, park at
the address and deliver on foot before the tip — and the clock — runs out. Three
timeouts end the shift.

## Run it

The bundled engine runs it straight from this folder:

```powershell
& '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe' --path .
```

`scenes/game.tscn` is the main scene (open the editor with `--editor` and press
F5 if you prefer). Add `--audio-driver Dummy` to any command for a silent run —
every automated test in this project uses it.

**Controls**: WASD / arrows move & drive · **E** interact (check ticket, receive
pizzas, load/retrieve cargo, deliver, enter/exit the van) · **Tab** cycle the
selected order at the cargo door · **Space** handbrake · **H** honk · **M** town
map · **Esc** back (menus first,
then pause) · **R** restart/return to title from pause or results · **Enter**
start the shift. **Camera**: right-mouse drag orbits/looks · wheel zooms ·
**C** recenters · **F** opens the free camera (WASD move, Q/CTRL rise and fall,
Shift boost, mouse look, **F**/**Esc** return) · gamepad right stick looks.
Menus work with mouse, keyboard and controller; every action in the Controls
screen can be rebound, and `Esc` there cancels a rebind instead of leaving the
screen. A controller moves menu focus with the d-pad or left stick, confirms with
**PAD A** and backs out with **PAD START** (both rebindable in Controls). Pause first to restart an active shift. Van entry and exit require a
stop (at most 0.25 m/s); blocked, unsupported or steep exits leave Pip seated
and explain why. Use the brakes/handbrake to stop before pressing E.

On Linux, use a Godot 4 executable on `PATH`:

```sh
godot --audio-driver Dummy --path .
godot --headless --audio-driver Dummy --path . --quit-after 180
```

This checkout includes Godot **4.7.2** for Windows; the regression suite below
uses that bundled version.

## Core correctness checks

Phase 01 has focused acceptance checks for real keyboard-event routing,
pause/resume, exclusive movement, safe vehicle exits, state transitions,
payment and world-contract failures:

```sh
godot --headless --audio-driver Dummy --path . --script tools/phase01_checks.gd
```

Expect `PHASE 01: 136 checks, 0 failures` and exit status 0. Five deliberate
missing-world fixtures log `ERROR: World contract: ...`; those are expected
negative checks, not broken normal resources. No other errors are expected.
Fixtures use teleporting and direct interactions as setup; they do not prove
human driving, route reachability, rendered appearance or audible output.
The seeded scenario runner and full regression suite are now available:

```sh
python3 tools/run_checks.py
```

This captures both output streams, rejects unexpected engine/script errors,
replays seeded logical outcomes, verifies deliberate failures return nonzero,
and writes fresh evidence under `.godot/test-runs/`. Use `--godot /path/to/engine`,
`--seed 20261018` or `--output /path/to/evidence` as needed. It uses only Python's
standard library and Godot. See [scenario schema and workflow](tools/SCENARIOS.md).

Gameplay ownership, service APIs, immutable snapshots and modal pause semantics
are documented in [the architecture guide](docs/ARCHITECTURE.md). The suite also
checks nested modals, generation-safe transactions, scene reloads, the Phase 04
camera rig (58 assertions plus a replayed camera scenario), the Phase 05
menus/preferences/free roam (251 assertions and a three-process settings
persistence probe), the Phase 06/07 conversation and shop flows (177 and 40
checks), and Phase 08's order/cargo transactions plus a 20-check physical route
from Mona's counter through van loading, driving, safe exit, unloading and
payment. Phase 10 adds graph checks and a real-input foot and van loop through
all five districts. Deterministic dialogue, shop-handoff and cargo-handoff
scenarios also run in the suite:

```powershell
& '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe' --headless --audio-driver Dummy --path . --script tools/phase05_checks.gd
```

Keyboard defaults match all device IDs. `tools/setup_project.gd` preserves that
setting when regenerating project defaults. Startup rejects missing houses,
Door/Park markers, addresses, pickup and spawn nodes with diagnostics and a
world-setup error screen instead of starting a broken shift.

## Menus, settings and free roam

Every screen is readable and reachable with mouse, keyboard and controller, and
stays usable when enlarged. **Options** covers the audio buses, window mode,
shadows, screen shake, UI scale (85–150 %), camera sensitivity/invert and text
speed; **Controls** rebinds every gameplay action with conflict detection, a
RESET CONTROLS button and `Esc` cancelling an active rebind; the title also
offers CREDITS, FREE ROAM and a confirm-guarded QUIT. `Esc` unwinds one layer at
a time (rebind → subpanel → screen → pause → results → title) and menus pump the
window's UI scale so a card that no longer fits scrolls instead of hiding an
action.

Preferences live in `user://settings.cfg`, are validated key by key when loaded
and applied immediately; a hand-edited or truncated file falls back to defaults
instead of blocking startup.

**Free Roam** reuses the same town with no tickets, deadline or strikes: the HUD
shows a `FREE ROAM · no clock` hint and the shop counter and house doors stay
dormant until a real shift starts, so exploring cannot create, deliver or fail a
ticket. Restarting from the pause menu keeps the mode you chose, and the results
screen belongs to shifts only.

## People and conversations

One interaction table decides what a press does. Every target — the shop
counter, the waiting customer, the van's door, the driver's seat, the neighbour
on the plaza — registers an anchor, an approach point, a range, a priority and a
gate, and the HUD prompt and the action itself read that same entry. A target
that is too far, behind a wall, behind Pip's back or blocked right now says why
instead of doing nothing: `COUNTER CLOSED`, `HANDS FULL`, `NOTHING TO DELIVER`,
`WRONG ORDER`, `STOP THE VAN TO EXIT`.

Conversations live in `data/dialogue/*.json` and are validated at load: unknown
fields, unknown text tokens, dangling node links, unreachable lines, a choice
maze with no exit and a conditional last entry are all rejected, and
`tools/check_dialogue.gd` proves the shipped files plus every rejection.
A conversation freezes the world; `Esc` leaves the ones that cost nothing and
stacks the pause menu *over* the ones that do, so an order can never be handed
over by accident. Effects run on the node that carries them, and the `order`
effects that move cargo or money only ever run on a commit node, exactly once —
the tests replay a completed delivery to prove it pays nothing the second time.

## Tickets and physical cargo

Mona can queue up to three active orders. Each ticket has a stable run-local ID,
destination, quantity, preparation state and deadline. Pip carries up to three
boxes at once; the van holds six package slots by default. At its rear hatch, E
moves one whole selected order between Pip and the van. Tab cycles the loaded
order when more than one bundle is aboard. The HUD lists each order's address,
quantity and current location, and shows occupied van slots.

At the right customer's door, Pip can hand over only the complete matching
bundle. Wrong-address dialogue leaves the order and payment unchanged. A timeout
reclassifies its boxes as discarded, frees its van slots and adds one strike;
repeated settlement or timeout cannot pay twice or leave deliverable boxes
behind. The settlement shows base pay, per-pizza pay, tip and the quality
adjustment. `tools/phase08_route_checks.gd` exercises the full counter-to-door
route with movement and driving inputs, without teleport or actor autopilot.

## Navigation, map and recovery

The HUD navigation card follows legal roads to the selected ticket: a manoeuvre
line (`TURN LEFT ON MARINARA WAY`, `CROSS THE ROAD`, `PARK AT …`, `WALK TO …`,
`DOOR — INTERACT`) with the remaining distance, over a minimap, a compact compass
or nothing (`hud/navigation` in **Options**). **M** opens the town map while a
shift runs — districts, roads, addresses, POIs and recovery anchors, the live
route and every outstanding ticket as its own stop with arrival-window
comparisons. The stop list is advice, not autopilot: reorder it with the row
buttons and set your own waypoint. The map is a pause, so it stacks over the
pause menu and returns to it.

Estimates are conservative (4.2 m/s van, 1.35 m/s on foot, plus parking, exit,
walk and handoff allowances) and a route is re-planned only when the target,
closures, topology or a real deviation changes — never every frame. If you end up
stuck, **UNSTUCK** on the pause screen (and the map) moves you to the nearest
recovery anchor and charges each running ticket a flat 15 s, floored so a rescue
can never itself time out a delivery; free roam pays nothing. An unreachable
ticket says so instead of drawing a line through a building.

`tools/phase11_route_checks.gd` drives the longest reachable address of every
district with ordinary throttle and steering and compares each measurement with
the published estimate; `tools/plans/map.json` exercises the same surfaces in a
running game.

## Target machine and quality presets

The reference machine is an **RTX 3050 6 GB laptop (95 W)** and the shipping
target is **1920 × 1080 at 60 FPS** with the **HIGH** preset: Forward+ renderer,
4 × MSAA, ambient occlusion, glow and a 140 m shadow range on a 4096 directional
shadow atlas. The default window is 1920 × 1080, clamped to the usable desktop so
it still fits a 1080p panel with its title bar on screen.

**Options → VIDEO** exposes the preset plus every key it writes (anti-aliasing,
ambient occlusion, glow, frame cap, shadows, shadow quality), so a preset is a
macro, never a hidden switch. The frame cap (60 / 120 / unlimited) exists for
laptop thermals and never throttles headless runs.

`tools/perf_probe.gd` measures rendered gameplay on a fixed street route —
frame-time percentiles, hitches, draw calls, primitives, nodes, memory and
physics:

```powershell
& '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe' --audio-driver Dummy --path . `
  --script res://tools/perf_probe.gd -- --perf-quality=high --perf-res=1920x1080 `
  --perf-frames=1800 --perf-warm=900
```

Phase 05 baseline on the 3050 (68 × 56 m prototype, no traffic): **median 4.7 ms
(≈ 213 FPS), p99 6.7 ms, 0 hitches**, ~1 000 draw calls and 2 073 nodes at
1920 × 1080 HIGH. That is roughly 2.5 × the 60 FPS budget, so later phases may
spend the room on density — but draw calls and node count, not shader cost, are
the ceiling this project has to plan for (batching lands in phases 09/10 and 20).

Phase 10 measurement on the expanded map, same GPU and settings: **median
4.85 ms (206 FPS), p95/p99 5.61 ms, 0 hitches**, max 730 draw calls, 26,085
primitives, 5,829 nodes, 113.3 MiB static memory and 0.68 ms median physics
time. It used 900 warmup frames and 1,800 sampled frames with VSync and the
frame cap off. The profiler followed 303 authored pedestrian waypoints and
reported 0 timed-out legs.

Phase 11 locked-vantage A/B on the same GPU (`--perf-hold=1`: one authored spot,
one live route, 300 warmup + 600 sampled frames, VSync off): no ticket 6.04 ms
(repeat 7.36 ms), ticket with the card off 5.60 ms (repeat 5.89 ms), compass
6.88 ms, minimap 6.11 ms — all inside the session's ~0.3–1.3 ms repeat spread,
with 0 hitches, so the navigation display's per-frame cost is below this
machine's noise floor. Its price is draw calls: 920 with the card hidden, 933
with the compass, 1,079 with the minimap (+159, ~+2 k primitives). The A/B was
captured on battery with a busy desktop, so its absolute times are deliberately
not compared with the phase-10 AC/idle baseline above.

## The game

- The island is 320 × 240 m: five connected districts and 44 delivery addresses
  around Downtown, Cedar Grove, Harborfront, Summit Hill and Market Works. The
  original eight Marinara Way homes and the Pizza Plaza remain at the center;
  clinic, harbor office, lodge, market stall and workshop deliveries join the
  new residential lots. The generated island, address and props scenes contain
  2,419, 1,771 and 789 geometry pieces, respectively. Each address has a door,
  parking point, approach path,
  district label and customer placement marker.
- Loop: check the ticket → receive the ready boxes → drive → park → deliver on
  foot → get paid $10 + $2 per pizza,
  plus a tip that scales with the time left. The clock tightens as deliveries
  bank; $150 completes the shift.
- `scripts/game.gd` composes the session, order, actor and world owners;
  `scripts/hud.gd` draws the cash card, objective, waypoint compass, timer and
  toasts from a typed read-only snapshot.

| Script | Role |
| --- | --- |
| `scripts/game.gd` | Scene composition, interaction coordination and snapshot API |
| `scripts/services/` | Session, orders/cargo/pay, actors, world references, presentation and settings |
| `scripts/ui/` | Menu screens plus the shared theme/scroll factory; `menu_layer.gd` owns the stack and focus |
| `scripts/session_input.gd` | Routes focused input (Esc back stack, R restart) without owning game state |
| `scripts/player.gd` | Pip on foot: camera-relative walk, limb swing, pizza stack |
| `scripts/vehicle.gd` | Arcade van: throttle/brake/reverse, wheel spin, engine hum |
| `scripts/camera_rig.gd` | Player camera: title orbit, on-foot orbit, driving chase, swept collision boom and the free camera |
| `scripts/marker.gd` | Floating pickup / deliver markers |
| `scripts/hud.gd` | All UI, drawn in code |

Scene contracts to keep when editing art: each delivery lot has stable
`address_id`/`district_id` metadata plus `Door` and `Park` markers, Pip's limbs are `Visual/LeftLeg…` pivots, the
van's wheels are `octagonal_tyre*` nodes, and the shop exposes `CounterAccess`,
`StaffStation`, `ShopEntrance` and the legacy `PickupPoint` counter alias — these
names are looked up by the scripts.

## Rebuild the world

Everything in `assets/` is generated. The Python tools are the source of truth
and rebuilding **replaces** the `.tscn` files.

```powershell
python tools/build_art.py     # land, pizza_shop, pizza_van, pip, street_details
python tools/build_town.py    # town scenes, scenes/town.tscn, data/world/world_layout.json
python tools/make_sfx.py      # assets/audio/*.wav (recorder-free SFX)
```

Both scene builders accept `--output <staging-root>` for isolated reproducible
builds. `tools/world_data.py` authors the district/address catalog, road lanes,
pedestrian links, POIs, collision classes and actor clearance. Check the current
topology and emit its directed-road/walkway diagram with:

```powershell
python tools/validate_world.py --layout data/world/world_layout.json --diagram docs/world_graph.dot
```

Spawn points (`PlayerSpawn`, `VanSpawn` and their yaw metadata) live in
`tools/build_town.py`. Two sanity checks keep the built scenes honest:

```powershell
& '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tools/check_town.gd
& '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tools/validate_art.gd
& '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe' --headless --audio-driver Dummy --path . --script tools/phase10_route_checks.gd
```

`tools/export_assets.gd` additionally writes portable `.glb` copies of the five
art assets, and `tools/setup_project.gd` regenerates the input map / main scene
config in `project.godot` if it is ever lost.

For collision debugging, `tools/dump_colliders.gd` prints every static body in
the built town (ground plane, island edge walls, house bodies, the shop) with
its shapes and world positions.

## Captures & playtests

`tools/capture.gd` is an explicitly invoked developer autoload. Plans support
bounded condition waits and state assertions. With no `--capture-plan` argument
it remains inert. Every run writes its own `result.json` and image directory;
historical images are preserved. Screenshots are awaited before quitting and
explicitly skipped in headless runs.

```powershell
$exe = '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe'
& $exe --audio-driver Dummy --path . --quit-after 30000 -- --capture-plan=res://tools/plans/views.json
& $exe --audio-driver Dummy --path . --quit-after 30000 -- --capture-plan=res://tools/plans/playfast.json
& $exe --audio-driver Dummy --path . --quit-after 30000 -- --capture-plan=res://tools/plans/playtest.json
```

- `views.json` — five beauty checks of the town (plaza, house, street, park, title).
- `playfast.json` — one asserted pickup/van/handoff delivery, with two shots.
- `playtest.json` — two asserted deliveries and next-order transitions, four shots.
- `dialogue.json` — counter → door → declined-counter route: 11 assertions over
  the conversation and interaction fields, with two shots.
- `shop-handoff.json` — ready ticket, staffed dialogue, received cargo and four
  shots of the exterior entrance, interior ticket, dialogue and visible handoff.
- `cargo-handoff.json` — rear hatch, loaded package slots and retrieval shots;
  its teleporting setup is for presentation only. `phase08_route_checks.gd`
  separately completes a real-input counter-to-customer delivery.
- `core.json` — seeded pause, forced-repeat, ownership, result and restart checks.
- `camera.json` — on-foot orbit, chase zoom and the free camera.
- `menu.json` — title/options/controls/credits/pause/confirm/results plus free
  roam and gameplay at 100 %, 125 % and 150 % UI scale (rendered evidence).
- `vanprobe.json` — dev diagnostic: drives the van from the west house pad to
  the shop forecourt with a state print every 0.5 s (no shots) — used to verify
  parking/stop behaviour.
- `phase10-world.json` — rendered 320 × 240 m aerial overview and street views
  for Downtown, Cedar Grove, Harborfront, Summit Hill and Market Works.
- `map.json` — live guidance after a counter pickup, the town map opened from the
  pause menu over a paused world, the transparent unstuck charge and closing back
  to a running world (10 assertions, two shots).
- `nav-panel.json` — one live route shown three ways: minimap, compass card and
  hidden, with a shot of each and the route asserted live throughout (9
  assertions).

`--quit-after` counts **frames**, not seconds: keep it huge as a backstop and let
the plan's own `quit` step end the run. The complete plan format is documented in [tools/SCENARIOS.md](tools/SCENARIOS.md).

Presentation renders still exist for standalone previews (these scenes contain
no game systems):

```powershell
& $exe --path . -- --capture-town   # also --capture-town-street / -top / -houses, --capture, --capture-pip
```

Previews are saved in `previews/`.
