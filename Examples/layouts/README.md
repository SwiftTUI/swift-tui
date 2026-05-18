# Layouts Example

56 focused layout examples of the public `SwiftTUI` surface,
reachable from a full-screen push/pop picker. Each layout is pinned
with a smoke test; `.behaviour`-tagged layouts add targeted
behaviour tests that pin the specific measure/place rule the layout
is meant to demonstrate.

## Run

```bash
cd Examples/layouts
swiftly run swift run layouts-demo
```

The app launches directly into the picker. `↑↓` move, `⏎` opens a
layout, `esc` pops back, `⌃C` quits.

## Test

```bash
cd Examples/layouts
swiftly run swift test
```

81 tests across 54 suites: 56 parameterised smoke tests (one per
catalog entry), targeted behaviour tests for the `.behaviour` tier,
catalog-integrity invariants, and a picker-shell test that
rasterises every category section.

## Findings

Library divergences and design questions surfaced while implementing the
behaviour tests are documented inline in the behaviour test files.
Behaviour tests pin the *observed* behaviour today; update a test's
comment and open a discussion before changing the library.
