# Phase 17 — Create fair delivery hurdles
Read rules and 11–16 handoffs. Add genuine difficulty through route/access decisions, not just a shrinking timer.

## Result
Players encounter telegraphed challenges with viable responses: detours, busy streets, weather exposure, access puzzles and delivery prioritization. They can improve through knowledge and skill.

## Milestone A — Encounter framework
Define data-authored event IDs, location/region, prerequisites, warning, active duration, affected graph edges, completion/failure conditions, reward/consequence and cooldown. Maintain an event director budget that limits concurrent difficulty and excludes incompatible combinations. Separate optional encounters from mandatory story encounters.

On activation, verify at least one valid route and a feasible remaining deadline for accepted orders. If no safe path remains, postpone event or offer explicit grace/reroute/cancel-without-penalty. Update maps/AI through graph events. Never spawn a barrier across the van's current stopping envelope.

## Milestone B — Implement at least six encounters
1. Signed roadworks closing one route but preserving a marked alternate.
2. Congested market street where parking early and walking is faster.
3. Brief crossing/school-zone-style pedestrian surge with clear slow cues.
4. Gated apartment/courtyard delivery with an intercom/code clue in the ticket or dialogue.
5. Fragile large order favoring smoother roads over a risky shortcut.
6. Wet waterfront job with covered footpath versus exposed shorter route.
Use existing town facts rather than isolated minigame overlays. Add at least one voluntary rush/batch order with clearly stated risk/reward. Encounters must teach one concept before combining them.

## Milestone C — Difficulty and recovery
Create Relaxed, Standard and Challenging presets for deadline margins, traffic density, damage penalties and event frequency. Keep world/story content accessible across presets; show rewards consistently. Standard should allow a first-time cautious player to finish normal orders; Challenging requires deliberate route and cargo choices.

Explain failure reasons, offer retry/recovery and avoid forcing a whole campaign restart after three minor mistakes. Replace the prototype's three-strike rule where necessary with shift-local consequences and story-safe retries. No economy death spiral. Save/checkpoint boundaries are handled in 22, but events must expose serializable state now.

## Acceptance
Play each encounter alone and a valid two-event combination. Demonstrate a safe successful response and an understandable recoverable failure. A road closure cannot isolate a destination or gridlock all traffic. No new event materializes under a moving van. Test expiration/cancellation of event during dialogue/pause and after restart. Record seed, estimated versus actual route time, warnings and consequences. Run one mixed-weather delivery with traffic and gate access.

Handoff: encounter catalog, director budget, graph hooks, difficulty values, anti-softlock rules and narrative integration points for 18.
