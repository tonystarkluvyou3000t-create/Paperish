# Phase 21 — Polish sound, onboarding, and accessibility
Read rules and 20 handoff. Make the complete systems understandable and comfortable for a first-time player.

## Result
The first delivery teaches controls through play. Sound conveys place/state, and essential information remains available without relying on hearing, color or tiny text.

## Milestone A — Soundscape
Expand existing procedural SFX with distinct walking surfaces, engine load/idle, braking, cargo door, counter handoff, customer knock, UI focus/confirm, weather and district ambience. Add simple original/licensed music or a restrained procedural score with title/shop/driving/story variations. Record licenses if any.

Route master/music/SFX/ambience through real buses connected to settings. Crossfade district/interior/weather layers and duck nonessential ambience during dialogue. Avoid replaying transition sound every frame. Limit/pool voices and spatial sources; parked engine behavior should match whether the van is actually running. Stop loops on scene change/pause as appropriate.

## Milestone B — Onboarding
Implement a short first-shift tutorial: walk/look -> find staffed counter -> read/receive ticket -> load van -> drive/brake -> park/exit -> retrieve cargo -> meet customer. Each step observes real completion events and supports re-entry after retry. Avoid a long instruction wall. Display current remapped controls and one next action.

Teach map, headlights, weather quality and access hurdles when first needed later. Experienced players can skip/replay tutorial through menus without breaking story flags or granting duplicate rewards. Add contextual help in pause/journal.

## Milestone C — Accessibility
Finish controller coverage, remapping, UI scale/text size, subtitles/text speed, high-contrast objective icons, reduced camera motion, invert/look sensitivity and difficulty presets. Essential cues use shape/text plus color. Warn about deadline/food quality with visible indicators rather than sound alone. Support hold/toggle preferences for sustained actions where useful.

Remove rapid flashes and unnecessary shake. Dialogue remains readable at large scale; prompts do not disappear behind the minimap. Include a compact controls/help page explaining pickup/cargo, pause, map, orbit/free camera, weather and recovery. Accessibility settings must work on title before starting.

## Acceptance
A fresh player/test script completes first delivery without reading README and without developer teleport/autopilot. Validate every tutorial transition, skip and replay. Run muted with subtitles/visual cues; complete a delivery. Run controller-only and enlarged UI; essential menu/gameplay controls remain reachable. Change bus volume and verify affected sounds, scene transitions and pause. Inspect no clipping at small/narrow/large resolutions.

Handoff: tutorial states/events, bus layout, audio assets/licenses, accessibility coverage, remaining usability findings and actual onboarding evidence.
