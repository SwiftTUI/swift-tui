# SwiftUI Focus

This document is a high-level, implementation-oriented explanation of how SwiftUI focus works. It treats focus as a runtime model, not just a bag of modifiers, and it tries to separate the distinct jobs that SwiftUI's focus APIs perform:

- deciding which view receives non-pointing input
- letting app state observe or control that decision
- propagating context outward from the focused area
- shaping how focus moves through irregular layouts
- choosing a starting focus target

It is not a catalog of every focus-related symbol in SwiftUI, but it does cover the APIs that define the model in practice.

The short version:

- Focus is SwiftUI's routing system for keyboard, remote, crown, switch-control, and similar non-pointing input.
- Focus does not belong to every view. Some controls participate automatically; custom controls opt in.
- `@FocusState` is the main bridge between the runtime focus graph and app state.
- Focused values are a separate mechanism that exports context from the focused subtree or active scene.
- Focus sections influence movement without becoming focusable controls themselves.
- Default-focus APIs decide where focus starts or resets; they are not the same thing as normal traversal.
- Focus appearance is related to focus, but it is not the same as focus ownership.

Separate but related:

- `AccessibilityFocusState` is a different focus system for assistive technologies; this document is about SwiftUI's standard interaction focus model.

## 1. What Focus Is

SwiftUI focus exists to answer a simple question:

> If the user presses a key, swipes on a remote, turns the Digital Crown, or triggers another non-pointing input, which view should receive that input?

Pointer-driven systems do not need focus in the same way, because the pointer provides coordinates. Focus provides the missing target information when input is not tied to a point on screen.

Apple's WWDC descriptions are consistent on this point:

- focus is the system that directs non-pointing input
- the focused view is usually visually emphasized
- SwiftUI handles most ordinary focus behavior automatically
- developers intervene when default behavior is not enough

That makes focus feel more like a logical cursor than a selection model. It tracks where the user's attention is currently directed for input purposes.

## 2. The Core Mental Model

The most useful way to think about SwiftUI focus is as five related but distinct layers.

### 2.1 Focus Targets

A focus target is a view that can meaningfully receive focus.

Important consequences:

- Not every view is focusable.
- Focus should generally land on authored interactive controls, not incidental containers.
- Built-in controls have platform-specific default behavior.
- Custom controls opt in with focus APIs.

Built-in examples:

- text fields are editing-oriented focus targets
- buttons are activation-oriented focus targets
- tvOS cells and menu items commonly participate in directional focus
- crown-adjustable watch controls participate in focus on watchOS

Custom views typically opt in with `.focusable(...)`.

### 2.2 Current Focus

At any moment, a focus system tracks a current focused target for the active context. In practice that context is tied to the active scene or window, not to the entire process indiscriminately.

SwiftUI can derive several things from that current target:

- where keyboard or remote input should go
- which view should be visually emphasized
- which focused values should be visible to remote parts of the UI
- how traversal should continue when the user presses Tab or navigates directionally

### 2.3 Focus Movement

SwiftUI focus is not only about "what is focused now"; it is also about "where should focus go next?"

The movement rules are platform-shaped:

- keyboard traversal generally follows authored order and locale-aware layout order
- directional systems use geometry and adjacency
- default focus chooses the initial target when focus first enters a screen or scope
- focus sections can enlarge the logical movement target without turning containers into controls

This is one of the places where layout and focus meet. The geometry of the placed interface affects directional movement.

### 2.4 Programmatic Focus Control

SwiftUI exposes programmatic focus control through `@FocusState` and related modifiers.

This gives you a bidirectional link:

- when focus moves in the UI, your state updates
- when your state updates, SwiftUI can move focus in response

That is the core of programmatic focus:

- move the cursor to the invalid field in a form
- dismiss the keyboard by clearing focused state
- focus a newly inserted row or text field
- restore a preferred target when a view appears

### 2.5 Focus Context Propagation

Focused values are not about who is focused. They are about what context should be exported from the focused area.

This is a different job:

