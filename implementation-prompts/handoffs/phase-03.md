# Phase 03 — Separate gameplay services and data
Status: VERIFIED

## Implemented behavior

The original delivery loop remains playable with the Phase 01 correctness rules.
Game is now a scene composition root and distance-based interaction coordinator;
orders/cash/cargo/deadlines, session pause and actor mode have separate owners.
No empty future managers, new world geometry, story/weather systems or save
serialization were introduced.

- OrderService owns the current prototype ticket lifecycle, isolated RNG,
  authoritative cargo count, deadlines, money, deliveries and strikes. Pip reads
  cargo through its owner; set_carrying updates only visual meshes.
- SessionService owns TITLE/PLAYING/RESULT and a set of modal pause reasons.
  Map and dialogue can both pause; closing one leaves the other paused. Actor
  mode FOOT/DRIVING is separate from order lifecycle and session flow.
- ActorController owns switching, movement flags, stop/clearance/floor probes,
  body/camera reset and target handoff. WorldRegistry validates/looks up live
  scene references using stable string destination IDs.
- Presentation/SoundPresenter consume committed events for text, markers,
  toasts, sounds and summaries. They cannot settle orders or award money.
- HUD and Capture read typed frozen GameSnapshot values, not a mutable gameplay
  object. A dictionary copy cannot change the snapshot or owner state.
- Balance Resource data centralizes pay, tip, goal/strikes, interaction ranges,
  deadline tuning and movement/exit thresholds. It is configuration, not run state.
- A ticket closes and commits all counters/cargo before settlement/timeout
  signals. Reentrant/conflicting requests reject. Generation/order guards and a
  closed-run flag prevent pending old work from creating another ticket after
  a restart or session end inside an event callback.

## Files and ownership

`docs/ARCHITECTURE.md` contains the ownership table, dependency diagram, exact
APIs, signal payloads and lifetime/transaction rules. Implemented owners under
`scripts/services/`:

| File | Ownership |
| --- | --- |
| balance.gd + data/balance.tres | Immutable-by-contract tuning |
| session_service.gd | Flow, generation and modal reason set |
| order_service.gd | Ticket state, current cargo, deadlines and current shift ledger |
| actor_controller.gd | Actor mode, body/movement/exit and camera handoff |
| world_registry.gd | Scene references, validation and destination identity |
| game_snapshot.gd | Typed frozen read model; primitive/value fields only |
| presentation.gd | Derived HUD/marker/result/toast effects |
| sound_presenter.gd | Scene-local audio adapter |

Other changes: Game composition/compatibility facade, HUD snapshot supplier,
player cargo getter, SessionInput public commands, Capture typed reads/stable-ID
orders, `tools/dev_fixture.gd`, `tools/phase03_checks.gd`, full suite integration,
scenario plans, README and scenario documentation. Phase 01/02 uncommitted work
is preserved. No tracked generated assets/audio/historical shots were changed.

## Contracts for the next phase

Public Game commands are `start_shift() -> bool`, `interact()`, `restart()`,
`force_destination(id: String) -> bool`, `set_order_seed(value: int)`,
`open_modal(reason: StringName) -> bool`, `close_modal(reason) -> bool`, and
`get_snapshot() -> GameSnapshot`. Compatibility underscore methods and legacy
State/getter fields remain for isolated old fixtures; they delegate to real
owners and do not hold duplicate run state.

OrderService signals `ticket_created`, `picked_up`, `settled`, `timed_out`,
`shift_ended` each carry a read-only Dictionary: generation, order_id,
destination_id, outcome, pay, money, deliveries, strikes, pizzas, cargo_count.
Settle/expire accept expected generation and ticket ID. Signal consumers must
not infer an old ticket's identity by reading a newly created ticket later.

SessionService.changed carries immutable flow, generation, paused and outcome.
`open_modal` / `close_modal` affect only their own named reason. The input owner's
Esc toggles user_pause. Do not make the whole Game always-processing. Session
exit clears inherited tree pause; reset prepares orders/actors before publishing
the new generation. Services/signals are created once per Game and reused on
reset; scene destruction removes them. No global managers retain live pointers.

Stable destination ID format is the validated unique address string, e.g.
`2 Marinara Way`. It does not depend on scene child order. New correctness plans
use `order.destination_id`. The old `order.index` remains a compatibility adapter
through WorldRegistry.legacy_id. Order RNG choices are now sorted by stable ID,
so pre-Phase-03 unforced destination traces may differ; fixed seed/event-order
replays are deterministic within the new contract. Forced index semantics remain.
Ticket identity is generation plus monotonic order_id within a service lifetime;
future persistence must use stable IDs, not Nodes or numeric child positions.

