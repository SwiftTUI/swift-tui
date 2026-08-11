# Understanding Focus

The runtime focus model for input routing, state control, and context export.

## Overview

This article explains the SwiftTUI focus implementation. Focus is a runtime
model, not only a set of modifiers. The focus APIs perform these distinct jobs:

- deciding which view receives non-pointing input
- letting app state observe or control that decision
- propagating context outward from the focused area
- shaping how focus moves through irregular layouts
- choosing a starting focus target

The model follows the shape of SwiftUI. This article identifies each intentional
SwiftTUI difference.

The short version:

- Focus routes keyboard input and other non-pointing host input.
- Focus does not belong to every view. Some controls participate automatically.
  Custom controls opt in.
- ``FocusState`` is the main bridge between the runtime focus graph and app state.
- Focused values are a separate mechanism that exports context from the focused subtree or active scene.
- Focus sections influence movement without becoming focusable controls themselves.
- Default-focus APIs decide where focus starts or resets. They are different
  from normal traversal.
- Focus appearance is related to focus, but it is not the same as focus ownership.

## What Focus Is

Focus exists to answer a simple question:

> If the user presses a key, which view receives that input?

Pointer-driven systems do not need focus in the same way because a pointer
provides coordinates. Focus supplies the target when input has no screen
position.

The shape of the model:

- focus is the system that directs non-pointing input
- the focused view is usually visually emphasized
- the runtime handles most ordinary focus behavior automatically
- you intervene when default behavior is not enough

Focus acts like a logical cursor, not a selection model. It tracks the
current target for user input.

## The Core Mental Model

Think of focus as five related but distinct layers.

### Focus Targets

A focus target is a view that can meaningfully receive focus.

Important consequences:

- Not every view is focusable.
- Focus usually lands on authored interactive controls, not incidental
  containers.
- Built-in controls have default behavior chosen by the framework.
- Custom controls opt in with focus APIs.

Built-in examples:

- text fields are editing-oriented focus targets
- buttons are activation-oriented focus targets

Custom views typically opt in with `.focusable(...)`.

### Current Focus

The focus system tracks one current target for the active context.

The runtime derives several things from that current target:

- the target for keyboard input
- the view that receives visual emphasis
- the focused values that remote UI can read
- the next traversal target after the user presses Tab

### Focus Movement

Focus identifies both the current target and the next target.

The movement rules:

- keyboard traversal generally follows authored order and layout order
- default focus chooses the initial target when focus first enters a screen or scope
- focus sections can enlarge the logical movement target without turning containers into controls

This is one of the places where layout and focus meet. The geometry of the placed interface affects movement.

### Programmatic Focus Control

``FocusState`` and related modifiers expose programmatic focus control.

This gives you a bidirectional link:

- when focus moves in the UI, your state updates
- when your state updates, the framework can move focus in response

That is the core of programmatic focus:

- move the cursor to the invalid field in a form
- focus a newly inserted row or text field
- restore a preferred target when a view appears

### Focus Context Propagation

Focused values do not identify who is focused. They identify the context that
the focused area exports.

This is a different job:

- ``FocusState`` answers "which thing is focused?"
- focused values identify the data that other UI can read from the focused area

Focus ownership and focus-derived context are separate subsystems.

## The Main API Families

### `FocusState` And `.focused(...)`

``FocusState`` is the main state bridge into the focus system.

You use it in two common shapes:

- `Bool` for "is this one thing focused?"
- `Optional<Hashable>` for "which one of these mutually exclusive things is focused?"

```swift
struct LoginView: View {
    enum Field: Hashable {
        case email
        case password
    }

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack {
            TextField("Email", text: $email)
                .focused($focusedField, equals: .email)

            SecureField("Password", text: $password)
                .focused($focusedField, equals: .password)

            Button("Submit") {
                if email.isEmpty {
                    focusedField = .email
                } else {
                    focusedField = nil
                }
            }
        }
    }
}
```

Semantics:

- `.focused($binding)` links a single focusable view to a `Bool` focus state.
- `.focused($binding, equals: value)` links a view to one case or identifier in a larger focus state.
- Setting the state moves focus when the runtime can resolve the target.
- Clearing the state with `nil` or `false` dismisses that local focus relationship.

This is the main tool for:

- form validation
- programmatic keyboard dismissal
- auto-focusing inserted content
- conditional styling driven by focus placement

#### `defaultFocus`

`.defaultFocus` identifies the preferred target for the first UI evaluation.

```swift
struct GroceryListView: View {
    @FocusState private var focusedItemID: UUID?
    let lastItemID: UUID

    var body: some View {
        List { /* fields */ }
            .defaultFocus($focusedItemID, lastItemID)
    }
}
```

What it does:

- asks the runtime to seed focus by writing a value into a ``FocusState`` binding
- works with the same identifiers you already use for `.focused(_:equals:)`

Default focus is part of the ``FocusState`` model. It is not a separate focus
storage mechanism.

#### Namespace-Scoped Default Focus

SwiftTUI also supports the namespace-scoped default-focus family:

- `.focusScope(namespace)` marks the subtree whose default-focus candidates
  belong to `namespace`
- `.prefersDefaultFocus(_:in:)` registers a preferred focus candidate in that
  namespace
- `EnvironmentValues.resetFocus` provides a ``ResetFocusAction`` that asks the
  runtime to reevaluate the namespace's preferred focus

```swift
struct LoginView: View {
    @Namespace private var namespace
    @State private var complete = false

    var body: some View {
        EnvironmentReader(\.resetFocus) { resetFocus in
            VStack {
                TextField("Username", text: .constant(""))
                    .prefersDefaultFocus(!complete, in: namespace)

                Button("Submit") {}
                    .prefersDefaultFocus(complete, in: namespace)

                Button("Reset") {
                    complete = false
                    resetFocus(in: namespace)
                }
            }
            .focusScope(namespace)
        }
    }
}
```

This API uses the same runtime focus tracker as keyboard traversal, pointer
activation, and ``FocusState`` synchronization. If a preferred candidate is not
currently focusable, reset falls back to the first focusable region in the
namespace scope.

### `.focusable(...)` And Custom Controls

Built-in controls participate in focus where appropriate. Custom controls must
opt in.

That is what `.focusable(...)` is for.

```swift
struct RatingPicker: View {
    let options = ["1", "2", "3", "4"]
    @State private var selection = 2

    var body: some View {
        HStack {
            ForEach(options.indices, id: \.self) { index in
                Text(options[index])
            }
        }
        .focusable(interactions: .edit)
    }
}
```

The current model distinguishes interaction intent:

- `.activate`: focus is an alternative path to activation
- `.edit`: focus is used to continuously update state over time
- `.automatic`: let the runtime choose

Note:

- opting a container into `.focusable(...)` means you are authoring it as a control, not just styling it

### Reading Or Styling Focus

Two important environment values for focus styling:

- `@Environment(\.isFocused)` tells a view whether it is in the currently focused context
- `@Environment(\.isFocusEffectEnabled)` tells a view whether focus effects
  currently render

And one modifier controls the default visual effect:

- `.focusEffectDisabled()`

These APIs are about appearance and local reaction, not about moving focus.

```swift
struct FocusAwareLabel: View {
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Text("Library")
            .padding(8)
            .background(isFocused ? .blue.opacity(0.2) : .clear)
    }
}
```

Important distinction:

- A view can stay logically focused after you disable or replace the default
  focus effect.
- Focus-effect customization does not create focusability by itself.

### Focused Values

Focused values export context to remote parts of your interface.

The model is like custom environment values. It uses the focused subtree as
the key instead of plain ancestry.

You define a key:

```swift
struct SelectedRecipeKey: FocusedValueKey {
    typealias Value = Binding<Recipe>
}

extension FocusedValues {
    var selectedRecipe: Binding<Recipe>? {
        get { self[SelectedRecipeKey.self] }
        set { self[SelectedRecipeKey.self] = newValue }
    }
}
```

You publish the value from the focused area:

```swift
struct RecipeView: View {
    @Binding var recipe: Recipe

    var body: some View {
        Text(recipe.title)
            .focusedSceneValue(\.selectedRecipe, $recipe)
    }
}
```

And you read it remotely:

```swift
struct RecipeCommands: View {
    @FocusedBinding(\.selectedRecipe) private var selectedRecipe: Recipe?

    var body: some View {
        Button("Add to Grocery List") {
            if let selectedRecipe {
                addRecipe(selectedRecipe)
            }
        }
        .disabled(selectedRecipe == nil)
    }
}
```

