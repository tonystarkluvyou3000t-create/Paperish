# Phase 02 — Build deterministic regression checks
Read the shared rules, audit and phase 01 handoff. Implement only this phase.

## Result
A failed core interaction must fail a test, rather than merely printing a state and exiting successfully. Preserve the useful screenshot harness, but distinguish visual captures from correctness assertions.

## Inspect
tools/capture.gd, tools/check_town.gd, tools/validate_art.gd, tools/plans/*.json, README.md, and the current flow APIs. playfast historically sets its first forced destination after starting; its later order injection can affect a different delivery.

## Milestone A — Deterministic scenarios
1. Add an explicit seed option and isolated RNG ownership for orders. Inject a forced destination before the order is created.
2. Add condition-based wait steps with finite timeouts, assertions over public diagnostic state, and clear failure messages. Define a small supported schema, not arbitrary code execution in JSON.
3. Include assertion fields such as session mode, active order/destination ID, cargo count, deliveries, money, strikes, driving, paused and timer bounds. Validate unknown step names, missing keys and wrong types before running a plan.
4. Failed assertions, invalid plans and timeouts must produce nonzero exit status. Teardown releases held actions, resets time scale/pause and frees resources.
5. Keep screenshots asynchronous but awaited before quitting; headless runs skip visual capture explicitly rather than hanging on render waits.

## Milestone B — Core regression suite
Create short scenarios for pause/resume input routing, exclusive actor controls, forced repeated destination, clean restart, illegal fast exit, blocked exit, delivery-once payment, timeout-once strike and terminal autopilot cancellation. Use minimal isolated geometry for collision fixtures where useful. At least one test must send actual input through the scene rather than call the target method directly. Add a complete one-delivery smoke scenario with state assertions and one two-delivery transition scenario. Use generous bounded waits rather than machine-specific timestamps.

Upgrade check_town to verify required root nodes, spawns, valid address metadata, unique house identities and Door/Park contracts, and to fail on missing/non-PackedScene resources. Keep expected negative fixtures outside normal resources or provide a fixture parameter so the default town is never corrupted.

## Milestone C — Developer workflow
Document one command for a fast headless suite and one for a rendered smoke run. Make new evidence paths unique per run. Preserve historical images. Clarify that teleport/autopilot is a setup tool and cannot prove human driving or route reachability. Capture stderr; a zero engine exit is insufficient if script errors were logged.

## Acceptance
- Run a passing suite twice with the same seed and confirm the same logical outcomes.
- Deliberately invert one assertion in a temporary fixture; the suite exits nonzero, identifies the assertion and cleans up.
- Missing resource, malformed plan, unknown action and never-satisfied wait fail promptly.
- Main delivery smoke confirms exactly one payout, expected cargo removal and next order creation.
- A rendered capture produces a valid image; a headless assertion run does not require graphics.
- Ordinary launch without developer arguments is unaffected.

Handoff: scenario schema, suite entry point, test commands, fixed seed and real results. Avoid introducing an external test framework unless the existing Godot tools cannot meet a concrete need.
