# Layouts SwiftUI Comparison Example

56 focused layout examples rendered side by side: native SwiftUI on the left
and the matching SwiftTUI implementation embedded through `SwiftUIHost` on the
right. The matching SwiftTUI package owns the raster smoke and behaviour tests
for the shared catalog IDs.

Design and taxonomy live in
[../../docs/plans/2026-04-24-001-layouts-example-plan.md](../../docs/plans/2026-04-24-001-layouts-example-plan.md).

## Run

```bash
cd Examples/LayoutsSwiftUI
swiftly run swift run layouts-swiftui-demo
```

The app launches directly into a sidebar and comparison detail. Selecting a
layout updates both panes to the same catalog ID.

## Build

```bash
cd Examples/LayoutsSwiftUI
swiftly run swift build
```

This package does not have a test target; the corresponding SwiftTUI layouts
package owns the raster behaviour tests.

## Findings

Library divergences and design questions surfaced while
implementing the behaviour tests are tracked in
[../../docs/proposals/layout/BEHAVIOUR_FINDINGS.md](../../docs/proposals/layout/BEHAVIOUR_FINDINGS.md).
Behaviour tests pin the *observed* behaviour today; the findings
doc is the place to escalate "what should this actually do?"
before changing the library.
