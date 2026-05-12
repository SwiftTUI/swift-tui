# About SwiftTUI


SwiftTUI is SwiftUI for the terminal.
It builds terminal user interfaces with an authoring model, layout model, and
runtime contract that are deliberately shaped after SwiftUI.

Principles:

- Implement subsets of SwiftUI only if they map to high value TUI use cases.
- Avoid everything deprecated, and anything questionable.
- Once implementing, do so uncompromisingly.

In scope today:

- SwiftUI-shaped layout, state, environment, and focus
- ``RunLoop``-driven interactive sessions with alternate-screen ownership and ANSI rendering
- Tree-forward collection presentation as a first-class authoring pattern
- PNG and baseline JPEG image presentation
- GIF import/export and finite animation through the peer `SwiftTUIAnimatedImage` product
- Compact charts and metric components through the peer `SwiftTUICharts` product
- Terminal-native presentation through alerts, confirmation dialogs, sheets,
  popovers, popover tips, menus, and toasts
- Binding-driven `NavigationStack` destination presentation
- Keyboard based focus and navigation model with pointer based augmentation
- Terminal capability detection for colors, images, pointer precision, etc.
- Shared accessibility semantics with terminal, Web/WASI, and SwiftUI host delivery

Deliberately deferred:

- `NavigationLink`, public `NavigationPath`, and automatic Back chrome
- Host-native text value/selection transport and IME/composition
- Process reattachment for terminal workspaces after app restart
- Media-heavy surfaces beyond static PNG / JPEG presentation and the peer
  `SwiftTUIAnimatedImage` product

## See Also

- <doc:Architecture>
- <doc:Runtime>
- <doc:Host-Integration>
- [Project Vision](https://github.com/adamz/swift-tui/blob/main/docs/VISION.md)
