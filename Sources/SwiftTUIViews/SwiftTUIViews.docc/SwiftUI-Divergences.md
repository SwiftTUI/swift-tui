# SwiftUI divergences

A register of the places where SwiftTUI's public API departs from SwiftUI,
with the recorded rationale for each departure.

SwiftTUI mirrors SwiftUI's *shape*. However when a literal desktop behavior can
degrade the terminal experience, SwiftTUI uses a terminal-native default while
the API shape stays SwiftUI-shaped. Similarly, SwiftTUI implement subsets of 
SwiftUI only if they map to high-value TUI use cases, does
not implement deprecated or questionable APIs, and preserves the important
semantics of every API that is implemented.

## Principled omissions

- **No `NavigationLink`.** Navigation is strictly data-driven: a push mutates
  the bound path (`NavigationStack(path:root:)` plus
  `navigationDestination(for:destination:)`).
  `NavigationLink` fuses a control to a navigation side effect, so navigation
  state stops being derivable from — and mutable through — the app's data.
  There is deliberately no link-control sugar.
- **No `@Environment(\.dismiss)`.** Presented content receives no ambient
  dismiss command. The presenter owns a Boolean or optional-item binding, and
  dismissal clears that source value. 
  A view cannot know the context in which it is displayed, so a child-side self-dismissal
  command couples reusable content to an assumed presenter. Presenter-side
  observation (`onDismiss:`) is compatible with the stance; child-side
  dismissal commands are not. See <doc:Dismissal-Is-Data>.
- **No `View.tabItem(_:)`.** Tabs are declared with the structured
  `Tab(_:detail:badge:value:content:)` form.
  This is an implementation detail that should change if it causes issues.
- **No heterogeneous `NavigationPath`.** Only the homogeneous
  `Binding<[Route]>` path form ships. 
  This is an implementation detail that should change if it causes issues.
- **No `NavigationSplitView`.** Recorded as out of scope for the navigation
  surface.
  This is an implementation detail that should change if it causes issues.

## App entry, scenes, and lifecycle

- **`App.main()` is asynchronous.** `SwiftUI.App.main()` is synchronous and a
  top-level `MyApp.main()` call works there. SwiftTUI's `App` refines
  `AsyncParsableCommand`, so only `@main` binds the asynchronous entry point.
  A bare `MyApp.main()` — muscle memory from SwiftUI — would resolve to the
  synchronous `ParsableCommand.main()` overload from swift-argument-parser and
  never start the runtime, so SwiftTUI ships a trapping shim that rejects the
  call with a precise diagnostic in both DEBUG and release builds.
- **An `App` is also a CLI command.** The batteries-included `App` conforms to
  `SwiftTUICommand`, and apps opt into the standard option surface
  (`--accessible`, `--no-color`, `--ascii`, `--reduce-motion`, `--json`,
  `--linear`, `--debug`, `--web`, ...) with
  `@OptionGroup var swiftTUIOptions: SwiftTUIOptions`. SwiftUI's `App` has no
  argument-parsing surface. The recorded framing: the command-enabled `App` is
  the batteries-included overlay over `SwiftTUIRuntime.App`, which remains
  available for host-managed declarations without the command surface.
- **One active root scene.** The runtime drives a single full-canvas
  `WindowGroup` per session rather than SwiftUI's multi-window, multi-scene
  model. 
  Host-specific integration allowing multi-scene orchestration lives in sibling
  products, not in the core runtime.
- **No `ScenePhase`.** There is no app-lifecycle environment signal.
  This is a framework level TODO.

## Data flow and observation

- **Observation-only data flow.** The state surface is `State`, `Binding`,
  `Bindable`, `Environment`, and `FocusState`. The Combine-era object family —
  `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`,
  `@EnvironmentObject` — does not exist. Models are `@Observable` classes.
  The authoring layers are Foundation-free by policy and build on
  non-Apple platforms where Combine is unavailable, and the subset policy
  excludes APIs that modern SwiftUI itself has superseded; the Observation
  path is the one data-flow model that satisfies both.
- **Environment models must be `Sendable`.** `EnvironmentKey.Value` is
  `Sendable`-constrained, so `@Environment(Model.self)` and
  `environment(_:)` accept only `Observable & Sendable` classes. SwiftUI has
  no such constraint. 
  The environment store is `Sendable`-constrained so environment snapshots
  can cross the off-main frame tail; a `@MainActor @Observable final class` 
  is implicitly `Sendable` and is the natural authoring shape here.
- **`Binding.init(get:set:)` takes `@MainActor` closures.** SwiftUI's
  accessors carry no isolation annotation. 
  This is downstream of the framework itself using strict, unsuppressed, concurrency.
