# Phase 18 — Write and implement the island story
Read rules and 06–17 handoffs. Implement complete playable narrative content, not a lore document or introductory cutscene alone.

## Result
A warm three-chapter delivery story of roughly 45–75 minutes gives purpose to the island, recurring customers and escalating mechanics. Keep dialogue concise and let deliveries carry the action.

## Narrative brief
Pip helps the family pizza shop earn a place at the island's upcoming community night. Early deliveries rebuild trust, the middle chapter connects residents with conflicting needs, and a weather-hit final shift requires choosing routes and helping the town keep the event running. Avoid generic save-the-world stakes. The antagonist can be time, logistics and misunderstandings rather than an evil rival.

Create at least 12 named recurring residents with distinct voice/role, including shopkeeper, mechanic, harbor worker, market organizer and skeptical regular. Use identities authored in 12; do not replace them with disconnected quest NPCs.

## Milestone A — Story graph and authored content
Write a concise story bible and actual dialogue/quest data. Chapters:
1. **First Shift:** staffed pickup, safe van use, doorstep etiquette and first familiar customer; 3–4 short missions.
2. **Across the Island:** unlock reasons to visit all districts, batching/access/route tradeoffs, repair/help errands and a community conflict; 4–5 missions.
3. **Community Night:** dusk/rain, prepared detours, a multi-stop decision and final event delivery; 3–4 missions plus aftermath.
Implement at least 10 authored missions total with concrete triggers, locations, objectives, success/failure/retry paths and rewards.

Story uses explicit IDs/flags/objective graph. Validate references, cycles without exits and unreachable conditions. Mission triggers subscribe to order/event outcomes, not poll arbitrary HUD strings.

## Milestone B — Choices with consequences
Add at least three meaningful choices, e.g. favor a vulnerable customer's warm food over a bigger tip, help repair a public shortcut or take a faster paid job, choose final delivery sequence. Consequences change relationship/dialogue, a route resource, optional support or ending details. Do not lock the only progression path behind an unannounced earlier choice.

Write beginning/middle/end dialogue, optional character conversations and at least two distinct ending/epilogue variants. Reward effects are idempotent and branch joins remain completable. Main story can be finished on Relaxed without perfect scores or buying every upgrade.

## Milestone C — Integration
Add mission journal/objective tracking and clear main/optional distinction. Mandatory dialogue freezes food clocks. Use normal shop/cargo/customer interactions; no story-only bypass that hides broken gameplay. After finale unlock endless shifts and free roam with character aftermath.

## Acceptance
Play all chapters through actual missions once, then validate alternate major choices with targeted scenarios. Test mission failure/retry, duplicate completion signals, conversation cancellation, busy/missing NPC representation and chapter transition during an active order. Document narrative playtime actually measured; label unmeasured target time honestly. Capture chapter starts/finale and verify no placeholder dialogue or unreachable story node remains.

Handoff: story bible/data paths, flags, mission graph, choice consequences, checkpoint-ready boundaries and continuation mode.
