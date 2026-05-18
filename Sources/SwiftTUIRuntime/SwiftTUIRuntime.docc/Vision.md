# About SwiftTUI

SwiftTUI is SwiftUI for the terminal.
It builds terminal user interfaces with an authoring model, layout model, and
runtime contract that are deliberately shaped after SwiftUI.

## Principles

- Implement subsets of SwiftUI only if they map to high-value TUI use cases.
- Avoid everything deprecated, and anything questionable.
- Once implementing, do so uncompromisingly.

The goal is not to expose a terminal-specific DSL. The goal is to preserve the
parts of SwiftUI that make large UI codebases composable and predictable while
targeting cell-based rendering.

## What SwiftTUI Is Today

SwiftTUI provides:

- SwiftUI-shaped layout, state, environment, and focus
- ``RunLoop``-driven interactive sessions with alternate-screen ownership and ANSI rendering
- Tree-forward collection presentation as a first-class authoring pattern
- PNG and baseline JPEG image presentation
- GIF import/export and finite animation through the peer `SwiftTUIAnimatedImage` product
- Compact charts and metric components through the peer `SwiftTUICharts` product
- Terminal-native presentation through alerts, confirmation dialogs, sheets,
  popovers, popover tips, menus, and toasts
- Binding-driven `NavigationStack` destination presentation
- Keyboard-based focus and navigation model with pointer-based augmentation
- Terminal capability detection for colors, images, pointer precision, and more
- Shared accessibility semantics with terminal, Web/WASI, and SwiftUI host delivery

## See Also

- <doc:Architecture>
- <doc:Runtime>
- <doc:Host-Integration>
- [Project Vision](https://github.com/SwiftTUI/swift-tui/blob/main/docs/VISION.md)
- [Vision Gap](https://github.com/SwiftTUI/swift-tui/blob/main/docs/VISION-GAP.md)
