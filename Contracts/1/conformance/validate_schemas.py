#!/usr/bin/env python3
"""Validate the kit's 2020-12 schemas and independent positive/negative vectors offline.
Install conformance/requirements-schema.txt once before going offline.
"""
import json
from pathlib import Path
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

root = Path(__file__).resolve().parents[1]
schemas = {p.name: json.loads(p.read_text()) for p in (root / 'schemas').glob('*.json')}
registry = Registry().with_resources((s['$id'], Resource.from_contents(s)) for s in schemas.values())
for schema in schemas.values():
    Draft202012Validator.check_schema(schema)
failed = []
cases = json.loads((root / 'fixtures/schema-cases.json').read_text())
for case in cases:
    schema = schemas[case['schema']]
    if 'definition' in case:
        schema = {'$ref': schema['$id'] + '#/$defs/' + case['definition']}
    valid = Draft202012Validator(schema, registry=registry).is_valid(case['value'])
    if valid != case['valid']:
        failed.append(case['id'])
print(json.dumps({'schemas': len(schemas), 'cases': len(cases), 'passed': not failed, 'failures': failed}))
raise SystemExit(bool(failed))
