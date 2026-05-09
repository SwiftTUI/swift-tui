# Accessibility

This page is the durable reference for shipped accessibility behavior in
SwiftTUI. The long research record remains in
[`proposals/ACCESSIBILITY.md`](proposals/ACCESSIBILITY.md); this page describes
what app authors and host-package maintainers can rely on today.

## Model

Accessibility data is produced during the shared `semantics` phase:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

The semantic snapshot is the source of truth for terminal accessible output,
Web/WASI ARIA, the embedded WebHost browser runtime, and the SwiftUI host
accessibility overlay. App code should not maintain a parallel accessibility
tree for each target.

The public semantic record is `AccessibilityNode`, which carries:

- stable node identity and optional parent identity
- cell-space bounds
- `AccessibilityRole`
- optional label and hint
- hidden state
- optional live-region priority
- optional cursor anchor for terminal cursor-following mode

Built-in controls publish roles and labels where the framework can infer them
from authored content. Authors add or override semantics with view modifiers.

## Authoring API

Use the SwiftUI-shaped modifiers on `View`:

```swift
Text("Save")
  .accessibilityRole(.button)
  .accessibilityLabel("Save changes")
  .accessibilityHint("Writes the current document to disk")
```

Available authoring modifiers:

- `.accessibilityRole(_:)`
- `.accessibilityLabel(_:)`
- `.accessibilityHint(_:)`
- `.accessibilityHidden(_:)`
- `.accessibilityLiveRegion(_:)`
- `.accessibilityCursorAnchor(_:)`

`AccessibilityRole` includes common controls and structures such as `.button`,
`.link`, `.textField`, `.secureField`, `.textEditor`, `.toggle`, `.slider`,
`.stepper`, `.picker`, `.menu`, `.tabView`, `.image`, `.progressBar`,
`.status`, `.alert`, `.sheet`, `.table`, `.cell`, `.heading(level:)`, and
`.custom(String)`.

`AccessibilityPoliteness` has `.off`, `.polite`, and `.assertive`.

Use `AccessibilityAnnouncer.announce(_:politeness:)` for app-triggered messages
that should reach the active accessibility target:

```swift
AccessibilityAnnouncer.announce("Export complete", politeness: .polite)
```

Calls outside an active SwiftTUI runtime are ignored.

## Runtime Policy

`RuntimeConfiguration` owns the resolved runtime accessibility policy. It can
come from environment detection, `SwiftTUIArguments`, or a host runner.

Important fields:

- `output`: `.tui`, `.json`, or `.accessible`
- `glyphs`: `.unicode` or `.ascii`
- `motion`: `.normal` or `.reduced`
- `noProgress`
- `linear`
- `cursorFollowsFocus`

Accessible CLI output implies ASCII glyphs, reduced motion, no progress
ornament, and linear output. JSON output remains machine output and is not
linearized or annotated for screen readers.

Environment-variable precedence is implemented by
`RuntimeConfiguration.detect(environment:isStdoutTTY:)`:

- `NO_COLOR` wins over forced color.
- `SWIFTTUI_JSON=1` wins over `SWIFTTUI_ACCESSIBLE=1`.
- `SWIFTTUI_ACCESSIBLE=1` implies ASCII, reduced motion, no progress, and
  linear output.
- `SWIFTTUI_CURSOR_FOLLOWS_FOCUS=1` enables terminal cursor-following mode.
- `SWIFTTUI_PLAIN=1` implies no color, ASCII glyphs, and reduced motion.
- `CI=true` implies reduced motion and no progress, but does not imply
  accessible output.
- Non-TTY output implies reduced motion, but does not imply accessible output.

Apps that import `SwiftTUIArguments` get matching flags such as
`--accessible`, `--ascii`, `--reduce-motion`, `--no-progress`,
`--cursor-follows-focus`, and `--web`.

## Reduced Motion

The runtime copies `RuntimeConfiguration.motion == .reduced` into
`EnvironmentValues.accessibilityReduceMotion` before rendering. Consumers can
read or override that environment value in authored views.

Current shipped behavior:

- `Spinner` renders static text when reduced motion is active.
- Indeterminate `ProgressView` renders static status text when reduced motion
  or no-progress mode is active.
