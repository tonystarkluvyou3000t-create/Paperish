# Phase 05 — Build menus and settings
Read shared rules and 03–04 handoffs. Implement real working UI, not decorative mock buttons.

## Result
A cohesive title screen, pause screen, options and result screen support mouse, keyboard and controller. Keep the pizza-shop visual identity while making navigation clear and scalable.

## Inspect
hud.gd builds every overlay procedurally; title/pause/results contain labels, no actual buttons. The gameplay cash card remains visible behind the historical title. Keep useful HUD components but separate major menu ownership from active gameplay presentation.

## Milestone A — Navigation
Title: New Game/Start Shift, Free Roam, Options, Controls, Credits, Quit. Until campaign/save phases exist, label the current playable mode honestly; do not expose a fake Continue button. Free Roam can reuse the existing town without failure clocks, clearly distinct from shift play. Later phases extend these routes.

Pause: Resume, Options, Controls, Restart Shift, Return to Title, Quit. Confirm only actions that discard current progress; never require confirmation for Resume. Results: Retry, Next/Return as applicable, itemized earnings/strikes and a clear reason for failure. Return-to-title must reset session/controllers without leaving paused trees or leaked audio.

Use a consistent back stack and initial focus. Ensure Esc closes the top overlay and does not both close options and resume the game in the same event. Buttons need visible hover/focus/disabled states and actual action wiring.

## Milestone B — Settings
Persist preferences under user:// with sensible defaults: master/music/SFX/ambience levels, window/fullscreen, resolution or window preset, UI scale, render quality/shadows, camera sensitivity/invert/recenter, reduced camera motion, subtitles/text speed and input bindings. Hide unavailable renderer features or explain them. Include reset-to-defaults. Settings persistence is separate from future campaign saves.

Input remapping: capture keyboard/mouse/controller actions, show conflicts, allow cancel, and retain a usable menu confirm/back path. Critical movement actions cannot be silently cleared. Render prompts from current bindings rather than hard-coded E/WASD strings.

## Milestone C — Layout and accessibility
Use containers/anchors and a reusable theme. Verify 1280×720, 1920×1080, a narrow aspect ratio and a large UI/text scale. Prevent long addresses from overlapping money/timer. Hide active-run furniture on title/results unless intentionally used in summary. Avoid flashing text as the only start affordance. Add clear controller focus and restore focus after closing a subpanel.

## Acceptance
Every visible button works. Complete new game -> pause -> settings -> resume -> restart -> title -> new game without stale driving/camera/pause state. Preference changes survive relaunch. Mouse/gamepad/keyboard can each reach every essential screen. Capture title, pause, options and results at normal and enlarged UI scales. Run core regressions.

Handoff: menu scene paths, navigation routes, settings schema, input mapping and extension points for campaign/Continue. No disabled placeholder routes presented as finished.
