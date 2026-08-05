# Divergences and gaps

The single register of where SwiftTUI's public API departs from SwiftUI and
where the implementation at `HEAD` falls short of the API shape or the
project's intent.

SwiftTUI mirrors SwiftUI's *shape*. When a literal desktop behavior would
degrade the terminal experience, SwiftTUI uses a terminal-native default while
the API shape stays SwiftUI-shaped. SwiftTUI implements subsets of SwiftUI
only where they map to high-value TUI use cases, does not implement deprecated
or questionable APIs, and preserves the important semantics of every API it
does implement.

## How to read this register

Every entry carries one of three statuses:

- ***Ratified*** — a deliberate, recorded stance. The rationale is part of the
  entry, and the divergence is expected to persist.
- ***Provisional*** — deliberate today, held loosely. The behavior is a
  considered default that should be revisited if it causes real friction.
- ***Gap*** — `HEAD` delivers less than the API shape or the project vision
  implies. Gaps are recorded, not scheduled — nothing in this register is a
  roadmap or a promise.

Two scope notes. Under the subset policy, a bare absence is a scope decision,
not a divergence: absent APIs appear here only when the absence has a recorded
stance or breaks an idiom. And items the vision document declares out of scope
are omitted even when SwiftUI exposes a corresponding API.

## Omissions

- **No `NavigationLink`.** *Ratified.* Navigation is strictly data-driven: a
  push mutates the bound path (`NavigationStack(path:root:)` plus
  `navigationDestination(for:destination:)`). `NavigationLink` fuses a control
  to a navigation side effect, so navigation state stops being derivable from —
  and mutable through — the app's data. There is deliberately no link-control
  sugar.
- **No `@Environment(\.dismiss)`.** *Ratified.* Presented content receives no
  ambient dismiss command. The presenter owns a Boolean or optional-item
  binding, and dismissal clears that source value. A view cannot know the
  context in which it is displayed, so a child-side self-dismissal command
  couples reusable content to an assumed presenter. Presenter-side observation
  (`onDismiss:`) is compatible with the stance; child-side dismissal commands
  are not. See <doc:Dismissal-Is-Data>.
- **No `View.tabItem(_:)`.** *Provisional.* Tabs are declared with the
  structured `Tab(_:detail:badge:value:content:)` form.
- **No heterogeneous `NavigationPath`.** *Provisional.* Only the homogeneous
  `Binding<[Route]>` path form ships.
- **No `NavigationSplitView`.** *Provisional.* Out of scope for the current
  navigation surface.

## App entry, scenes, and lifecycle

- **`App.main()` is asynchronous.** *Ratified.* `SwiftUI.App.main()` is
  synchronous and a top-level `MyApp.main()` call works there. SwiftTUI's
  `App` refines `AsyncParsableCommand`, so only `@main` binds the asynchronous
  entry point. A bare `MyApp.main()` — muscle memory from SwiftUI — would
  resolve to the synchronous `ParsableCommand.main()` overload from
  swift-argument-parser and never start the runtime, so SwiftTUI ships a
  trapping shim that rejects the call with a precise diagnostic in both DEBUG
  and release builds.
- **An `App` is also a CLI command.** *Ratified.* The batteries-included `App`
  conforms to `SwiftTUICommand`, and apps opt into the standard option surface
  (`--accessible`, `--no-color`, `--ascii`, `--reduce-motion`, `--json`,
  `--linear`, `--debug`, `--web`, ...) with
  `@OptionGroup var swiftTUIOptions: SwiftTUIOptions`. SwiftUI's `App` has no
  argument-parsing surface. The command-enabled `App` is the
  batteries-included overlay over `SwiftTUIRuntime.App`, which remains
  available for host-managed declarations without the command surface.
- **One active root scene.** *Ratified.* The runtime drives a single
  full-canvas `WindowGroup` per session rather than SwiftUI's multi-window,
  multi-scene model. Host-specific integration allowing multi-scene
  orchestration lives in sibling products, not in the core runtime.
- **No `ScenePhase`.** *Gap.* There is no app-lifecycle environment signal.