- `@FocusState` answers "which thing is focused?"
- focused values answer "what data should other UI read because focus is currently here?"

That difference matters. Focus ownership and focus-derived context are separate subsystems in SwiftUI.

## 3. The Main API Families

### 3.1 `@FocusState` And `.focused(...)`

`@FocusState` is the main state bridge into the focus system.

You use it in two common shapes:

- `Bool` for "is this one thing focused?"
- `Optional<Hashable>` for "which one of these mutually exclusive things is focused?"

Example:

```swift
import SwiftUI

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
- Setting the state moves focus when SwiftUI can resolve the target.
- Clearing the state with `nil` or `false` dismisses that local focus relationship.

This is the main tool for:

- form validation
- programmatic keyboard dismissal
- auto-focusing inserted content
- conditional styling driven by focus placement

Important distinction:

- `@FocusState` is for focus ownership and programmatic control
- it is not a general substitute for selection state or navigation state

#### `defaultFocus`

`defaultFocus` is the modern "when this UI is first evaluated, prefer this focused target" modifier.

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

- asks SwiftUI to seed focus by writing a value into a `@FocusState` binding
- works with the same identifiers you already use for `.focused(_:equals:)`
- supports a priority parameter for default-focus evaluation

Conceptually, `defaultFocus` is still part of the `@FocusState` model. It is not a separate focus storage mechanism.

### 3.2 `.focusable(...)` And Custom Controls

SwiftUI's built-in controls already know how to participate in focus where appropriate. Custom controls need to opt in.

That is what `.focusable(...)` is for.

```swift
struct RatingPicker: View {
    let options = ["😡", "😕", "🙂", "😍"]
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
- `.automatic`: let SwiftUI choose

Apple explicitly called out the text-field versus button distinction:

- text fields use focus for editing
- buttons use focus for activation

That distinction matters when designing custom controls. A slider-like or picker-like control usually wants edit semantics. A button-like control usually wants activate semantics.

Also note:

- older `focusable(_:onFocusChange:)` overloads are deprecated in favor of `@FocusState` plus `.focused(...)`
- opting a container into `.focusable(...)` means you are authoring it as a control, not just styling it

### 3.3 Reading Or Styling Focus

SwiftUI exposes two important environment values around focus styling:

- `@Environment(\.isFocused)` tells a view whether it is in the currently focused context
- `@Environment(\.isFocusEffectEnabled)` tells a view whether focus effects should currently render

And one modifier controls the default visual effect:

- `.focusEffectDisabled()`

These APIs are about appearance and local reaction, not about moving focus.

Example:

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

### 3.4 Focused Values

Focused values are how focus exports context to remote parts of your interface.

Apple's mental model here is close to custom environment values, but keyed off the focused subtree instead of plain ancestry.

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
struct RecipeCommands: Commands {
    @FocusedBinding(\.selectedRecipe) private var selectedRecipe: Recipe?

