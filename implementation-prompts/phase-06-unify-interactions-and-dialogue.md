# Phase 06 — Unify interactions and dialogue
Read shared rules and 03–05 handoffs. Build the reusable system needed by shop staff and customers.

## Result
One validated interaction target drives both the prompt and the action. People can hold short conversations with choices while input and game time behave predictably.

## Milestone A — Interaction selection
Replace duplicated distance-only logic in the old _context/_try_pickup_or_deliver with an explicit interactable interface/component. Each target exposes stable ID, action label, enabled state, priority and interaction anchor. Query nearby candidates and validate range, line of sight, facing/access and actor mode. Wall/floor queries must exclude the actor without ignoring buildings.

Resolve ties deterministically; a customer handoff, cargo door and driver door should not randomly compete. Prompts explain relevant blocked reasons such as Stop the van, Wrong order, Counter closed or Hands full. Revalidate at action time to prevent stale prompts. Holding/repeated E must not trigger twice, skip an entire conversation or deliver while a menu consumes input.

## Milestone B — Dialogue
Add data-authored dialogue with speaker ID/name, text, portrait/color/icon if useful, choices, conditions and explicit effect commands. Use stable node IDs and validate references before play. Keep effect commands whitelisted (set flag, start order, complete objective), not arbitrary executable code in text.

Implement readable dialogue UI with speaker, advance/skip current typewriter, choices, subtitles/text speed and controller navigation. One confirm first reveals a partial line, the next advances. Consume the triggering interaction input. Freeze gameplay deadlines/AI via the modal reason system. Cancel behavior must be authored: optional chatter can close; transaction-critical choices must leave state unchanged until committed.

## Milestone C — Transactions and examples
Create at least three functional examples: shopkeeper greeting, customer door response and ambient optional conversation. These may use current characters/placeholders until NPC phase, but must run in the world. Dialogue must emit a single committed result so a cancelled choice cannot grant a reward or remove cargo. Track busy target and conversation session generation; handle target deletion/reload gracefully.

Add validation for missing dialogue nodes, duplicate IDs and choice paths with no valid exit. Preserve developer scenario hooks through a public interaction adapter.

## Acceptance
Cannot pick up or deliver through a wall; accepted target matches prompt. A press opens one dialogue, not open-and-advance. Cancel causes no payout/item loss. Reopening a completed reward conversation cannot pay twice. Pause/settings nested over dialogue do not resume the world early. Long lines, large text and controller-only choice selection work. A deleted target closes safely. Run baseline/core suite plus one conversation transaction test.

Handoff includes interaction interface, selector priorities, dialogue schema/effect commands, modal policy and example content paths. Do not write the full campaign yet; phase 18 uses this system.