## Data flow and observation

- **Observation-only data flow.** *Ratified.* The state surface is `State`,
  `Binding`, `Bindable`, `Environment`, and `FocusState`. The Combine-era
  object family — `ObservableObject`, `@Published`, `@StateObject`,
  `@ObservedObject`, `@EnvironmentObject` — does not exist. Models are
  `@Observable` classes. The authoring layers are Foundation-free by policy
  and build on non-Apple platforms where Combine is unavailable, and the
  subset policy excludes APIs that modern SwiftUI itself has superseded; the
  Observation path is the one data-flow model that satisfies both.
- **Environment models must be `Sendable`.** *Ratified.* `EnvironmentKey.Value`
  is `Sendable`-constrained, so `@Environment(Model.self)` and
  `environment(_:)` accept only `Observable & Sendable` classes. SwiftUI has
  no such constraint. The environment store is `Sendable`-constrained so
  environment snapshots can cross the off-main frame tail; a
  `@MainActor @Observable final class` is implicitly `Sendable` and is the
  natural authoring shape here.
- **`Binding.init(get:set:)` takes `@MainActor` closures.** *Ratified.*
  SwiftUI's accessors carry no isolation annotation. This is downstream of the
  framework itself using strict, unsuppressed concurrency.
- **No `Binding` projections.** *Gap.* `Binding.animation(_:)`,
  `Binding.transaction(_:)`, and `Binding.init?(_:)` (optional unwrapping) are
  absent.
- **Equal-value `State` writes are inert.** *Provisional.* Writing a value
  equal to the current one does not invalidate the owner.

## Geometry and units

- **Two named coordinate domains instead of `CGFloat` geometry.** *Ratified.*
  `CellPoint`/`CellSize`/`CellRect` are the integer terminal grid (layout,
  semantic bounds, raster); `Point`/`Size`/`Rect`/`Vector` are continuous cell
  space (gestures, hover, `Canvas`, interpolation); `Pixel*` types carry host
  device-pixel provenance. `frame(width:height:)` takes `Int`, and
  `Shape.path(in:)` receives a `Rect`, not a `CGRect`.
- **`ScrollPosition` shares SwiftUI's name with different semantics.** *Gap.*
  In SwiftUI, `ScrollPosition` is an identity/edge/anchor abstraction applied
  with `scrollPosition(_:)`. In SwiftTUI it is a raw cell offset
  (`x`/`y: Int`) threaded through a `ScrollView(position:)` initializer that
  SwiftUI does not have.
- **`contentShape(_:)` is dual-denominated.** *Provisional.* Rectangular
  content shapes are cell-denominated (`CellRect`); path content shapes use
  continuous cell space.

## Layout

- **Surplus distribution floors every member at its ideal.** *Provisional.* In
  SwiftUI, text can respond *larger* than a lean offer, so equal-division
  surplus offers are safe. SwiftTUI's measure truncates instead, so in surplus
  no group member is offered below its own ideal while the group budget still
  covers the remaining ideals.