    var body: some Commands {
        CommandMenu("Recipe") {
            Button("Add to Grocery List") {
                if let selectedRecipe {
                    addRecipe(selectedRecipe)
                }
            }
            .disabled(selectedRecipe == nil)
        }
    }
}
```

The important parts of the model:

- `FocusedValueKey` defines the key space.
- `FocusedValues` is the container.
- `.focusedValue(...)` publishes a value for the currently focused subtree.
- `.focusedSceneValue(...)` publishes scene-level context for the active scene.
- `@FocusedValue` reads an optional value.
- `@FocusedBinding` reads a binding and unwraps it into value-style access.
- `@FocusedObject` does the same pattern for `ObservableObject`.
- modern Observation-based reference types also have convenience overloads in the current SDK.

This is especially important for:

- app commands and menus
- command routing
- front-most-window behavior on macOS-style apps
- cross-tree coordination that should follow focus rather than direct containment

The key design point is that focused values are dynamic and contextual:

- when focus changes, the visible focused values can change
- when the active window or scene changes, the visible scene-focused values can change

### 3.5 Focus Sections

`focusSection()` is a movement API, not a control API.

It exists to help directional or tab-based traversal through layouts where the real focusable items are too small or too far apart for geometry alone to produce the desired movement.

Example:

```swift
struct ContentView: View {
    var body: some View {
        VStack {
            HStack {
                Button("A") {}
                Button("B") {}
                Button("C") {}
            }

            HStack {
                Spacer()
                Button("Add to Grocery List") {}
                Spacer()
            }
            .focusSection()
        }
    }
}
```

What a focus section does:

- it makes the container's frame participate as a movement target
- it guides focus toward the nearest focusable descendant
- it does not itself become a focus stop

That last point is critical. `focusSection()` does not mean "this container is now a control." It means "use this larger region when deciding movement toward the controls inside it."

Apple's WWDC guidance also called out an operational detail:

- a focus section only helps if its frame is meaningfully larger than its contents

In other words, a section cannot guide movement through empty geometry it does not actually occupy.

### 3.6 Default-Focus Scope APIs

SwiftUI also has an older scoped default-focus family:

- `.prefersDefaultFocus(_:in:)`
- `.focusScope(_:)`
- `@Environment(\.resetFocus)`

Example:

```swift
struct LoginView: View {
    @Namespace private var namespace
    @State private var areCredentialsFilled = false
    @Environment(\.resetFocus) private var resetFocus

