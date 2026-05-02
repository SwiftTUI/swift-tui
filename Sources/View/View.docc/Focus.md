# Understanding Focus

The runtime focus model: how non-pointing input is routed, how state observes and controls it, and how focused values export context across the tree.

## Overview

This article is a high-level, implementation-oriented explanation of how focus works in SwiftTUI. It treats focus as a runtime model, not just a bag of modifiers, and it tries to separate the distinct jobs that the focus APIs perform:

- deciding which view receives non-pointing input
- letting app state observe or control that decision
- propagating context outward from the focused area
- shaping how focus moves through irregular layouts
- choosing a starting focus target

The model is shaped after SwiftUI's. Where SwiftTUI deviates intentionally, the article calls that out explicitly.

The short version:

- Focus is the routing system for keyboard input (and any other non-pointing input the host exposes).
- Focus does not belong to every view. Some controls participate automatically; custom controls opt in.
- ``FocusState`` is the main bridge between the runtime focus graph and app state.
- Focused values are a separate mechanism that exports context from the focused subtree or active scene.
- Focus sections influence movement without becoming focusable controls themselves.
- Default-focus APIs decide where focus starts or resets; they are not the same thing as normal traversal.
- Focus appearance is related to focus, but it is not the same as focus ownership.

## What Focus Is

Focus exists to answer a simple question:

> If the user presses a key, which view should receive that input?

Pointer-driven systems do not need focus in the same way, because the pointer provides coordinates. Focus provides the missing target information when input is not tied to a point on screen.

The shape of the model:

- focus is the system that directs non-pointing input
- the focused view is usually visually emphasized
- the runtime handles most ordinary focus behavior automatically
- you intervene when default behavior is not enough

That makes focus feel more like a logical cursor than a selection model. It tracks where the user's attention is currently directed for input purposes.

## The Core Mental Model

The most useful way to think about focus is as five related but distinct layers.

### Focus Targets

A focus target is a view that can meaningfully receive focus.

Important consequences:

- Not every view is focusable.
- Focus should generally land on authored interactive controls, not incidental containers.
- Built-in controls have default behavior chosen by the framework.
- Custom controls opt in with focus APIs.

Built-in examples:

- text fields are editing-oriented focus targets
- buttons are activation-oriented focus targets

Custom views typically opt in with `.focusable(...)`.

### Current Focus

At any moment, the focus system tracks a current focused target for the active context.

Several things are derived from that current target:

- where keyboard input should go
- which view should be visually emphasized
- which focused values should be visible to remote parts of the UI
- how traversal should continue when the user presses Tab

### Focus Movement

Focus is not only about "what is focused now"; it is also about "where should focus go next?"

The movement rules:

- keyboard traversal generally follows authored order and locale-aware layout order
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

Focused values are not about who is focused. They are about what context should be exported from the focused area.

This is a different job:

- ``FocusState`` answers "which thing is focused?"
- focused values answer "what data should other UI read because focus is currently here?"

That difference matters. Focus ownership and focus-derived context are separate subsystems.

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

`.defaultFocus` is the "when this UI is first evaluated, prefer this focused target" modifier.

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

Conceptually, default focus is still part of the ``FocusState`` model. It is not a separate focus storage mechanism.

### `.focusable(...)` And Custom Controls

Built-in controls already know how to participate in focus where appropriate. Custom controls need to opt in.

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
- `@Environment(\.isFocusEffectEnabled)` tells a view whether focus effects should currently render

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

- a view can be logically focused even if you disable or replace the default focus effect
- focus effect customization does not create focusability by itself

### Focused Values

Focused values are how focus exports context to remote parts of your interface.

The mental model is close to custom environment values, but keyed off the focused subtree instead of plain ancestry.

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

- ``FocusedValueKey`` defines the key space.
- ``FocusedValues`` is the container.
- `.focusedValue(...)` publishes a value for the currently focused subtree.
- `.focusedSceneValue(...)` publishes scene-level context for the active scene.
- ``FocusedValue`` reads an optional value.
- ``FocusedBinding`` reads a binding and unwraps it into value-style access.

This is especially important for:

- app commands and menus
- command routing
- cross-tree coordination that should follow focus rather than direct containment

The key design point is that focused values are dynamic and contextual:

