# Pip the Pizza Boy

A small voxel pizza-delivery game for Godot 4. Take orders at Pip's Pizza on the
plaza, load up the van, drive along Marinara Way, park at the address and deliver
on foot before the tip — and the clock — runs out. Three timeouts end the shift.

## Run it

The bundled engine runs it straight from this folder:

```powershell
& '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe' --path .
```

`scenes/game.tscn` is the main scene (open the editor with `--editor` and press
F5 if you prefer). Add `--audio-driver Dummy` to any command for a silent run —
every automated test in this project uses it.

**Controls**: WASD / arrows move & drive · **E** interact (load pizzas, deliver,
enter/exit the van) · **Space** handbrake · **H** honk · **Esc** pause ·
**R** return to the title/reset from pause or results · **Enter** start the shift.
**Camera**: right-mouse drag orbits/looks · wheel zooms · **C** recenters ·
**F** opens the free camera (WASD move, Q/E rise and fall, Shift boost, mouse
look, **F**/**Esc** return) · gamepad right stick looks. Pause first to restart
an active shift. Van entry and exit require a stop
(at most 0.25 m/s); blocked, unsupported or steep exits leave Pip seated and
explain why. Use the brakes/handbrake to stop before pressing E.

On Linux, use a Godot 4 executable on `PATH`:

```sh
godot --audio-driver Dummy --path .
godot --headless --audio-driver Dummy --path . --quit-after 180
```

The current cloud environment has Godot **4.6.3**, tested with the headless
checks below; the Windows engine/version named above is not bundled here.

## Core correctness checks

Phase 01 has focused acceptance checks for real keyboard-event routing,
pause/resume, exclusive movement, safe vehicle exits, state transitions,
payment and world-contract failures:

```sh
godot --headless --audio-driver Dummy --path . --script tools/phase01_checks.gd
```

Expect `PHASE 01: 137 checks, 0 failures` and exit status 0. Five deliberate
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
checks nested modals, generation-safe transactions, scene reloads and the Phase
04 camera rig (58 assertions plus a replayed camera scenario).

Keyboard defaults match all device IDs. `tools/setup_project.gd` preserves that
setting when regenerating project defaults. Startup rejects missing houses,
Door/Park markers, addresses, pickup and spawn nodes with diagnostics and a
world-setup error screen instead of starting a broken shift.

## The game

- The island is 68 × 56 m: Marinara Way with Basil Street and Olive Street, a
  pizza plaza (Pip's Pizza, picked up out back), a park with a pond, and eight
  customer houses along the road.
- Loop: pick up → drive → park → deliver on foot → get paid $10 + $2 per pizza,
  plus a tip that scales with the time left. The clock tightens as deliveries
  bank; $150 completes the shift.
- `scripts/game.gd` composes the session, order, actor and world owners;
  `scripts/hud.gd` draws the cash card, objective, waypoint compass, timer and
  toasts from a typed read-only snapshot.

| Script | Role |
| --- | --- |
| `scripts/game.gd` | Scene composition, interaction coordination and snapshot API |
| `scripts/services/` | Session, orders/cargo/pay, actors, world references and presentation |
| `scripts/player.gd` | Pip on foot: camera-relative walk, limb swing, pizza stack |
| `scripts/vehicle.gd` | Arcade van: throttle/brake/reverse, wheel spin, engine hum |
| `scripts/camera_rig.gd` | Player camera: title orbit, on-foot orbit, driving chase, swept collision boom and the free camera |
| `scripts/marker.gd` | Floating pickup / deliver markers |
| `scripts/hud.gd` | All UI, drawn in code |

Scene contracts to keep when editing art: each house has `Door` and `Park`
markers plus address metadata, Pip's limbs are `Visual/LeftLeg…` pivots, the
van's wheels are `octagonal_tyre*` nodes, and the shop has a `PickupPoint` —
these names are looked up by the scripts.

## Rebuild the world

Everything in `assets/` is generated. The Python tools are the source of truth
and rebuilding **replaces** the `.tscn` files.

```powershell
python tools/build_art.py     # land, pizza_shop, pizza_van, pip, street_details
python tools/build_town.py    # town_island, town_houses, town_props, scenes/town.tscn
python tools/make_sfx.py      # assets/audio/*.wav (recorder-free SFX)
```

Spawn points (`PlayerSpawn`, `VanSpawn` and their yaw metadata) live in
`tools/build_town.py`. Two sanity checks keep the built scenes honest:

```powershell
& '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tools/check_town.gd
& '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tools/validate_art.gd
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
- `core.json` — seeded pause, forced-repeat, ownership, result and restart checks.
- `vanprobe.json` — dev diagnostic: drives the van from the west house pad to
  the shop forecourt with a state print every 0.5 s (no shots) — used to verify
  parking/stop behaviour.

`--quit-after` counts **frames**, not seconds: keep it huge as a backstop and let
the plan's own `quit` step end the run. The complete plan format is documented in [tools/SCENARIOS.md](tools/SCENARIOS.md).

Presentation renders still exist for standalone previews (these scenes contain
no game systems):

```powershell
& $exe --path . -- --capture-town   # also --capture-town-street / -top / -houses, --capture, --capture-pip
```

Previews are saved in `previews/`.
