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

Ordinary `Text` publishes its full source string as semantic text in layout
reading order, including styled/rich text. Supporting browser hosts expose real
text nodes for native selection and text-unit review. `Text.paragraph()` adds an
explicit paragraph boundary; ordinary newlines do not infer one. Wrapping and
truncation do not shorten the source. An explicit role
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
`ProgressView` and `Spinner` publish progress indicators as described below. Explicit
`accessibilityLabel(_:)` overrides take precedence. See <doc:Style-System> for
the naming contract when a custom style omits its label. Names and roles are
only part of the contract: composite navigation remains host-dependent. The following built-in
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

### Progress And Activity

At current HEAD, every `ProgressView` style publishes one `progressBar` with its
name and completed fraction in `0...1`. The value follows the visual clamp;
indeterminate progress omits the numeric value. An unlabeled indicator is named
“Progress”; supply a task-specific label when several tasks need distinguishing.
The current-value label supplies value text separately from the name, including
generic composed text. Repeated style placement does not repeat that text.
Literal and generic labels remain available when a custom style omits their
slots; authored generic slots retain their state through omission and placement.

Every `Spinner` preset, including custom glyph styles, publishes a progress
indicator with “Inactive”, “In progress”, or “Completed” value text. The active
stage is indeterminate; inactive and finished stages publish zero and one.
Use `.accessibilityLabel("Sync")` to name the activity. A spinner used as style
chrome inside another primitive does not add a second reading item.

These indicators have no adjustment actions or keyboard focus stop. Names and
value text remain available with reduced motion; changing animation glyphs do
not change their semantic content. They are not live regions by default. Use
`AccessibilityAnnouncer` for meaningful completion/failure milestones, or
separate authored live status text when updates need to be announced. Do not
announce every animation tick. Override value wording through
`.accessibilityProperties(.init(valueDescription: "Half received"))` and hide
pure decoration with `.accessibilityHidden()`.

The existing Canvas and DOM browser adapters carry these semantics through WASI
and native WebSocket. This describes source behavior; it does not claim a tagged
release, actual screen-reader acceptance, or an interactive terminal reader.

### Tables, Lists And Outlines

`Table` publishes a static table, including a logical header row, body rows,
column counts and cell positions. Header names remain available when visual
headers are hidden or text is clipped. Set `TableColumn.isRowHeader` for a column
that names its records, and `TableColumn.sort` to the current authored sort order:

```swift
let columns = [
    TableColumn("Person", sort: .ascending, isRowHeader: true),
    TableColumn("Score")
]
```

The application sorts its data through an ordinary button or other authored
operation and updates the column's sort value. A selectable table adds a semantic
Selection column with one pressed-state button per realized row. Each button
uses the table's existing selection binding. Multiple selection toggles that row;
single selection chooses it without writing the same value again. Nested cell
buttons and editors remain separate operations. Read-only and disabled table
semantics prevent selection mutations. This is the static-table pattern with
embedded controls; it does not claim an interactive grid's arrow-key behavior.

`List` publishes structural list items around authored row content, including
logical position and total count. Section rows describe their header
and their position within the section together, while keeping their global list
position. Named containers preserve
the complete text and nested controls inside their rows. Eager and indexed
collections use the same semantics for realized rows; indexed collections retain
bounded materialization and do not expose unrealized rows as hidden controls.

`OutlineGroup` exposes hierarchical list items. Branches begin expanded and offer a
separate button to collapse or expand children; terminal keyboard, pointer and
browser assistive input use the same state. Items expose level and sibling
position; connector glyphs are decorative. Authored row buttons retain their own
actions. The outline does not claim the ARIA tree pattern's managed arrow-key
model. Disclosure state survives row recycling, and only viewport rows evaluate
their content in a bounded scroll region or a direct outline-backed List.

Nonempty lists and tables expose a separate **Review items** position control.
Set its logical position, step, choose first/last or page, then use **Read item**
to move assistive focus to the realized row. **Return to previous item** restores
the previous logical bookmark. Review does not change selection or ordinary
keyboard focus. It remains available when row operations are disabled. Data
changes follow the current ID; removing that ID moves the bookmark to the
nearest surviving position. Old ordinal commands retire when membership changes.

