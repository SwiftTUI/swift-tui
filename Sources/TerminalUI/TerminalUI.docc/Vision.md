# About TerminalUI

What this project is, what's in scope today, and what's deliberately deferred.

## Overview

TerminalUI is a Swift package for building terminal user interfaces with an authoring model, layout model, and runtime contract that are deliberately shaped after SwiftUI. It implements a SwiftUI-shaped subset, terminal-native and keyboard-first, with capability-aware presentation.

In scope today:

- SwiftUI-shaped layout, state, environment, and focus
- ``RunLoop``-driven interactive sessions with alternate-screen ownership and ANSI rendering
- Tree-forward collection presentation as a first-class authoring pattern
- PNG, baseline JPEG, and GIF image presentation through Kitty graphics or Sixel when the terminal supports them, with capability-aware fallback into terminal cells when it does not
- Pointer interaction as an augmentation, not a replacement for the focus model

Deliberately deferred:

- `NavigationStack` and richer popover-style presentation
- A full accessibility-tree or assistive-technology story
- Pixel-precise layout or any second, non-terminal presentation model
- Animated GIF playback, progressive JPEG, video, remote fetching, and other media-heavy surfaces beyond static PNG / JPEG / GIF presentation

## See Also

- <doc:Architecture>
- <doc:Runtime>
- <doc:Host-Integration>
- [Project Vision](https://github.com/adamz/swift-terminal-ui/blob/main/docs/VISION.md)