- **No `Binding` projections.** `Binding.animation(_:)`,
  `Binding.transaction(_:)`, and `Binding.init?(_:)` (optional unwrapping) are
  absent. 
  This is a framework level TODO.
- **Equal-value `State` writes are inert.** Writing a value equal to the
  current one does not invalidate the owner.
  This is an implementation detail that should change if it causes issues.

## Geometry and units

- **Two named coordinate domains instead of `CGFloat` geometry.**
  `CellPoint`/`CellSize`/`CellRect` are the integer terminal grid (layout,
  semantic bounds, raster); `Point`/`Size`/`Rect`/`Vector` are continuous cell
  space (gestures, hover, `Canvas`, interpolation); `Pixel*` types carry host
  device-pixel provenance. `frame(width:height:)` takes `Int`, and
  `Shape.path(in:)` receives a `Rect`, not a `CGRect`. 
- **`ScrollPosition` shares SwiftUI's name with different semantics.** In
  SwiftUI, `ScrollPosition` is an identity/edge/anchor abstraction applied
  with `scrollPosition(_:)`. In SwiftTUI it is a raw cell offset
  (`x`/`y: Int`) threaded through a `ScrollView(position:)` initializer that
  SwiftUI does not have.
  This is a framework level TODO.
- **`contentShape(_:)` is dual-denominated.** Rectangular content shapes are
  cell-denominated (`CellRect`); path content shapes use continuous cell
  space.
  This is an implementation detail that should change if it causes issues.

## Layout

- **Surplus distribution floors every member at its ideal.** In SwiftUI, text
  can respond *larger* than a lean offer, so equal-division surplus offers are
  safe. SwiftTUI's measure truncates instead, so in surplus no group member is
  offered below its own ideal while the group budget still covers the
  remaining ideals. 
  This is an implementation detail that should change if it causes issues.
