# Phase 06 — Unify interactions and dialogue
Status: VERIFIED

## Implemented behavior

- A single `InteractionService` registry now supplies both the HUD prompt and
  the action accepted by `Game.interact()`. Each target has a stable ID, anchor,
  optional access point, range, priority, eligibility, blocked reason and action.
  Selection rechecks actor mode, range, line of sight, facing and anchor
  validity, and resolves ties deterministically.
- The shipped targets are `shop.counter`, `house.customer`, `van.driver`,
  `van.seat` and `plaza.gossip`. The prompt and activation cannot select
  different targets. Wall geometry blocks interactions; actors and vehicles do
  not occlude them. Blocked targets can explain states such as `HANDS FULL`,
  `WRONG ORDER`, `COUNTER CLOSED` and `STOP THE VAN TO EXIT`.
- `DialogueService` loads and validates JSON conversations with stable node
  IDs, conditional entry nodes, choices, explicit effects and whitelisted
  commands. The current examples are Mona's shop pickup, the customer handoff
  and Nino's optional tip. Tokens render order data into lines and choice labels.
- Dialogue owns a session and busy target, consumes the opening press, supports
  typewriter reveal/skip, keyboard and focus-based choice navigation, optional
  cancellation, and `dialogue` modal pause ownership. Menus can stack above it;
  closing another modal does not resume the world while dialogue still owns a
  pause reason. Effects run only at authored commit nodes, so cancellation and
  replay do not grant cargo or pay twice.
- Placeholder people are authored in the scene with no collision. Each new
  `ticket_created` event places the customer at that ticket's house; this also
  covers tickets created inside order settlement, not only the first ticket of
  a shift.

## Files and ownership

- `scripts/services/interaction_service.gd` owns target registration, query,
  ranking, prompt data, activation and refusal signals.
- `scripts/services/dialogue_service.gd` owns dialogue loading/validation,
  conditions, flags, session generation, node flow and committed effects.
- `scripts/ui/dialogue_screen.gd` and `scripts/ui/menu_layer.gd` own the readable
  conversation panel, choices and modal focus; `scripts/session_input.gd`
  routes the interact/back actions.
- `scripts/game.gd`, `scripts/services/presentation.gd`, `scripts/hud.gd` and
  `scenes/game.tscn` wire the systems, publish the selected prompt and add the
  placeholder people. `scripts/npc_placeholder.gd` supplies their simple
  current visuals.
- `data/dialogue/{shopkeeper,customer,gossip}.json` holds the three examples.
- `tools/check_dialogue.gd`, `tools/phase06_checks.gd`,
  `tools/plans/dialogue.json`, `tools/capture.gd`, `tools/dev_fixture.gd` and
  `tools/run_checks.py` add validation, regressions, scenario support and suite
  integration. `tools/plans/playfast.json` and `playtest.json` now exercise the
  interaction flow. `tools/phase01_checks.gd` and `phase03_checks.gd` keep their
  synthetic-input and service assertions aligned with the current contracts.
- `tools/phase04_checks.gd` pins camera preferences for its camera-specific
  checks so the user's persisted sensitivity cannot change the expected look
  delta. `README.md`, `docs/ARCHITECTURE.md` and `tools/SCENARIOS.md` document
  the new systems.

## Contracts for the next phase

- `InteractionService` is a `Node` configured with the `WorldRegistry`,
  `ActorController` and `DialogueService`. Its public methods include
  `register(entry)`, `unregister(id)`, `clear()`, `ids()`, `entries()`,
  `select()`, `prompt()`, `prompt_view()`, `prompt_id()`, `activate()` and
  `available()`. `activated` and `refused` emit dictionary event payloads.
- `DialogueService` loads `res://data/dialogue/*.json`. Top-level content uses
  `id`, `speaker`, `cancel`, `entry` and `nodes`; nodes use `id`, `text`,
  `next`, `choices`, `effects` and `commit`; choices use `label`, `next` and
  `effects`. Conditions currently support flags, cargo, deliveries, lifecycle
  and mode. Effects support flags, toasts and order commands. Bound order
  commands are `pick_up` and `deliver`; do not put executable code in dialogue
  files. `validate_set()` reports duplicate IDs, bad references and invalid
  exits before conversations are used.
- `DialogueService` signals `opened`, `updated` and `closed`; the public flow
  includes `load_all()`, `bind_command()`, `start()`, `advance()`, `choose()`,
  `cancel()`, `reset()`, `active()` and `snapshot()`.
- The current counter command calls `OrderService.pickup()` at the committed
  dialogue node. Phase 07 should replace the immediate pickup with the ready
  ticket and physical handoff flow while keeping `shop.counter` as the public
  interaction ID and preserving the modal/cancel transaction rules. Phase 08
  can consume the resulting receipt/cargo events.
- Customer placement follows `OrderService.ticket_created`; future ticket
  services should keep that signal after their transaction has committed.

## Validation evidence

- Full command: `python tools/run_checks.py --godot '.\\godot-engine\\Godot_v4.7.2-stable_win64_console.exe'`
- Result: **SUITE PASS — 45 commands**, seed 20261018. Phase 06: 177 checks,
  0 failures; Phase 01: 136/0; Phase 03: 44/0; Phase 04: 58/0; Phase 05: 251/0.
  Dialogue data/world checks, both dialogue and delivery plans, deterministic
  replays, and all expected-failure fixtures passed.
- Logs: `.godot/test-runs/suite-1792341148135815600-13580/`.
- Rendered command:

  ```powershell
  & '.\\godot-engine\\Godot_v4.7.2-stable_win64_console.exe' --audio-driver Dummy --path . --quit-after 30000 -- --capture-plan=res://tools/plans/dialogue.json --capture-output=res://.godot/phase06-evidence
  ```

- Rendered Forward+ on the NVIDIA GeForce RTX 3050 6GB Laptop GPU. Inspected
  `.godot/phase06-evidence/dialogue-21320-5184697/dialogue_counter.png` and
  `dialogue_door.png`; the centered panel, speaker color, text and action hints
  remain legible over the 1080p world. The screenshots intentionally catch the
  typewriter while it is revealing the opening line.

## Known defects / incomplete acceptance items

- The acceptance checks pass. The three people are static visual placeholders
  without collision; Phase 12 replaces them with the pedestrian system.
- Long-line and 150% UI scaling are covered by headless layout assertions; no
  physical controller session or human play session was run.
- Full campaign dialogue and narrative content remain Phase 18 work.

## Player controls and documentation

- Existing **E / Interact** opens the nearby target and then advances or skips
  the current line. Keyboard/controller focus selects choices; mouse selection
  remains available. **Esc** closes cancellable chatter; on the transactional
  shop conversation it opens the pause menu above the chat without cancelling
  the order.
- No new input actions were added.

## Next phase entry point

Phase 07 builds an enterable shop interior and a staffed, ticket-aware pickup.
Start with `implementation-prompts/phase-07-build-the-pizza-shop-handoff.md`,
`tools/build_art.py`, `tools/build_town.py`, `scripts/game.gd`,
`scripts/services/dialogue_service.gd`, `data/dialogue/shopkeeper.json` and the
shop/counter checks. Preserve `shop.counter` as the interaction target, replace
its immediate `pick_up` commit with the ready/collected ticket transaction,
and keep the countdown from starting before the player receives the boxes.
