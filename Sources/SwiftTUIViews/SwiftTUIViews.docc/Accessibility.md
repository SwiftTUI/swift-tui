# Accessibility

Attach semantic metadata to views so terminal screen readers, browser ARIA
trees, VoiceOver, and TalkBack can present your interface.

## Overview

Every SwiftTUI frame carries semantics alongside its rendered cells, and each
presentation path reads the same semantics: the terminal presents them through
cursor-follows-focus mode for terminal screen readers, the Web/WASI host
mounts them as an ARIA tree beside the raster canvas, and the SwiftUI and
Android hosts map them to VoiceOver and TalkBack.

Most interfaces get correct semantics for free. Annotation is for custom
controls and for visual-only content.

### When Built-Ins Are Enough

Built-in controls publish their own roles: `Button`, `Toggle`, `TextField`,
`SecureField`, `TextEditor`, `Slider`, `Stepper`, `Picker`, `Link`, `Menu`,
and `DisclosureGroup` each attach the matching `AccessibilityRole` and
participate in focus. `TextField` and `SecureField` also publish their title
as the accessible label. A plain form needs no annotation at all:

```swift
VStack(alignment: .leading, spacing: 1) {
    TextField("Title", text: $title)
    Toggle("Include focused tests", isOn: $includeTests)
    Picker("Priority", selection: $priority) {
        ForEach(Priority.allCases, id: \.self) { priority in
            Text(priority.rawValue).tag(priority)
        }
    }
    Button("Save draft") { save() }
}
```

Reach for the accessibility modifiers when you:

- build a custom control out of `Text`, shapes, or `Canvas`
- show visual-only content (images, charts, animation) that needs a label
- surface changing status text that a screen reader should track
- hide decorative content from assistive technology

### Annotating A Custom Control

A custom control opts into focus with `.focusable(_:interactions:)` and then
describes itself with `.accessibilityRole(_:)`, `.accessibilityLabel(_:)`,
and `.accessibilityHint(_:)`:

```swift
struct RatingPicker: View {
    @State private var rating = 3

    var body: some View {
        HStack {
            ForEach(1...5, id: \.self) { star in
                Text(star <= rating ? "*" : ".")
            }
        }
        .focusable(interactions: .edit)
        .onKeyPress(.arrowRight) { _ in
            rating = min(rating + 1, 5)
            return .handled
        }
        .onKeyPress(.arrowLeft) { _ in
            rating = max(rating - 1, 1)
            return .handled
        }
        .accessibilityRole(.slider)
        .accessibilityLabel("Rating: \(rating) of 5 stars")
        .accessibilityHint("Use the left and right arrows to adjust.")
    }
}
```

SwiftTUI has no separate value modifier, so fold the current value into the
label, as above. Because the label is re-resolved on every state change,
assistive technology always reads the current value.

In cursor-follows-focus terminal mode, the hardware cursor parks on the
focused view's origin by default; `.accessibilityCursorAnchor(_:)` moves that
anchor to another `CellPoint` within the view's bounds when a different cell
reads better.

### Announcements

For events with no natural place in the view tree — a save completing, a
background failure — push a message imperatively with
``AccessibilityAnnouncer``:

```swift
Button("Save draft") {
    save()
    AccessibilityAnnouncer.announce("Draft saved", politeness: .polite)
}
```

`announce(_:politeness:)` accepts `AccessibilityPoliteness` values `.off`,
`.polite` (default), and `.assertive`. Calls made outside a running SwiftTUI
runtime are ignored.

### Live Regions And Hidden Content

For status text that updates in place, mark the region live so screen readers
speak changes without moving focus, and hide purely decorative content:

```swift
VStack(alignment: .leading) {
    LabeledContent("Priority", value: priority.rawValue)
    LabeledContent("Focused tests", value: includeTests ? "yes" : "no")
}
.accessibilityLiveRegion(.polite)

Text("~~~~~~~~~~")  // decorative divider
    .accessibilityHidden()
```

`.accessibilityHidden(_:)` defaults to `true`; pass `false` to re-expose a
subtree conditionally.

### Reduced Motion

The `--reduce-motion` flag (or `SWIFTTUI_REDUCE_MOTION=1`) suppresses
animations and spinners, and `--accessible` (`SWIFTTUI_ACCESSIBLE=1`) implies
both `--reduce-motion` and `--cursor-follows-focus`. Built-in animated views
honor the preference: `Spinner` renders static text, `PhaseAnimator` holds
its first phase, and `SwiftTUIAnimatedImage` shows its first frame. Authored
animation should do the same:

```swift
struct PulseBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Text("● Recording")
        } else {
            PhaseAnimator([true, false]) { phase in
                Text(phase ? "● Recording" : "○ Recording")
            }
        }
    }
}
```

### Output Modes

Accessible mode is one of several runtime output policies (color, ASCII,
JSON, stable capture output) resolved from flags, environment variables, and
TTY state at session start. The full list and its precedence rules live in
the `SwiftTUIRuntime` article
[Environment Variables](https://swifttui.sh/docs/documentation/swifttuiruntime/environment-variables).

### Current Limits

Assistive-technology interaction is currently one-way. Runtime focus is
presented to VoiceOver, TalkBack, and the browser tree, but focus traversal
is not fed back into SwiftTUI's runtime, and there is no action, adjustment,
or control-value route, so native and browser accessibility trees present
the interface but do not yet activate or adjust SwiftTUI controls.

## See Also

- <doc:Focus>
- <doc:Authoring-Views>
- <doc:State-Environment-And-Focus>
