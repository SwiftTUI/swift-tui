# Accessibility

SwiftTUI supplies shared semantic metadata and typed actions for supported
built-in controls. Accessibility depends on the control, host, version, and
application task; a label or role alone does not make a custom control operable.

## Overview

Canvas and DOM browser hosts mount a semantic sidecar and route supported
assistive actions back to Swift. Terminal cursor-following moves the hardware
cursor; it does not publish that semantic tree, speak announcements, or provide
an interactive linear reader. The public native SwiftUI host's semantic
presentation does not provide the browser action adapter. iOS and Android
assistive operation require their own qualification; browser VoiceOver evidence
does not establish native-host support.

### When Built-Ins Are Enough

Ordinary `Text` publishes its full source string as a named semantic group in
layout reading order, including styled/rich text and `Text.paragraph()`.
Wrapping and truncation do not shorten that accessible name. An explicit role
(such as a heading or status) and `accessibilityLabel(_:)` still take precedence;
an empty label stays empty. Empty or whitespace-only unannotated text is omitted.
Use `accessibilityHidden()` for decorative text.

Primitive labels and style chrome are represented by their owner's accessible
name rather than separate reading items. A standalone `Label` publishes its
authored title, including when its style displays only the icon. Disclosed and
menu content remains independently readable, and nested controls retain their
own names. An explicitly named aggregate represents unannotated descendant text
with that name; explicitly annotated children retain their own semantics.
These semantics supply content to host adapters; actual assistive
reading remains subject to each host's qualification boundary.

Built-in controls publish their own roles: `Button`, `Toggle`, `TextField`,
`SecureField`, `TextEditor`, `Slider`, `Stepper`, `Picker`, `Link`, `Menu`,
and `DisclosureGroup` each attach the matching `AccessibilityRole` and
participate in focus. Styled controls publish their authored title or composed
label as their accessible name, excluding style chrome and displayed values.
`TextField` and `SecureField` retain their titles when showing entered text.
`ProgressView` publishes its label with the status role. Explicit
`accessibilityLabel(_:)` overrides take precedence. See <doc:Style-System> for
the naming contract when a custom style omits its label. Names and roles are
only part of the contract: Picker selection, composite navigation, and table
relationships do not yet have complete assistive support. The following built-in
controls register their own supported actions without extra annotations:

```swift
VStack(alignment: .leading, spacing: 1) {
    TextField("Title", text: $title)
    Toggle("Include focused tests", isOn: $includeTests)
    Button("Save draft") { save() }
}
```

Reach for the accessibility modifiers when you:

- build a custom control out of `Text`, shapes, or `Canvas`
- show visual-only content (images, charts, animation) that needs a label
- surface changing status text that a screen reader should track
- hide decorative content from assistive technology

### Choosing An Operable Adjustable Control

Use a built-in `Stepper` or `Slider` for adjustment. These controls register
increment, decrement, and value-setting actions as well as keyboard behavior:

```swift
struct RatingControl: View {
    @State private var rating = 3

    var body: some View {
        Stepper("Rating", value: $rating, in: 1...5)
            .accessibilityHint("Choose one to five stars.")
    }
}
```

Adding `.accessibilityRole(.slider)` and arrow-key handlers to a custom drawing
does not register assistive adjustment. Public custom action registration and a
separate authored value modifier are absent. A changing label describes state;
it cannot substitute for an action route. Prefer a styled built-in control when
its behavior fits the task.

In cursor-follows-focus terminal mode, the hardware cursor parks on the
focused view's origin by default; `.accessibilityCursorAnchor(_:)` moves that
anchor to another `CellPoint` within the view's bounds when a different cell
reads better. Outside that mode, the hardware cursor shows only at a focused
text input's caret.

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
runtime are ignored. Delivery requires a host announcement adapter; the terminal
cursor mode does not speak these messages. Verify ordering, repetition, and
focus stability with the intended screen reader.

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
both `--reduce-motion` and `--cursor-follows-focus`. It does not imply
`--no-color` or `--ascii`, start a browser, or select a sequential reader.
Built-in animated views
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

### Host action contract

Semantic control nodes publish an opaque `actionTarget`, supported `actions`,
enabled state, and a typed value where applicable. Hosts return an
`InputEvent.accessibility(AccessibilityActionRequest)` to the owning scene.
The runtime resolves that token against its committed tree and active focus
scope before dispatching through the control's retained action registration.
Removed/recreated targets, disabled controls, hidden content, modal background
controls, unsupported actions, and invalid value types are rejected.

Buttons support focus and activation. Toggle and DisclosureGroup also accept
boolean values. Slider and Stepper accept increment, decrement, and numeric
values within their bounds. TextField and TextEditor accept replacement text;
SecureField accepts replacement text but never publishes its contents. Input
normalization remains owned by the control (including single-line editing).
Repeated focus and value echoes do not write the binding or schedule new work.