Ordinary `ScrollView` regions offer named page and edge operations for their
axes, including lazy content and nested viewports. These use the viewport's
existing scroll owner. Giving the viewport an accessibility label also names its
operations through sizing wrappers. Text editors keep their own editing model.
Physical scrolling and logical collection review are separate operations.
Verify collection reading, context and operation with the intended reader.

### Composite Controls And Presentations

`TabView` publishes one logical tab list across all strip styles and overflow
layouts. Each tab names the live panel and exposes selection. Browser Left/Right
and Home/End move review among enabled tabs; Enter/Space selects the reviewed
tab. Selection preserves retained child state. Removing a reviewed tab returns
review to a surviving selected tab. Inactive panels are absent from reading.

`Menu` and `DisclosureGroup` publish a trigger button separately from expanded
content. Expansion and content relationships stay valid for inline and floating
styles. Menus expose command roles, disabled state and nested menu scope.
Browser arrows enter and traverse menu commands; Escape/Left closes the current
menu and returns to its trigger. Closing one programmatically also restores the
trigger when the reviewed command departs. These operations use typed runtime
actions, with no duplicate terminal key activation.

Named `NavigationStack` regions expose a **Back** operation while a destination
is active. Sheets, alerts, confirmation dialogs, covers and popovers expose
**Dismiss**. Modal surfaces publish their modal state, exclude background reading
and preserve the full authored content. Standard close controls have a readable
name. Read-only tips remain nonmodal; toasts expose their complete message as a
polite status and have a dismiss operation. Browsers display named operations
as associated buttons. Actual reader announcements and navigation still require
qualification with the supported reader/browser combination.

`AccessibilityProperties.popup` uses ``AccessibilityPopup`` to describe a
control's popup kind; `modal` describes dialog modality. Built-in controls supply
these fields automatically. Supplying either property to a custom element does
not create an operation or a focus scope.

### Assistive Focus And Content Navigation

`@AccessibilityFocusState` binds semantic focus independently of `@FocusState`
and terminal keyboard focus. Use a Boolean for one destination or an optional
hashable value for several destinations:

```swift
@AccessibilityFocusState private var review: String?

Text("Quarterly results")
    .accessibilityRole(.heading(level: 2))
    .accessibilityFocused($review, equals: "summary")
    .accessibilityNavigationCategory("Report sections")
```

Assign `review = "summary"` to request native browser focus on that committed
semantic element; assign `nil` to clear it. Static text does not become a
terminal keyboard stop. Disabled controls remain reviewable but cannot mutate
state. Removed or out-of-modal-scope targets clear their binding; delayed events
from a removed target cannot focus a replacement. Repainting does not repeat an
already-applied focus request. Browser focus changes update the binding only
where the host can observe native semantic focus. A screen reader's independent
virtual review cursor is not exposed by browser DOM focus events.

Repeat `accessibilityNavigationCategory(_:)` to include a destination in several
named groups. Canvas and DOM hosts expose these groups through native controls
in the scene's **Navigate content** panel. Choosing a destination moves semantic
review without sending a keyboard-focus request to the application. Blank names
are ignored and repeated category names are deduplicated. Native heading and
landmark navigation still uses the authored roles. Named groups include committed,
visible destinations; they do not materialize offscreen virtual rows.

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
does not register assistive adjustment. Pair `accessibilityAdjustableAction(_:)`
with `accessibilityValue` for a custom control (see below), or use a styled
built-in control when its behavior fits the task. A changing label alone
cannot substitute for an action route.

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

### Custom controls and actions

Custom controls can register public assistive operations without SPI or fabricated
key events. Keep the accessible name separate from its current value:

```swift
struct RatingPicker: View {
    @Binding var rating: Int

    var body: some View {
        Text("Stars: \(rating)")
            .accessibilityLabel("Rating")
            .accessibilityValue(Double(rating), in: 0...5, description: "\(rating) of 5 stars")
            .accessibilityAdjustableAction { direction in
                rating = min(5, max(0, rating + (direction == .increment ? 1 : -1)))
            }
            .accessibilityAction(named: "Reset rating") { rating = 0 }
    }
}
```

