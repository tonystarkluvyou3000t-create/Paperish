#!/usr/bin/env python3
"""Godot regression runner: checks exit codes, stderr, reports and determinism."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
BAD = re.compile(r"^(?:SCRIPT ERROR:|ERROR:|WARNING: ObjectDB|FAIL )", re.M)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=shutil.which('godot') or 'godot')
    parser.add_argument('--seed', type=int, default=20261018)
    parser.add_argument('--output', type=Path, default=ROOT / '.godot' / 'test-runs')
    args = parser.parse_args()
    run_dir = args.output.resolve() / f'suite-{time.time_ns()}-{os.getpid()}'
    run_dir.mkdir(parents=True)
    print(f'EVIDENCE {run_dir}', flush=True)
    count = 0

    def run(name: str, arguments: list[str], *, fail: str | None = None,
            expected_world_errors: int = 0) -> str:
        nonlocal count
        cmd = [args.godot, '--headless', '--audio-driver', 'Dummy', '--path', str(ROOT), *arguments]
        try:
            completed = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=35)
        except subprocess.TimeoutExpired as exc:
            (run_dir / f'{name}.log').write_text(str(exc.stdout) + str(exc.stderr))
            raise AssertionError(f'{name}: outer timeout (runner may have crashed)') from exc
        output = completed.stdout + completed.stderr
        (run_dir / f'{name}.log').write_text(output)
        if fail is None:
            assert completed.returncode == 0, f'{name}: exit {completed.returncode}; see log'
        else:
            assert completed.returncode != 0, f'{name}: negative case incorrectly exited zero'
            assert fail in output, f'{name}: expected diagnostic {fail!r}'
        bad_lines = [line for line in output.splitlines() if BAD.match(line)]
        expected = [line for line in bad_lines if line.startswith('ERROR: World contract:')]
        assert len(expected) == expected_world_errors, f'{name}: unexpected world errors: {expected}'
        assert bad_lines == expected, f'{name}: unexpected engine/script errors: {bad_lines}'
        count += 1
        print(f'PASS {name}' + (' (expected failure)' if fail else ''), flush=True)
        return output

    def scenario(name: str, plan: Path | str, fail: str | None = None) -> dict:
        output = run(name, ['--', f'--capture-plan={plan}', f'--scenario-seed={args.seed}',
                            f'--capture-output={run_dir}'], fail=fail)
        match = re.search(r'^CAPTURE_RESULT (.+)$', output, re.M)
        assert match, f'{name}: no result file from this run'
        path = Path(match[1])
        assert path.is_relative_to(run_dir), f'{name}: result outside current run'
        report = json.loads(path.read_text())
        assert report['success'] == (fail is None), name
        assert report['cleanup'] == {'paused': False, 'time_scale': 1,
                                     'held_actions': [], 'pressed_actions': []}, f'{name}: cleanup failed'
        if fail is None:
            assert report['assertions'] > 0, f'{name}: no assertions executed'
            assert not report['images'], f'{name}: headless capture must skip images'
        return report

    try:
        run('main', ['--quit-after', '180'])
        run('town', ['--script', 'res://tools/check_town.gd'])
        run('art', ['--script', 'res://tools/validate_art.gd'])
        phase1 = run('core-physics', ['--script', 'res://tools/phase01_checks.gd'], expected_world_errors=5)
        assert 'PHASE 01: 137 checks, 0 failures' in phase1
        services = run('services', ['--script', 'res://tools/phase03_checks.gd'])
        assert re.search(r'PHASE 03: [1-9][0-9]* checks, 0 failures', services)
        rng = run('order-rng', ['--script', 'res://tools/check_order_rng.gd'])
        assert 'RNG PASS' in rng
        # The camera rig consumes real InputMap actions; regenerate settings from
        # the generator of record first so project.godot cannot silently drift.
        setup = run('setup-project', ['--script', 'res://tools/setup_project.gd'])
        assert 'project settings saved, err=0' in setup
        camera = run('camera', ['--script', 'res://tools/phase04_checks.gd'])
        assert 'PHASE 04: 58 checks, 0 failures' in camera
        menus = run('menus-settings', ['--script', 'res://tools/phase05_checks.gd'])
        assert re.search(r'PHASE 05: [1-9][0-9]* checks, 0 failures', menus)
        # Preferences only count as persisted when a second process reads them.
        probe_path = 'user://phase05-probe.cfg'
        probe = run('settings-write', ['--script', 'res://tools/settings_probe.gd', '--',
                                       '--mode=write', f'--settings={probe_path}'])
        assert 'PROBE WRITE OK' in probe
        probe = run('settings-read', ['--script', 'res://tools/settings_probe.gd', '--',
                                      '--mode=read', f'--settings={probe_path}'])
        assert 'PROBE READ OK' in probe
        probe = run('settings-clean', ['--script', 'res://tools/settings_probe.gd', '--',
                                       '--mode=clean', f'--settings={probe_path}'])
        assert 'PROBE CLEAN OK' in probe
        # The performance harness runs headless too: frame times need a window,
        # but the route, the sampling loop and the report must not rot.
        perf = run('perf-harness', ['--script', 'res://tools/perf_probe.gd', '--',
                                    '--perf-frames=120', '--perf-quality=high'])
        assert 'PERF HARNESS OK' in perf
        for name in ['core', 'playfast', 'playtest', 'camera', 'menu']:
            plan = ROOT / 'tools' / 'plans' / f'{name}.json'
            first = scenario(f'{name}-1', plan)
            second = scenario(f'{name}-2', plan)
            assert first['logical'] == second['logical'], f'{name}: same seed changed logical outcomes'
            if name.startswith('play'):
                last = first['logical'][-1]
                assert last['deliveries'] == (1 if name == 'playfast' else 2)
                assert last['cargo_count'] == 0 and last['order_id'] == last['deliveries'] + 1
                assert last['money'] > 0
            if name == 'menu':
                # The menu timeline must walk title -> roam -> shift -> results
                # and land back on the title with nothing paused.
                path = [step['menu_screen'] for step in first['logical']]
                assert 'options' in path and 'controls' in path and 'credits' in path, path
                assert 'pause' in path and 'confirm' in path, path
                assert 'results' in path, path
                assert path[0] == 'title' and path[-1] == 'title', path
                assert any(step['play_mode'] == 'roam' for step in first['logical']), 'menu: no roam step'
                assert not any(step['paused'] for step in first['logical'][-1:]), 'menu: ended paused'
            print(f'PASS deterministic replay {name} seed={args.seed}', flush=True)
        fixtures = run_dir / 'fixtures'
        fixtures.mkdir()
        def plan(name: str, steps: list[dict]) -> dict:
            return {'name': name, 'seed': args.seed, 'steps': steps + [{'do': 'quit'}]}
        negatives = {
            'inverted': (plan('inverted', [{'do': 'assert', 'label': 'deliberately inverted',
                                          'expect': {'mode': 'failed'}}]), 'deliberately inverted'),
            'unknown-action': (plan('unknown-action', [{'do': 'press', 'action': 'not_an_action'}]), 'unknown keyboard/mouse action'),
            'unknown-step': (plan('unknown-step', [{'do': 'run_arbitrary_code'}]), 'unknown step'),
            'unknown-menu': (plan('unknown-menu', [{'do': 'menu', 'id': 'not_a_screen'}]), 'menu id not accepted'),
            'unknown-setting': (plan('unknown-setting', [{'do': 'setting', 'key': 'audio/nope', 'value': 1}]),
                                'unknown setting key'),
            'wrong-type': (plan('wrong-type', [{'do': 'assert', 'expect': {'paused': 1}}]), 'wrong type'),
            'missing-key': (plan('missing-key', [{'do': 'wait', 'expect': {'mode': 'title'}}]), 'missing timeout'),
            'unknown-field': (plan('unknown-field', [{'do': 'assert', 'expect': {'typo': 1}}]), 'unknown diagnostic field'),
            'wait-timeout': (plan('wait-timeout', [{'do': 'wait', 'timeout': 0.1,
                                                 'label': 'never satisfied', 'expect': {'deliveries': 999}}]), 'never satisfied'),
            'cleanup': (plan('cleanup', [{'do': 'start'}, {'do': 'time_scale', 'v': 2},
                                       {'do': 'down', 'action': 'move_forward'}, {'do': 'press', 'action': 'pause'},
                                       {'do': 'assert', 'label': 'cleanup failure', 'expect': {'mode': 'failed'}}]), 'cleanup failure'),
            'range': (plan('range', [{'do': 'order', 'index': 999}]), 'destination index out of range'),
        }
        for name, (data, diagnostic) in negatives.items():
            path = fixtures / f'{name}.json'
            path.write_text(json.dumps(data))
            scenario(name, path, fail=diagnostic)
        malformed = fixtures / 'malformed.json'
        malformed.write_text('{"name":')
        scenario('malformed', malformed, fail='malformed JSON')
        scenario('missing-plan', fixtures / 'missing.json', fail='plan not found')
        run('missing-resource', ['--script', 'res://tools/check_town.gd', '--',
                                f'--resource={fixtures / "missing.tscn"}'], fail='missing resource')
        not_scene = fixtures / 'resource.tres'
        not_scene.write_text('[gd_resource type="Resource" format=3]\n[resource]\n')
        run('not-scene', ['--script', 'res://tools/check_town.gd', '--',
                         f'--resource={not_scene}'], fail='not PackedScene')
        # Structural failure fixture stays outside normal town resources.
        broken_town = fixtures / 'broken-town.tscn'
        broken_town.write_text('[gd_scene format=3]\n[node name="Town" type="Node3D"]\n')
        run('broken-town', ['--script', 'res://tools/check_town.gd', '--',
                           f'--town-scene={broken_town}'], fail='required Node3D missing')
        # A minimal otherwise-valid town proves duplicate identity and marker
        # checks without touching the project's generated scenes.
        base = '[gd_scene format=3]\n[node name="Town" type="Node3D"]\n'
        for node in ['Island', 'Houses', 'Props', 'PizzaShop', 'StreetDetails', 'PlayerSpawn', 'VanSpawn']:
            base += f'[node name="{node}" type="Node3D" parent="."]\n'
            if node.endswith('Spawn'):
                base += 'metadata/yaw = 0.0\n'
        base += '[node name="PickupPoint" type="Node3D" parent="PizzaShop"]\n'
        for index in range(2):
            base += f'[node name="House{index}" type="Node3D" parent="Houses"]\n'
            base += f'metadata/address = "2 Marinara Way"\nmetadata/label = "fixture"\nmetadata/number = {index+1}\nmetadata/north = true\n'
            for marker in ['Door', 'Park']:
                base += f'[node name="{marker}" type="Node3D" parent="Houses/House{index}"]\n'
        duplicate = fixtures / 'duplicate-town.tscn'
        duplicate.write_text(base)
        run('duplicate-town', ['--script', 'res://tools/check_town.gd', '--',
                              f'--town-scene={duplicate}'], fail='duplicate address identity')
        missing_marker = fixtures / 'missing-marker.tscn'
        base = base.replace('metadata/address = "2 Marinara Way"', 'metadata/address = "4 Marinara Way"', 1)
        base = base.replace('[node name="Door" type="Node3D" parent="Houses/House0"]\n', '')
        missing_marker.write_text(base)
        run('missing-marker', ['--script', 'res://tools/check_town.gd', '--',
                              f'--town-scene={missing_marker}'], fail='requires Door marker')
        summary = {'success': True, 'commands': count, 'seed': args.seed, 'evidence': str(run_dir)}
        (run_dir / 'summary.json').write_text(json.dumps(summary, indent=2))
        print(f'SUITE PASS: {count} commands; logical replays match; evidence={run_dir}')
        return 0
    except (AssertionError, OSError, ValueError) as exc:
        (run_dir / 'summary.json').write_text(json.dumps({'success': False, 'error': str(exc)}))
        print(f'SUITE FAIL: {exc}; evidence={run_dir}', file=sys.stderr)
        return 1

if __name__ == '__main__':
    raise SystemExit(main())