    var body: some View {
        VStack {
            TextField("Username", text: .constant(""))
                .prefersDefaultFocus(!areCredentialsFilled, in: namespace)

            Button("Log In") {}
                .prefersDefaultFocus(areCredentialsFilled, in: namespace)

            Button("Clear") {
                areCredentialsFilled = false
                resetFocus(in: namespace)
            }
        }
        .focusScope(namespace)
    }
}
```

The idea here is different from `defaultFocus`:

- `focusScope` creates a namespace-limited region for default-focus decisions
- `prefersDefaultFocus` marks one or more candidates within that scope
- `resetFocus` asks the system to reevaluate the scope's default focus

This family is especially relevant to focus-first platforms like tvOS and macOS, and to watchOS. In the current Xcode 26.3 SDK interfaces, these APIs are explicitly unavailable on iOS and visionOS.

## 4. Movement And Traversal Semantics

The focus model is not just storage and modifiers. It also defines movement rules.

### 4.1 Keyboard Traversal

WWDC23 described the default keyboard model like this:

- focus starts at the top-most control nearest the leading edge
- pressing Tab moves focus forward in locale-aware layout order
- reaching the end wraps back to the beginning

That is a useful baseline model, but authors still influence it by:

- which controls are focusable at all
- which controls are disabled or hidden
- how geometry is laid out
- where focus sections enlarge movement targets
- which target is chosen as the default focus candidate

### 4.2 Directional Traversal

Directional systems such as tvOS remote navigation are geometry-driven:

- movement only works toward adjacent targets
- distant controls are not automatically linked
- focus sections help bridge irregular layouts by enlarging logical target regions

This is why focus behavior cannot be understood independently of layout. Focus routing depends on the placed geometry of the final interface.

### 4.3 Initial And Reset Focus

There are two related but distinct questions:

- which target should receive focus when a screen first becomes active?
- when focus is cleared or reset, where should it go next?

SwiftUI answers those with:

- `defaultFocus` for focus-state-driven initial targeting
- `prefersDefaultFocus` plus `focusScope` plus `resetFocus` on platforms that support the scoped family

## 5. Platform Notes

SwiftUI focus is cross-platform, but it is not uniform.

### 5.1 macOS And iPadOS With Keyboard Navigation

Apple explicitly called out an important distinction:

- text fields are naturally focusable for editing
- buttons only participate in keyboard traversal when the system allows keyboard navigation for those controls

That means a control can be activatable by pointer or touch but still not participate in the same way in keyboard focus traversal unless the platform settings support it.

### 5.2 tvOS

tvOS is the clearest focus-first platform in SwiftUI:

- directional movement is central
- focus effects are central to presentation
- default focus and reset behavior matter a lot
- focus sections are often necessary in irregular layouts

### 5.3 watchOS

On watchOS, focus is also tied to continuous non-pointing input, especially the Digital Crown. This is why SwiftUI keeps both activation-style and edit-style focus semantics.

### 5.4 visionOS

In the current Xcode 26.3 SDKs, the core focus model APIs are present in the visionOS SwiftUI interface, including `@FocusState`, `.focused(...)`, focused values, `defaultFocus`, and `.focusable(...)`.

However, the same SDK marks these APIs unavailable on visionOS:

- `focusSection()`
- `prefersDefaultFocus(_:in:)`
- `focusScope(_:)`
- `resetFocus`

So the visionOS focus surface currently aligns more closely with the modern `@FocusState` and `defaultFocus` model than with the older scoped-default-focus family.

## 6. Availability Snapshot

The table below summarizes the major focus APIs as verified against the SwiftUI interfaces shipped in Xcode 26.3.

| API family | Purpose | Availability notes |
| --- | --- | --- |
| `@FocusState`, `.focused(...)` | observe and control focus placement | available in current SDKs across SwiftUI platforms; introduced as iOS 15 / macOS 12 / tvOS 15 / watchOS 8 family |
| `defaultFocus` | choose initial focus through a `FocusState` binding | current SDK availability family starts at iOS 17 / macOS 13 / tvOS 16 / watchOS 9; present in current visionOS SDK |
| `.focusable()` | opt a custom control into focus participation | current SDK availability family starts at iOS 17 / macOS 12 / tvOS 15 / watchOS 8; present in current visionOS SDK |
| `.focusable(interactions:)`, `FocusInteractions`, `.focusEffectDisabled()`, `isFocusEffectEnabled` | refine focus semantics and appearance | current SDK availability family starts at iOS 17 / macOS 14 / tvOS 17 / watchOS 10; present in current visionOS SDK |
| `FocusedValueKey`, `FocusedValues`, `@FocusedValue`, `@FocusedBinding`, `.focusedValue(...)` | export context from the focused subtree | introduced as iOS 14 / macOS 11 / tvOS 14 / watchOS 7 family; present in current visionOS SDK |
| `.focusedSceneValue(...)` | export context from the active scene | introduced as iOS 15 / macOS 12 / tvOS 15 / watchOS 8 family; present in current visionOS SDK |
| `@FocusedObject`, `.focusedObject(...)`, `.focusedSceneObject(...)` | focused-context access for `ObservableObject` | introduced as iOS 16 / macOS 13 / tvOS 16 / watchOS 9 family; present in current visionOS SDK |
| Observation object-focused overloads | focused-context access for `Observation.Observable` reference types | current SDK availability family starts at iOS 17 / macOS 14 / tvOS 17 / watchOS 10; present in current visionOS SDK |
| `focusSection()` | guide traversal geometry without creating a focus stop | available on macOS 13+ and tvOS 15+; unavailable on iOS, watchOS, and visionOS in current SDK |
| `prefersDefaultFocus`, `focusScope`, `resetFocus` | namespace-scoped default focus and reset | available on macOS 12+, tvOS 14+, watchOS 7+; unavailable on iOS and visionOS in current SDK |

## 7. What SwiftUI Decides For You Versus What You Author

The model works best if you are clear about which responsibilities belong to SwiftUI and which belong to your code.

SwiftUI decides:

- how the platform's built-in controls participate by default
- how focus is visually emphasized by the platform unless you opt out
- how ordinary traversal follows layout order or directional adjacency
- how to propagate the currently active focused values once you publish them

You author:

- which custom views are focusable
- what focus state identifiers represent
- which value is written when a target becomes focused
- which data should be exported through focused values
- where focus sections should enlarge traversal targets
- which target should be preferred as default focus

That separation is a useful design constraint. If focus behavior feels confusing, it is usually because one of these responsibilities is being assigned to the wrong layer.

## 8. Common Mistakes

These are the mistakes that most often create a distorted mental model.

### 8.1 Treating Focus As Generic Selection State

Focus is about input routing, not arbitrary selection. Some selected things are not focused, and some focused things are not part of any broader selection model.

### 8.2 Confusing Focus Effect With Focus Ownership

The focus ring, lift, or highlight is presentation. Disabling or replacing the effect does not mean the view is no longer focused.

### 8.3 Making Containers Focusable By Accident

If a container should only guide movement, use `focusSection()`. If it should truly behave as a control, use `.focusable(...)`. Those are different authoring decisions.

### 8.4 Using Focused Values For Plain Parent-Child Data Flow

Focused values are best for remote, focus-dependent context such as commands and active-scene actions. They are not a general replacement for environment values, bindings, or plain model injection.

### 8.5 Ignoring Platform Settings

On keyboard-driven platforms, some controls only participate in focus traversal when the system configuration allows it. Testing only with pointer interaction will miss important focus behavior.

### 8.6 Forgetting Scene Semantics

`focusedSceneValue(...)` is intentionally scene-aware. In multi-window apps, what commands see depends on which scene is active.

## 9. Practical Implications For This Project

For a SwiftUI-faithful terminal runtime, the practical takeaways are straightforward:

- focus should attach to authored controls, not to layout containers by accident
- `@FocusState`-style bindings and focused values should be modeled as separate systems
- traversal policy should be geometry-aware rather than purely linear
- focus sections should influence routing without becoming focus stops
- default-focus behavior should be modeled separately from ordinary next/previous traversal
- scene-focused context matters for eventual multi-window and command routing work

This aligns with the existing project vision:

- explicit `.focusable(...)` modifiers should be authoritative
- containers should not become focus stops accidentally
- focused values and focus state are part of SwiftUI-faithful runtime semantics, not convenience extras
- **the focus chain is load-bearing for the scope hypothesis.** Commands belong to scopes, and a scope's activation predicate is that its anchor node is on the current focus chain. Tree presence is a prerequisite but not sufficient — a resolved-but-unreachable node is philosophically silent. This elevates focus from "keyboard routing" to "the primary reachability primitive" — every command availability decision the framework makes bottoms out in focus-chain membership. See [STATUS.md](STATUS.md) for the full scope hypothesis.

## 10. Sources

Primary Apple sources used for this document:

- [Direct and reflect focus in SwiftUI (WWDC21)](https://developer.apple.com/videos/play/wwdc2021/10023/)
- [Build SwiftUI apps for tvOS (WWDC20)](https://developer.apple.com/videos/play/wwdc2020/10042/)
- [SwiftUI on the Mac: Build the fundamentals (WWDC21)](https://developer.apple.com/videos/play/wwdc2021/10062/)
- [The SwiftUI cookbook for focus (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10162/)
- [FocusState](https://developer.apple.com/documentation/swiftui/focusstate)
- [focused(_:equals:)](https://developer.apple.com/documentation/swiftui/view/focused(_:equals:))
- [focusable(_:interactions:)](https://developer.apple.com/documentation/swiftui/view/focusable(_:interactions:))
- [FocusedValues](https://developer.apple.com/documentation/swiftui/focusedvalues)
- [focusedSceneValue(_:_:)](https://developer.apple.com/documentation/swiftui/view/focusedscenevalue(_:_:))
- [focusSection()](https://developer.apple.com/documentation/swiftui/view/focussection())
- [defaultFocus(_:_:priority:)](https://developer.apple.com/documentation/swiftui/view/defaultfocus(_:_:priority:))

Availability details in this document were also cross-checked against the SwiftUI module interfaces shipped with Xcode 26.3:

- `/Applications/Xcode-26.3.0.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.2.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface`
- `/Applications/Xcode-26.3.0.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64-apple-ios-simulator.swiftinterface`
- `/Applications/Xcode-26.3.0.app/Contents/Developer/Platforms/XRSimulator.platform/Developer/SDKs/XRSimulator26.2.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64-apple-xros-simulator.swiftinterface`
