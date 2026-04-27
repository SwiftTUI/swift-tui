# Understanding Focus

The runtime focus model: how non-pointing input is routed, how state observes and controls it, and how focused values export context across the tree.

## Overview

This article is a high-level, implementation-oriented explanation of how focus works in TerminalUI. It treats focus as a runtime model, not just a bag of modifiers, and it tries to separate the distinct jobs that the focus APIs perform:

- deciding which view receives non-pointing input
- letting app state observe or control that decision
- propagating context outward from the focused area
- shaping how focus moves through irregular layouts
- choosing a starting focus target

The model is shaped after SwiftUI's. Where TerminalUI deviates intentionally, the article calls that out explicitly.

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

## Practical Implications For TerminalUI

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
- **the focus chain is load-bearing for the scope hypothesis.** Commands belong to scopes, and a scope's activation predicate is that its anchor node is on the current focus chain. Tree presence is a prerequisite but not sufficient — a resolved-but-unreachable node is philosophically silent. This elevates focus from "keyboard routing" to "the primary reachability primitive" — every command availability decision the framework makes bottoms out in focus-chain membership.

## A Nuanced Case: Focus Appearance In `List`

The relationship between focus, selection, and visual highlighting in `List` is one of the places where SwiftUI is easier to caricature than to describe. It is worth working through carefully because the project diverges from one plausible reading of SwiftUI's behavior, and the divergence is intentional.

### What You Actually See In SwiftUI

When you keyboard-navigate a SwiftUI `List(selection: $sel)` — for example, a sidebar in a `NavigationSplitView` with `NavigationLink` rows — you do see a tint move row by row as you press the arrow keys. It is tempting to call that a "focus tint," but it is not. It is the *selection* tint, and the reason it tracks the arrow keys is that on selection-driven lists the keyboard navigation drives the selection binding directly. Focus and selection move together because that is how the platform wires keyboard navigation through a selection-bound list, not because the list paints a separate focus highlight on top of selection.

A few consequences fall out of that:

- A selection-bound `List` can show its selected-row tint even when keyboard focus has left the list entirely. The tint is bound to selection, not to focus ownership.
- The list *container* itself does not paint a single uniform background tint behind every row simply because focus is inside it. The visible affordance is row-shaped, not list-shaped.
- macOS sidebars do communicate "this list is the active one" through a subtle border or inset treatment, but that lives at the chrome edge, not as a content-region fill.

So the short version of SwiftUI's behavior is:

- The row tint is selection.
- Selection follows keyboard navigation.
- The container does not get a separate focus fill.

### Why The Analogy Is Imperfect

This runtime does not implement `NavigationLink`. Its `List` accepts a `selection:` binding, but selection is not tied to a navigation routing system. There is no sidebar-versus-detail relationship to anchor the "selection persists when focus leaves" pattern, and there is no separate route-driven selection that competes with keyboard movement.

That changes the design question. In SwiftUI a selection-bound list has two distinct things to communicate (the route-active row, and where the keyboard cursor currently is) and uses one channel (selection-follows-focus) for both. Without `NavigationLink`, this project effectively only has the second of those things to communicate. The selected row *is* the focused row in almost every case the runtime cares about.

That makes any one-to-one parity argument suspect. The faithful answer is not "do whatever SwiftUI does," because SwiftUI's behavior is shaped by a navigation model the project does not yet have. The faithful answer is to ask which of SwiftUI's signals are still meaningful here, and which were doing work that is no longer needed.

### The Decision The Project Has Made

The runtime models focus appearance for `List` at the row layer, not the container layer:

- The container chrome (`List`'s own background and border fills) stays neutral regardless of whether focus is inside the list.
- The active row (the focused-or-selected row) gets its row chrome resolved with `isFocused: true, isSelected: true`, which paints a row-shaped background.
- A small caret glyph at the leading edge of the active row reinforces the row-shaped signal in low-color terminals.

The reason this matters: when an earlier version of the runtime tinted both the list container *and* the active row using the same shape style, the two highlights resolved to identical colors and visually merged. The user could see that "something is selected" but not "which row is selected." Two redundant signals at different layers, painted with the same color, cancel each other out.

Removing the container tint leaves a single, row-shaped focus signal, which is the SwiftUI-faithful affordance for the sub-problem the project actually solves (a selection-bound list without navigation routing).

### What This Decision Does Not Cover

There is one case the current behavior does not communicate well: a `List` that has focus but no active row — for example, an empty list, or a list that has just received focus and has no selection yet. Today such a list shows no focus affordance at all, because the only signal lives at the row layer and there is no row to paint.

If the project later needs to express "this list is the currently active container" independently of any row, the right move is probably to give the list back a focused *border* tone without re-introducing the focused content-background fill. That preserves the row-shaped affordance as the dominant signal while still letting the chrome edge announce list-level activation, which is closer to the macOS sidebar pattern than the previous all-rows-tinted behavior was.

### The General Principle

The case generalizes beyond `List`. When a SwiftUI-faithful runtime considers focus appearance, the useful question is not "does SwiftUI paint a highlight here?" — it is "what is SwiftUI's highlight actually communicating, and does that signal still have a referent in the simplified model?" Selection-follows-focus tinting in a navigation sidebar is a real SwiftUI behavior, but it is doing work that depends on machinery (selection plus routing) that may or may not exist downstream. Borrowing the *appearance* without the *machinery* produces a highlight that means nothing, which reads as visual noise rather than as an affordance.

The project's working rule is therefore to model focus appearance against the runtime's own semantics, with SwiftUI as a reference for the questions worth asking, not as a literal style sheet.

## Topics

### Related Articles

- <doc:State-Environment-And-Focus>
- <doc:State-Keying>
- <doc:Authoring-Views>