- **Deficit compresses proportionally from ideals.** Surplus uses equal
  division from zero (SwiftUI's treatment of unbounded children) with the
  ideal floor; deficit keeps proportional compression so trailing spacers
  collapse before content loses rows. 
  This is an implementation detail that should change if it causes issues.
- **Offers round half-up.** Integer division of surplus is balanced across
  children rather than floored. 
  This is an implementation detail that should change if it causes issues.
- **`Text` has a zero structural minimum on the horizontal axis.** SwiftUI
  reserves the truncation minimum; in SwiftTUI a higher-priority flexible
  sibling can squeeze a `Text` to zero width. Recorded as the sharpest
  priority edge of the layout model, kept from the historical compression
  path.
- **Custom `Layout` types must be `Sendable`, with `Sendable` caches.**
  The renderer evaluates custom layouts on the off-main frame-tail worker.
- **`Layout` caches are pass-local scratch.** SwiftUI persists `Cache` values
  across passes through `updateCache`. SwiftTUI shares the cache between
  measurement and placement for one pass, then drops it. 
  This is a framework level TODO.
- **Measurement does not realize deferred content.** Measuring a
  `GeometryReader` or an unselected `ViewThatFits` candidate does not realize
  its authored content and commits no lifecycle, task, gesture, focus, or
  semantic side effects. 
  This is an implementation detail that should change if it causes issues.
- **Missing named coordinate spaces fall back to global.** A
  `frame(in: .named(...))` read whose space is not present resolves in global
  coordinates and records a frame diagnostic instead of trapping; duplicate
  names keep last-writer-wins.
  This is a framework level TODO.
- **The lazy path requires a single direct `ForEach`.** `LazyVStack` and
  `LazyHStack` window only an indexed row source under a scroll-declared
  viewport; other shapes fall back to exhaustive realization. Heterogeneous
  builder collections are eager and report a runtime issue past a few hundred
  rows. 
  This is a framework level TODO.

## Collections and selection

- **Tree-forward, keyboard-first collections.** `List`, `OutlineGroup`, and
  `Table` lean toward structural, keyboard-first navigation rather than
  touch-scrolling ergonomics. This is one of the vision document's deliberate
  terminal-native deviations.
- **`Table` takes column values, not a column builder.** SwiftUI's `Table`
  uses `@TableColumnBuilder` with per-column cell closures keyed into row
  values. SwiftTUI takes `[TableColumn]` metadata plus positional row cells.
  This is the `Tab(...)` stance applied to columns: structured
  value metadata gives deterministic terminal text and avoids resolving
  per-cell label trees for chrome.
- **Column widths are a monotonic high-water mark.** Source-backed automatic
  columns widen when a wider row enters the viewport and do not narrow while
  element IDs are stable. 
  (A column does not move as rows scroll through it.)
- **Selection requires an explicit `.tag`.** Rows without a usable tag render
  but are unselectable, and the runtime reports an issue.
  Selection is a typed value binding; deriving tags implicitly could silently bind the
  wrong value, and the fail-loud diagnostic matches the framework's general
  preference for reported issues over silent inference.
  This is an implementation detail that should change if it causes issues.
- **`List` adds `selection:onActivate:`.** SwiftUI's `List(selection:)` only
  binds selection; activation arrives through taps or `onChange`. The
  recorded framing: SwiftTUI retains its terminal-specific activation
  callback and column schema rather than adopting SwiftUI's unrelated
  sort/customize surface.
- **`Picker` options are scraped to text.** Option content is extracted into
  labeled option values; arbitrary option views degrade to their extracted
  text. 
  This default treatment exists because terminal option rows are single-line
  text by construction, and structured option metadata keeps every picker style
  deterministic, the same trade recorded for tab labels.
  A ViewModifier to allow changing this treatment is a framework level TODO.
- **`TabView` resolves only the selected body.** Unselected tab content is
  not resolved, so tab-local state can reset on deselection; state that must
  survive belongs above the tab seam. 
  This is a framework level TODO.
  Resolving only the visible tab keeps resolve
  and commit cost proportional to the visible surface, which matters more on
  a terminal than in SwiftUI's retained scene graph.
  This is an implementation detail that should change if it causes issues.

## Focus and commands

- **Focus traversal is geometry-aware and wraps.** Focus starts at the
  top-most control nearest the leading edge; Tab moves forward in
  locale-aware layout order and wraps back to the beginning. 
  Traversal policy uses geometry, not only a linear order.
  Wrapping is the terminal-native reading — there is no surrounding
  native UI for focus to escape to, so the chain cycles instead of
  ending.
- **The `List` focus highlight is row-shaped.** The active row receives
  focused chrome and the container stays neutral, where SwiftUI focuses the
  container. Row-level chrome is the restrained-chrome default: a
  container-wide highlight would repaint the whole list to say what the row
  already says.
- **`keyboardShortcut` is replaced by the command surface.** There is no
  `keyboardShortcut(_:)` or `KeyEquivalent`. Key bindings are authored with
  `keyCommand` and `paletteCommand` on the `ActionScope` surface, dispatched
  shallowest-wins along the focus chain, with modifier-less bindings
  framework-reserved.
  This is an implementation detail that should change if it causes issues.
- **No `onSubmit` or `submitLabel`.** Return inside a `TextField` is not a
  field-level submit event. 
  This is a framework level TODO.
- **No `onMoveCommand` or `onExitCommand`.**
  This is a framework level TODO.

## Presentations

- **Alerts and confirmation dialogs queue first-in, first-out.** Sheets,
  full-screen covers, popovers, and menus stack as independent surfaces;
  prompts queue, and only the oldest active prompt is visible. SwiftUI leaves
  concurrent-presentation behavior largely undefined.
  Escape dismisses the most recently activated *visible* presentation across
  families, so a queued prompt cannot intercept dismissal from a visible
  surface.
- **`fullScreenCover` has no chrome.** It occupies the complete terminal
  proposal with no header, inset, border, or implicit close button — the
  vision document's restrained-chrome default applied to the modal family.
- **`onDismiss` is observation, not command.** It runs once after a committed
  activation disappears — for state writes, Escape, built-in actions, toast
  expiration, item-ID replacement, and removal of the presenting subtree
  alike. This is the presenter-side half of the dismissal stance; see
  <doc:Dismissal-Is-Data>.
- **Item presentations refresh on same-ID replacement.** Replacing a
  presented item with an equal-ID value refreshes mounted content without
  losing state; changing the ID tears down and remounts. This is the
  framework's entity-identity model applied to presentation.
- **Extra presentation families and forms.** `toast` and `popoverTip` have no
  SwiftUI equivalent. The item-driven `alert` and `confirmationDialog` forms
  are recorded as intentional data-model extensions, not claims that SwiftUI
  has the same labels; titled sheet forms mirror SwiftTUI's existing titled
  Boolean sheet.
- **`Menu` anchors at the presentation host.** The menu surface is non-modal
  and anchors top-leading rather than at its source control. 
  This is a framework level TODO.

## Gestures and input

- **Cell-denominated gesture defaults.** `DragGesture.minimumDistance`
  defaults to `0` cells (SwiftUI: 10 points), and
  `LongPressGesture.maximumDistance` defaults to `0` cells (SwiftUI: 10
  points). 
  These are terminal-faithful defaults —
  any continuous cell movement is meaningful, and callers pass positive
  values to allow pointer drift. Velocity is reported in cells per second.
- **Tap timing is explicit.** A single tap has no timing component: one
  on-target down-and-up fires it for any press duration, because terminals
  have no OS-level tap coalescing. Multi-tap sequences fail if the next tap
  misses the public 350 ms `TapGesture.interTapWindow`. 
  This is an implementation detail that should change if it causes issues.
- **A claiming high-priority gesture suppresses controls.** Once a
  high-priority recognizer claims the pointer stream, sibling recognizers do
  not receive it and a descendant control does not activate;
  `simultaneousGesture` is the explicit exception. 
  This is a framework level TODO.
- **`GestureMask` applies at registration time.** A mask flip over a spared
  subtree is not retro-applied until that subtree re-resolves, and the mask
  governs gesture recognizers, not hover handlers or control activation.
  This is an implementation detail that should change if it causes issues.
- **`Gesture.updating(_:body:)` receives a stand-in `Transaction`.** The
  `inout Transaction` parameter is a no-op; mutations are discarded. 
  This is a framework level TODO.
- **`DragGesture.Value` and `SpatialTapGesture.Value` carry extra fields.**
  Drag values add pointer provenance and the sampled `path` for the current
  gesture (with a documented lifetime); spatial tap values add a
  `PointerLocation`.
  Terminal pointer quality varies by host, so
  values carry their provenance the same way `PointerInputCapabilities`
  surfaces input quality: as metadata for optional precision
  affordances.
- **`onPointerHover` replaces `onHover`/`onContinuousHover`.** One modifier
  delivers `HoverPhase` values carrying continuous cell-space points; neither
  SwiftUI spelling exists. 
- **`onScrollWheel` exists; SwiftUI has no equivalent.
  This is an implementation detail that should change if it causes issues.
- **Cell-only terminals synthesize pointer locations.** Where a host reports
  only cell coordinates, the runtime supplies the cell center as the
  continuous location; native, web, and terminal-pixel hosts can carry true
  sub-cell positions. 
  Use these for optional affordances — layout stays cell-based.

## Shapes and drawing

- **`Shape` conformance is dual.** Conform with SwiftUI-style `path(in:)`
  *or* with an analytic `geometry` primitive; the two are bridged. The
  recorded context: the five analytic primitives carry exact, fixture-pinned
  cell output and cell-aspect correction that sampled paths cannot promise;
  see <doc:AspectCorrectShapes>.
- **Vector-transform APIs are absent.** No `trim(from:to:)`,
  `offset`, `rotation`, `scale`, or `transform` shape adapters ("path/vector
  transforms with no faithful meaning over discrete cells"), no `lineWidth:`
  stroke overloads (strokes are one cell wide; weight is the glyph palette
  via `borderSet`), no `addArc` (needs an angle type), no general
  `clipShape(_:)` to an arbitrary path, and no animatable path
  morphing (parameterized shapes animate their parameters instead).
  This is a framework level TODO.
- **Custom shapes stretch; built-ins inscribe.** A custom `path(in:)` shape
  fills its frame, while `Circle` stays round by inscribing the short axis —
  recorded as consequences of the cell grid, together with sub-cell
  quantization of custom paths versus bit-exact primitives.
- **`FillRule` has a dual default.** Hit-testing (`contains`) defaults to
  even-odd to preserve existing hit regions; the rendering bridge defaults to
  non-zero, SwiftUI's default.
  This is a framework level TODO.
- **`Canvas` prefers value drawings.** `Canvas(SomeCanvasDrawing())` is the
  recommended form because value drawings compare structurally across
  rerenders; the SwiftUI-shaped closure form compares by identity. An extra
  `init(grid:_:)` hands SwiftUI-habit code the size alongside the context.

## Animation and transitions

- **`Int` animates with truncating scale.** `Int` conforms to
  `VectorArithmetic` with truncate-toward-zero scaling, so a delta of one
  jumps at the end of the curve. Terminal cel coordinates are integer-quantized;
  callers needing sub-cell precision use `Double`.
- **`Transaction` exposes only animation intent.** 
  This is a framework level TODO.
- **The transition effect palette is opacity and offset.** Other modifiers
  inside a custom `Transition.body` are silently ignored, and there is no
  built-in `.scale` transition; `TransitionContent` is an inert probe
  placeholder rather than SwiftUI's fully capable view.
  This is a framework level TODO.
- **`matchedGeometryEffect` interpolates position only.** A matched pair that
  changes size snaps to the destination size for the whole animation, and the
  signature omits `properties:` and `anchor:`. The size narrowing is a gap
  register entry. 
  This is a framework level TODO.
- **Matched-geometry namespaces work without `@Namespace`.** The wrapper
  exists with SwiftUI semantics, but `matchedGeometryEffect(id:in:)` also
  accepts `.default` — one global namespace — where SwiftUI requires a
  `Namespace.ID`.
  This is a framework level TODO.
- **Memoized body reuse is an `Equatable`-only opt-in.** SwiftUI's engine
  compares view inputs structurally and implicitly; SwiftTUI reuses memoized
  bodies only for views that are `Equatable` (directly or via
  `.equatable()`).
  This is a framework level TODO.
- **Reduced motion changes rendering, not just timing.** Under reduced
  motion, `Spinner` renders static text, `PhaseAnimator` renders only its
  first phase, and `AnimatedImage` renders its first frame; `CI=true` and
  non-TTY stdout imply reduced motion. SwiftUI treats the flag as advisory.
  Terminal output is frequently captured, piped, and read by
  screen readers; degrading to stable output is the terminal-native reading
  of the accessibility preference rather than a per-app opt-in.

## Styling and color

- **Semantic roles resolve through a host-owned theme.** Views write semantic
  style roles (`.foreground`, `.warning`, `.tint`, ...) and the active host
  integration selects the theme that resolves them; `Theme` is not part of
  the `View` authoring surface. 
  The inner TUI app does not select or inspect host style variants, and
  terminal capability affects presentation, not layout semantics.
- **Style families are open protocols.** `ButtonStyle`, `TextFieldStyle`,
  `PickerStyle`, `ListStyle`, `TabViewStyle`, and peers are public,
  extensible protocols with `Any*Style` erasers — including families SwiftUI
  keeps closed. 
  `ToggleStyle`/`ProgressViewStyle`/`LabelStyle`/`MenuStyle` as
  accidental incompleteness within that design, explicitly not intentional.
- **`Color` vocabulary differs.** Initializers use `alpha:` where SwiftUI
  uses `opacity:`, mixing is `mixed(with:amount:method:)`
  rather than `mix(with:by:)` 
  This is a framework level TODO.
- There is no `Color.primary`, `.secondary`, or `.accentColor`. 
  This is a framework level TODO.
- **No `ColorScheme` axis.** Views can read `colorSchemeContrast` and the
  raw `TerminalAppearance`, but there is no light/dark `ColorScheme` type.
  A terminal reports foreground/background colors, not a scheme;
  the appearance surface exposes what the host actually knows, and semantic
  roles absorb the light/dark decision in the theme.


## Surface extensions with no SwiftUI analog

These are additions rather than changed semantics; they are listed so the
register is complete. Terminal-program embedding (`TerminalView`) and the
continuous-coordinate system are recorded as deliberate terminal-native
capabilities in the vision document. The others follow the same stance:

- `EnvironmentReader`, for reading environment values and actions inline.
- `TextFigure`, FIGlet banner text with embedded fonts.
- `PointerInputCapabilities`, `CellPixelMetrics`, and `PointerLocation` input
  metadata via `GeometryProxy` — recorded as metadata that must not change
  the base layout contract.
- `EnvironmentValues.requestTermination` and
  `EnvironmentValues.terminalHandoff` — recorded as runtime-injected verbs
  that expose host-owned actions without putting host mechanics in views.
- Per-side border styling (`BorderEdgeStyle`) and animatable perimeter
  gradients (`BorderBlend`).
- `ProgressView(value:total:barWidth:)` — a terminal-cell width control on an
  otherwise SwiftUI-shaped control.
- The `SwiftTUIProfiling` product and the host-contract surface
  (`SceneManifest`, `HostedSceneSession`, and peers).

## Where divergences are recorded

The vision document states the divergence policy and the principled
omissions. The gap register lists SwiftUI-shaped APIs with narrower behavior
and is the only place future work is tracked. Guide articles in this catalog
carry the per-surface contracts: <doc:AnyView> documents its own
"Differences From SwiftUI" (state is keyed by the erased payload type),
<doc:Shapes> its "deliberately absent" list, and <doc:State-Keying>,
<doc:Dismissal-Is-Data>, <doc:Focus>, <doc:Collections>,
<doc:Geometry-And-Preferences>, and <doc:Pointer-And-Canvas> the rest.
Individual API documentation comments carry the divergences local to one
symbol, marked with headings such as "Terminal-faithful defaults".
