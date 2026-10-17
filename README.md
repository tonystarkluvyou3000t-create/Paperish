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
**R** restart · **Enter** start the shift.

## The game

- The island is 68 × 56 m: Marinara Way with Basil Street and Olive Street, a
  pizza plaza (Pip's Pizza, picked up out back), a park with a pond, and eight
  customer houses along the road.
- Loop: pick up → drive → park → deliver on foot → get paid $10 + $2 per pizza,
  plus a tip that scales with the time left. The clock tightens as deliveries
  bank; $150 completes the shift.
- `scripts/game.gd` runs the shift state machine; `scripts/hud.gd` draws the
  cash card, objective, waypoint compass, timer and toasts entirely in code.

| Script | Role |
| --- | --- |
| `scripts/game.gd` | Shift flow: orders, timers, tips, strikes, van in/out |
| `scripts/player.gd` | Pip on foot: camera-relative walk, limb swing, pizza stack |
| `scripts/vehicle.gd` | Arcade van: throttle/brake/reverse, wheel spin, engine hum |
| `scripts/camera_rig.gd` | Chase camera (orbit view on the title screen) |
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

`tools/capture.gd` is an autoload harness: start the game with a plan and it
replays scripted steps (walk, drive, interact, screenshots) and saves shots to
`shots/`.

```powershell
$exe = '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe'
& $exe --audio-driver Dummy --path . --quit-after 30000 -- --capture-plan=res://tools/plans/views.json
& $exe --audio-driver Dummy --path . --quit-after 30000 -- --capture-plan=res://tools/plans/playfast.json
& $exe --audio-driver Dummy --path . --quit-after 30000 -- --capture-plan=res://tools/plans/playtest.json
```

- `views.json` — five beauty checks of the town (plaza, house, street, park, title).
- `playfast.json` — smoke run of one full delivery, minimal wall time.
- `playtest.json` — scripted two-delivery shift with eight shots.
- `vanprobe.json` — dev diagnostic: drives the van from the west house pad to
  the shop forecourt with a state print every 0.5 s (no shots) — used to verify
  parking/stop behaviour.

`--quit-after` counts **frames**, not seconds: keep it huge as a backstop and let
the plan's own `quit` step end the run. The step list (shot, press, walk_to,
drive_to, place, camera, order, state, …) is documented at the top of
`tools/capture.gd`.

Presentation renders still exist for standalone previews (these scenes contain
no game systems):

```powershell
& $exe --path . -- --capture-town   # also --capture-town-street / -top / -houses, --capture, --capture-pip
```

Previews are saved in `previews/`.
