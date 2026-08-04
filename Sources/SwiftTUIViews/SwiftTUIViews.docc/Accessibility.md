# Accessibility

Attach semantic metadata to views so terminal screen readers, browser ARIA
trees, VoiceOver, and TalkBack can present your interface.

## Overview

SwiftTUI builds accessibility into the render pipeline rather than bolting it
on. Every frame produces one semantic snapshot, and each presentation path —
the terminal's linear accessible output, the terminal cursor-follows-focus
mode, the Web/WASI ARIA tree, and the native SwiftUI and Android host
overlays — presents that same snapshot.

## Semantic Modifiers

Authored views attach semantic metadata with modifiers:

- `.accessibilityRole(_:)`
- `.accessibilityLabel(_:)`
- `.accessibilityHint(_:)`
- `.accessibilityHidden(_:)`
- `.accessibilityLiveRegion(_:)`
- `.accessibilityCursorAnchor(_:)`

`AccessibilityRole` is an open-ended enum covering controls and structures
(button, link, text field, toggle, slider, tab, table, heading, and many
more). `AccessibilityPoliteness` has `.off`, `.polite`, and `.assertive`.

During the semantics phase of the pipeline, the placed tree produces a
semantic snapshot whose accessibility nodes form a flat array with parent
links, so consumers can reconstruct a tree. A node carries identity, parent
identity, rect, role, label, hint, hidden, live region, and cursor anchor. It
deliberately does **not** bake in focus state: consumers cross-reference live
focus during presentation, so one snapshot stays valid when focus moves.

## Announcements

`AccessibilityAnnouncer.announce(_:politeness:)` lets app code push an
announcement to the accessibility target of the active runtime. The runtime
ignores calls that occur outside a running runtime.

## Reduced Motion

The runtime resolves a motion policy that authored views can read as
`EnvironmentValues.accessibilityReduceMotion`. Built-in animated views honor
it: `Spinner` renders static text, `PhaseAnimator` renders only its first
phase without cycling, and `AnimatedImage` renders its first frame.

## Output-Mode Detection

The output, glyph, motion, and progress policy is resolved from the process
environment and the TTY state at session start. The precedence is fixed:

1. `NO_COLOR` / `CLICOLOR=0`, then `FORCE_COLOR` / `CLICOLOR_FORCE`.
2. `SWIFTTUI_JSON=1` selects JSON output and wins over
   `SWIFTTUI_ACCESSIBLE=1`.
3. `SWIFTTUI_ACCESSIBLE=1` selects accessible output, which also forces ASCII
   glyphs, reduced motion, no progress animation, and linear rendering.
4. `SWIFTTUI_PLAIN=1` is shorthand for no-color, ASCII, reduced motion.
5. `CI=true` implies reduced motion and no progress animation.
6. A non-TTY stdout implies reduced motion but not accessible output.

The full environment-variable reference, including the accessible-output
family, lives in the `SwiftTUIRuntime` article
[Environment Variables](https://swifttui.sh/docs/documentation/swifttuiruntime/environment-variables).

## Current Limits

The runtime-to-native-assistive-technology direction is one-way: VoiceOver- or
TalkBack-originated focus traversal is not yet fed back into SwiftTUI's
runtime focus.

## See Also

- <doc:Focus>
- <doc:Authoring-Views>
- <doc:State-Environment-And-Focus>