- when focus changes, the visible focused values can change
- when the active scene changes, the visible scene-focused values can change

### Focus Sections

`focusSection()` is a movement API, not a control API.

It exists to help traversal through layouts where the real focusable items are too small or too far apart for geometry alone to produce the desired movement.

What a focus section does:

- it makes the container's frame participate as a movement target
- it guides focus toward the nearest focusable descendant
- it does not itself become a focus stop

That last point is critical. `focusSection()` does not mean "this container is now a control." It means "use this larger region when deciding movement toward the controls inside it."

A focus section only helps if its frame is meaningfully larger than its contents — a section cannot guide movement through empty geometry it does not actually occupy.

## Movement And Traversal Semantics

### Keyboard Traversal

The default keyboard model:

- focus starts at the top-most control nearest the leading edge
- pressing Tab moves focus forward in locale-aware layout order
- reaching the end wraps back to the beginning

That is a useful baseline model, but authors still influence it by:

- which controls are focusable at all
- which controls are disabled or hidden
- how geometry is laid out
- where focus sections enlarge movement targets
- which target is chosen as the default focus candidate

### Initial And Reset Focus

There are two related but distinct questions:

- which target should receive focus when a screen first becomes active?
- when focus is cleared or reset, where should it go next?

The runtime answers those with default-focus modifiers tied to ``FocusState``.

## What The Runtime Decides For You Versus What You Author

The model works best if you are clear about which responsibilities belong to the runtime and which belong to your code.

The runtime decides:

- how the built-in controls participate by default
- how focus is visually emphasized unless you opt out
- how ordinary traversal follows layout order
- how to propagate the currently active focused values once you publish them

You author:

- which custom views are focusable
- what focus state identifiers represent
- which value is written when a target becomes focused
- which data should be exported through focused values
- where focus sections should enlarge traversal targets
- which target should be preferred as default focus

That separation is a useful design constraint. If focus behavior feels confusing, it is usually because one of these responsibilities is being assigned to the wrong layer.

## Common Mistakes

These are the mistakes that most often create a distorted mental model.

### Treating Focus As Generic Selection State

Focus is about input routing, not arbitrary selection. Some selected things are not focused, and some focused things are not part of any broader selection model.

### Confusing Focus Effect With Focus Ownership

The focus ring, lift, or highlight is presentation. Disabling or replacing the effect does not mean the view is no longer focused.

### Making Containers Focusable By Accident

If a container should only guide movement, use `focusSection()`. If it should truly behave as a control, use `.focusable(...)`. Those are different authoring decisions.

### Using Focused Values For Plain Parent-Child Data Flow

Focused values are best for remote, focus-dependent context such as commands and active-scene actions. They are not a general replacement for environment values, bindings, or plain model injection.

### Forgetting Scene Semantics

`focusedSceneValue(...)` is intentionally scene-aware. In multi-window apps, what commands see depends on which scene is active.

## Practical Implications For SwiftTUI

For a SwiftUI-faithful terminal runtime, the practical takeaways are straightforward:

- focus should attach to authored controls, not to layout containers by accident
- ``FocusState``-style bindings and focused values should be modeled as separate systems
- traversal policy should be geometry-aware rather than purely linear
- focus sections should influence routing without becoming focus stops
- default-focus behavior should be modeled separately from ordinary next/previous traversal
- scene-focused context matters for multi-window and command routing

This aligns with the project's design intent:

- explicit `.focusable(...)` modifiers should be authoritative
- containers should not become focus stops accidentally
- focused values and focus state are part of SwiftUI-faithful runtime semantics, not convenience extras
- focus-chain membership is the activation predicate for command availability — see [Action Scopes And Commands](https://github.com/adamz/swift-tui/blob/main/docs/proposals/ACTION_SCOPES_AND_COMMANDS.md) for the full scope hypothesis.

## Focus Highlight In `List`

Focus highlight in `List` is row-shaped, not container-shaped. The active row (the focused-or-selected row) gets its row chrome resolved with `isFocused: true, isSelected: true`; the list container itself stays neutral. See [docs/FOCUS.md](https://github.com/adamz/swift-tui/blob/main/docs/FOCUS.md) for the rationale and what the decision does and does not cover.

## See Also

- <doc:State-Environment-And-Focus>
- <doc:State-Keying>
- <doc:Authoring-Views>
