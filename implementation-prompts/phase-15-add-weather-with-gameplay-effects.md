# Phase 15 — Add weather with gameplay effects
Read rules and 14 handoff. Weather must change decisions and atmosphere while remaining fair.

## Result
Clear, cloudy, rain and fog states transition smoothly. Rain affects stopping/grip/food exposure; fog affects visibility and route choice. A heavier storm variant can be an authored story/event condition, not constant random punishment.

## Milestone A — Weather authority
Create data profiles with visual state, duration range, transition duration, light/fog/audio parameters and bounded gameplay modifiers. Seed weather separately from orders/decor. Blend continuous values; switch discrete hazards at documented thresholds with cooldowns. Provide forecast/current-weather UI before job acceptance.

Use phase 14 environment composition. Avoid two services overwriting sun/fog every frame. Time and weather advance only with simulation; UI forecast remains responsive in pause. Author overrides take precedence with a clear expiry/restore policy.

## Milestone B — Presentation
Add efficient localized rain particles, wet road appearance/puddles, roof/surface splash cues and fog. Do not spawn world-sized dense particles. Use shared material parameters/shader approach that does not mutate every unrelated material resource. Keep puddles on valid road/ground surfaces and avoid shop interiors.

Rain visibility must work from gameplay camera, not just a close-up render. Fog must not hide a pedestrian inside stopping distance. Add interior rain attenuation and sheltered areas.

## Milestone C — Mechanics and fairness
Rain modifies traction, braking and possibly carrying/slip risk through a shared surface/weather query; values are readable and bounded. Food in an uncovered carried stack degrades faster than protected van cargo; insulated protection is an upgrade later. Fog encourages slower travel and headlights, without secretly reducing deadlines.

Estimate current and likely weather cost when accepting jobs; use a safety margin for mid-delivery transitions. During active jobs, abrupt severe weather must either ramp slowly enough to adapt or grant explicit grace/alternative completion. Tutorial introduces rain gently. Do not combine unseen fog obstacles with instant-failure cargo damage.

## Acceptance
Seeded clear -> cloudy -> rain -> clear and fog transitions have no visual pops or lingering particle/audio leak. Dry/wet braking tests show measurable, documented differences. A covered box fares better than exposed cargo under equal conditions. Fog route is drivable with visible road-edge/address cues. Entering shop hides interior rain. Pause/resume and developer time jump do not desync weather. Capture comparable street views and run core delivery scenarios under each profile.

Handoff includes weather data, blend API, modifier ranges, forecast rules, renderer costs and exact fairness policy for existing orders.
