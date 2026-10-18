# Phase 05b — Render target, quality presets and the performance harness

**Status: VERIFIED.** Headless suite `SUITE PASS: 41 commands` (Phase 05 is
251/0) plus rendered Forward+ evidence inspected on the reference machine.

This is **not** a numbered roadmap phase. It is the owner-directed change set
that locked the render target between phases 05 and 06, so phases 06–10 stop
inheriting the old Compatibility/720p assumptions. `PHASE_PROGRESS.md` still
counts numbered phases only (5 of 24).

## Decision

The owner's instruction was "3050 is our target" — the available machine (RTX
3050 6 GB laptop GPU, 95 W, 1920×1080 panel) is the *only* target. The project
therefore spends the headroom on quality instead of staying on the Compatibility
renderer, and the earlier 1280×720 target is retired. Everything else stays:
procedural generators, deterministic checks, no photorealism chase.

## What changed

| Area | Change |
|---|---|
| Renderer | `tools/setup_project.gd` writes `rendering/renderer/rendering_method = forward_plus` (generator of record), `msaa_3d = 2` (4 ×), `directional_shadow/size = 4096`, `soft_shadow_filter_quality = 3`; viewport/window default 1920×1080 |
| Look | `scenes/game.tscn` Environment: tonemap AgX (white 1.3), ambient 0.45, SSAO (radius 1.1, intensity 2.0, power 1.5, light affect 0.15), glow (normalized, intensity 0.9, bloom 0.05, soft-light blend, HDR threshold 0.85) |
| Presets | `SettingsService` gained `video/quality` (LOW/MEDIUM/HIGH), `video/msaa` (OFF/2×/4×), `video/ssao` (OFF/LOW/HIGH), `video/glow`, `video/frame_cap` (60/120/unlimited) with validation, apply paths and rows. `video/quality` is a macro: it writes the fine keys through `set_value`, so each one keeps its own row, stored value and effect |
| Apply split | Service applies renderer-global pieces (MSAA on the root viewport, SSAO quality/half-size project keys, shadow atlas size, `Engine.max_fps`); Game applies scene-owned pieces (sun shadows, Environment SSAO/glow) from `changed` |
| Window | `_apply_window` clamps to the desktop's usable rect and centres there, so the 1920×1080 default still fits a 1080p panel with its title bar visible; `video/window_preset` default is now 2 (1920×1080) |
| UI | `options_screen.gd`: per-key refreshers so a preset's writes show in the fine rows, `refresh_values()` on activation (wired in `MenuLayer._refresh()` before `_focus`), the row list is named `Rows`, and `_fit_scroll()` sizes it to the logical view (fits 150 % at 720p, uses the card at 1080p) |
| Harness | New `tools/perf_probe.gd`: fixed route, fixed seed, chosen tier/resolution, scratch settings file, frame-time percentiles + hitches + draw calls/primitives/nodes/memory + physics; `perf-harness` suite command runs it headless (`PERF HARNESS OK`) |
| Spec | phase-20 and phase-23 prompt lines that assumed Compatibility/1280×720 were amended; README/ARCHITECTURE/SCENARIOS updated |

Headless behaviour is deliberately unchanged: `Engine.max_fps` is forced to 0
without a real window, so checks and captures still simulate far faster than real
time, and the renderer swap is invisible to a dummy rendering driver.

## Evidence

- `PHASE 05: 251 checks, 0 failures` — 37 new checks cover the preset macro → fine
  keys, MSAA on the live viewport, SSAO/glow reaching the Environment, the SSAO
  renderer keys, frame-cap values with the headless carve-out, shadow-distance
  mapping, RESET restoring HIGH, unknown/wrong-typed values falling back,
  vertical card fit at 150 %, the 1080p list room, and the shipped project
  settings (Forward+, 4096, 1920×1080).
- Suite: `SUITE PASS: 41 commands` (01 137/0, 03 44/0, 04 58/0, 05 251/0,
  `perf-harness`, all replays and negatives), evidence
  `.godot/test-runs/suite-1792323060964869900-18052`.
