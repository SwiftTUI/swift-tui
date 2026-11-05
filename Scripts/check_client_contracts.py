#!/usr/bin/env python3
"""Verify generated leaves, immutable kit files and the independent recovery witness."""
from pathlib import Path
import json
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
kit = root / 'Contracts/1'
subprocess.run([sys.executable, str(kit / 'generate.py'), '--check'], check=True)
command = [sys.executable, str(kit / 'conformance/run.py')]
adapter = ['--adapter', sys.executable, str(kit / 'examples/python_host.py')]
result = subprocess.run(command + adapter, check=True, capture_output=True, text=True)
report = json.loads(result.stdout)
assert report['passed'] and report['steps'] > 0
for mutation in ['baseline', 'arity', 'image', 'reset']:
    result = subprocess.run(command + adapter + ['--mutation', mutation], capture_output=True, text=True)
    assert result.returncode == 1, (mutation, result.stdout, result.stderr)
    assert json.loads(result.stdout)['failures'], mutation
with tempfile.TemporaryDirectory(prefix='swifttui-contract-digest-') as temp:
    copy = Path(temp) / 'kit'
    shutil.copytree(kit, copy)
    fixture = copy / 'fixtures/trace-recovery.json'
    fixture.write_bytes(fixture.read_bytes() + b'\n')
    result = subprocess.run([sys.executable, str(copy / 'conformance/run.py'), '--verify-only'], capture_output=True, text=True)
    assert result.returncode != 0 and 'kit digest mismatch' in result.stderr
print(f"client contract kit: {report['steps']} independent steps, four rejected transition mutations, rejected digest corruption")
