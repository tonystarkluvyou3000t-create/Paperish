# Phase 20 — Enrich world art and animation
Read rules and 10–19 handoffs. Polish the now-functional game while preserving performance and generator ownership.

## Result
Each district feels inhabited and distinct at driving speed and on foot. Add purposeful detail with consistent collision/visual language.

## Milestone A — District identity
Define a compact art direction sheet using existing cream/ivory, teal/mint, brick red and gold palette. Downtown gets shop awnings/posters/stacked roofs; residential gets gardens/mailboxes/porches; harbor gets boats/crates/moorings; hillside gets terraces/retaining walls/overlook; market/workshop district gets stalls/signage/loading bays. Use silhouette/material variation without noisy random recoloring.

Add street-name signs, visible address plaques, curb/crossing markings and landmark sightlines. Place detail where routes and camera reveal it, not only in aerial beauty shots. Hide repetitive lot patterns with purposeful frontage/roof variations. No new prop blocks a validated route, staff interaction or camera.

## Milestone B — Feedback and animation
Improve Pip's walk/carry/turn, van enter/exit/cargo handling, staff handoff and customer receive/thank gestures. Simple procedural animation is acceptable if readable. Ensure three-box stacks do not intersect body/door and effects match authoritative transfer timing.

Add subtle environmental motion: flags/awning sway, gentle water movement, oven smoke and occasional birds. Weather intensity modifies appropriate motion. Night windows/shop signs gain emissive life. Delivery completion gets its own short-lived visible effect rather than flashing a marker hidden immediately by the next order.

Use modest road wear, puddles, planted patches, benches/bins and market clutter. Classify each prop as solid, traversable decoration or interaction object; visible fences/large crates should not behave inconsistently.

## Milestone C — Efficient presentation
Batch repeated static meshes/materials with MultiMesh or merged district pieces where appropriate. Keep interactable/collider identity separate from rendered batching. Use distance visibility and lightweight variants. Do not optimize by removing all readable landmarks at normal route distance. Ensure lighting/material changes work in the project's Compatibility renderer and do not require a silent renderer switch.

## Acceptance
Capture comparable daylight/night/rain views in every district plus close-up receiving/cargo/customer sequences. Traverse crowded market and shop after regeneration: no blocked route or clipping regression. Check visual transfer matches package ledger. Compare measured node/draw/frame costs with phase 10 baseline. Reduce motion setting suppresses decorative/camera motion appropriately. Generator rebuild reproduces all permanent art changes; portable GLBs updated or their documented legacy purpose retained.

Handoff: art generation paths, material/mesh budgets, collision classifications, animation hooks and representative visual evidence. Do not spend this phase on unrelated photorealism.
