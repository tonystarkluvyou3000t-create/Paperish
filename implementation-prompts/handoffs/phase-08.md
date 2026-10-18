# Phase 08 — Implement orders and physical cargo
Status: VERIFIED

## Implemented behavior

- Mona can queue up to three active orders. Orders have stable run-local IDs, destination IDs, quantity, preparation state, independent deadlines and immutable event payloads. The default shift still starts with one ticket.
- Each pizza receives a stable package ID (`g{generation}-o{order}-p{index}`) and one authoritative location: counter, Pip, van, customer or discarded. Pip carries three boxes by default; the van has six numbered slots.
- E at the van's rear cargo door moves one whole selected bundle between Pip and a van slot. The driver interaction remains separate. Tab cycles van-held bundles. The HUD shows ticket addresses, quantities, locations and occupied slot count.
- Delivery requires the matching order, full package quantity in Pip's hands, a live deadline and the correct customer. Wrong-address dialogue has no order effect. Settlement transfers boxes to the customer and credits itemized base, per-pizza, tip and quality amounts once.
- Expiry discards the full bundle, frees van capacity and adds one strike. Repeated expiry/settlement and stale generations cannot double-pay or double-strike. Dialogue freezes the deadline; restart clears package records.
- A complete staff pickup → load → drive → safe exit → unload → correct-door dialogue → payment route passes with ordinary walk/drive actions and without actor teleports or autopilot.

## Files and ownership

- `scripts/services/cargo_service.gd` owns package records, bundle lookup, capacity/slot reservation, physical locations, visuals and global cargo invariants. `OrderService` owns per-order lifecycle, preparation/freshness, expiry and settlement.
- `scripts/game.gd` connects the counter, cargo-door, driver, customer and wrong-address interactions. `scripts/hud.gd`, `scripts/services/game_snapshot.gd`, `scripts/services/presentation.gd` and `tools/capture.gd` expose inventory and payment data.
- `scripts/services/balance.gd` defines the default queue/carry/van limits, route estimate fallback and pay/quality settings. `tools/setup_project.gd` adds Tab as `cargo_cycle`; `project.godot` is regenerated from it.
- `data/dialogue/shopkeeper.json` adds queue-ticket dialogue; `data/dialogue/wrong_address.json` is a non-committing address refusal. `tools/check_dialogue.gd` validates it.
- `tools/build_art.py` generates the rear hatch/rack appearance; generated output is `assets/pizza_van.tscn`.
- `tools/phase08_checks.gd` covers transactions and invariants; `tools/phase08_route_checks.gd` covers the physical delivery path. `tools/plans/cargo-handoff.json` and `tools/capture.gd` provide rendered cargo evidence. `tools/run_checks.py` runs all Phase 08 acceptance checks and deterministic capture replay.
- `README.md`, `docs/ARCHITECTURE.md`, `tools/SCENARIOS.md` and this handoff document player controls and ownership.

## Contracts for the next phase

- `OrderService.Lifecycle`: `IDLE`, `AT_SHOP`, `ON_ROUTE`, `CLOSED`. `TicketState`: `NONE`, `PREPARING`, `READY`, `COLLECTED`. Public order APIs include `create_ticket`, `queue_ticket`, `can_queue`, `pickup_order`, `select_order`, `order_data`, `outstanding_order_ids`, `settle_order`, `expire_order`, `tick`, `tip` and `close`.
- `CargoService` locations are `counter`, `pip`, `van`, `customer`, `discarded`. Core APIs: `create_order`, `package_ids`, `location_for_order`, `count_for_order`, `transfer_order`, `settle_order`, `discard_order`, `select_next_van_order`, `van_order_ids`, `inventory_lines` and `invariant_errors`. `changed(event)` contains action/order ID and aggregate counts.
- `OrderService` events `ticket_created`, `ticket_ready`, `picked_up`, `receipt_created`, `settled`, `timed_out` and `shift_ended` are read-only dictionaries. Settlement keys include `base_pay`, `pizza_pay`, `tip_pay`, `quality_adjustment` and `settlement_total`.
- `Game` owns stable destination lookup through `WorldRegistry.ids()` and `destination(id)`. `OrderService.route_estimator` calls `Game._estimate_route_seconds(destination_id)` when admitting a ticket. Replace that Euclidean-distance × 1.55 / 4.2 m/s + 8 s fallback with Phase 09 directed-road costs, while preserving explicit rejection for disconnected routes.
- `cargo_cycle` defaults to Tab and is accepted only on foot at the rear cargo access point. Existing `van.driver`, `van.seat`, `house.customer[.NN]` and address-door targets remain independent.
- `GameSnapshot` and the capture schema expose `order_count`, `cargo_inventory`, `van_cargo_count` and `van_capacity` in addition to `cargo_count` and `order_pizzas`.

## Validation evidence

- Full suite command: `python tools/run_checks.py --godot '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe'` — **SUITE PASS: 52 commands; logical replays match**. Evidence: `.godot/test-runs/suite-1792347628811839600-10196/`. Includes 51 Phase 08 transaction checks, the 20-check physical route, two cargo-handoff replays and the existing suite.
- Standalone route command: `& '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe' --headless --audio-driver Dummy --path . --script tools/phase08_route_checks.gd` — **20 checks, 0 failures**. The test starts at authored spawns, moves Pip with `move_forward`, and drives with throttle/steer/brake actions. It does not call `Fixture.place`, `autopilot`, or set actor positions.
- `tools/build_art.py` ran from isolated staging folder `.godot/phase08-stage/`. SHA-256 hashes for all five generated assets and `scenes/pizza_corner.tscn` match the working tree; only `assets/pizza_van.tscn` differs from the Phase 07 baseline, as intended.
- Rendered command: `& '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe' --audio-driver Dummy --path . -- --capture-plan=res://tools/plans/cargo-handoff.json --scenario-seed=20261018 --capture-output=.godot/phase08-final` — **6 assertions passed** on Forward+ / NVIDIA RTX 3050. Inspected `van-cargo-loaded.png` and `van-cargo-retrieved.png` under `.godot/phase08-final/cargo-handoff-26000-1734305/`.
- `git diff --check` is clean.

## Known defects / incomplete acceptance items

- Phase 09 must replace the current Euclidean route estimate with graph distance, legal vehicle entry and explicit unreachable-address handling. This is the documented next integration point, not a completed graph feature.
- The rendered cargo-handoff plan uses a teleport to compose the cargo screenshots. It is visual evidence only; the separate route check is the no-teleport/no-autopilot navigation evidence. A human free-play session was not recorded.

## Player controls and documentation

- **E** at Mona's counter checks/accepts a ready ticket; a queue offer appears after receipt when capacity allows.
- **E** at the van rear loads Pip's selected held bundle or retrieves the selected van bundle. **Tab** cycles orders at the rear cargo door. **E** at the driver door/seat enters or exits when stopped.
- **E** at the matching customer's door opens delivery dialogue. Incorrect addresses leave cargo and payment unchanged.
- The ticket list shows active order ID, address, quantity, location and occupied van slots. README and architecture documentation now explain the capacities, timeout policy and settlement formula.

## Next phase entry point

Read `implementation-prompts/phase-09-author-world-and-road-graphs.md`, `implementation-prompts/handoffs/phase-03.md` and this handoff. Start by adding source-authored district/segment/junction/address records and a validated `WorldRegistry` lookup. Then adapt `Game._estimate_route_seconds` and route consumers to the graph without changing order IDs or cargo ownership. Preserve the deterministic capture and full physical route checks.
