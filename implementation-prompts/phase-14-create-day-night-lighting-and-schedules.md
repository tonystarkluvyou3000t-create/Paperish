# Phase 14 — Create day-night lighting and schedules
Read rules and 12–13 handoffs. Add a simulation clock that drives both presentation and town behavior.

## Result
The island visibly transitions through morning, noon, dusk and night. Street/shop/vehicle lights and population schedules make the change meaningful. Night remains navigable.

## Milestone A — Time authority
Implement a single TimeService exposing day index, time-of-day minutes, phase and configurable scale. Proposed default: a full world day around 24 real minutes, with story shifts using selected time windows; tune later. Separate simulation time, active delivery seconds and UI animation/wall time. Pause/map/dialogue/free-camera must freeze relevant clocks/AI consistently.

Emit phase/schedule boundary events without checking equality of floating timestamps. Crossing midnight or a large simulated step must process due events once. Developer time jumps are explicit and disabled in release.

## Milestone B — Lighting
Compose sun direction/color/intensity, ambient/fill, sky/background and fog across smooth keyframes. Add moon or low-cost night fill. Streetlights, porch/shop lights, windows and headlights switch with hysteresis/fades; do not oscillate at a threshold.

Use a bounded set of real nearby lights plus emissive distant lamps. Respect Compatibility renderer support. A decorative yellow lamp mesh alone does not light a road. Night camera exposure/contrast must keep pedestrians, road edges and address numbers readable without flattening the whole scene to daylight.

Centralize environment output so the upcoming weather service contributes modifiers rather than fighting sun/environment property writes.

## Milestone C — Daily life
Map NPC routines to home/work/leisure anchors and business hours. Define customer/order availability without invalidating an already accepted ticket just because closing time passes. Traffic density changes between commute, normal and late hours. Shop closing policy is explicit: accepted orders remain completable or are compensated, never silently deleted.

Add a compact clock and optional district/business status on the map. Tutorial starts in stable clear daylight; story can select dusk/night later.

## Acceptance
Capture the same street at dawn/noon/dusk/night and a drivable night delivery. Run accelerated full-day cycles and midnight transitions: no repeated schedule rewards, vanishing active customer or exploding population. Pause for several real seconds and verify clocks/AI stay aligned. Existing order deadline uses active seconds rather than accidentally multiplying by world-day scale. Inspect light counts and frame cost at night.

Handoff: time units/API, default scale, schedule schema, opening-hours/accepted-order policy and environment composition interface for weather.