- **Deficit compresses proportionally from ideals.** *Provisional.* Surplus
  uses equal division from zero (SwiftUI's treatment of unbounded children)
  with the ideal floor; deficit keeps proportional compression so trailing
  spacers collapse before content loses rows.
- **Offers round half-up.** *Provisional.* Integer division of surplus is
  balanced across children rather than floored.
- **`Text` has a zero structural minimum on the horizontal axis.** *Ratified.*
  SwiftUI reserves the truncation minimum; in SwiftTUI a higher-priority
  flexible sibling can squeeze a `Text` to zero width. Recorded as the
  sharpest priority edge of the layout model, kept from the historical
  compression path.
- **Custom `Layout` types must be `Sendable`, with `Sendable` caches.**
  *Ratified.* The renderer evaluates custom layouts on the off-main
  frame-tail worker.
- **`Layout` caches are pass-local scratch.** *Gap.* SwiftUI persists `Cache`
  values across passes through `updateCache`. SwiftTUI shares the cache
  between measurement and placement for one pass, then drops it.
- **Measurement does not realize deferred content.** *Provisional.* Measuring
  a `GeometryReader` or an unselected `ViewThatFits` candidate does not
  realize its authored content and commits no lifecycle, task, gesture, focus,
  or semantic side effects.
- **Missing named coordinate spaces fall back to global.** *Gap.* A
  `frame(in: .named(...))` read whose space is not present resolves in global
  coordinates and records a frame diagnostic instead of trapping; duplicate
  names keep last-writer-wins.
- **The lazy path requires a single direct `ForEach`.** *Gap.* `LazyVStack`
  and `LazyHStack` window only an indexed row source under a scroll-declared
  viewport; other shapes fall back to exhaustive realization. Heterogeneous
  builder collections are eager and report a runtime issue past a few hundred
  rows.

## Collections and selection

- **Tree-forward, keyboard-first collections.** *Ratified.* `List`,
  `OutlineGroup`, and `Table` lean toward structural, keyboard-first
  navigation rather than touch-scrolling ergonomics. This is one of the
  vision document's deliberate terminal-native deviations.
- **`Table` takes column values, not a column builder.** *Ratified.* SwiftUI's
  `Table` uses `@TableColumnBuilder` with per-column cell closures keyed into
  row values. SwiftTUI takes `[TableColumn]` metadata plus positional row
  cells. This is the `Tab(...)` stance applied to columns: structured value
  metadata gives deterministic terminal text and avoids resolving per-cell
  label trees for chrome.
- **Column widths are a monotonic high-water mark.** *Ratified.* Source-backed
  automatic columns widen when a wider row enters the viewport and do not
  narrow while element IDs are stable. A column does not move as rows scroll
  through it.
- **Selection requires an explicit `.tag`.** *Provisional.* Rows without a
  usable tag render but are unselectable, and the runtime reports an issue.
  Selection is a typed value binding; deriving tags implicitly could silently
  bind the wrong value, and the fail-loud diagnostic matches the framework's
  general preference for reported issues over silent inference.
- **`List` adds `selection:onActivate:`.** *Ratified.* SwiftUI's
  `List(selection:)` only binds selection; activation arrives through taps or
  `onChange`. SwiftTUI retains its terminal-specific activation callback
  rather than adopting SwiftUI's unrelated sort/customize surface.
- **`Picker` options are scraped to text.** *Ratified.* Option content is
  extracted into labeled option values; arbitrary option views degrade to
  their extracted text. Terminal option rows are single-line text by
  construction, and structured option metadata keeps every picker style
  deterministic — the same trade recorded for tab labels. A modifier that
  overrides this treatment is an open gap.
- **`TabView` resolves only the selected body.** *Ratified.* Resolving only
  the visible tab keeps resolve and commit cost proportional to the visible
  surface, which matters more on a terminal than in SwiftUI's retained scene
  graph. Consequence: tab-local state can reset on deselection, so state that
  must survive belongs above the tab seam. Preserving tab-local state across
  deselection without eager resolution is an open gap.

## Focus and commands

- **Focus traversal is geometry-aware and wraps.** *Ratified.* Focus starts at
  the top-most control nearest the leading edge; Tab moves forward in layout
  order and wraps back to the beginning. Traversal policy uses geometry, not
  only a linear order. Wrapping is the terminal-native reading — there is no
  surrounding native UI for focus to escape to, so the chain cycles instead
  of ending.
- **The `List` focus highlight is row-shaped.** *Ratified.* The active row
  receives focused chrome and the container stays neutral, where SwiftUI
  focuses the container. Row-level chrome is the restrained-chrome default: a
  container-wide highlight would repaint the whole list to say what the row
  already says.
- **`keyboardShortcut` is replaced by the command surface.** *Provisional.*
  There is no `keyboardShortcut(_:)` or `KeyEquivalent`. Key bindings are
  authored with `keyCommand` and `paletteCommand` on the `ActionScope`
  surface, dispatched shallowest-wins along the focus chain, with
  modifier-less bindings framework-reserved.
- **No `onSubmit` or `submitLabel`.** *Gap.* Return inside a `TextField` is
  not a field-level submit event.
- **No `onMoveCommand` or `onExitCommand`.** *Gap.*

## Presentations

- **Alerts and confirmation dialogs queue first-in, first-out.** *Ratified.*
  Sheets, full-screen covers, popovers, and menus stack as independent
  surfaces; prompts queue, and only the oldest active prompt is visible.
  SwiftUI leaves concurrent-presentation behavior largely undefined. Escape
  dismisses the most recently activated *visible* presentation across
  families, so a queued prompt cannot intercept dismissal from a visible
  surface.
- **`fullScreenCover` has no chrome.** *Ratified.* It occupies the complete
  terminal proposal with no header, inset, border, or implicit close button —
  the vision document's restrained-chrome default applied to the modal
  family.
- **`onDismiss` is observation, not command.** *Ratified.* It runs once after
  a committed activation disappears — for state writes, Escape, built-in
  actions, toast expiration, item-ID replacement, and removal of the
  presenting subtree alike. This is the presenter-side half of the dismissal
  stance; see <doc:Dismissal-Is-Data>.
- **Item presentations refresh on same-ID replacement.** *Ratified.* Replacing
  a presented item with an equal-ID value refreshes mounted content without
  losing state; changing the ID tears down and remounts. This is the
  framework's entity-identity model applied to presentation.
- **Extra presentation families and forms.** *Ratified.* `toast` and
  `popoverTip` have no SwiftUI equivalent. The item-driven `alert` and
  `confirmationDialog` forms are recorded as intentional data-model
  extensions, not claims that SwiftUI has the same labels; titled sheet forms
  mirror SwiftTUI's existing titled Boolean sheet.
- **`Menu` anchors at the presentation host.** *Gap.* The menu surface is
  non-modal and anchors top-leading rather than at its source control.

## Gestures and input

- **Cell-denominated gesture defaults.** *Ratified.* `DragGesture.minimumDistance`
  defaults to `0` cells (SwiftUI: 10 points), and
  `LongPressGesture.maximumDistance` defaults to `0` cells (SwiftUI: 10
  points). These are terminal-faithful defaults — any continuous cell
  movement is meaningful, and callers pass positive values to allow pointer
  drift. Velocity is reported in cells per second.
- **Tap timing is explicit.** *Provisional.* A single tap has no timing
  component: one on-target down-and-up fires it for any press duration,
  because terminals have no OS-level tap coalescing. Multi-tap sequences fail
  if the next tap misses the public 350 ms `TapGesture.interTapWindow`.
- **A claiming high-priority gesture suppresses controls.** *Gap.* Once a
  high-priority recognizer claims the pointer stream, sibling recognizers do
  not receive it and a descendant control does not activate;
  `simultaneousGesture` is the explicit exception.
- **`GestureMask` applies at registration time.** *Provisional.* A mask flip
  over a spared subtree is not retro-applied until that subtree re-resolves,
  and the mask governs gesture recognizers, not hover handlers or control
  activation.
- **`Gesture.updating(_:body:)` receives a stand-in `Transaction`.** *Gap.*
  The `inout Transaction` parameter is a no-op; mutations are discarded.
- **`DragGesture.Value` and `SpatialTapGesture.Value` carry extra fields.**
  *Ratified.* Drag values add pointer provenance and the sampled `path` for
  the current gesture (with a documented lifetime); spatial tap values add a
  `PointerLocation`. Terminal pointer quality varies by host, so values carry
  their provenance the same way `PointerInputCapabilities` surfaces input
  quality: as metadata for optional precision affordances.
- **`onPointerHover` replaces `onHover`/`onContinuousHover`.** *Ratified.* One
  modifier delivers `HoverPhase` values carrying continuous cell-space
  points; neither SwiftUI spelling exists.
- **`onScrollWheel` exists; SwiftUI has no equivalent.** *Provisional.*
- **Cell-only terminals synthesize pointer locations.** *Ratified.* Where a
  host reports only cell coordinates, the runtime supplies the cell center as
  the continuous location; native, web, and terminal-pixel hosts can carry
  true sub-cell positions. Use these for optional affordances — layout stays
  cell-based.

## Shapes and drawing

- **`Shape` conformance is dual.** *Ratified.* Conform with SwiftUI-style
  `path(in:)` *or* with an analytic `geometry` primitive; the two are
  bridged. The five analytic primitives carry exact, fixture-pinned cell
  output and cell-aspect correction that sampled paths cannot promise; see
  <doc:AspectCorrectShapes>.
- **No path/vector transform adapters.** *Ratified.* No `trim(from:to:)`,
  `offset`, `rotation`, `scale`, or `transform` shape adapters — path/vector
  transforms have no faithful meaning over discrete cells — and no
  `lineWidth:` stroke overloads: strokes are one cell wide, and weight is the
  glyph palette via `borderSet`.
- **No `addArc`, no general `clipShape(_:)`, no animatable path morphing.**
  *Gap.* `addArc` needs an angle type; clipping to an arbitrary path is
  unimplemented; parameterized shapes animate their parameters instead of
  morphing paths.
- **Custom shapes stretch; built-ins inscribe.** *Ratified.* A custom
  `path(in:)` shape fills its frame, while `Circle` stays round by inscribing
  the short axis — recorded as consequences of the cell grid, together with
  sub-cell quantization of custom paths versus bit-exact primitives.
- **`FillRule` has a dual default.** *Gap.* Hit-testing (`contains`) defaults
  to even-odd to preserve existing hit regions; the rendering bridge defaults
  to non-zero, SwiftUI's default.
- **`Canvas` prefers value drawings.** *Ratified.*
  `Canvas(SomeCanvasDrawing())` is the recommended form because value
  drawings compare structurally across rerenders; the SwiftUI-shaped closure
  form compares by identity. An extra `init(grid:_:)` hands SwiftUI-habit
  code the size alongside the context.
- **`Canvas` draws on the legacy integer-cell interface internally.** *Gap.*
  The internal drawing coordinate model is still the integer-cell interface,
  not the fractional cell-coordinate model the rest of the geometry system
  uses.

## Animation and transitions

- **`Int` animates with truncating scale.** *Ratified.* `Int` conforms to
  `VectorArithmetic` with truncate-toward-zero scaling, so a delta of one
  jumps at the end of the curve. Terminal cell coordinates are
  integer-quantized; callers needing sub-cell precision use `Double`.
- **`Transaction` exposes only animation intent.** *Gap.* Other SwiftUI
  transaction fields are not exposed.
- **The transition effect palette is opacity and offset.** *Gap.* Other
  modifiers inside a custom `Transition.body` are silently ignored, and there
  is no built-in `.scale` transition; `TransitionContent` is an inert probe
  placeholder rather than SwiftUI's fully capable view.
- **`matchedGeometryEffect` interpolates position only.** *Gap.* A matched
  pair that changes size snaps to the destination size for the whole
  animation, and the signature omits `properties:` and `anchor:`.
- **Matched-geometry namespaces work without `@Namespace`.** *Provisional.*
  The wrapper exists with SwiftUI semantics, but
  `matchedGeometryEffect(id:in:)` also accepts `.default` — one global
  namespace — where SwiftUI requires a `Namespace.ID`.
- **Memoized body reuse is an `Equatable`-only opt-in.** *Gap.* SwiftUI's
  engine compares view inputs structurally and implicitly; SwiftTUI reuses
  memoized bodies only for views that are `Equatable` (directly or via
  `.equatable()`).
- **Reduced motion changes rendering, not just timing.** *Ratified.* Under
  reduced motion, `Spinner` renders static text, `PhaseAnimator` renders only
  its first phase, and `AnimatedImage` renders its first frame; `CI=true` and
  non-TTY stdout imply reduced motion. SwiftUI treats the flag as advisory.
  Terminal output is frequently captured, piped, and read by screen readers;
  degrading to stable output is the terminal-native reading of the
  accessibility preference rather than a per-app opt-in.

## Styling and color

- **Semantic roles resolve through a host-owned theme.** *Ratified.* Views
  write semantic style roles (`.foreground`, `.warning`, `.tint`, ...) and
  the active host integration selects the theme that resolves them; `Theme`
  is not part of the `View` authoring surface. The inner TUI app does not
  select or inspect host style variants, and terminal capability affects
  presentation, not layout semantics.
- **Style families are open protocols.** *Ratified.* `ButtonStyle`,
  `TextFieldStyle`, `PickerStyle`, `ListStyle`, `TabViewStyle`, and peers are
  public, extensible protocols with `Any*Style` erasers — including families
  SwiftUI keeps closed.
- **`ToggleStyle`, `ProgressViewStyle`, `LabelStyle`, and `MenuStyle` have no
  open protocol.** *Gap.* Their absence is accidental incompleteness within
  the open-protocol design, explicitly not a stance.
- **`Color` vocabulary differs.** *Gap.* Initializers use `alpha:` where
  SwiftUI uses `opacity:`, and mixing is `mixed(with:amount:method:)` rather
  than `mix(with:by:)`.
- **No `Color.primary`, `.secondary`, or `.accentColor`.** *Gap.*
- **No `ColorScheme` axis.** *Ratified.* Views can read `colorSchemeContrast`
  and the raw `TerminalAppearance`, but there is no light/dark `ColorScheme`
  type. A terminal reports foreground/background colors, not a scheme; the
  appearance surface exposes what the host actually knows, and semantic roles
  absorb the light/dark decision in the theme.

## Surface extensions with no SwiftUI analog

These are ratified additions rather than changed semantics; they are listed so
the register is complete. Terminal-program embedding (`TerminalView`) and the
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

## Accessibility

The semantic substrate, terminal linear renderer, cursor-follows-focus, and
Web/WASI ARIA tree are complete. The SwiftUI-host overlay pushes runtime focus
to VoiceOver, and the Android host provides a Compose semantics overlay.

- **Native assistive-technology focus is one-way.** *Gap.* Focus flows
  runtime → VoiceOver/TalkBack only. Native assistive-technology-originated
  focus traversal is not fed back into SwiftTUI's runtime focus.
- **No WCAG-referenced conformance suite or automated screen-reader
  testing.** *Gap.* Unit tests and guardrail scripts cover accessibility, but
  no conformance checklist exists.

## Android host

`SwiftTUIAndroidHost` builds for `aarch64-unknown-linux-android28`, and the
`swift-tui-examples/AndroidGallery` app embeds `GalleryView()` in a Compose
host: styled cells, embedded images, damage-aware row repaints over a retained
bitmap, a transparent TalkBack semantics overlay, hardware keys, the soft
keyboard, touch, wheel scrolling, hyperlinks, and the system clipboard
(app-requested clipboard writes return through the JNI/C ABI).

- **Android accessibility focus and IME composition are one-way.** *Gap.*
  Runtime focus reaches TalkBack, but TalkBack-originated focus traversal is
  not fed back into the runtime, and full IME pre-edit/marked-text
  composition (beyond committed text) is not implemented.
- **No Android content URI import.** *Gap.* SAF / `content://` ingestion into
  the runtime drop path is not implemented.
- **No automated Android runtime gate.** *Gap.* `AndroidGallery` assembles
  locally and the Kotlin client logic has JVM unit tests
  (`./gradlew testDebugUnitTest`, which run without the NDK), but
  emulator/device smoke is not in CI.
- **No `x86_64` Android packaging.** *Gap.* The framework — including the
  vendored `swift-png`/`JPEG` image path — cross-compiles for
  `x86_64-unknown-linux-android28` (the earlier `swift-png` SIMD build
  blocker was replaced by a scalar reimplementation), but `arm64-v8a` is the
  only ABI the `AndroidGallery` example currently packages and smoke-tests.

## Terminal-program embedding

`TerminalView`, `TerminalProcessSession` over a pty, and the
`SwiftTUITerminalWorkspace` tabbed/split-pane layer ship on macOS and Linux.

- **No Sixel/Kitty graphics inside embedded panes.** *Gap.*
- **No Kitty keyboard protocol or OSC 99 notification namespacing.** *Gap.*
- **No pane-local selection/copy/scrollback mode.** *Gap.*
- **No process reattachment.** *Gap.* Reconnecting to a still-running child
  process after the host app restarts — and a daemon-backed session
  lifecycle — are not implemented.
- **No iOS or WASI builds of the embedding products.** *Gap.*

## Runtime and pipeline internals

The seven-phase pipeline, off-main frame-tail execution, and explicit
work-stack paths for parts of measurement and placement are complete.

- **Built-in layout is not fully iterative.** *Gap.* The explicit work-stack
  migration is partial: built-in layout still recurses on the Swift call
  stack, so the frame-tail worker uses an enlarged stack instead of a bounded
  iterative engine.
- **`ViewGraph` decomposition is design-only.** *Gap.* Smaller `ViewGraph`
  types with cleaner ownership, dependency-aware (profile-gated) body
  re-evaluation, explicit context threading through resolve, and interning of
  `Identity` values remain designs with no corresponding code.
- **The retained frame index rebuilds fully every frame.** *Gap.* Deriving
  the next retained index performs a full rebuild; the incremental fragment
  patch is deferred because measurement shows retained-index construction is
  a sub-1% slice of frame time. The debug byte-equivalence oracle is retained
  for the moment a real patch path lands.

## WASI and browser execution

The `SwiftTUIWASI` runner, `web-surface` wire, and current WASI resolve
behavior are described by the per-host engine profiles in
`docs/HOSTS-AND-PLATFORMS.md`. This section records only what remains
divergent from the project's intent.

- **No per-tick frame emission under retained reuse.** *Gap.* When retained
  reuse is active (the full profile and the partial lean-profile option),
  reuse gates coalesce surface publications, so task-driven ticks that change
  the raster surface do not always produce a frame — in Chromium 0.1.9, Life
  emitted approximately one wire frame for four generations. The default lean
  profile masks this fault because it disables retained reuse. This fault
  must close before the full profile or JSPI main-thread mode becomes the
  WASI default.
- **Bounded-stack resolve is a profile mechanism, not architecture.** *Gap.*
  The chunked driver is a stack-lean profile mechanism, not a fully iterative
  engine. Resolve and built-in layout (registered under "Runtime and
  pipeline internals") still recurse on the Swift call stack, so stack
  budgets remain a per-engine constraint rather than a non-issue.

## Images and compositing

PNG and JPEG images render as host presentation attachments, and
`SwiftTUIAnimatedImage` displays pre-composed frames by feeding PNG bytes
through the same image surface. `View.blendMode(_:)` works for terminal-cell
content such as text, fills, strokes, and borders; a still `Image(...)` with
an active blend mode is precomposed against the sampled backdrop in linear
sRGB with glyph-aware backdrops and presented through the existing attachment
path, while unblended images keep the fast native path.

- **No animated-image/GIF blending.** *Gap.*
  `AnimatedImage(...).blendMode(...)` still emits unblended frames; the
  precomposition path covers still images only.
- **No ordered-layer compositing or native-host replay.** *Gap.* Multiple
  overlapping blended images do not composite as ordered layers, and the
  precomposed variant is not replayed on native hosts outside the terminal
  image path.

## Where divergences are recorded

This article is the project's single divergence-and-gap register; it absorbed
the former `docs/VISION-GAP.md` gap register, and its *Gap* entries are the
only recorded future-facing statements in this repository — shortfalls, not
plans. The vision document states the divergence policy and the scope
decisions. Guide articles in this catalog carry the per-surface contracts:
<doc:AnyView> documents its own "Differences From SwiftUI" (state is keyed by
the erased payload type), <doc:Shapes> its "deliberately absent" list, and
<doc:State-Keying>, <doc:Dismissal-Is-Data>, <doc:Focus>, <doc:Collections>,
<doc:Geometry-And-Preferences>, and <doc:Pointer-And-Canvas> the rest.
Individual API documentation comments carry the divergences local to one
symbol, marked with headings such as "Terminal-faithful defaults".
