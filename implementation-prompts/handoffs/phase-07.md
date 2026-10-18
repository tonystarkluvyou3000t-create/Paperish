# Phase 07 — Build the pizza shop handoff
Status: VERIFIED

## Implemented behavior

- Pip's Pizza has a walk-through entrance, open visual door, split front wall and frame, public queue space, service counter and warm-lit kitchen. Mona stands behind the counter and faces the entrance.
- A shift creates a PREPARING ticket. The preparation clock advances during unpaused play, freezes during dialogue/pause, and switches the shelf and HUD to READY when complete. Shelf stock matches the order quantity.
- At the counter, E opens Mona's ticket conversation. During preparation she explains the wait; when ready she identifies the order, customer, address and quantity. TAKE THE ORDER commits the handoff; NOT YET leaves it unchanged.
- The receipt transfers the ticket quantity once, updates Pip's held-box stack, hides the shelf boxes, and starts the freshness deadline. Duplicate receipts and pickup attempts are rejected.
- The customer and delivery marker remain linked to the current ticket. Restart clears the ticket, shelf state and any in-flight conversation.

## Files and ownership

- `tools/build_art.py` generates the shop shell, split doorway frame, counter, kitchen, stock, lighting and stable markers. `tools/build_town.py` assembles the rotated shop and keeps `Town/PizzaShop/PickupPoint` as a counter-approach compatibility alias.
- Generated output: `assets/pizza_shop.tscn`, `scenes/town.tscn`.
- `scripts/services/order_service.gd` owns ticket state and the preparation/freshness clocks; `scripts/services/balance.gd` owns the preparation duration; `scripts/services/world_registry.gd` resolves the shop markers.
- `scripts/game.gd`, `scripts/services/presentation.gd`, `scripts/hud.gd`, `scripts/player.gd`, `scripts/npc_placeholder.gd`, `scripts/services/dialogue_service.gd` and `data/dialogue/shopkeeper.json` connect interaction, presentation and the committed handoff.
- `tools/phase07_checks.gd`, `tools/plans/shop-handoff.json`, `tools/capture.gd`, `tools/dev_fixture.gd` and the older phase checks/scenarios cover the lifecycle and compatibility behavior.
- `README.md`, `docs/ARCHITECTURE.md` and `tools/SCENARIOS.md` document the player loop and service contracts.

## Contracts for the next phase

- `OrderService.TicketState` is `NONE`, `PREPARING`, `READY`, `COLLECTED`; `ticket_state_name()` reports the matching lowercase strings. `Lifecycle.AT_SHOP` covers both preparation and ready-to-receive states; `ON_ROUTE` begins only after receipt.
- `ticket_ready(event)` fires once when preparation reaches zero. `pickup()` accepts only a READY ticket with no cargo, changes it to COLLECTED/ON_ROUTE, transfers `pizzas` into `cargo_count`, and starts `remaining` at `duration`.
- `receipt_created(event)` is the read-only handoff contract for Phase 08. Its event includes `generation`, `order_id`, `destination_id`, `quantity`/`pizzas`, `ticket_state`, `cargo_count`, `remaining` and `duration`. `picked_up` remains for existing presentation integrations; new cargo ownership should consume `receipt_created`.
- The current prototype still represents cargo as one authoritative count and a visual stack. Phase 08 owns package IDs and counter/Pip/van/customer locations; it should preserve the single-receipt guard and atomically connect receipt to cargo creation.
- World markers are `Town/PizzaShop/CounterAccess`, `StaffStation`, `ShopEntrance` and `ReadyStock`. `PickupPoint` remains at the counter approach for compatibility. The `shop.counter` target is foot-only, near-range, facing and line-of-sight checked.
- The counter conversation ID is `shopkeeper`. Dialogue owns a modal pause; preparation and freshness clocks freeze while it is open, and only the committed ready-ticket choice may call the guarded pickup.

## Validation evidence

- Full suite: `python tools/run_checks.py --godot '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe'` — **SUITE PASS: 48 commands; logical replays match**, seed `20261018`. Evidence: `.godot/test-runs/suite-1792344324818104300-2740/`.
- `tools/phase07_checks.gd` — **40 checks, 0 failures**, including real Pip movement from the authored spawn through the doorway and back.
- Final isolated staging rebuild: `.godot/phase07-stage3/`. `python tools/build_art.py` and `python tools/build_town.py` completed there; Godot 4.7.2 editor import succeeded. Regenerated `assets/pizza_shop.tscn` and `scenes/town.tscn` SHA-256 hashes match the project outputs.
- In staging, `tools/check_town.gd` reported **0 failures** and `tools/validate_art.gd` loaded all ten asset files, verified **608 original mesh pieces**, and exited successfully.
- Rendered capture used the Forward+ renderer on the RTX 3050 6 GB laptop at the project's 1920 × 1080 default. `shop-handoff.json`, seed `20261018`, passed **7 assertions**. The four inspected images and `result.json` are in `.godot/phase07-stage3/.godot/phase07-evidence/rendered/shop-handoff-20840-1687909/`.

## Known defects / incomplete acceptance items

- No Phase 07 acceptance failures remain. A manual free-play session was not part of this verification; the captured rendered route and physics movement checks were inspected.
- Per-package cargo identity, van slots, load/unload interactions and customer package settlement are intentionally deferred to Phase 08. The receipt signal is ready to drive that work.

## Player controls and documentation

- **E** at the counter checks Mona's ticket. Wait while it is PREPARING, then choose TAKE THE ORDER to receive the shown quantity or NOT YET to leave it available.
- The gameplay ticket card shows order ID, address, customer label, quantity and PREPARING/READY/COLLECTED state. The delivery clock appears only after receipt.
- The standard **E** interaction remains in use for van entry/exit and customer delivery. Updated instructions are in `README.md` and `tools/SCENARIOS.md`.

## Next phase entry point

Read `implementation-prompts/phase-08-implement-orders-and-physical-cargo.md` and this handoff first. Start at `OrderService.receipt_created`, `Game._on_ticket_received()` and the current held-box presentation in `scripts/player.gd`. Add stable package/order identities and physical cargo locations without allowing a driver-seat transition or repeated E input to duplicate the committed receipt.
