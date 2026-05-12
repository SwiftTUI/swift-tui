# Layouts Example

56 focused layout examples of the public `SwiftTUI` surface,
reachable from a full-screen push/pop picker. Each layout is pinned
with a smoke test; `.behaviour`-tagged layouts add targeted
behaviour tests that pin the specific measure/place rule the layout
is meant to demonstrate.

Design and taxonomy live in
[../../docs/plans/2026-04-24-001-layouts-example-plan.md](../../docs/plans/2026-04-24-001-layouts-example-plan.md).

## Run

```bash
cd Examples/LayoutsSwiftUI
swiftly run swift run layouts-swiftui-demo
```

The app launches directly into the picker. `↑↓` move, `⏎` opens a
layout, `esc` pops back, `⌃C` quits.

## Build

```bash
cd Examples/LayoutsSwiftUI
swiftly run swift build
```

This SwiftUI reference package does not have a test target; the corresponding
SwiftTUI layouts package owns the raster behaviour tests.

## Findings

Library divergences and design questions surfaced while
implementing the behaviour tests are tracked in
[../../docs/proposals/layout/BEHAVIOUR_FINDINGS.md](../../docs/proposals/layout/BEHAVIOUR_FINDINGS.md).
Behaviour tests pin the *observed* behaviour today; the findings
doc is the place to escalate "what should this actually do?"
before changing the library.
