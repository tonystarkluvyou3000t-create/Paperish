# Phase 24 — Verify and package the complete game
Read all latest handoffs and shared rules. This is integration and release readiness, not another feature expansion.

## Result
Produce a reviewable release candidate with an honest feature checklist, runnable instructions, passed checks and clearly identified remaining issues.

## Milestone A — Requirements audit
Map every user request and pack target to implementation evidence:
- Bugs fixed with regressions; substantially larger five-district world and reachable addresses.
- NPC pedestrians and cars with crossing/junction behavior.
- Day/night, weather and actual gameplay effects.
- Orbit/zoom/chase/free camera and polished functional menus.
- Staffed pizza receiving, cargo loading/retrieval and customer dialogue.
- Story, relationships, progression, optional activity and meaningful fair hurdles.
- World detail, audio/onboarding/accessibility, save/resume and recovery.
Record actual quantities/playtime/performance; do not check a feature complete because a manager/class exists. Any unmet required acceptance item stays open and is fixed before declaring release-ready.

## Milestone B — End-to-end matrix
1. Fresh profile -> menu/options -> tutorial -> staff pickup -> cargo -> drive/park -> correct customer -> payment.
2. Full campaign through all chapters, at least one alternate major branch, retries and finale/endless unlock.
3. Multi-order route with traffic, wet night, detour/access gate, wrong-customer rejection and eventual settlement.
4. Free roam + free camera -> return -> save/title -> Continue.
5. Pause/map/dialogue/settings nesting, input remap and controller-only play.
6. Failure/timeout, blocked exit, collision, recovery, depleted funds and damaged/cold cargo.
7. Save corruption/backup, active-run resume, scene reload and late reward signal.
8. Small/narrow/large display, large UI/text, muted accessibility and reduced motion.
Use real controls for at least one representative end-to-end route and complete campaign. Automated fixtures supplement manual play; teleports do not establish route usability.

Run baseline resource checks and all phase regression suites. Fail on script errors even if an exit code is zero. Rebuild world/art in an isolated copy, import from clean cache and run again to expose hidden generated-output dependence. Check portable exports if still advertised.

## Milestone C — Packaging and documentation
Update root README with accurate install/run/build controls, modes, world/features, save paths, generation workflow, test commands and known limitations. Include credits/licenses and concise release notes. Document supported engine/render settings and minimum tested environment, not guessed compatibility.

Create or verify Godot export presets for the supported local platform and produce a distributable if export templates are available. If unavailable, keep a source-run candidate with exact missing requirement and never claim a binary was built. Gate/exclude capture/autopilot/teleport/time-jump developer features in release. Verify from a clean user profile that saves go under user:// and no absolute developer paths are required.

## Acceptance
A new user can run and finish the game using delivered instructions. Feature checklist links to evidence; all release-blocking defects are resolved. Package or source-run candidate launches outside the editor. No placeholder mission, fake menu route, unplayable address or hidden cheat requirement remains. Report tests actually run, untested platforms and any non-blocking known issues plainly.

Final handoff: release artifact paths, commands, requirement/evidence matrix, measured limits, remaining issues and one short next-step recommendation. Do not add new features during this phase unless needed to satisfy an explicit unmet requirement.
