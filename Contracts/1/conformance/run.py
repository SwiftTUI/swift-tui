#!/usr/bin/env python3
"""Offline conformance: exact observations from a persistent NDJSON host adapter."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def verify():
    manifest = json.loads((ROOT / 'manifest.json').read_text())
    for name, expected in manifest['files'].items():
        path = ROOT / name
        if Path(name).is_absolute() or '..' in Path(name).parts or not path.resolve().is_relative_to(ROOT):
            raise ValueError('unsafe kit path: ' + name)
        if not path.is_file() or path.stat().st_size != expected['bytes'] or hashlib.sha256(path.read_bytes()).hexdigest() != expected['sha256']:
            raise ValueError('kit digest mismatch: ' + name)
    digest = hashlib.sha256(json.dumps(manifest['files'], sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    if digest != manifest['contentSHA256']: raise ValueError('manifest content digest mismatch')
    return manifest

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected-digest')
    parser.add_argument('--verify-only', action='store_true')
    parser.add_argument('--adapter', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    manifest = verify()
    if args.expected_digest and args.expected_digest != manifest['contentSHA256']:
        raise ValueError('selected kit digest mismatch')
    if args.verify_only:
        print(json.dumps({'verified': manifest['contentSHA256']}))
        return 0
    if not args.adapter: parser.error('--adapter COMMAND [ARGS...] is required')
    failures = []
    count = 0
    traces = []
    profiles = set()
    for name in sorted(manifest['files']):
        if not name.startswith('fixtures/trace-') or not name.endswith('.json'): continue
        path = ROOT / name
        trace = json.loads(path.read_text())
        profiles.add(trace['profile'])
        traces.append({'id': trace['id'], 'sha256': manifest['files'][name]['sha256']})
        process = subprocess.run(args.adapter, input=''.join(json.dumps(row['operation']) + '\n' for row in trace['steps']),
                                 text=True, capture_output=True, timeout=30)
        try: actual = [json.loads(line) for line in process.stdout.splitlines()]
        except ValueError: actual = []
        expected = [row['expect'] for row in trace['steps']]
        count += len(expected)
        if process.returncode or actual != expected:
            first = next((i for i in range(min(len(actual), len(expected))) if actual[i] != expected[i]), min(len(actual), len(expected)))
            failures.append({'trace': trace['id'], 'step': first,
                             'expected': expected[first] if first < len(expected) else None,
                             'actual': actual[first] if first < len(actual) else None,
                             'exit': process.returncode, 'stderr': process.stderr[-2000:]})
    if count == 0: raise ValueError('no conformance traces selected')
    print(json.dumps({'profile': manifest['profile'], 'kit': manifest['contentSHA256'], 'runner': args.adapter,
                      'exercisedProfiles': sorted(profiles),
                      'notExercised': ['android-native', 'wasi-execution', 'companion-bootstrap', 'terminal-cli', 'swift-source'],
                      'traces': traces, 'steps': count, 'passed': not failures, 'failures': failures}, indent=2))
    return bool(failures)

if __name__ == '__main__':
    try: sys.exit(main())
    except (ValueError, subprocess.TimeoutExpired) as error: sys.exit(str(error))
