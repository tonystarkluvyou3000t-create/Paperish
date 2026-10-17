# Phase 22 — Persist campaign and resume safely
Read rules and 18–21 handoffs. Implement robust saves using the stable IDs established earlier.

## Result
Campaign, money, upgrades, relationships and settings survive relaunch. Continue restores a coherent playable situation without duplicate rewards, vanished cargo or impossible deadlines.

## Milestone A — Save design
Define a versioned schema with save metadata, chapter/objective IDs, story flags/choices, ledger/balance, purchased upgrade IDs, relationship/discovery progress, tutorial state, day/time/weather and meaningful run state. Settings remain separate. Never serialize raw Nodes/Resources through unsafe object decoding or store child indexes as identity.

Choose explicit checkpoints: before/after authored missions and settled deliveries, plus save-and-return at safe moments. Support active-run resume by storing order IDs, remaining active seconds, package ownership/condition, player/van transforms and active event state. If some scene/modal states cannot be safely snapshotted, close/commit/cancel them through a documented transition before saving; never quietly discard paid-for cargo or mission progress.

Do not simulate wall-clock offline deadline decay. Reconstruct nearby traffic/pedestrians from population rules rather than storing every transient physics body.

## Milestone B — Atomic writes and restore
Write to a temporary file, validate it, then atomically replace the active slot where supported; retain a backup. Validate ranges, types, IDs, duplicates, version and impossible ownership. Fail gracefully on corrupted/unknown-newer schema without overwriting the only good copy.

Restore in order: configuration/world registry -> progression/story -> time/weather -> orders/cargo -> actors/events -> UI/control. Delay signal-driven rewards until hydration is complete. Validate restored transforms against current geometry and use nearby safe recovery anchors if necessary. Revalidate routes/deadline fairness when topology changed.

Provide at least one real migration path/fixture and a clean handling policy for removed content IDs. Idempotent transaction IDs prevent re-awarding a delivered mission on load.

## Milestone C — UI and recovery
Enable Continue only for a valid save, show chapter/time metadata, and make New Game overwrite confirmation clear. Provide retry backup/recover-to-checkpoint options on corruption. Surface save errors without pretending success. Avoid writing every physics frame. Save-and-return from pause must finish the snapshot before changing scene.

## Acceptance
Relaunch after first delivery, mid-campaign choice, upgraded van and finale; all expected state survives. Resume with boxes in van and remaining deadline, with no offline decay or duplicate money. Test failure/retry, restore after changed safe spawn, corrupt/truncated file, missing IDs, future version and simulated interrupted write using fixtures. A bad save cannot destroy its backup. Nested dialogue/pause save behavior follows policy. Run full regression suite.

Handoff: schema/version, write/restore order, checkpoints, migrations/fixtures, save paths and concrete resume evidence.
