# Coming from SwiftUI

Orientation for SwiftUI developers: what transfers unchanged, which reflexes
need retraining, and what is not here yet.

SwiftTUI mirrors SwiftUI's *shape*. Where a literal desktop behavior would
degrade the terminal, the default is terminal-native while the API stays
SwiftUI-shaped. This article is a guided tour of that boundary for someone
arriving with SwiftUI muscle memory. It summarizes and links; the
authoritative list of every recorded departure is <doc:Divergences-And-Gaps>,
and the rationale for the principled omissions is published in
[About SwiftTUI](https://swifttui.sh/docs/documentation/swifttuiruntime/vision).
The website publishes a shorter, side-by-side version of this tour as
[Differences from SwiftUI](https://swifttui.sh/differences-from-swiftui/).

## What transfers unchanged

The reflexes transfer, even where a signature narrows.

- **The authoring model.** `body`-only `View` types, `@ViewBuilder`
  composition, `ViewModifier`, modifier-order sensitivity, and scene
  declaration all behave the way you expect.
- **State and data flow.** `@State`, `@Binding`, `@Bindable`,
  `@Environment`, and `@FocusState` keep their SwiftUI semantics, including
  structural state identity; see <doc:State-Keying> for the details you
  half-remember about position-keyed storage, `.id(_:)`, and `ForEach`
  identity.
- **Layout negotiation.** Stacks, `ZStack`, alignment, `fixedSize`,
  `layoutPriority`, `overlay(alignment:content:)` and
  `background(alignment:content:)`, `GeometryReader`, and the
  propose-respond-place contract.
- **Lifecycle and reaction.** `onChange(of:initial:)` with modern
  semantics, `task(_:)` and `task(id:)` including the `.userInitiated`
  priority default, and the `disabled(_:)` AND-down cascade.
- **Animation.** `withAnimation`, `Transaction`, `Animatable`, and
  transitions on insertion and removal.
- **Presentation shapes.** `sheet`, `fullScreenCover`, `alert`, and
  `confirmationDialog` take the initializer shapes you know, and `ButtonRole`
  carries the same case set.
- **Gestures.** Gesture composition (sequencing, simultaneity, and
  `highPriorityGesture`) follows SwiftUI's model, in continuous cell
  coordinates.

## The reframes

Seven deliberate rereadings organize almost every difference you will notice.
Each is a *Ratified* stance in <doc:Divergences-And-Gaps>; this section gives
you the working idiom.

### The cell is the unit of truth

Geometry is integer terminal cells, in two named coordinate domains: the
`CellRect` grid for layout and rasterization, and continuous cell space
(`Point`, `Rect`) for gestures, hover, and `Canvas`. There is no `CGFloat`
and no CoreGraphics. `frame(width:height:)` takes `Int`, `padding()` is
literally one cell, and a `border` occupies real cells, so it defaults to
*inset* placement without changing layout allocation. Request `.outset`
explicitly when the border should reserve cells instead of painting over the
content's outermost cells.
`Spacer()` reserves nothing until siblings leave room.

### State is the only authority

Navigation and dismissal are strictly data-driven. A push appends to the
bound path; dismissal clears the presenting binding:

```swift
@State private var path: [Route] = []
@State private var selectedBuild: Build?

// Push:
path.append(.detail(build.id))
// Dismiss the sheet presenting `selectedBuild`:
selectedBuild = nil
```

There is deliberately no `NavigationLink` and no `@Environment(\.dismiss)`;
see <doc:Dismissal-Is-Data> for the full contract, including `onDismiss` as
observation rather than command and same-ID item replacement refreshing
without remounting.

### Modern-only, portable data flow

Models are `@Observable` classes; the Combine-era `ObservableObject` family
does not exist. The authoring layers are Foundation-free by policy and build
on Linux, WASI, and Android. Because frames finish on an off-main frame
tail, strict, unsuppressed concurrency is visible in the API: environment
models must be `Sendable`, `Binding(get:set:)` accessors are `@MainActor`,
and some generic bounds add `Sendable`. The natural authoring shape
satisfies all of it at once:

```swift
@MainActor @Observable
final class DeployModel {  // implicitly Sendable
  var builds: [Build] = []
}
```

### Keyboard-first interaction

Focus traversal is geometry-aware and wraps; there is no surrounding native
UI for focus to escape to. Key bindings are authored with `keyCommand` and
`paletteCommand` on the `ActionScope` surface rather than
`keyboardShortcut`. `onKeyPress` is reshaped honestly for a terminal byte
stream: complete key events without down/up/repeat phases. Collections are
tree-forward and keyboard-first, and selection requires an explicit `.tag`:
untagged rows fail loud instead of guessing. See <doc:Focus> and
<doc:Collections>.

### Deterministic chrome from value metadata

Tabs are `Tab(...)` values, `Table` takes `[TableColumn]` metadata with
positional row cells, toolbar items are `ToolbarItemConfig` values, and
`Picker` options are scraped to labeled text. Tagged, unmodified `Text` values
are represented losslessly. Other option trees keep their extracted text and
tag routing but emit `picker.unrepresentableOptionContent`, so deterministic
terminal chrome no longer hides discarded structure or modifiers. All four
surfaces follow the same stance: structured value metadata gives deterministic
terminal chrome without retaining arbitrary label view trees.

### Restrained chrome, fail-loud verbs

`fullScreenCover` is chromeless, `background` fills bounds without bleeding,
and the `List` focus highlight is row-shaped. Alerts and confirmation
dialogs queue first-in, first-out where SwiftUI leaves concurrency
undefined. Environment verbs such as `\.openLinkAction` and `\.resetFocus`
return `Bool` to report whether anything consumed them, and the runtime
reports issues instead of silently inferring intent.

### Accessibility and capture as defaults

Reduced motion changes *rendering*, not just timing: `Spinner` goes static
and `PhaseAnimator` holds its first phase. `CI=true` or a non-TTY stdout use
the same stable built-in rendering without changing the app-visible
accessibility preference. Semantic style roles (`.foreground`, `.tint`, `.warning`,
and the `.primary`/`.secondary` aliases) resolve through a host-owned theme;
there is deliberately no `ColorScheme`. And an `App` is also a CLI command,
with `--accessible`, `--no-color`, `--ascii`, `--reduce-motion`, and
`--json` out of the box. See <doc:Accessibility>.

## Muscle-memory traps

Intentional divergences that compile, or almost compile, and then
surprise. Each links back to its register section by name.

### The first hour

| You write or expect | What happens here | Do instead |
| --- | --- | --- |
| `MyApp.main()` | Traps with a precise diagnostic: the call would resolve to the synchronous ArgumentParser overload and never start the runtime | `@main` |
| `class Model: ObservableObject`, `@Published`, `@StateObject`, `@EnvironmentObject` | The family does not exist | `@MainActor @Observable final class`; `@Environment(Model.self)`; `@Bindable` |
| `NavigationLink("Detail", value:)`, `@Environment(\.dismiss)` | Deliberately omitted | Mutate the bound path; clear the presenting binding (<doc:Dismissal-Is-Data>) |
| `.frame(width: 20.5)`, `CGRect`, `CGFloat` | Geometry is `Int` cells plus continuous cell space; no CoreGraphics types | The `CellRect`/`Rect` vocabulary; `frame(width:height:)` takes `Int` |
| `Text("a") + Text("b").bold()`; `.font(.title)` | No `+`, no `Font`; `Text` is literal, with no localization | Interpolate: `Text("a \(Text("b").bold())")`; emphasis lives on `Text`; banners via `TextFigure` |
| `.keyboardShortcut("s")` | Does not exist | `keyCommand`/`paletteCommand` on the `ActionScope` surface |
| `.padding()`; `.border(.red)` | Padding is one literal cell; the border paints into the existing frame (inset default) | Expect cell-quantized layout; request `.outset` to reserve border cells |

### The first week

| You write or expect | What happens here | Do instead |
| --- | --- | --- |
| Tab-local reference state surviving tab switches | `TabView` resolves only the selected body; value-typed `@State` is archived and restored across deselection, but class-backed state, running tasks, and captured closures are torn down | Hoist reference-backed models above the tab seam; see <doc:Dormant-Tab-State> |
| `List(selection:)` with untagged rows | Rows render but are unselectable; a runtime issue is reported | An explicit `.tag` per row |
| `Slider(value: $x)` | `in:` is required; there is no `0...1` default | Pass the range; `Double` forms are continuous by default |
| Several simultaneous `alert`s | Prompts queue first-in, first-out; only the oldest is visible; Escape dismisses the most recent *visible* presentation | By design; sequence prompts |
| A `Table` column builder, `ToolbarItem` views, arbitrary `Picker` option views | Structured value metadata; picker options scrape to text | `[TableColumn]` plus positional cells; `ToolbarItemConfig`; text-shaped options |
| `ForEach(items) { … }` with a non-`Sendable` ID; `Binding(get:set:)` off the main actor | Strict-concurrency bounds: IDs are `Hashable & Sendable`, accessors are `@MainActor`, environment models are `Sendable` | Author models as `@MainActor @Observable` (implicitly `Sendable`) |
| `ForEach($items) { $item in … }` | The bare `$item` sugar does not compile: Swift drops the closure's contextual isolation from property-wrapper parameters | The plain parameter *is* the element binding, or spell `{ @MainActor $item in … }` |
| `.onSubmit(of: .text) { … }`; `.submitLabel(.go)` | `onSubmit` takes no `of:` (text is the only trigger a terminal can have) and `submitLabel` is omitted (no software keyboard to relabel) | Plain `onSubmit { … }`; `submitScope(_:)` bounds propagation |
| `onKeyPress(.upArrow, action:)` or `phases:` | Reshaped: `perform:`, `KeyPressMatch`, `.arrowUp`, no `phases:` | The reshaped form is canonical |

### Subtle behaviors worth knowing

- **Equal-value `@State` writes are inert.** Writing an unchanged value does
  not invalidate the owner, so a `Binding.animation(_:)` write of an equal
  value animates nothing.
- **`DynamicProperty` is reference-backed.** Its nonmutating
  `update(in:) -> DynamicPropertyUpdateResult` rejects plain-value mutation,
  carries an invalidation lease for asynchronous storage, and makes custom
  reuse certification explicit (<doc:Custom-Dynamic-Properties>).
- **Composed wrappers need `DynamicProperty`.** Property wrappers composed
  inside a helper type that does *not* conform to `DynamicProperty` share
  storage by declaration site, surfaced by the `state.duplicateSlotClaim`
  runtime issue. Conform the helper.
- **Measurement does not realize deferred content.** Measuring a
  `GeometryReader` or an unselected `ViewThatFits` candidate commits no
  lifecycle, task, gesture, focus, or semantic side effects.
- **A missing named coordinate space falls back to global** with a frame
  diagnostic rather than trapping.
- **Reduced motion changes what renders; capture stability is a separate
  policy.** `CI=true` and non-TTY stdout show the same static built-in forms,
  while app reads of `accessibilityReduceMotion` remain unchanged.

## Not there yet

The gaps a SwiftUI developer is most likely to hit, with the working idiom
where one exists. These are *Gap* entries in <doc:Divergences-And-Gaps>:
recorded shortfalls, not a roadmap; the register holds the full list and the
current status of each.

| Gap | What to do today |
| --- | --- |
| No `scrollPosition(_:)` identity abstraction | `ScrollViewReader` (its proxy's `scrollTo` returns `Bool`, so check it) or `ScrollView(position:)` with a raw `ScrollCellOffset` |
| `Color` vocabulary: `alpha:` not `opacity:`, `mixed(with:amount:method:)` not `mix(with:by:)`, no `Color.accentColor` | Prefer semantic roles (`.primary`, `.secondary`, `.tint`) resolved through the host theme; they are the intended currency |
| No `ScenePhase` | None; a session is one full-canvas scene |
| Scale transitions and matched size changes use placed bounds and clipping rather than re-layout or bitmap scaling | Expect whole-cell steps; content keeps its destination layout while the interpolated frame clips it |
| `Menu` anchors top-leading, not at its source control | None; noted so it is not mistaken for a layout bug |
| The lazy path requires a single direct `ForEach` | Restructure heterogeneous content into one indexed source; the eager fallback reports a runtime issue past a few hundred rows |
| No `addArc`, no general `clipShape(_:)`, no animatable path morphing | Analytic primitives plus parameter animation; see <doc:Shapes> and <doc:AspectCorrectShapes> |
| `ToggleStyle`, `ProgressViewStyle`, `LabelStyle`, `MenuStyle` have no open protocol | Wrap and style; recorded as accidental incompleteness within the open-style design, not a stance |
| No `onMoveCommand`/`onExitCommand`; `Text` is not `Hashable` | Note-only |

Beyond the recorded gaps sits a larger class of bare absences. The
high-traffic ones include `searchable`, `refreshable`, `contextMenu`,
`swipeActions`, `DatePicker`, `@AppStorage`, and the render-effect modifiers
`scaleEffect`, `blur`, and `shadow`. These are scope decisions under the
subset policy, not divergences: SwiftTUI implements subsets of SwiftUI only
where they map to high-value TUI use cases. The register's scope note is the
rule: a bare absence appears there only when the absence has a recorded
stance or breaks an idiom.

When you find yourself porting a desktop habit, also check the register's
surface-extension list for the terminal-native tool you would not think to
look for: terminal-program embedding (`TerminalView`), `toast` and
`popoverTip`, `TextFigure` banners, per-side border styling and animated
perimeter gradients, and open style protocols including families SwiftUI
keeps closed.

## Where to go deeper

- <doc:Divergences-And-Gaps>: the single register of every recorded
  departure and shortfall, tagged *Ratified* / *Provisional* / *Gap*.
- [About SwiftTUI](https://swifttui.sh/docs/documentation/swifttuiruntime/vision):
  the faithfulness stance and the rationale for the principled omissions.
- Per-surface contracts: <doc:Dismissal-Is-Data>, <doc:State-Keying>,
  <doc:State-Environment-And-Focus>, <doc:Custom-Dynamic-Properties>,
  <doc:Focus>, <doc:Collections>, <doc:AnyView>,
  <doc:Geometry-And-Preferences>, <doc:Pointer-And-Canvas>, <doc:Shapes>.
