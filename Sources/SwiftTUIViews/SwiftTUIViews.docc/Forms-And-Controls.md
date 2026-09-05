# Forms and Controls

Build a settings form from focusable terminal controls, then wire up
submission, focus movement, and validation.

## Overview

This article assembles a small task-settings form one control at a time:
buttons, toggles, steppers, pickers, sliders, text fields, and a command
menu. Along the way it covers the keys each control answers to.

The interaction model is uniform. Every control is a focus target. Tab
moves focus forward in layout order and wraps; Shift-Tab moves backward.
Return or Space activates the focused control. Arrow keys go to the
focused control first — a slider claims Left/Right, a picker claims its
selection keys — and an unclaimed arrow key moves focus directionally
instead. App-level shortcuts layer on top of this; see
<doc:Commands-And-Key-Input>.

## Start with a button

`Button` pairs a label with an action closure. The title form is the
common case; the trailing-closure form takes any label view:

```swift
struct TaskSettingsForm: View {
  @State private var savedCount = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Button("Save") {
        savedCount += 1
      }
      .buttonStyle(.borderedProminent)

      Button("Discard draft", role: .destructive) {
        savedCount = 0
      }
    }
  }
}
```

Return or Space runs the focused button's action. A `role:` tints the
control's chrome through the terminal theme: `.destructive` draws with
the danger tone, `.cancel` and `.close` mute the label, and `.confirm`
uses the accent tint. Styles come from `buttonStyle(_:)` —
`.automatic`, `.bordered`, `.borderedProminent`, `.plain`, and `.link`.

## Flip a toggle, step a value

`Toggle` binds a `Bool`; `Stepper` nudges a number. Both render as
single focusable rows:

```swift
@State private var remindMe = true
@State private var retries = 3

var body: some View {
  VStack(alignment: .leading, spacing: 1) {
    Toggle("Remind me", isOn: $remindMe)
    Stepper("Retries", value: $retries, in: 0...10)
  }
}
```

Return or Space flips the focused toggle. Left and Right arrows
decrement and increment the focused stepper; `in:` is optional and
`step:` defaults to 1, with `Int` and `Double` forms of both.

## Pick one option

`Picker` selects one tagged value. Give each option a `tag` matching
the selection type:

```swift
private enum Priority: String, CaseIterable, Hashable {
  case low = "Low"
  case normal = "Normal"
  case high = "High"
}

@State private var priority: Priority = .normal

var body: some View {
  Picker("Priority", selection: $priority) {
    ForEach(Priority.allCases, id: \.self) { option in
      Text(option.rawValue).tag(option)
    }
  }
  .pickerStyle(.segmented)
}
```

The default style lists options vertically and changes selection with
Up and Down; `.segmented` lays them out horizontally and uses Left and
Right; `.radioGroup` and `.menu` are also available. Terminal option
rows are single-line text, so SwiftTUI scrapes option content to
labeled text values: an unmodified tagged `Text` is represented
losslessly, and anything richer keeps its extracted text and tag but
reports a runtime issue instead of degrading silently. See
<doc:Divergences-And-Gaps>.

## Slide along a range

`Slider` adjusts a number along a bounded track:

```swift
@State private var effort = 0.5

var body: some View {
  Slider("Effort", value: $effort, in: 0...1)
}
```

Unlike SwiftUI, the `in:` range is required. `Double` sliders are
continuous by default — track drags snap to a fine span-derived quantum
and Left/Right arrows move about a tenth of the span — while `Int`
sliders default to `step: 1`. See <doc:Divergences-And-Gaps>.

## Edit text

`TextField` edits a single-line string. Its title names the control for
accessibility and doubles as the placeholder while the field is empty.
`SecureField` has the same shape but masks the rendered value.
`TextEditor` edits multiline text; give it a frame so the layout
reserves rows for it:

```swift
@State private var title = ""
@State private var passphrase = ""
@State private var notes = ""

var body: some View {
  VStack(alignment: .leading, spacing: 1) {
    TextField("Title", text: $title)
      .textFieldStyle(.roundedBorder)
    SecureField("Passphrase", text: $passphrase)
    Text("Notes")
    TextEditor(text: $notes)
      .frame(height: 6)
  }
}
```

While a text input is focused it consumes editing keys: characters
insert, Backspace and Delete remove, Left/Right move the cursor, and
Home/End jump to the ends of the line. Ctrl- or Alt-modified arrows
move by word, the same modifiers with Backspace delete a word, Ctrl+A
selects all, and Ctrl+C, Ctrl+X, and Ctrl+V copy, cut, and paste a
selection. Tab still leaves the field, so traversal keeps working
inside a form.

## Submit and move focus

`onSubmit(_:)` runs when Return submits a focused `TextField` or
`SecureField`. A `TextEditor` inserts a newline instead and never
submits. Pair submission with `@FocusState` to walk focus through the
form:

```swift
private enum Field: Hashable {
  case title
  case passphrase
}

@FocusState private var field: Field?

var body: some View {
  VStack(alignment: .leading, spacing: 1) {
    TextField("Title", text: $title)
      .focused($field, equals: .title)
      .onSubmit { field = .passphrase }
    SecureField("Passphrase", text: $passphrase)
      .focused($field, equals: .passphrase)
      .onSubmit { save() }
  }
}
```

Writing to the focus state moves focus; the runtime writes it back as
focus moves. Every enclosing `onSubmit` action runs, innermost first,
and `submitScope(_:)` stops a submission from propagating further up.
SwiftTUI omits the `of: SubmitTriggers` parameter and `submitLabel`
(see <doc:Divergences-And-Gaps>). For choosing where focus starts, and
for the rest of the focus model, see <doc:Focus>.

## Validate and disable

Gate an action by disabling its control. `disabled(_:)` applies to any
subtree:

```swift
Button("Save") {
  save()
}
.disabled(title.isEmpty)
```

A disabled control renders with muted chrome, ignores activation, and
drops out of focus traversal, so Tab skips straight to the next enabled
control. Simple validation is therefore just state: derive the
condition from your bindings and let the form re-render.

## Group commands in a menu

`Menu` collapses related actions behind one focusable trigger row:

```swift
Menu("Actions") {
  Button("Save draft") { save() }
  Divider()
  Button("Reset form", role: .destructive) { reset() }
}
```

The trigger renders inline as `Actions ▾`, taking one row. Activating
it floats the content above the surrounding layout without reflowing
siblings, and Escape dismisses the topmost open menu. The menu is
non-modal and currently anchors at the presentation host's top-leading
corner rather than at the trigger — a recorded gap; see
<doc:Divergences-And-Gaps>. For Escape's wider dismissal contract
across sheets and other presentations, see <doc:Dismissal-Is-Data>.

Use `.menuStyle(.button)`, `.borderlessButton`, or `.inline` to change the
treatment. A custom ``MenuStyle`` composes the captured label with
`configuration.trigger { ... }`. For floating content, wrap that inline anchor
in `configuration.portal(presentation: .init()) { ... }`; the portal presents
`configuration.content` and Menu retains activation and Escape handling.
An inline style includes `configuration.content` when `isPresented` is true.

``ControlGroup`` uses `.automatic` or `.horizontal` for a labeled row,
`.vertical` for a column, and `.compactMenu` for a Menu containing the authored
controls. Switching these styles preserves child identity and persistent state.
Closed compact content has no focus targets or active control actions.

## See Also

- <doc:Focus>
- <doc:Commands-And-Key-Input>
- <doc:Dismissal-Is-Data>
- <doc:Divergences-And-Gaps>