HUD receives only a Callable returning GameSnapshot. Snapshot fields include all
Phase 02 diagnostics plus generation, session_mode, actor_mode, order_lifecycle,
HUD text/waypoints and actor_position. The internal value dictionary is read-only;
to_dictionary returns an isolated copy for JSON compatibility. New code should
not mutate services via Game aliases. Explicit developer-only injection belongs
in `tools/dev_fixture.gd` / isolated physics fixtures, never HUD or ordinary input.

Pip's `cargo_source` points to OrderService; carrying is a getter. Per-package
physical cargo remains Phase 08. CameraRig still implements the original chase/
orbit behavior; ActorController supplies target and driving state. Phase 04 can
extend that boundary without reintroducing session/order state into the rig.

## Validation evidence

Engine: Linux Godot 4.6.3.stable.official.7d41c59c4; Python 3.12.14. From
`/workspace/Paperish`, source `/workspace/.paperish-env/activate.sh` here first.

```sh
python3 tools/run_checks.py --output /workspace/.paperish-env/phase03
```

The full 27-command Phase 02 suite passed after each extraction stage:
- Orders: `/workspace/.paperish-env/logs/phase03-orders.log`
- Session/actor/world: `phase03-session-actors.log`
- Presentation/typed snapshots: `phase03-presentation.log`

The final expanded suite passes **28 command checks**, including **137 core
assertions** and **44 Phase 03 service assertions**, seed 20261018 and all seeded
logical replay comparisons. Baseline startup/town/art checks and all deliberate
failure/cleanup cases pass. The only five engine ERROR lines in the isolated
Phase 01 negative fixture are expected world-contract diagnostics; no unexpected
engine/script errors or resource leaks remain.

Final suite evidence:
`/workspace/.paperish-env/phase03/suite-1792270376983802148-6849/`
with command logs, fresh reports, fixtures and summary.json. Console log:
`/workspace/.paperish-env/logs/phase03-final.log`.

The 44 service assertions verify: duplicate-start rejection; immutable snapshots
and copy isolation; independent flow/order/actor modes; two nested modal owners;
frozen deadlines and controls; consistent HUD/marker/order identity; authoritative
cargo; immutable committed settlement and reentrant settle/timeout rejection;
stale generation rejection; stable-ID lookup after registry reordering; three
fresh scene lifetimes with exactly one connection per presenter/actor/test
subscriber; reset without duplicate subscriptions; restart inside settlement
cancelling next-ticket work; result inside settlement cancelling pending work.

Rendered regression also passed using the existing Xorg dummy display/Mesa
llvmpipe:

```sh
DISPLAY=:91 LIBGL_ALWAYS_SOFTWARE=1 godot --audio-driver Dummy --rendering-method gl_compatibility --path . -- --capture-plan=res://tools/plans/playfast.json --capture-output=/workspace/.paperish-env/phase03-rendered
```

Nine assertions passed, one delivery paid $22, cargo cleared and the next ticket
was created. Two 1280x720 PNGs were independently decoded/verified as nonempty:
`/workspace/.paperish-env/phase03-rendered/playfast-6645-12610505/`.
Log: `/workspace/.paperish-env/logs/phase03-rendered.log`. The virtual driver emits
one V-Sync capability warning; no rendering/script error occurred. Historical
screenshots were not overwritten.

`git diff --check` passes. No authoring generators changed, so world regeneration
was unnecessary. The updated project-config generator still has its Phase 01
keyboard-device fix; this phase adds no actions requiring generator changes.

## Known defects / incomplete acceptance items

No required Phase 03 acceptance items remain. Manual navigation, full-shift
balance and audible output remain untested by teleport fixtures. The original
camera obstruction behavior is unchanged and belongs to Phase 04. Later authored
interactions, physical cargo and world expansion are not represented as finished.
The Windows 4.7.2 executable remains unavailable/unverified in this environment.

## Player controls and documentation

No new player controls. Esc pause/resume and paused/result R restart retain
Phase 01 behavior. Internal modal reasons now compose safely. Architecture and
migration notes: `docs/ARCHITECTURE.md`; developer schema: `tools/SCENARIOS.md`.
Balance edits belong in the shared Resource; no asset regeneration is needed.

## Next phase entry point

Phase 03 is complete. The user requested ending the turn at this phase's
completion; Phase 04 has not been started. Read its prompt and architecture guide
before extending camera control, using SessionService modal reasons to freeze
simulation and ActorController for target/control handoff. Preserve the fast
regression and typed read-model contracts.
