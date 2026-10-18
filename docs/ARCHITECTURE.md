# Gameplay ownership (Phase 03)

Game is the composition root and current distance-based interaction coordinator.
It creates/configures scene-local owners, connects their explicit signals and
exposes compatibility commands. It does not own a second copy of order, cash,
cargo, pause or seated state. No global event bus or empty future managers exist.

| Concern | Real owner | State / interface |
| --- | --- | --- |
| Session/input | `services/session_service.gd`, `session_input.gd` | TITLE/PLAYING/RESULT, generation, modal reason set; input commands always process while the world is paused. |
| Tickets, deadlines, settlement | `services/order_service.gd` | IDLE/AT_SHOP/ON_ROUTE/CLOSED; destination/ticket IDs, RNG, money/deliveries/strikes, remaining time. |
| Current cargo | OrderService | One authoritative carried count for the current prototype. Pip reads it through cargo_source; `set_carrying` only updates meshes. Per-package cargo is Phase 08, not an empty service today. |
| Actor mode/control | `services/actor_controller.gd` | FOOT/DRIVING, exclusive control flags, stop/entry/exit probes, reset and camera target handoff. |
| World references/identity | `services/world_registry.gd` | Validated house/pickup/spawn/body references and stable address lookup; no order/session state. |
| Interaction | Game `interact()` | Existing distance/range selection delegates to order/actor commands; a shared validated target pipeline belongs to Phase 06. |
| Camera | `camera_rig.gd` | One rig with TITLE_ORBIT/FOLLOW/CHASE/FREE modes. ActorController supplies target/driving, SessionService supplies flow/pause, Balance supplies tuning. Free view freezes play through the `free_camera` modal reason and drives its own `free_*` actions; nothing else moves the camera. |
| View/effects | `services/presentation.gd`, `sound_presenter.gd` | Derived text/waypoints, markers, sound/toasts/results from committed events. No pay/deadline mutation. |
| HUD/tests | `services/game_snapshot.gd` | Typed frozen values with no Node/service handles; HUD receives only a Callable supplying this read model. |
| Menus/navigation | `ui/menu_layer.gd` | Pooled full-screen cards, the visible screen stack and menu focus. Emits `menu_action(id)` for Game to execute; never writes session, order or actor state. |
| Preferences | `services/settings_service.gd`, `services/input_bindings.gd` | `user://settings.cfg`: audio/window/UI scale/camera/text plus remapped actions. Load/save/validate/reset and applying live values are the service's job, not a menu's. |
| Balance configuration | `data/balance.tres`, `services/balance.gd` | Shared Resource: ranges, deadline floor/start/decrease, pay/tip/goal/strikes, stop/exit thresholds. Never mutated during play. |

All service paths above are under `scripts/`. Later traffic/time/weather/story,
progress and save owners should consume stable IDs/committed events. Their
managers and persistence schemas are deliberately not implemented in this refactor.

```mermaid
flowchart LR
  Game --> Session
  Game --> Orders
  Game --> Actors
  Game --> World
  Session -- changed --> Actors
  Session -- changed --> Presentation
  Session -- changed --> Menus
  Menus -- menu_action --> Game
  Settings -- changed --> Game
  Orders -- committed events --> Presentation
  Orders -- settled --> Actors
  Orders -- shift_ended --> Game
  Presentation --> Sound
  Presentation --> Markers
  Game -- frozen Snapshot --> HUD
  Game -- frozen Snapshot --> Capture
```

## Session and lifetime

`SessionService.Flow` is TITLE/PLAYING/RESULT. Modal reasons are independent of
that base flow. `open_modal(reason: StringName)` and `close_modal(reason)` return
bool; multiple different reasons can coexist. Closing one cannot resume another.
An empty reason, duplicate open or unknown close is rejected. `toggle_pause()`
owns only `user_pause`. The effective snapshot session_mode is title/playing/
paused/result; order_lifecycle and actor_mode remain separate fields.

`reset()` increments generation, clears reasons and returns to title. `start()`
starts only from title; `finish(win)` returns to result only from unpaused play.
`changed(event: Dictionary)` emits a read-only value containing flow, generation,
paused and outcome. It also applies the tree pause state. Only SessionInput,
Session, HUD and the camera rig (free view and its modal) need always-processing
behavior; Game/world stay pausable.
Exiting the service tree clears inherited tree pause for a replacement scene.

One Game instance creates one set of services and signal connections. Reset
reuses them, never reconnecting. Scene destruction removes the entire owner graph;
no cached service/node pointers or connections survive in an autoload. Game reset
prepares OrderService and actors before publishing the new session generation,
so subscribers cannot observe a new title generation with the old cash/cargo/body.

## Camera and player view

`camera_rig.gd` is the single owner of the player view. ActorController keeps its
existing contract (`target`, `driving`, `orbit`); the rig derives one mode from
that plus session flow:

