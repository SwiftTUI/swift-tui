# SwiftTUI host contract kit 1

This directory is a self-contained contract kit. Select it by an immutable
framework commit and the `contentSHA256` in `manifest.json`; a package version
or a mutable `main` URL does not select immutable bytes. Every distributed file
is indexed by relative path, byte count and SHA-256. The content digest hashes
the sorted, compact JSON file index. The manifest itself is not self-hashed.

The [wire profile](profiles/wire.md) defines admission, state and recovery.
[JSON Schema 2020-12](schemas/host.schema.json) owns structural definitions,
limits, canonical vocabulary and tuple arities. The [ABNF](grammar/host.abnf)
owns command framing and scalar syntax. Semantic bounds and transport-specific
lifecycle rules still apply after structural validation. The
[Android ABI](profiles/android-abi.md) and [C header](include/swift_tui_android.h)
specify the binary boundary independently of wire capabilities.

Generated Swift, TypeScript and Kotlin leaf bindings are in `bindings/`.
They contain constants, field sets, tuple arities and the checked UInt64 scalar;
they do not materialize a JSON tree. Shipping clients perform their own bounded
single decode and state transitions. A general-purpose schema engine belongs
in tooling, never on the frame path.

## Offline use

Download the directory intact before disconnecting. Python 3.10 or newer is
sufficient for file verification, trace execution and the example host:

```sh
python3 conformance/run.py --verify-only
python3 conformance/run.py --expected-digest SELECTED_SHA256 \
  --adapter python3 examples/python_host.py
```

The runner launches one persistent adapter process per trace. It writes one
JSON operation per line to stdin and compares one JSON observation per line on
stdout. Diagnostics belong on stderr. A nonzero exit, missing/extra observation,
changed retained state or changed outbound effect fails. A process timeout is
30 seconds. Trace bytes and expectations are checked in independently of the
production decoders. The output names exercised and unexercised profiles;
passing the core trace does not certify an Android library, a browser launch,
Swift source compatibility or a terminal implementation.

Operations are `feed` (hexadecimal bytes), `action` (target and action),
`evictImage` (ID), and `reset`. Observations include epoch, generation, ordered
styled rows, effective styles, retained image IDs, settled IDs, pending IDs and
outbound effects. The example implements the recovery trace's `activate`
action; it reports other actions as unsupported. It is a readable independent
wire-core witness, not a complete renderer or all-profile host SDK.

```sh
# Each mutation must FAIL: a passing mutation means the witness is insufficient.
python3 conformance/run.py --adapter python3 examples/python_host.py --mutation baseline
python3 conformance/run.py --adapter python3 examples/python_host.py --mutation arity
python3 conformance/run.py --adapter python3 examples/python_host.py --mutation image
python3 conformance/run.py --adapter python3 examples/python_host.py --mutation reset
```

For structural schema checks, install `conformance/requirements-schema.txt`
once, then run `python3 conformance/validate_schemas.py` offline. All references
resolve within the kit; the schema `$id` URLs are stable identifiers and do not
require a network fetch. Scene resolution and runtime authorization require
semantic tests in addition to JSON Schema.

## Evolution and selection

Full frame versions 1/2 and delta version 3 are frozen deployed shapes. Unknown
optional keys remain ignorable. Frozen tuples cannot acquire extra slots.
A changed meaning requires a new profile or an explicit capability, with old
reader replay before publication. A malformed optional action reply is local
failure; an invalid state-bearing record preserves the last valid frame and
requests repair. Deployed-reader differences belong in the selected comparison
corpus; they do not expand the canonical writer grammar.

The kit revision, content digest, native ABI major/minor, wire capability bits
and package release are separate identifiers. Consumers record which profile
they implement and require, together with the selected schema/binding hashes.
Generator checks prove copied leaf definitions match their authority; producer
field-mapping/omission tests remain adjacent to the Swift encoder.
