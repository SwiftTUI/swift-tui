# Layouts SwiftUI Comparison Example

56 focused layout examples rendered side by side: native SwiftUI on the left
and the matching SwiftTUI implementation embedded through `SwiftUIHost` on the
right. The matching SwiftTUI package owns the raster smoke and behaviour tests
for the shared catalog IDs.

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

Library divergences and design questions surfaced while implementing the
behaviour tests are documented inline in the behaviour test files.
Behaviour tests pin the *observed* behaviour today; update a test's
comment and open a discussion before changing the library.