- Baseline, windowed on the reference machine, Forward+, vsync off, frame cap 0,
  walking the fixed street route with the real follow camera:

  | Tier / resolution | frames | median | p95 | p99 | max | hitches | draw calls | nodes |
  |---|---|---|---|---|---|---|---|---|
  | HIGH 1920×1080 (warm 900) | 1800 | 4.68 ms (214 FPS) | 6.25 | 6.25 | 6.25 | 0 | 996 | 2,073 |
  | HIGH 1920×1080 (warm 900, repeat) | 1800 | 4.68 ms (214 FPS) | 5.48 | 5.48 | 5.48 | 0 | 996 | 2,073 |
  | HIGH 1920×1080 (warm 1200) | 3600 | 4.76 ms (210 FPS) | 6.68 | 6.68 | 6.68 | 0 | 1,081 | 2,073 |

  Physics 0.63–0.68 ms median, static memory ≈ 80 MB, adapter reported as
  `NVIDIA GeForce RTX 3050 6GB Laptop GPU`. 60 FPS budget is 16.6 ms, so the
  worst measured frame is ≈ 2.5 × inside it. Early runs with a short warmup
  reported 14–17 ms p95 tails; those are first-run Vulkan pipeline compiles, not
  steady-state cost (they vanish with ≥ 900 warmup frames).
- Rendered: camera plan (6 shots) and menu plan (13 shots, 18 assertions) re-run
  at 1920×1080 in Forward+ under `.godot/phase055-evidence/`; the Options card now
  shows 11 rows with the scroll bar instead of 5.

## Contracts for later phases

1. **Do not reintroduce Compatibility.** The generator owns the renderer; if a
   setting is worth exposing it needs a `DEFAULTS`/`SPEC` row, a validate path
   and a real apply path.
2. New/changed keys: `video/quality` (`low`/`medium`/`high`, default `high`),
   `video/msaa` (0/1/2, default 2), `video/ssao` (0/1/2, default 2), `video/glow`
   (default true), `video/frame_cap` (0/60/120, default 60),
   `video/shadow_quality` (default now 2 → 140 m), `video/window_preset`
   (default now 2 → 1920×1080).
3. `Engine.max_fps` must stay 0 when `DisplayServer.get_name() == "headless"`.
4. Phases 14/15/20: keep new lighting/weather systems preset-aware and applied
   through Game's `changed` handler; prefer depth fog + GPU particles over
   volumetric fog; keep the 60 FPS cap as the shipped default.
5. Phases 10/12/13/20/23: the ceiling is draw calls and node count, not shader
   cost (~1 000 draw calls / 2 073 nodes today). Re-run `tools/perf_probe.gd`
   after the island grows, and quote `median`/`p99`/`hitches` with the adapter,
   resolution and tier. `--perf-quality=low|medium|high`, `--perf-res=WxH`,
   `--perf-frames`, `--perf-warm`, `--perf-output` are the knobs.
6. Rendered evidence is now 1920×1080 Forward+; shots taken before this change
   are not comparable for look, only for layout.

## Caveats

- The look is judged from rendered shots, not a human play session; final
  palette/saturation/detail tuning belongs to phase 20.
- The perf route is a walk with autopilot waypoints: 1–5 legs per run can time
  out where the walker cannot reach a marker within 14 s. Sampling and counters
  are unaffected, but "legs/stalled" is reported so this is never hidden.
- The baseline has no traffic, pedestrians or NPCs and only ~1 000 draw calls. It
  is a floor for the 320×240 m target, not a promise about it.
- No weak-GPU fallback path is wired: a Compatibility export would be a separate
  build (Godot's renderer is a startup choice), and that is currently out of
  scope.
- The two low-priority follow-ups found while working are recorded, not done:
  the phase-04 awning still has no collider, and `subtitle`/text-pacing tuning is
  untouched.
