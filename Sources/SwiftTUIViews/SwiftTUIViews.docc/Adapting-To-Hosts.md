# Adapting an Interface to Its Host

Keep one SwiftTUI view tree while adapting layout and interaction to a terminal,
browser, or native touch surface.

## Share the model and the view tree

The host supplies rendering, input, clipboard, and platform integration.
Your SwiftTUI views own application state, navigation, selection, and actions.
Keep those decisions in the shared tree, and let each host's entry point mount
the app through its runner or scene host. See
[Hosts and Platforms](https://swifttui.sh/docs/documentation/swifttuiruntime/hosts-and-platforms)
for the supported deployment paths and their limits.

Shared source does not require identical interaction on every device. A dense
keyboard workspace and a phone screen can share the same state owners and
commands while presenting different layouts and control sizes.

## Read capabilities instead of guessing the platform

`EnvironmentValues.pointerInputCapabilities` describes the current input host.
Its `supportsScrollPanning` flag is the runtime's touch-style scrolling policy:
when true, a drag can pan scroll content. On a terminal or macOS, a press-drag
remains a click-drag. Use that policy when choosing touch-oriented chrome:

```swift
struct PlaybackControls: View {
  @Environment(\.pointerInputCapabilities) private var pointer
  @State private var isPlaying = false

  var body: some View {
    Button(isPlaying ? "Pause" : "Play") {
      isPlaying.toggle()
    }
    .padding(.horizontal, pointer.supportsScrollPanning ? 2 : 1)
    .padding(.vertical, pointer.supportsScrollPanning ? 1 : 0)
    .buttonStyle(.bordered)
  }
}
```

This capability is an interaction policy, not a device-name or screen-size
test. Use the available layout proposal to decide whether content fits beside
an inspector, belongs in a separate navigation destination, or needs scrolling.
Keep view identity and model ownership stable when changing that presentation.

Cell dimensions are not points or pixels. Padding by one row increases the
target by the host's actual cell height. Check the rendered target on the
intended device and font size instead of assuming a fixed point conversion.

## Make actions reachable by touch and keyboard

Expose primary actions as `Button`, `Toggle`, `Picker`, and other semantic
controls. Add keyboard commands as an additional route to the same action.
An icon-only action needs an authored accessible label; built-in styles
preserve that label.

Use `onMoveCommand` and `onExitCommand` for arrows and Escape that belong to the
focused region. Return `.ignored` when the region does not consume the event,
so enclosing handlers and default navigation can continue. These routes do not
replace visible Back, Cancel, or Close controls on touch surfaces.

Prefer a navigation destination or `fullScreenCover` for a substantial phone
editor. A full-screen cover occupies the entire proposal and supplies no
implicit close button, so give its content a visible action that clears the
presenter's binding. See <doc:Commands-And-Key-Input>,
<doc:Navigation-And-Tabs>, and <doc:Dismissal-Is-Data>.

## Let the host manage text entry

The native SwiftUI host presents the software keyboard when a text-input
control receives focus. Its optional keyboard toggle is configured with
`SwiftUIHostConfiguration(showsKeyboardToggleButton: true)` and appears only
when no text-input control is focused. Enable it when a keyboard-driven tool
benefits from manual access; ordinary touch navigation should have visible
controls. The [SwiftUI host README](https://github.com/SwiftTUI/swift-tui-swiftui#readme)
shows the integration.

Keyboard focus and scrolling are separate. Moving focus into offscreen content
reveals it, while a wheel or pan can move the viewport without changing
selection. Nested scroll containers hand unused wheel input outward at their
boundaries. See <doc:Focus> and <doc:Scrolling>.

## Keep model lifetime separate from visibility

Deselected tabs archive authored `@State`, including owned model references,
while their view trees and lifecycle registrations leave the active graph.
Returning restores state and starts view tasks again. Put a model above the
tab or navigation boundary when it must also survive removal of that boundary
or serve several destinations. An application task stored inside a model is
still owned by the application; the view lifecycle does not cancel it.

Use stable data IDs for lists and lazy content, and keep each presentation's
binding with its source. That gives a responsive layout change a stable state
owner instead of creating an accidental reset. See <doc:Dormant-Tab-State> and
<doc:State-Keying>.

## Respect drawing and accessibility contracts

All hosts share cell-based layout, authored image ordering, and shape clip
coverage. `clipShape` changes drawing without changing hit testing; use
`contentShape` separately for the interaction region. A native host can draw
with pixels without changing the shared view's cell coordinate system.

Read `accessibilityReduceMotion` when authoring decorative effects. Built-in
animations settle under reduced motion, animated images use a static frame,
and animation completion callbacks still run. Keep essential status visible
without requiring motion or color alone.

Semantic presentation and assistive actions are different host capabilities.
The native Apple overlay exposes roles, labels, hints, and runtime focus to
VoiceOver, but assistive-origin focus and actions are not routed back into
SwiftTUI. Consult <doc:Accessibility> and the host's documentation when
qualifying an accessibility workflow.

## Validate on the destination host

Use deterministic frame rendering to check shared layout and state. Then run
the interaction on its destination host: touch panning, text entry, focus
movement, pointer targets, keyboard dismissal, and resizing. A successful
terminal snapshot does not establish native keyboard or accessibility behavior.

## See Also

- <doc:Shapes>
- <doc:Animating-Views>
- <doc:Collections>