The adjustable callback owns the bounds and the one application mutation. Its
published value is authoritative feedback, not a request to mutate the binding.
The numeric overload supplies range information and an optional spoken value
description in one declaration; the string overload supplies a description alone.
The default `accessibilityAction(_:)` replaces only
assistive activation. Other existing primitive actions remain available.
Named operations compose; an outer operation with the same name replaces the
inner callback. Empty names are ignored. Disabled, read-only, modal-background
and removed controls retain the runtime's committed dispatch guards.

Browsers present an adjustable control as a spinbutton and named operations as
adjacent buttons in a group named after the control. This is a browser-native
operation list, not a VoiceOver custom-actions rotor implementation. Named actions
and adjustment have automated retained-state and browser coverage; actual reader
usability requires qualification for the deployed host and version. Terminal
cursor-following mode does not expose these operations as a semantic reader.

`accessibilityAddTraits(_:)` and `accessibilityRemoveTraits(_:)` support button,
link, image, heading, static-text and selected semantics. Traits describe meaning;
adding a button or link trait alone does not register activation. Browser roles
are mutually exclusive: when several role traits are supplied, static text,
heading, image, link, then button have descending precedence. Selected state is
independent. Use `accessibilityRole(_:)` and `accessibilityProperties(_:)` for an
explicit role, heading level and additional widget state. Device-only SwiftUI
traits have no implied implementation.

`Link`, including a link interpolated into `Text`, publishes its destination
separately from its name. Rich prose exposes text and links once in authored
order; a link inside a control's label remains part of that control's name.
The browser uses a
native anchor for safe HTTP, HTTPS, mail and telephone destinations. Default
links open in the browser (or its configured host link callback); a custom Swift
`OpenLinkAction` or `accessibilityAction` instead receives activation once.
Other schemes retain the typed
application action without an executable browser URL.

`LabeledContent` publishes a named group with its text value, excluding style
chrome and repeated value slots. Interactive content remains independently
readable and operable. Authored names and values survive omitted style slots,
including generic view content. When a style omits a generic slot, the primitive
resolves it once as unpainted semantic content. The first authored occurrence
retains its persistent state when moved between visible and omitted placements;
additional visible copies retain independent state. Names create no extra
keyboard stops or assistive actions. Interactive value content stays operable
through its virtual semantic controls. Browser groups expose
value descriptions as descriptions because ARIA groups have no range value.

Assistive action targets remain stable while the same control is continuously
present in committed semantic frames. Removing and restoring a control issues a
new target even if its root graph owner survives. Requests from the earlier
appearance are rejected before mutation.

### Reduced Motion

A live preference change settles in-flight property, content, insertion, removal
and matched-geometry animations at their model state. Completion barriers fire
once after the settled frame commits. Re-enabling motion does not replay the
interrupted animation. Scroll panning still follows direct input; inertia stops
at the current position and does not restart by itself. These rules also apply
to a subtree's environment override.

`TimelineView(.animation)` holds its displayed instant while motion is reduced.
Periodic and custom schedules still receive `.lowFrequency` so clocks and useful
status can update. Custom timers and animation styles must read
`accessibilityReduceMotion` and provide a static, meaningful presentation;
throttling decorative motion is not sufficient. Keyframes settle finite work at
its endpoint, repeating phase/keyframe effects use their rest pose, and animated
images show their first frame. Progress and activity retain their labels/values.
Blink text emphasis is removed before raster output. Browser focus rings and
carets are static; a terminal application's cursor setting remains host-owned.

Visual motion policy is separate from announcements: do not mark every animation
or timer tick as live content. Use deliberate status changes for useful feedback.
Stable-output capture also suppresses built-in motion, while the public user
preference remains unchanged.


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
SecureField accepts replacement text but never publishes its contents. The
`editText` and `selectText` actions carry directed UTF-16 selection with the
expected text. Selection-only review never writes the application binding;
obsolete text, split graphemes and invalid offsets are rejected. Read-only
controls permit selection review but reject edits. Nonsecure editors publish
selection/caret for browser and ordinary keyboard handoff. Secure controls omit
that state and their value from host snapshots. Input normalization remains
owned by the control (including single-line editing).
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
Browser native editors retain their local composition while Swift frames arrive,
then send the committed value and caret once. Unchanged acknowledgements preserve
the native value and undo history. Nonsecure server selection updates preserve
direction; secure local values are cleared on blur and removal. Native browser
selection, paste and undo remain subject to browser support. Shared host-native
IME/pre-edit presentation is excluded. Committed Unicode, paste and final
composition values are delivered exactly once. Shared runtime
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