The important parts of the model:

- `FocusedValueKey` defines the key space.
- `FocusedValues` is the container.
- `.focusedValue(...)` publishes a value for the currently focused subtree.
- `.focusedSceneValue(...)` publishes scene-level context for the active scene.
- ``FocusedValue`` reads an optional value.
- ``FocusedBinding`` reads a binding and unwraps it into value-style access.

This is especially important for:

- app commands and menus
- command routing
- cross-tree coordination that follows focus instead of direct containment

Focused values are dynamic and contextual:

- when focus changes, the visible focused values can change
- when the active scene changes, the visible scene-focused values can change

### Focus Sections

`focusSection()` is a movement API, not a control API.

It helps traversal when focusable items are too small or too far apart for
geometry alone.

What a focus section does:

- it makes the container's frame participate as a movement target
- it guides focus toward the nearest focusable descendant
- it does not itself become a focus stop

`focusSection()` does not make a container a control. It uses the larger region
to guide movement toward the controls inside it.

A focus section helps only when its frame is larger than its contents. It
cannot guide movement through geometry that it does not occupy.

## Movement And Traversal Semantics

### Keyboard Traversal

The default keyboard model:

- focus starts at the top-most control nearest the leading edge
- pressing Tab moves focus forward in layout order
- reaching the end wraps back to the beginning

That is a useful baseline model, but authors still influence it by:

- which controls are focusable at all
- which controls are disabled or hidden
- how geometry is laid out
- where focus sections enlarge movement targets
- which target is chosen as the default focus candidate

### Initial And Reset Focus

There are two related questions:

- Which target receives focus when a screen first becomes active?
- After focus is cleared or reset, where does it go next?

The runtime answers those with default-focus modifiers tied to ``FocusState``
and namespace-scoped reset through ``ResetFocusAction``.

## What The Runtime Decides For You Versus What You Author

The runtime and your code have separate responsibilities.

The runtime decides:

- how the built-in controls participate by default
- how focus is visually emphasized unless you opt out
- how ordinary traversal follows layout order
- how to propagate the currently active focused values once you publish them

You author:

- which custom views are focusable
- what focus state identifiers represent
- which value is written when a target becomes focused
- the data that focused values export
- the places where focus sections enlarge traversal targets
- the preferred default-focus target

This separation is a useful design constraint. Confusing focus behavior usually
means that a responsibility is in the wrong layer.

## Common Mistakes

### Treating Focus As Generic Selection State

Focus is about input routing, not arbitrary selection. Some selected things are not focused, and some focused things are not part of any broader selection model.

### Confusing Focus Effect With Focus Ownership

The focus ring, lift, or highlight is presentation. Disabling or replacing the effect does not mean the view is no longer focused.

### Making Containers Focusable By Accident

If a container only guides movement, use `focusSection()`. If it is a control,
use `.focusable(...)`. These are different authoring decisions.

### Using Focused Values For Plain Parent-Child Data Flow

Focused values are best for remote, focus-dependent context such as commands and active-scene actions. They are not a general replacement for environment values, bindings, or plain model injection.

### Forgetting Scene Semantics

`focusedSceneValue(...)` is intentionally scene-aware. In multi-window apps, what commands see depends on which scene is active.

## Practical Implications For SwiftTUI

For a SwiftUI-faithful terminal runtime, the practical takeaways are:

- focus must attach to authored controls, not to layout containers by accident
- ``FocusState``-style bindings and focused values are separate systems
- traversal policy uses geometry, not only a linear order
- focus sections influence routing without becoming focus stops
- default-focus behavior is separate from ordinary next/previous traversal
- scene-focused context matters for multi-window and command routing

This matches the project's design intent:

- explicit `.focusable(...)` modifiers are authoritative
- containers do not become focus stops accidentally
- focused values and focus state are part of SwiftUI-faithful runtime semantics, not convenience extras
- focus-chain membership is the activation predicate for command availability.
  Action scopes and key/palette commands are part of the public authoring
  surface.

## Focus Highlight In `List`

The focus highlight in `List` has the shape of a row, not the container. The
active row receives chrome with `isFocused: true, isSelected: true`. The list
container stays neutral.

## See Also

- <doc:State-Environment-And-Focus>
- <doc:State-Keying>
- <doc:Authoring-Views>
