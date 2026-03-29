# Vision

## What This Project Is

TerminalUI is a Swift package for building terminal user interfaces with an authoring model, layout model, and runtime contract that are deliberately shaped after SwiftUI.

The project implements the SwiftUI subset needed to build strong terminal applications without shortcuts in the layout algorithm, state model, or render pipeline. The goal is not to mimic SwiftUI cosmetically. The goal is to preserve the parts of SwiftUI that make large UI codebases predictable.

## Core Principles

### SwiftUI Faithfulness

The package aims to match SwiftUI semantics as closely as the terminal domain allows:

- Layout is recursive parent-child negotiation, not global constraint solving
- A parent proposes a size, a child chooses, and the parent places the child
- Modifier order matters because modifiers participate in layout and semantics
- State drives rendering, not the reverse
- `Layout` is the public surface of custom layout participation
- Focus should belong to authored controls rather than incidental containers, and explicit focus modifiers should remain authoritative

Terminal-specific differences are restricted to the edges of the system: integer-cell geometry, glyph-width-aware text layout, and ANSI or capability-aware presentation. Those constraints do not justify collapsing phases or inventing a fundamentally different authoring story.

See [SWIFTUI_LAYOUT.md](SWIFTUI_LAYOUT.md) for the upstream layout model that serves as the reference target.

### Implementing A Useful Subset

TerminalUI is intentionally not implementing every SwiftUI concept.

What that means in practice:

- Layout primitives come first: stacks, frames, padding, overlays, scrolling, and custom layouts
- State and environment come next: `@State`, `@Binding`, `@Observable`, focused values, and focus bindings
- Runtime correctness comes next: lifecycle ownership, task staging, and incremental terminal presentation
- Navigation, modal presentation, and other broader orchestration APIs arrive only after the foundation is firm
- Terminal-only chrome that would bend the public authoring story away from SwiftUI does not belong in the core library

### Deviations From SwiftUI

Deviations are permitted only when all of the following are true:

1. The deviation is well-considered and explicitly justified
2. The deviation solves a real terminal problem rather than copying another TUI framework by habit
3. The deviation is documented here and reflected in the public API inventory

Confirmed deviations today:

- **Tree-forward collection presentation.** Hierarchical list and outline presentation is more central in TUI software than it is in common SwiftUI app design. TerminalUI supports tree-style collection display as a first-class authoring pattern while still staying close to SwiftUI’s `OutlineGroup` and `children` vocabulary.
- **Repo-owned `@Bindable`.** The package ships its own bindable wrapper to keep observable editing on the same invalidation path as `@State` and the rest of the runtime.

### Input Philosophy

TerminalUI is keyboard-first, but not keyboard-only.

- Keyboard and focus traversal remain the primary design center
- Mouse reporting and pointer-style interaction are supported when the terminal exposes them
- Pointer interaction should augment authored controls and collections, not replace the keyboard or focus model

That means pointer support is in scope, but touch-first, pointer-first, or pixel-precise interaction models are not the architectural center of the project.

### SwiftUI Concepts That Need A Stronger Hypothesis First

Some SwiftUI concepts likely belong in TerminalUI eventually, but the package does not yet have a strong enough model to ship them confidently.

Deferred items:

- `NavigationStack` and `NavigationSplitView`
- `Toolbar` and `ToolbarItem`
- alerts and confirmation dialogs
- sheets and popovers

These should not be implemented just because terminal frameworks often have analogous surfaces. They should land only once the terminal-specific interaction model is clear and the API still reads like the same product.

Current implementation status and short-term constraints live in [STATUS.md](STATUS.md). Deferred items should not jump ahead of foundation work without an explicit tradeoff.

### What Is Not In Scope Today

- media-heavy surfaces beyond PNG image presentation
- a full accessibility-tree or assistive-technology story
- pixel-precise layout or a second, non-terminal presentation model

### Image Rendering

TerminalUI now ships a narrow image surface for PNG content:

- SwiftUI-shaped `Image` authoring for explicit named resources, local `file://` URLs, and embedded `[UInt8]` PNG bytes
- runtime-hosted terminal presentation through Kitty graphics or Sixel when the terminal advertises support
- capability-aware fallback rendering into terminal cells when graphics protocols are unavailable

That scope is intentionally tight. PNG images are in. Broader media playback, animation, remote fetching, or bundle-driven asset systems are still outside the core story.

## Aesthetic And Component Guidance

[Bubble Tea](https://github.com/charmbracelet/bubbletea) and [Lip Gloss](https://github.com/charmbracelet/lipgloss) are useful reference points for what terminal applications often need visually and structurally. They are evidence, not templates.

See [LIPGLOSS_SWIFTUI_EQUIVALENTS.md](LIPGLOSS_SWIFTUI_EQUIVALENTS.md) for the mapping between Lip Gloss concepts and the SwiftUI-shaped surfaces TerminalUI prefers.

## TerminalUICharts

`TerminalUICharts` is intentionally a separate track. It demonstrates how compact dashboard and metrics components can be built on the same view and runtime foundation without allowing charting needs to distort the core API story.
