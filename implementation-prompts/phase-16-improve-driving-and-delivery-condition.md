# Phase 16 — Improve driving and delivery condition
Read rules and 08/13–15 handoffs. Improve the arcade van; do not replace it with a fragile full racing simulator.

## Result
Smooth driving protects pizza quality, sensible braking matters in rain, and collisions have consistent recoverable consequences. The player can understand what went wrong.

## Milestone A — Handling
Separate requested speed/steering, actual velocity/contact response and presentation. Add tunable acceleration/reverse/braking curves, speed-sensitive steering, mild tire grip and safe handbrake behavior. Keep low-speed parking easy. Preserve predictable controls and physics delta independence.

Apply weather/surface grip through one query and a bounded handling modifier; avoid multiplying friction repeatedly each frame. Use signed travel direction for impacts and actual contact speed for damage. Differentiate a gentle scrape, hard collision and persistent resting contact. Debounce per contact so one wall does not charge damage every physics tick.

## Milestone B — Pizza and van condition
Give each order a quality/temperature score derived from time, exposure and significant handling incidents. Keep causes distinct: freshness, rain exposure and rough handling. Van-stored cargo has protection; held cargo reacts only to meaningful events. No random pizza damage unrelated to player action.

Add readable feedback: quality icon/text, a short cause toast, impact sound and optional reduced-motion camera response. Payment explains base + tip and condition adjustment. Avoid a hidden formula that surprises the player at delivery.

Add light vehicle wear/repair as a recoverable layer. No arbitrary total-loss softlock: if the van cannot proceed, offer roadside recovery/service with transparent cost/time, and a forgiving tutorial/free-roam policy. Upgrades arrive in 19; leave clean modifier hooks.

## Milestone C — Parking skill
Add optional safe-parking bonuses when stopped in a legal near-customer bay without blocking traffic. Require low speed, adequate alignment and real proximity; do not demand pixel-perfect parking for normal delivery. Parking can give advantage while walking remains viable. Add headlights/brake/reverse indicators and visible cargo door state.

## Acceptance
Measure dry/wet stopping distance at two speeds; compare low/high-speed turning. Reverse wall collision, slow scrape and hard frontal impact produce sensible distinct results. A single sustained contact cannot drain money/quality repeatedly. Smooth and reckless runs of the same seeded order have explainable pay differences. Roadside recovery preserves cargo and cannot be exploited for free route skipping. Controller and keyboard both park successfully. Run traffic collision regressions and capture feedback.

Handoff: handling config/modifier order, incident event schema, quality formula, payment breakdown and repair/recovery policy. Include measured results rather than claims of realistic physics.