See `docs/ACCESSIBILITY.md` in the source repository for the additive host-wire
format. The current `@swifttui/web` adapter connects assistive focus,
activation, adjustment and supported value edits to this contract. It mounts
one semantic sidecar for either presenter; the visible DOM text does not create
a duplicate accessible control tree. Older tagged hosts and producers may
provide only semantic presentation. Native host packages must connect their
assistive callbacks before those interfaces become operable; they have their
own qualification boundaries.

The browser's DOM presenter is **experimental and opt-in** (`renderer: "dom"`);
Canvas remains the default. Bounded Safari/VoiceOver control journeys have
human acceptance; the complete DOM assistive matrix remains open. Qualification is
scoped to macOS desktop; Windows High Contrast and physical mobile acceptance
are outside that scope. Ordinary prose passes narrow-width and doubled-text
WASI checks. Uniform CSS letter/word spacing and line height renegotiate the
Swift grid, and live announcements no longer add native Find matches.
`Text.paragraph()` explicitly marks authored paragraphs. Supporting DOM hosts
request uniform paragraph spacing through captured geometry; Swift reserves the
additional whole rows. Ordinary text and newlines do not infer boundaries.
There is no full WCAG conformance claim.
Shared host-native IME/pre-edit presentation is excluded. Committed Unicode,
paste and final composition values are delivered exactly once. Shared runtime
tests and browser automation do not establish VoiceOver, TalkBack, or WCAG
conformance. The browser package's
[DOM support statement](https://github.com/SwiftTUI/swift-tui-web/tree/main/packages/web#experimental-support-boundary)
documents the tested profile, selection/find limits, and other known exclusions.

## Version and application responsibilities

The default public dependency is release `0.15.1`. Ordinary static-text extraction
was added after that release in framework commit
[`5519ebb2`](https://github.com/SwiftTUI/swift-tui/commit/5519ebb246f556df217389c599617e17bfb5f2d4).
Its recorded Safari/VoiceOver reading journey used the DOM presenter and a
coordination candidate, not a fresh `0.15.1` consumer. It covers reading order,
full paragraphs, names and a button-driven count update; it does not prove
character navigation, text selection, every control, or the Canvas listening
journey. Pair producer and browser versions when evaluating a capability.

Authors still supply meaningful names for icon-only actions, descriptions and
alternatives for charts/images/custom Canvas drawing, useful validation messages,
and logical task structure. Charts do not expose navigable data automatically;
embedded TerminalView pixels do not expose the embedded program's controls or
history as a semantic application. Provide a task-complete alternative and test
it. Check reading, action, error recovery, focus, dynamic feedback, color and
motion on each supported host; naming the container is insufficient.

`--web` explicitly selects a browser session on platforms with the WebHost
runner. Terminal and browser launch are mutually exclusive; terminal launch does
not start a companion server, and Windows does not include WebHost. See
[Hosts And Platforms](https://swifttui.sh/docs/documentation/swifttuiruntime/hosts-and-platforms).

## Authored paragraph spacing

Apply paragraph semantics after styling the text:

```swift
VStack(alignment: .leading, spacing: 1) {
  Text("First paragraph.").bold().paragraph()
  Text("Second paragraph.").paragraph()
}
```

Swift owns wrapping and placement. A supporting DOM host measures uniform CSS
paragraph margins and asks Swift to reserve extra bottom rows; removing the
override removes those extra rows. Paragraph boundaries are independent of
accessibility visibility. They contain no duplicate source text. Hosts without
this negotiation retain the authored layout. Overlapping paragraph bounds and
nonuniform paragraph margins are outside this contract.

## See Also

- <doc:Focus>
- <doc:Authoring-Views>
- <doc:State-Environment-And-Focus>

## Optional widget state and relationships

Use `accessibilityProperties(_:)` to supply shared widget state when authoring
custom semantics. `AccessibilityProperties` includes selected, expanded,
required, invalid, busy and read-only states, descriptions, language, reading
structure, collection positions and same-scene identity relationships.
Specified fields merge individually; explicit `false` and empty strings/lists
override earlier values. Match properties to the element's role.

```swift
TextField("Email", text: $email)
  .accessibilityProperties(.init(
    required: true, invalid: emailIsInvalid,
    description: emailIsInvalid ? "Enter a complete email address." : ""
  ))
```

Current Canvas and DOM adapter sources consume these properties. Older browser
adapters ignore them. This metadata does not implement custom actions, an entire
widget interaction pattern, or native host support. Read-only state blocks
assistive mutations; the control author also owns keyboard and pointer editing
policy. See the framework's `docs/ACCESSIBILITY.md` for the source-version and
wire compatibility contract.
