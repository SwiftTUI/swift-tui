# About SwiftTUI


SwiftTUI is SwiftUI for the terminal. 
Building terminal user interfaces with an authoring model, layout model, and runtime contract that are deliberately shaped after SwiftUI. 

Principles:

- Implement subsets of SwiftUI only if they map to high value TUI use cases.
- Avoid everything deprecated, and anything questionable.
- Once implementing, do so uncompromisingly.

In scope today:

- SwiftUI-shaped layout, state, environment, and focus
- ``RunLoop``-driven interactive sessions with alternate-screen ownership and ANSI rendering
- Tree-forward collection presentation as a first-class authoring pattern
- PNG and baseline JPEG image presentation
- Keyboard based focus and navigation model with Pointer based augmentation
- Terminal capability detection for colors, images, pointer precision, etc.

Deliberately deferred:

- `NavigationStack` et al.
- A full accessibility-tree
- Media-heavy surfaces beyond static PNG / JPEG presentation and the peer
  `AnimatedImage` product

## See Also

- <doc:Architecture>
- <doc:Runtime>
- <doc:Host-Integration>
- [Project Vision](https://github.com/adamz/swift-tui/blob/main/docs/VISION.md)
