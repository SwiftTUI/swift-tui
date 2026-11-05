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
with tempfile.TemporaryDirectory(prefix='swifttui-contract-generator-') as temp:
    checkout = Path(temp)
    copied_kit = checkout / 'Contracts/1'
    shutil.copytree(kit, copied_kit)
    production = checkout / 'Sources/SwiftTUIRuntime/Terminal/HostContract.generated.swift'
    production.parent.mkdir(parents=True)
    shutil.copy2(kit / 'bindings/HostContract.swift', production)
    schema_path = copied_kit / 'schemas/host.schema.json'
    schema = json.loads(schema_path.read_text())
    limit = next(iter(schema['x-limits']))
    schema['x-limits'][limit] += 1
    schema_path.write_text(json.dumps(schema, indent=2) + '\n')
    generator = [sys.executable, str(copied_kit / 'generate.py')]
    assert subprocess.run(generator + ['--check'], capture_output=True).returncode != 0
    subprocess.run(generator, check=True, capture_output=True)
    subprocess.run(generator + ['--check'], check=True, capture_output=True)
    for language in ['swift', 'ts', 'kt']:
        name = 'bindings/HostContract.' + language
        assert (copied_kit / name).read_bytes() != (kit / name).read_bytes(), language
print(f"client contract kit: {report['steps']} independent steps, four rejected transition mutations, rejected digest corruption")
