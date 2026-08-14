# Accessibility

Attach semantic metadata to views so terminal screen readers, browser ARIA
trees, VoiceOver, and TalkBack can present your interface.

## Overview

SwiftTUI builds accessibility into the render pipeline rather than bolting it
on. Every frame produces one semantic snapshot, and each presentation path
(the terminal cursor-follows-focus mode, the Web/WASI ARIA tree, and the
native SwiftUI and Android host overlays) presents that same snapshot.

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
The current node does not carry activation, adjustment, enabled/selected
state, or an assistive-technology-originated focus route.

## Announcements

`AccessibilityAnnouncer.announce(_:politeness:)` lets app code push an
announcement to the accessibility target of the active runtime. The runtime
ignores calls that occur outside a running runtime.

## Reduced Motion

The runtime resolves a motion policy that authored views can read as
`EnvironmentValues.accessibilityReduceMotion`. Built-in animated views honor
it: `Spinner` renders static text, `PhaseAnimator` renders only its first
phase without cycling, and `AnimatedImage` renders its first frame.

Automatic capture detection is separate from that accessibility preference.
`CI=true`, redirected stdout, `SWIFTTUI_STABLE_OUTPUT=1`, and
`--stable-output` select deterministic rendering for built-in animation, but
they do not change `accessibilityReduceMotion` as observed by app code.

## Output-Mode Detection

The output, glyph, motion, and stable-output policies are resolved from the process environment
and the TTY state at session start. The precedence is fixed:

1. `NO_COLOR` / `CLICOLOR=0`, then `FORCE_COLOR` / `CLICOLOR_FORCE`.
2. `SWIFTTUI_JSON=1` selects JSON output.
3. `SWIFTTUI_ACCESSIBLE=1` is shorthand for `SWIFTTUI_REDUCE_MOTION=1` plus
   `SWIFTTUI_CURSOR_FOLLOWS_FOCUS=1`, and wins over explicit `0` values on
   those two variables.
4. `SWIFTTUI_STABLE_OUTPUT` explicitly controls deterministic capture output.
5. `CI=true` and a non-TTY stdout imply stable output, without changing the
   accessibility preference.

The full environment-variable reference lives in the `SwiftTUIRuntime` article
[Environment Variables](https://swifttui.sh/docs/documentation/swifttuiruntime/environment-variables).

## Current Limits

Assistive-technology interaction is currently one-way. Runtime focus is
presented to VoiceOver, TalkBack, and the browser tree, but focus traversal is
not fed back into SwiftTUI's runtime. The semantic snapshot also has no action,
adjustment, or control-value route, so native and browser accessibility trees
present the interface but do not yet activate or adjust SwiftTUI controls.

## See Also

- <doc:Focus>
- <doc:Authoring-Views>
- <doc:State-Environment-And-Focus>