Interactive terminal launches through `SwiftTUI` or `SwiftTUIWebHostCLI` offer a
loopback Canvas browser companion before entering full screen. Open the printed
URL to operate the same running scene, or use `--companion-url` from another
terminal to retrieve it. The browser uses bundled assets and does not open
unsolicited. Use `--companion off` to disable it. Redirected/noninteractive
launches do not start it by default. `--web` selects browser-only hosting.
The terminal-only `SwiftTUICLI` product does not include WebHost.
See [Browser Companion](https://swifttui.sh/docs/documentation/swiftuiwebhostcli/browser-companion)
and
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

## Picker selection in current source

`Picker` publishes all options, including rows outside an inline visual viewport,
with their labels, enabled state and opaque identities. Canvas and DOM use a
native select popup for `.menu`, a native listbox for `.inline`/`.automatic`, and
native radio groups for `.radioGroup`/`.segmented`. Browser-native popup state is
local to the browser; selection is sent directly to the Swift binding and the
returned frame supplies the authoritative value. No synthesized key events are
needed. Custom styles can set `accessibilityPresentation`; the default is `.list`.

Use `.disabled(true)` on an option to prevent selection through keyboard,
pointer and assistive routes, and `.accessibilityLabel(_:)` to name an option
without changing its visual text. Options retain identity through updates and
reject retired IDs after removal. Repeated selection of the current option does
not write the binding again. Whole-picker disabled, read-only, hidden and modal
scope policies still apply. Custom styles keep these semantics even if they omit
pointer route wrappers.

Radio and segmented style options that use `option.route` publish the placed
row or segment bounds to matching browser runtimes. These bounds align assistive
outlines and native activation with the rendered choice, excluding the Picker's
title and padding. Custom styles that omit the wrapper retain typed selection
semantics but do not supply precise option geometry.

These are current-source contracts requiring a matching browser runtime. They
are not a 0.15.1 support claim or recorded Safari/VoiceOver task acceptance.

## See Also

- <doc:Focus>
- <doc:Authoring-Views>
- <doc:State-Environment-And-Focus>


## Grouping and semantic representations

Use `accessibilityElement(children: .contain)` to keep related descendants
inside a named group. `.ignore` hides descendants and keeps the parent metadata;
provide the parent's meaning explicitly. `.combine` joins readable labels and
values, and promotes descendant activation/adjustment operations to named actions.
Editing and selection widgets, and default-opening links, keep independent
native surfaces inside the group. `accessibilitySortPriority(_:)` orders sibling
subtrees with larger priorities first; equal values keep authored order.

A representation supplies controls for custom paint without drawing those controls
or adding them to terminal keyboard/pointer traversal:

```swift
Text(isSelected ? "Selected" : "Available")
  .accessibilityRepresentation {
    Toggle("Selected", isOn: $isSelected)
  }
```

Use `accessibilityChildren` to keep the parent's meaning and replace its semantic
children, for example chart data points. Representation closures are authored
views, with normal bindings and retained graph ownership. They reserve no space
in the visual parent's layout. Hidden, disabled, read-only, modal and retired
control guards still apply to typed assistive actions. Browser semantic focus on
a virtual control does not move terminal keyboard focus. This is not a binding
to a screen reader's independent reading cursor.

For a chart, diagram or image that carries data, a short label alone cannot
provide arbitrary values or operations. Use a representation with named source
values, units and relationships, and bind its controls to the same state as the
graphic. Large datasets need bounded review controls or a lazy collection with
logical navigation; do not create a semantic control for every pixel or cell.
Keep decorative graphics hidden. The unlabeled-graphic diagnostic distinguishes
simple descriptions, data/operation representations and decoration; it cannot
infer the meaning of arbitrary drawing commands or image bytes.

```swift
Canvas(trafficDrawing)
  .accessibilityRepresentation {
    VStack {
      Text("Monday: 125 requests; Friday: 180 requests")
      Button("Inspect Friday") { selectedDay = .friday }
    }
  }
```

The representation reserves no visual space, including when its semantic
content is wider or taller than the graphic.

## User preferences

Read `EnvironmentValues.accessibilityPreferences` for the effective optional
choices, or the convenience values `accessibilityReduceMotion`,
`accessibilityDifferentiateWithoutColor`, `accessibilityReduceTransparency` and
`accessibilityColorProfile`. `colorSchemeContrast` honors an explicit contrast
choice before the terminal appearance heuristic. Custom styles receive the same
preferences through `configuration.styleEnvironment.accessibilityPreferences`.

Precedence is authored subtree override, explicit runtime/CLI/environment choice,
then host detection. An explicit `false` or standard profile remains an override;
`nil` inherits. Browser preferences can change live, including while a scene is
retained. Terminal environment variables are startup choices. Preferences express
user intent; labels, patterns and control behavior still need to honor that intent.

### Color and contrast

Enabled, opaque semantic text resolves to at least 4.5:1 against its painted
background in standard mode, including selected rows and tinted surfaces.
The default separator, muted and border palettes retain readable contrast.
Explicit foreground paints, authored fades and disabled treatments keep their
standard-mode appearance; user-selected color profiles and increased contrast
apply the broader policy below.

When reduced transparency is enabled, positive alpha in enabled text, shape,
gradient, tile and direct Canvas-cell paints becomes opaque. Positive view
opacity becomes one at the paint boundary. The authored ancestor cascade is
retained so a subtree's explicit `false` can restore it; live preference changes
repaint retained content. Zero opacity, transparent holes and disabled paints
retain their authored behavior. Image pixel alpha and custom blend effects are
not rewritten; provide an opaque alternative when their transparency obscures
essential information.

The standard profile preserves authored colors. Monochrome uses encoded relative
luminance, including gradients and tile paints. Protanopia/deuteranopia profiles
use a blue/orange semantic vocabulary; tritanopia uses red/cyan distinctions.
Explicit paints map to the selected palette, with neutral colors retaining their
lightness. These choices are palette adaptations, not a simulation of a person's
vision or a guarantee that categories remain distinguishable by hue.

For a selected color profile, enabled raster text is adjusted against its composed
background to target 4.5:1. Increased contrast targets 7:1 and may also change a
mid-luminance background that cannot support that ratio. Adjustments measure
eight-bit sRGB output, including authored alpha and text opacity. Stroke, tile,
Braille and decoration pairs target 3:1; direct Canvas text cells target 4.5:1.
Inactive controls are exempt from contrast adjustment, and invisible content
remains invisible. The resulting raster is shared by browser and terminal hosts.

Color cannot supply meaning alone: retain labels, selected/checked glyphs,
patterns, data alternatives and useful focus indicators. Raster image bytes are
not recolored; provide a description or structured data alternative for an image
that carries information. Applications must audit neighboring graphic colors,
custom blend effects, image content and external CSS separately. Numerical pair
targets are not whole-application WCAG conformance.

The automatic and compact Stepper styles reserve at least 24 by 24 CSS pixels
for each browser increment/decrement route, using the reported web cell metrics.
The two action regions remain separate when text size changes. Terminal cell
layouts retain their cell-sized affordances. Custom styles own the size and
spacing of their routed content, and application layouts must still provide
usable target spacing and avoid clipping controls.

Terminal `capabilityProfile.colorLevel` exposes the detected color repertoire.
With an explicit runtime color-profile/increased-contrast request, automatic
color mode falls back to the terminal's own text colors on ANSI-16/256 hosts,
retaining emphasis and reverse-video focus cues. `--color always` opts into
approximate palette colors; `--color never` suppresses all styling. True-color
terminals retain the adjusted RGB pairs. Remote/client palette customization and
live desktop preferences still require checking the actual terminal; a local
fallback cannot measure an emulator's user-defined palette. Browser companions
provide a separate true-color presentation of the same state.