| Mode | When | Manual controls |
| --- | --- | --- |
| TITLE_ORBIT | Session flow is TITLE | None; the diorama keeps orbiting |
| FOLLOW | Playing on foot | Drag/right-stick look, wheel zoom, C recenter |
| CHASE | Driving | Same, plus recenter behind the van after an idle grace |
| FREE | `free_camera` modal open | `free_*` movement and mouse/pad look |

Look input uses the `cam_orbit`, `cam_left/right/up/down` actions (mouse
right-drag, right stick, optional inverted Y); zoom uses `cam_zoom_in/out` with
per-mode minimum/maximum/default distance and pitch; `cam_recenter` (C) eases the
pose behind the followed actor; `cam_free` (F) toggles the free view.
`tools/setup_project.gd` is the generator of record for every binding, so
keyboard, mouse and joypad events survive project regeneration; `run_checks.py`
regenerates settings before the camera checks.

The boom is collision-aware: a sphere sweep against WORLD/VEHICLE from the
head-height pivot shortens the requested distance, and a pivot that already
overlaps geometry collapses to the mode's minimum boom instead of exploding.
Pull-in applies immediately while extension eases, and the followed actor only
gets a slight see-through fade (FOLLOW, inside 4.5 m) when the camera is close.
Losing window focus mid-drag drops the drag and hands the captured cursor back.

While any other modal owns pause the rig ignores camera actions entirely; it is
the only consumer of the `cam_*` actions. The free camera is the one exception:
`open_modal(&"free_camera")` freezes the world like the pause modal, the rig
keeps its own actions live through PROCESS_MODE_ALWAYS, and exiting restores the
saved target/mode/pose, play state and cursor. Restart, session end or an
external modal clear force-closes it. The snapshot publishes `camera_mode`
(title/foot/chase/free) and an empty `camera_hint` except while free, which the
HUD renders as the controls line.

## Menus, preferences and free roam (Phase 05)

`ui/menu_layer.gd` (a CanvasLayer above the HUD) owns one pooled `Control` per
screen — title, pause, results, credits, confirm, message, options, controls.
`_stack` is the visible stack: `_show_only(id)` for TITLE/RESULT, `_push/pop`
for everything else, and every screen is a full-rect `ScrollContainer` +
`CenterContainer` card so an enlarged UI scale scrolls instead of hiding an
action. Screens are transparent to state: buttons call `activate(id)`, which
either pushes/pops (menu ids) or emits `menu_action(id)` for Game to execute
game ids (`start_shift`, `start_roam`, `resume`, `restart_shift`,
`return_to_title`, `quit`). Confirm dialogs remember their pending game id in
`_pending` and only then emit it.

Esc is a single back stack owned by `SessionInput` -> `Game.handle_back()`:
an open menu first (subpanels, then the screen below it), then the free camera,
then the pause toggle, then results -> title. `R` stays an instant restart
shortcut while paused, at the results screen or at the title, and is ignored
during an active shift. The rebindable `confirm` action is a second route into
the focused menu button, used only when a rebind makes it differ from the
builtin `ui_accept` that Enter already triggers. The HUD keeps in-game
furniture only (cash, objective, waypoint, timer, strikes, prompt, toasts); it
hides all of it at the title and results screens, and the pause screen is a
menu, not a HUD card.

Free roam is a session mode, not a separate scene: `SessionService.mode` is
`"shift"` or `"roam"` and `roaming()` is true only while playing in roam. It
starts through the same `start()` path, so camera/actor/order wiring is
unchanged, but the run has no ticket, no deadline and no strikes: the HUD hides
cash, objective, timer and strikes and shows a `FREE ROAM · no clock` hint.
The shop counter and house doors stay dormant in roam while van entry still
works, so exploring cannot create, deliver or fail a ticket. A restart from the
pause menu keeps the mode the player chose (roam restarts roam, a shift
restarts a shift) and the results screen can only be reached from a shift.

`services/settings_service.gd` owns `user://settings.cfg` and the only live
accessor is `value(key)`. `DEFAULTS`/`SPEC` declare every key with type, range
and default; `load_settings()` validates stored values key by key (wrong type or
out-of-range falls back to the default or the nearest legal value), so a
half-written or edited file can never break startup. Audio, window mode, UI
scale and InputMap are applied by the service itself; camera, sun shadows and
text speed are applied by Game when the service emits `changed`. `configure(path,
autosave)` lets checks and probes write to their own file instead of the real
one. `services/input_bindings.gd` serializes/deserializes the map, reports
conflicts (skipping `ui_*`), keeps critical movement actions always bound and
produces the prompt labels the HUD and controls screen show.

## Orders and transaction boundaries

OrderService APIs:

- `set_seed(value: int)`, `reset(next_generation: int)`.
- `force_destination(id: String, available: Array[String]) -> bool`.
- `create_ticket(available: Array[String]) -> bool` sorts stable IDs before seeded
  selection; an explicit destination takes precedence over anti-repeat logic.
- `pickup() -> bool` changes AT_SHOP to ON_ROUTE and sets current cargo once.
- `tick(delta: float, available: Array[String])` updates the active deadline.
- `settle(available, expected_generation: int, expected_order: int) -> bool`.
- `expire(available, expected_generation: int, expected_order: int) -> bool`.
- `tip() -> int`, `close()` and `event(outcome: String, pay: int=0) -> Dictionary`.

Signals `ticket_created`, `picked_up`, `settled`, `timed_out`, `shift_ended` each
carry a read-only Dictionary of generation, order_id, destination_id, outcome,
pay, money, deliveries, strikes, pizzas and cargo_count. There are no live Nodes
or mutable nested values in these payloads.

A terminal ticket marks its lifecycle CLOSED and commits cargo/counters/cash
**before** emitting. Reentrant settle/timeout attempts reject. After subscribers
return, pending next-ticket/result work runs only if generation and ticket ID
still match and the run was not closed. A restart or session end during a callback
cannot create an old session's next ticket or pay/strike a new session. The
expected-generation/order arguments also reject delayed work explicitly.

OrderService owns current prototype money until a later progress ledger exists;
there is no second cash counter in Game/HUD/Pip. Rendering adapters observe IDs
and outcomes, never settle tickets. `close()` cancels pending run work separately
from the per-ticket CLOSED lifecycle. Goal $150, three strikes and current pay
rules are unchanged.

## Identifiers and compatibility

A destination's stable string ID is its validated unique `address` metadata,
for example `2 Marinara Way`. It is independent of child index/order; changing
an address is an intentional ID migration. Labels are presentation data. Ticket
identity is `(session generation, order_id)`; order_id increments within a run
and resets at title restart. No live Node pointer belongs in future save data.

WorldRegistry `ids()`, `destination(id)`, `legacy_id(index)` expose the actual
registry. Only `legacy_id` depends on authoring child order. Capture's old
`order.index` remains a documented compatibility adapter; new correctness plans
use `order.destination_id`. The choices passed to OrderService are stable IDs,
not numeric scene positions. Registry lookup validates unique nonempty addresses
and the existing Door/Park/pickup/spawn/collision contracts.

Game exposes `start_shift() -> bool`, `interact()`, `restart()`,
`force_destination(id) -> bool`, `open_modal(reason)`, `close_modal(reason)`,
`get_snapshot() -> GameSnapshot` and `set_order_seed(value)`. Existing underscore
methods/legacy State/getter fields remain compatibility adapters for Phase 01
fixtures. New consumers should not write them. The legacy combined mode strings
remain in diagnostics so the Phase 02 assertion schema is preserved.

GameSnapshot exposes typed computed getters and a read-only internal dictionary.
It contains primitives/Vector3/Color values only. `to_dictionary()` is an isolated
JSON-compatible copy; changing it cannot change a snapshot or gameplay owner.
HUD gets no mutable Game/service reference. Phase 02 fields remain; additional
fields are generation, session_mode, actor_mode and order_lifecycle. Derived HUD
text, actor position and waypoint values use the same snapshot contract.

`tools/dev_fixture.gd` contains explicit test-only money/timer/mode injection,
teleport/autopilot, expiry/retry/result and teardown adapters. Capture imports it
only for an explicitly requested developer plan; ordinary gameplay never imports
it. `phase01_checks.gd` remains an isolated physics fixture and may inject body
velocities/colliders or restrict the registry for negative tests. Such hooks do
not establish player navigation or authorize arbitrary mutation in JSON.

## Regression commands

```sh
python3 tools/run_checks.py
godot --headless --audio-driver Dummy --path . --script tools/phase03_checks.gd
godot --headless --audio-driver Dummy --path . --script tools/phase04_checks.gd
godot --headless --audio-driver Dummy --path . --script tools/phase05_checks.gd
godot --headless --audio-driver Dummy --path . --script tools/settings_probe.gd -- --mode=write
```

The full suite includes original 137 physics/state assertions, typed snapshot/
modal/transaction/reload checks, order RNG isolation, settings regeneration
through `tools/setup_project.gd`, 58 camera checks, 214 menu/settings/free-roam
assertions, a three-process preferences persistence probe, repeated one/two-
delivery, camera and menu scenarios, and deliberately failing fixtures. The
preference probe runs `write`, `read` and `clean` as separate processes against
`user://phase05-probe.cfg`, because saved values only count as persisted when a
different process loads them; the real `user://settings.cfg` is never touched.
See `tools/SCENARIOS.md` for the JSON schema and rendered smoke command. No
world/art generation or serialization was introduced by this refactor.