- Animation modifiers skip non-essential interpolation when reduced motion is
  active.
- `PhaseAnimator` renders its first phase without starting phase-cycling tasks
  when reduced motion is active.
- `AnimatedImage` renders its first frame without starting a playback task when
  reduced motion is active.
- Transition intermediates and matched-geometry translations snap to the final
  state under the reduced-motion transaction policy.

## Terminal Output

Terminal-native accessibility has two modes:

- Default TUI output keeps the visual terminal interface and can optionally move
  the hardware cursor to the focused accessibility node when
  `cursorFollowsFocus` is enabled.
- Accessible output renders the semantic tree as a linear, append-only text
  stream for screen readers and logs.

Cursor-following uses the focused node's `cursorAnchor` when present and falls
back to the node origin. Built-in text inputs publish caret anchors for
`TextField`, `SecureField`, and `TextEditor`; custom focus targets can publish
an anchor with `.accessibilityCursorAnchor(_:)`.

CLI live-region announcements are delivered in accessible linear output. Normal
TUI mode does not write live-region text to a side channel because that would
corrupt the terminal surface.

## Web And WASI

The `web-surface` protocol carries accessibility data beside raster rows with
an `accessibilityTree` payload. Browser runtimes mount that tree as ARIA beside
the visual canvas, including roles, names, focus state, and live-region
announcements.

This path is used by the WASI web runtime and by binaries that opt into the
embedded WebHost runner. Terminal-only binaries do not link the web server and
reject `--web`.

See [`decisions/0014-accessibility-web-aria-wire-policy.md`](decisions/0014-accessibility-web-aria-wire-policy.md)
for the wire-format policy.

## SwiftUI Host

The SwiftUI host keeps the raster terminal view as the visual layer and mounts
a nonvisual accessibility overlay beside it. Each `AccessibilityNode` maps to a
native accessibility element with role-derived traits, label, hint, frame, and
live-region behavior where the host platform supports it.

SwiftUI host focus is metadata in v1. The host marks the matching semantic node
as focused for ordering and future focus work, but it does not programmatically
move global VoiceOver focus.

See [`decisions/0015-accessibility-swiftui-host-policy.md`](decisions/0015-accessibility-swiftui-host-policy.md)
for the native-host policy.

## Visual Content Policy

Visual-only content must be labeled, hidden, summarized, or explicitly accepted
by review. The semantic extractor warns when visual content such as `Canvas`,
`Image`, animated images, or chart surfaces is unlabeled instead of inventing a
misleading label.

`Scripts/check_accessibility_guardrails.sh` pins reviewed source files that
contain raw glyphs, color-state styling, and visual-only surfaces. Run it
before broad accessibility changes, and use `--update` only after reviewing the
new source for nonvisual semantics.

Manual listening coverage is documented in
[`../Tests/SwiftTUITests/Accessibility/README.md`](../Tests/SwiftTUITests/Accessibility/README.md).

## Remaining Gaps

The shipped accessibility substrate and first target consumers are in place.
The remaining known behavior gaps are:

- Modal presentation focus trapping and focus restoration.
- Richer native focus control in hosted platforms, beyond the current semantic
  focus metadata.

Historical plans and decisions:

- [`plans/2026-05-05-002-accessibility-remaining-work-plan.md`](plans/2026-05-05-002-accessibility-remaining-work-plan.md)
- [`plans/2026-05-05-003-accessibility-cli-runtime-plan.md`](plans/2026-05-05-003-accessibility-cli-runtime-plan.md)
- [`plans/2026-05-05-004-accessibility-web-aria-plan.md`](plans/2026-05-05-004-accessibility-web-aria-plan.md)
- [`plans/2026-05-05-005-accessibility-swiftui-host-plan.md`](plans/2026-05-05-005-accessibility-swiftui-host-plan.md)
- [`decisions/0013-accessibility-runtime-policy.md`](decisions/0013-accessibility-runtime-policy.md)
- [`decisions/0014-accessibility-web-aria-wire-policy.md`](decisions/0014-accessibility-web-aria-wire-policy.md)
- [`decisions/0015-accessibility-swiftui-host-policy.md`](decisions/0015-accessibility-swiftui-host-policy.md)
