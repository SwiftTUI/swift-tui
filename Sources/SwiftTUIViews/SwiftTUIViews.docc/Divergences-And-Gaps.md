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

- ***Ratified***: a deliberate, recorded stance. The rationale is part of the
  entry, and the divergence is expected to persist.
- ***Provisional***: deliberate today, held loosely. The behavior is a
  considered default that should be revisited if it causes real friction.
- ***Gap***: `HEAD` delivers less than the API shape or the project vision
  implies. Gaps are recorded, not scheduled; nothing in this register is a
  roadmap or a promise.

Two scope notes. Under the subset policy, a bare absence is a scope decision,
not a divergence: absent APIs appear here only when the absence has a recorded
stance or breaks an idiom. And items the vision document declares out of scope
are omitted even when SwiftUI exposes a corresponding API.

## Omissions

- **No value-based `NavigationLink` yet.** *Provisional.* A push currently
  mutates the bound path (`NavigationStack(path:root:)` plus
  `navigationDestination(for:destination:)`), so navigation remains wholly
  data-driven. A value-only link control that appends to that path is a
  compatible additive direction; destination-building links are not part of
  the current surface.
- **No `@Environment(\.dismiss)` yet.** *Provisional.* The presenter currently
  owns a Boolean or optional-item binding, and dismissal clears that source
  value; `onDismiss:` observes the result. A scoped `DismissAction`-like
  environment verb that reports whether the presenter handled it is a
  compatible additive direction and would still leave app data authoritative.
  See <doc:Dismissal-Is-Data>.
- **No `View.tabItem(_:)`.** *Provisional.* Tabs are declared with the
  structured `Tab(_:detail:badge:value:content:)` form.
- **No heterogeneous `NavigationPath`.** *Provisional.* Only the homogeneous
  `Binding<[Route]>` path form ships.
- **No `NavigationSplitView`.** *Provisional.* Out of scope for the current
  navigation surface.
- **`Text(_:)` is permanently literal.** *Ratified.* A string is content, not
  a localization key. `Text(verbatim:)` is an explicit alias of `Text(_:)`,
  not a compatibility hedge for silently changing that initializer later.
  Any future localization, locale-aware formatting, or bidirectional-text API
  must use an explicit additive spelling. Those directions remain
  *Provisional*: there is currently no `LocalizedStringKey`, `Locale`, bundle
  lookup, or right-to-left mirroring.
- **No `Font` or Dynamic Type axis.** *Ratified.* The authoring layers are
  Foundation-free by policy and a terminal renders one host-owned monospace
  glyph grid, so neither abstraction has a value the framework could honor.
  The emphasis vocabulary that SwiftUI hangs off `Font` lives directly on
  `Text` here; see the controls section.

## App entry, scenes, and lifecycle

- **`App.main()` is asynchronous.** *Ratified.* `SwiftUI.App.main()` is
  synchronous and a top-level `MyApp.main()` call works there. SwiftTUI's
  `App` refines `AsyncParsableCommand`, so only `@main` binds the asynchronous
  entry point. A bare `MyApp.main()`, muscle memory from SwiftUI, would
  resolve to the synchronous `ParsableCommand.main()` overload from
  swift-argument-parser and never start the runtime, so SwiftTUI ships a
  trapping shim that rejects the call with a precise diagnostic in both DEBUG
  and release builds.
- **An `App` is also a CLI command.** *Ratified.* The batteries-included `App`
  conforms to `SwiftTUICommand`, and apps opt into the standard option surface
  (`--accessible`, `--no-color`, `--ascii`, `--reduce-motion`, `--json`,
  `--debug`, `--web`, ...) with
  `@OptionGroup var swiftTUIOptions: SwiftTUIOptions`. SwiftUI's `App` has no
  argument-parsing surface. The command-enabled `App` is the
  batteries-included overlay over `SwiftTUIRuntime.App`, which remains
  available for host-managed declarations without the command surface.
- **One active root scene.** *Ratified.* The runtime drives a single
  full-canvas `WindowGroup` per session rather than SwiftUI's multi-window,
  multi-scene model. Host-specific integration allowing multi-scene
  orchestration lives in sibling products, not in the core runtime.
- **No `ScenePhase`.** *Gap.* There is no app-lifecycle environment signal.
- **`Scene` has no modifier surface.** *Ratified.* Not even scene-level
  `environment(_:_:)` exists; ambient values are injected inside the scene's
  `content`. A scene-modifier surface stays additive if a real need appears.
- **`WindowGroup` carries an identifier and exit-key extensions.** *Ratified.*
  `init(id:content:)` defaults the identifier, and `id` stays public because
  it satisfies `Identifiable` for the scene machinery; other storage is not
  public API. The exit-key-binding surface is a terminal-native extension
  with no SwiftUI analog.

## Data flow and observation

- **Observation-only data flow.** *Ratified.* The state surface is `State`,
  `Binding`, `Bindable`, `Environment`, and `FocusState`. The Combine-era
  object family (`ObservableObject`, `@Published`, `@StateObject`,
  `@ObservedObject`, `@EnvironmentObject`) does not exist. Models are
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
- **Equal-value `State` writes are inert.** *Provisional.* Writing a value
  equal to the current one does not invalidate the owner. A
  `Binding.animation(_:)` write of an unchanged value consequently animates
  nothing: the write short-circuits before the transaction is read, which
  matches SwiftUI's observable behavior.
- **`DynamicProperty` uses a narrower, reference-backed update contract.**
  *Ratified.* SwiftUI mutates a temporary working value, so a plain stored
  mutation is visible for one evaluation. SwiftTUI instead requires the
  nonmutating `update(in:) -> DynamicPropertyUpdateResult`: evaluation-visible
  custom state lives in reference storage or composed built-ins, and a plain
  `mutating update()` fails to conform rather than being silently discarded.
  The result explicitly certifies or denies retained and memoized reuse.
  `DynamicPropertyContext.invalidationLease` supplies a lifetime-scoped route
  for asynchronous storage; departed callbacks are inert. See
  <doc:Custom-Dynamic-Properties>.
- **State ownership is bound at capture, with an identity-refresh tier.**
  *Ratified.* Closures created during body evaluation carry their `@State`
  owner — SwiftTUI's analog of SwiftUI's `_location` injection, adapted to
  value-semantic checkpointable slots. A closure fired after its owner node
  was re-minted under the same resolve identity (list reshape, unmount/
  remount) re-addresses dispatch through a fire-time identity refresh and
  observes the live occupant's state; a closure that outlives its state's
  committed removal reads the authored seed *loudly* (a runtime issue plus
  the `state-seed-fallback` soundness violation) where SwiftUI's dead
  `_location` reads are silent. There is no ambient dispatch-context
  guessing: SwiftTUI never resolves a closure's state against whichever
  owner happens to be ambient at fire time.
- **Dynamic-property discovery sees stored properties only.** *Ratified.*
  Discovery reflects stored properties (as SwiftUI does); computed
  properties never participate in the update pass. Wrappers composed inside
  types that do **not** conform to `DynamicProperty` keep the legacy
  declaration-site slot identity: two instances of such a helper in one
  view silently share storage, now surfaced by the
  `state.duplicateSlotClaim` runtime issue. Conforming wrappers get
  path-qualified per-instance storage, and composition no longer requires
  forwarding the `line:`/`column:` init defaults the way `Namespace`'s
  shipped workaround does.
- **Generic bounds carry strict-concurrency narrowings.** *Ratified, as a
  class.* Where SwiftUI's signature has a looser generic, SwiftTUI may add
  `Sendable` or a comparison bound (`ForEach` IDs are `Hashable & Sendable`,
  `.animation(_:value:)` requires `Equatable & Sendable`, `alignmentGuide`
  closures are `@Sendable`) because view inputs cross the off-main frame
  tail under strict, unsuppressed concurrency. Recorded once for the whole
  class; individual members do not get separate entries. The keyframe
  family is in this class: `KeyframeAnimator` requires `Value: Sendable`
  and its `content`/`keyframes` closures are `@MainActor`, the scoped
  `View.animation(_:body:)`/`View.transaction(_:body:)` closures are
  `@MainActor`, `Transaction.addAnimationCompletion` closures are
  `@MainActor @Sendable`, and `KeyframeTrack` names its property generic
  parameter `TrackValue` because the `Keyframes` conformance binds `Value` to
  the root type.
- **`ForEach` over a collection binding writes back by identity; `Binding`
  collection conformances stay positional.** *Ratified.*
  `ForEach(_:content:)` and `ForEach(_:id:content:)` accept a `Binding` to a
  mutable collection and hand each row a `Binding` to its element. Row
  bindings verify identity on every access: after a reorder a write
  relocates by ID (occurrence-aware for duplicate IDs), and a write whose
  element has left the collection is dropped with a
  `forEach.staleElementBindingWrite` runtime issue, where SwiftUI writes
  through the captured index and can corrupt a neighbor or trap. A read of a
  departed element traps with a diagnostic, matching the optional-base
  unwrap precedent. Swift drops the contextual isolation from
  property-wrapper closure parameters, so SwiftUI's bare `{ $item in ... }`
  spelling does not compile against the isolated builder closure: the plain
  parameter is already the element binding (member access projects field
  bindings), and `{ @MainActor $item in ... }` restores the destructuring
  spelling, recorded under the strict-concurrency narrowing class. The
  `editActions:` forms are out of scope for the core package: a default
  platform edit behavior is a high-opinion surface that belongs to optional
  extension packages, because no one owns what a TUI "should feel like" the
  way a desktop platform vendor owns its idiom. `Binding` also conforms to
  `Sequence`/`Collection`/`BidirectionalCollection`/`RandomAccessCollection`
  where `Value` permits, as in SwiftUI, with two recorded differences: the
  conformances are `@MainActor`-isolated (`wrappedValue` is main-actor-gated
  here; the strict-concurrency narrowing class), and the positional
  subscript's element bindings are index-denominated with SwiftUI's exact
  retained-binding semantics, making the ID-verified `ForEach` rows the
  identity-safe tier of a deliberate two-tier story.

## Geometry and units

- **Two named coordinate domains instead of `CGFloat` geometry.** *Ratified.*
  `CellPoint`/`CellSize`/`CellRect` are the integer terminal grid (layout,
  semantic bounds, raster); `Point`/`Size`/`Rect`/`Vector` are continuous cell
  space (gestures, hover, `Canvas`, interpolation); `Pixel*` types carry host
  device-pixel provenance. `frame(width:height:)` takes `Int`, and
  `Shape.path(in:)` receives a `Rect`, not a `CGRect`.
- **`ScrollView(position:)` binds a raw cell offset, `ScrollCellOffset`.**
  *Ratified.* The offset type was renamed from `ScrollPosition` in the
  pre-launch sweep so SwiftUI's name (an identity/edge/anchor abstraction
  applied with `scrollPosition(_:)`) is no longer claimed by different
  semantics. The `ScrollView(position:)` initializer itself has no SwiftUI
  counterpart.
- **No `scrollPosition(_:)` identity abstraction.** *Gap.* SwiftUI's
  `ScrollPosition` model (scroll to identity, edge, or anchor through a
  bindable abstraction) is unimplemented; the name is now unclaimed and
  available to a faithful implementation.
- **`ScrollViewProxy.scrollTo` returns `Bool` and adds offset forms;
  `ScrollViewReader` evaluates `content` once.** *Ratified.* The `Bool`
  reports whether a scroll target resolved: the fail-loud preference applied
  to imperative scrolling. Cell-offset `scrollTo` overloads have no SwiftUI
  analog, and the reader's non-escaping content closure is evaluated once
  rather than kept re-callable.
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
  *Ratified.* The renderer can evaluate custom layouts on the off-main
  frame-tail worker.
- **`Layout` caches persist across passes.** *Ratified.* SwiftUI persists
  `Cache` values across passes through `updateCache`; SwiftTUI now matches:
  the cache bridges measurement and placement within a pass, and the
  placement-final value persists per container identity and proposal (four
  variants, least-recently-used) when the frame commits — abandoned frame
  candidates never write. A persisted cache still passes through
  `updateCache` (so the re-making default implementation observes no reuse),
  is equivalence-checked against the node it was built for, is denied when
  anything at or below the container invalidated, and is verified in debug
  builds against a fresh `makeCache` pass
  (`layout.persistedCacheDivergence`). `SWIFTTUI_PERSISTENT_LAYOUT_CACHE=0`
  restores per-pass scratch wholesale.
- **Engine re-entry nesting has a depth budget.** *Ratified.* A nested
  custom layout or hosted-collection (`List`/`Table`) windowing container
  re-enters the engine on the native call stack when measured, so nesting is
  budgeted rather than unbounded: trees nested past the frame-tail worker's
  offload budget of two levels run the frame tail on the main actor, whose
  truncation boundary affords 24 levels; direct engine callers and WASI keep
  the conservative four-level truncation limit (one small stack, no offload
  worker).
  Nesting past the active budget truncates with a
  `layout.customLayoutDepthLimitExceeded` runtime issue. Built-in layout is
  fully iterative (see runtime internals); this boundary is the completed
  architecture for author-code re-entry, which is synchronous by API shape
  and cannot be scheduled onto a heap work stack.
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
- **`padding()` is one cell.** *Ratified.* SwiftUI's unlabeled default is
  platform-adaptive; the cell is the terminal's natural quantum, and the
  literal default keeps padded layouts predictable.
- **`border` defaults to inset placement and does not affect layout.**
  *Ratified (parity).* The default occupies the content's existing outermost
  cells, aligning with SwiftUI's non-layout-affecting overlay behavior — but
  where SwiftUI strokes at sub-cell resolution and never occludes, a cell
  grid makes "inside the bounds" necessarily mean *replacing* the outermost
  content cells: a border on content with no padding overwrites its first
  and last rows and columns, and small content can disappear entirely with
  no diagnostic. Pad the content, size the frame for the border, or use
  explicit `placement: .outset`, which reserves terminal cells around the
  content and grows the frame.
- **`ignoresSafeArea` takes the edge set positionally.** *Ratified.*
  SwiftUI's first positional is `SafeAreaRegions`; terminal safe areas have a
  single region, so the positional parameter is the edge set. The labeled
  `edges:` spelling also compiles.
- **`safeAreaInset` is a single `Edge`-typed overload with `spacing: Int`.**
  *Ratified.* SwiftUI's two axis-typed overloads collapse into one; spacing
  is whole cells and defaults to `0`.
- **`Spacer(minLength:)` is a non-optional `Int` defaulting to `0`.**
  *Ratified.* SwiftUI's `CGFloat?` `nil` means "system default spacing",
  which has no terminal value; `Spacer()` reserves nothing until siblings
  leave room.

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
  extracted into labeled option values. An unmodified tagged `Text` value is
  represented losslessly. Arbitrary structure and unsupported modifiers keep
  their extracted text and tag routing, but emit one deduplicated
  `picker.unrepresentableOptionContent` runtime issue naming the option
  identity instead of degrading silently. Terminal option rows are
  single-line text by construction, and structured option metadata keeps every
  picker style deterministic, the same trade recorded for tab labels. A
  metadata-only authoring shape for non-Text content remains an additive gap.
- **`TabView` resolves only the selected body.** *Ratified.* Resolving only
  the visible tab keeps resolve and commit cost proportional to the visible
  surface, which matters more on a terminal than in SwiftUI's retained scene
  graph. Consequence: value-typed `@State` in a deselected tab is archived
  and restored on reselection (see <doc:Dormant-Tab-State>); reference-backed
  state, running tasks, and captured closures are torn down — unsupported
  values report `tab.dormantStateUnsupportedValue` — so hoist those above the
  tab seam. The remaining gap is preserving reference-backed state across
  deselection without eager resolution.
- **`listRowBackground` takes a non-optional `ShapeStyle`.** *Ratified.*
  SwiftUI takes a `View?` and accepts `nil`. Terminal row backgrounds are
  cell paints, not arbitrary views; clearing is expressed by not applying the
  modifier, and widening to an optional stays additive.
- **List rows and table cells default to one line; authored limits are
  honored.** *Ratified.* The single-line default is terminal-native: it is
  load-bearing for the windowed visible-layout math. What no longer happens
  is destruction or clobbering of authored values: an authored or ambient
  `lineLimit`/`truncationMode` reaches hosted rows and cells (rows grow to
  their measured height, and the payload boundary carries the attributes for
  flattened text). Flattened section chrome (headers/footers) honors the
  truncation mode but renders one line; an authored limit above one there
  reports a `collection.unsupportedSectionChromeLineLimit` runtime issue and
  clamps. Variable-height *flattened* lines remain a *Gap*.

## Controls and text

- **`Slider` requires `in:`, and `Double` sliders are continuous by
  default.** *Ratified.* SwiftUI defaults the range to `0...1`; SwiftTUI
  requires it. `step:` defaults to `nil` on the `Double` forms (track drags
  snap to a fine span-derived quantum and arrow keys move about a tenth of
  the span, matching SwiftUI's continuous default for the most
  SwiftUI-shaped call) while the `Int` forms keep `step: 1`.
- **`scaledToFit()` / `scaledToFill()` are `Image`-only and imply
  `resizable()`.** *Ratified.* The `View`-level versions require an
  aspect-ratio layout pass that cell layout does not model. The `Image` forms
  set `isResizable` because a non-resizable scaled image has no terminal
  meaning. An image whose source cannot be resolved measures zero and
  reports an `image.unresolvedSource` runtime issue rather than failing
  silently.
- **Emphasis is `Text`-scoped, with SGR extensions; decorations propagate
  ambiently.** *Ratified.* `bold()` and `italic()` return `Text` (glyph
  attributes with no `View`-level variants), and the SGR set adds `faint()`
  and `blink()` with no SwiftUI analog. `underline()` and `strikethrough()`
  exist at both levels, matching SwiftUI: the `View` forms are environment
  writes that every descendant text run stamps where its own value styling
  is unset, and a directly-styled `Text`, including an explicit
  `.underline(false)` clear, wins over the inherited style (verified
  against macOS SwiftUI, 2026-08-05).
- **`lineLimit`/`truncationMode`/`textWrappingStrategy` are environment
  values with SwiftUI's replacement semantics.** *Ratified (parity).* The
  `View` modifiers write public `\.lineLimit`/`\.truncationMode` (and the
  SwiftTUI-only `\.textWrappingStrategy`): the innermost write wins,
  `lineLimit(nil)` clears an inherited limit, and the raw authored value
  rides the environment while text layout clamps non-positive limits to one
  line, each verified against macOS SwiftUI. Text-run leaves (`Text`,
  `Link`) stamp the effective values into node metadata at resolve time
  because the fused frame tail cannot read the environment. `TextEditor`
  opts its body out (its movement map wraps at the measured content width,
  and SwiftUI's `TextEditor` ignores an ancestor limit too);
  `TextFigure` ignores all three (preformatted banner output).
- **`Text.cellBackground(_:)` paints the text's own cells.** *Ratified.*
  Renamed from `backgroundStyle(_:)` in the pre-launch sweep: SwiftUI's
  `backgroundStyle(_:)` is an environment write with different semantics,
  and that name is no longer claimed. The paint travels with the fragment
  when interpolated into rich content.
- **`Text` is `Equatable` and `Sendable` but not `Hashable`.** *Gap.*
  SwiftUI's `Text` is all three; hashing awaits `Hashable` metadata
  payloads.
- **`Image(fileURLString:)` names its input honestly.** *Ratified.* The
  initializer takes a `file://` URL *string* (parsed, host form and
  percent-encoding included); the earlier `fileURL:` label promised a URL
  value while taking a `String`. Plain paths use `init(path:)`.

## Focus and commands

- **Focus traversal is geometry-aware and wraps.** *Ratified.* Focus starts at
  the top-most control nearest the leading edge; Tab moves forward in layout
  order and wraps back to the beginning. Traversal policy uses geometry, not
  only a linear order. Wrapping is the terminal-native reading: there is no
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
- **`onSubmit` takes no `of:` triggers; `submitLabel` is omitted.**
  *Ratified.* `onSubmit(_:)` runs when Return submits a focused `TextField`
  or `SecureField`; a `TextEditor` inserts a newline and never submits, and
  a modified Return (any modifier bits) never submits. Every enclosing
  `onSubmit` action runs, innermost first, and `submitScope(_:)` stops
  submissions from propagating further up, which is SwiftUI's documented
  composition. The `of: SubmitTriggers` parameter is not implemented
  because `.text` is the only trigger a terminal can have (there is no
  `searchable` surface); adding the labeled form later is additive.
  `submitLabel` is omitted because there is no software keyboard whose
  Return key could be relabeled; the modifier would be inert theater, the
  same reasoning recorded for `onKeyPress` phases. Without an enclosing
  `onSubmit`, Return keeps its default routing.
- **No `onMoveCommand` or `onExitCommand`.** *Gap.*
- **`onKeyPress` is reshaped end to end and is the canonical key API.**
  *Ratified.* The closure is labeled `perform:`, matching is a
  `KeyPressMatch` value with terminal-native statics such as `.arrowUp`, and
  there is no `phases:` parameter. A terminal byte stream delivers complete
  key events, with no down/up/repeat phases to observe and no physical
  keyboard state to match against, so SwiftUI's phase surface would be
  unimplementable theater. The name stays because the role matches: this is
  where key handling is authored.
- **`\.openLinkAction` stands where SwiftUI has `\.openURL`, and environment
  verbs return `Bool`.** *Ratified.* The rename marks the changed contract
  (`LinkDestination` values, terminal link delivery), and `Bool` returns,
  here and on `\.resetFocus`, report whether any handler consumed the verb:
  the fail-loud preference applied to environment actions. No `\.openURL`
  alias ships.
- **Toolbar items are value metadata, hoisted by preference.** *Ratified.*
  `toolbarItem(_:)` takes a `ToolbarItemConfig`; there is no `ToolbarItem`
  view or `@ToolbarContentBuilder`. This is the third instance of the
  structured-metadata stance recorded for `Tab(...)` and `Table` columns:
  value metadata gives deterministic terminal chrome without resolving label
  trees.

## Presentations

- **Alerts and confirmation dialogs queue first-in, first-out.** *Ratified.*
  Sheets, full-screen covers, popovers, and menus stack as independent
  surfaces; prompts queue, and only the oldest active prompt is visible.
  SwiftUI leaves concurrent-presentation behavior largely undefined. Escape
  dismisses the most recently activated *visible* presentation across
  families, so a queued prompt cannot intercept dismissal from a visible
  surface.
- **`fullScreenCover` has no chrome.** *Ratified.* It occupies the complete
  terminal proposal with no header, inset, border, or implicit close button:
  the vision document's restrained-chrome default applied to the modal
  family.
- **`onDismiss` is observation, not command.** *Ratified.* It runs once after
  a committed activation disappears: for state writes, Escape, built-in
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
  points). These are terminal-faithful defaults: any continuous cell
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
- **`GestureMask` applies at registration time.** *Ratified.* The exact
  ancestor-suppression scope chain participates in retained-reuse currency, so
  a live mask flip narrowly re-resolves and republishes gesture-bearing
  descendants as a from-scratch build would. Modifier levels stacked at the
  exact masking identity remain self gestures; strict descendant identities
  are subviews. The mask governs gesture recognizers, not hover handlers or
  control activation.
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
  true sub-cell positions. Use these for optional affordances; layout stays
  cell-based.

## Shapes and drawing

- **`Shape` conformance is dual.** *Ratified.* Conform with SwiftUI-style
  `path(in:)` *or* with an analytic `geometry` primitive; the two are
  bridged. The five analytic primitives carry exact, fixture-pinned cell
  output and cell-aspect correction that sampled paths cannot promise; see
  <doc:AspectCorrectShapes>.
- **No path/vector transform adapters yet.** *Provisional.*
  `trim(from:to:)`, `offset`, `rotation`, `scale`, and `transform` shape
  adapters are absent. SwiftTUI's continuous cell-space paths can support
  additive transforms before rasterization, with the result quantized at the
  cell boundary; they are an open direction, not part of the current API.
- **Strokes are one cell wide.** *Ratified.* There are no `lineWidth:` stroke
  overloads; authors select apparent weight through the glyph palette via
  `borderSet`.
- **No `addArc`, no general `clipShape(_:)`, no animatable path morphing.**
  *Gap.* `addArc` needs an angle type; clipping to an arbitrary path is
  unimplemented; parameterized shapes animate their parameters instead of
  morphing paths.
- **Custom shapes stretch; built-ins inscribe.** *Ratified.* A custom
  `path(in:)` shape fills its frame, while `Circle` stays round by inscribing
  the short axis; both are recorded as consequences of the cell grid, together with
  sub-cell quantization of custom paths versus bit-exact primitives.
- **`FillRule` defaults are coherent.** *Ratified.* Path rendering and
  `Path.contains` both default to non-zero winding. Authors can request
  `.evenOdd` explicitly for both rendering and hit testing.
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
  Keyframe tracks over `Int` step the same way; prefer `Double` tracks and
  round in the content closure.
- **Animation and keyframe durations are `Duration`.** *Ratified.*
  `Animation`, the keyframe family (`LinearKeyframe`, `CubicKeyframe`,
  `SpringKeyframe`, `KeyframeTimeline.duration`, `value(time:)`), `Spring`,
  and `Animation.logicallyComplete(after:)` take Swift `Duration` values
  where SwiftUI takes `TimeInterval` seconds.
- **Keyframe content does not animate implicitly, and reduce motion snaps a
  triggered keyframe animation to its end value and rests a repeating one at
  its initial value.** *Ratified.* `KeyframeAnimator` writes every sample
  under a `disablesAnimations` transaction, so an enclosing `withAnimation`
  scope or `.animation(_:value:)` never layers a curve on the keyframe-driven
  values; transitions inside keyframe content are suppressed as a
  consequence. A trigger change under reduce motion writes the end value at
  once; repeating mode starts no task.
- **`Transaction` residue: `isContinuous` not consumed and
  `TransactionKey.Value` narrowed.** *Ratified.* `Transaction` carries
  animation intent, `disablesAnimations`, `isContinuous`, `tracksVelocity`,
  custom `TransactionKey` values, and completions added with
  `addAnimationCompletion(criteria:_:)`. `AnimationCompletionCriteria.logicallyComplete`
  fires when every curve reaches its logical endpoint (or its
  `logicallyComplete(after:)` instant), while `.removed` waits for a
  retained removal overlay to leave the tree. For non-removal animation they
  coincide. `TransactionKey.Value` requires `Hashable & Sendable` where
  SwiftUI leaves the associated type unconstrained (the environment-`Sendable`
  narrowing precedent; values cross the off-main frame tail and participate
  in reuse comparisons). `isContinuous` is author-facing metadata: the
  framework neither sets nor consumes it, and a SwiftUI probe (2026-08-05)
  showed SwiftUI does not auto-set it on drag updates either. A completion
  added by a resolve-time `.transaction(_:)` transform has no scope to fire
  in and is ignored.
- **Retargeted built-in springs carry velocity (flag).** *Ratified.* A
  spring retargeted mid-flight continues with the outgoing curve's velocity
  instead of restarting at rest, and writes made under
  `Transaction.tracksVelocity` seed the next spring on the same value.
  `SWIFTTUI_ANIMATION_VELOCITY=0` restores the at-rest restart for one
  release.
- **Scoped `body:` forms govern node-owning and node-decorating modifiers.**
  *Gap (narrowed).* `View.animation(_:body:)` and `View.transaction(_:body:)`
  scope the transaction to modifiers that create a node (`offset`,
  `position`, `frame`, `padding`, `border`) or decorate the placeholder node
  (`opacity`, draw effects). A style that flows through the environment
  (`foregroundStyle`, `tint`) applied inside `body` lands on the wrapped
  content's own nodes and follows their transaction, where SwiftUI scopes it
  too.
- **Custom `Transition` bodies are not exposed.** *Ratified.* SwiftTUI ships
  the built-in `AnyTransition` opacity, move, offset, combined, and asymmetric
  effects. It does not accept an arbitrary view body and then silently discard
  unsupported modifiers. A built-in `.scale` transition remains a *Gap*.
- **Content transitions roll per digit column; `.interpolate` is not
  offered.** *Ratified.* `View.contentTransition(_:)` and
  `EnvironmentValues.contentTransition` carry a `ContentTransition` to every
  `Text` beneath them (`Label` and `Button` titles included). When a
  plain-string `Text` changes inside an animated transaction,
  `.numericText(countsDown:)` steps each changed ASCII-digit column through
  the intermediate digits toward its target over the curve and dims the
  column at the midpoint; `.numericText(value:)` takes the direction from the
  sign of the change; any other changed column cross-fades (same-width ASCII
  glyphs old-then-new, anything else fades the new glyph in); a length change
  lays out at the new width at once and the added columns fade in, the
  remaining columns paired right-aligned so the units column stays put.
  `.opacity` dims the whole old string out to the midpoint and the new string
  in. The roll is a draw-time substitution on the new string's layout — every
  drawn column is the new string's character or a same-width substitute — so
  it never re-wraps or re-measures, and a retarget mid-roll continues from the
  digit on screen. An unanimated write, reduce motion, `.identity`, and rich
  `Text` content cut. SwiftUI's `.interpolate` (font and colour interpolation)
  has no cell-grid reading and is not offered.
- **Matched size interpolates by bounds and clip, not re-layout; tag outside
  the chrome.** *Ratified.* `matchedGeometryEffect(id:in:properties:anchor:isSource:)`
  interpolates the rect in anchor space; a size change is applied at the
  placed level: the node's bounds take the interpolated size and clip to it
  (the content lays out once at its destination size, so text never
  re-wraps mid-animation), and descendants coextensive with the matched
  node's bounds (a `.background`, an overlay, full-frame chrome) resize with
  it. Because the modifier tags its content, chrome that should follow the
  box goes inside the modifier.
- **A matched-geometry swap plays the pair's transitions along the matched
  path; there is no default transition.** *Ratified* / *Gap*. The departing
  instance's exit overlay travels to the destination rect while its removal
  phase plays and the arriving instance's insertion phase plays from the
  source rect, so `.transition(.opacity)` on both cross-fades like SwiftUI's
  removal-positioned-onto-source behaviour. An offset transition composes
  additively with the matched translation. The remaining *Gap*: SwiftUI
  applies a default `.opacity` transition to any view whose presence changes
  inside an animated transaction; SwiftTUI plays only registered
  transitions, so an untransitioned swap (or conditional) cuts.
- **Co-present non-source instances are positioned onto their source.**
  *Ratified.* While a source and an `isSource: false` instance share a key
  on one screen, the non-source is laid out at its own slot and rendered at
  the source's frame per its own `properties` and `anchor` (`.position`
  tracks the source's anchor point at the non-source's size, `.size` takes
  the source's size around the non-source's anchor, `.frame` both), every
  frame, without an animation; it hit-tests and focuses where it is drawn
  and, as the later sibling, above the source. Adoption needs exactly one
  source per key in the placed tree — zero or several sources adopt
  nothing. It is a placed-level override: the retained layout baseline
  stays un-adopted, reduce motion leaves it on, an unrelated animated write
  plans no match on a co-present non-source, a source that is itself
  mid-flight is followed at its drawn rect, and a departing adoptee's exit
  overlay starts where it was drawn. A non-source that is the *sole* holder
  of its key keeps SwiftUI's rule: it receives the match when the key swaps
  to it and supplies no geometry when it leaves.
- **Nested matched nodes keep the first-hit rule.** *Gap (narrowed).* A
  placed-level offset stops at the first identity it translates, so a matched
  node inside an adopted (or matched-animating) ancestor rides the ancestor's
  move and its own adoption or match is dropped; a source nested inside an
  adopted subtree also records its baseline rect as the next swap's `from`.
  Lifting this means walking into translated subtrees with a composed delta.
- **Matched-geometry namespaces work without `@Namespace`.** *Provisional.*
  The wrapper exists with SwiftUI semantics, but
  `matchedGeometryEffect(id:in:)` also accepts `.default`, one global
  namespace, where SwiftUI requires a `Namespace.ID`.
- **Memoized body reuse compares view inputs implicitly, with a narrower
  reach than SwiftUI's.** *Gap (narrowed).* The memo gate compares any view
  value whose type has a comparison plan: `Equatable` conformance, a
  whole-value byte compare for packed POD types, or a per-field plan built
  once per type from runtime field metadata. Types the planner cannot prove
  comparable (stored closures such as `Button` actions and builder-closure
  storage, `AnyView`, opaque existentials, non-POD non-`Equatable` enums) still
  recompute conservatively, a ceiling SwiftUI shares for closures. The
  sampled memo shadow oracle validates every served tier; `.equatable()`
  remains the explicit opt-in for types with custom equality semantics.
- **Reduced motion changes rendering, not just timing.** *Ratified.* Under
  reduced motion, `Spinner` renders static text, `PhaseAnimator` renders only
  its first phase, and `AnimatedImage` renders its first frame. SwiftUI treats
  the flag as advisory.
  Terminal output is frequently captured, piped, and read by screen readers;
  `CI=true` and non-TTY stdout therefore select a distinct stable-output
  policy with those same deterministic built-in forms. They do not claim an
  accessibility preference or change `accessibilityReduceMotion` for app code.

## Styling and color

- **Semantic roles resolve through a host-owned theme.** *Ratified.* Views
  write semantic style roles (`.foreground`, `.warning`, `.tint`, ...) and
  the active host integration selects the theme that resolves them; `Theme`
  is not part of the `View` authoring surface. The inner TUI app does not
  select or inspect host style variants, and terminal capability affects
  presentation, not layout semantics.
- **Style families are open protocols.** *Ratified.* `ButtonStyle`,
  `TextFieldStyle`, `PickerStyle`, `ListStyle`, `TabViewStyle`, and peers are
  public, extensible protocols with `Any*Style` erasers, including families
  SwiftUI keeps closed.
- **Styling is not yet uniformly overridable; an environment-scoped style
  system across the full surface is the intended destination.** *Gap.* The
  open-protocol model above — a public style protocol, a public
  configuration carrying the authored subviews and the render state a style
  legitimately needs, an `Any*Style` eraser stored in the environment, a
  lower-camel-cased modifier scoping a style to one control, a subtree, or
  an application, and retained-reuse participation — is the framework's
  intended styling contract for every styleable surface, not only the
  families that have it today. The destination extends that contract to
  `Toggle`, `ProgressView`, `Label`, `Menu`, `Slider`, `Stepper`,
  `DisclosureGroup`, `GroupBox`, `ControlGroup`, `LabeledContent`,
  `TextEditor`, `ScrollView`, and `Link`, and to the
  alert/confirmation-dialog, sheet,
  full-screen-cover, popover, palette, and toolbar presentation surfaces —
  body-producing where composition is the customization,
  presentation-valued where the primitive must keep a runtime invariant,
  with built-in treatments implemented through the same public
  configuration and routing contract available to third-party styles. At
  `HEAD`, environment-scoped families exist for `Button`, `TextField`,
  `Picker`, `List`, `OutlineGroup`, `Table`, `Spinner`, `Sheet`, `Toolbar`,
  and `TabView`. Toast deliberately keeps its declaration-scoped style
  argument, and palette rendering stays internal until the public
  `PaletteStyle` family ships. The other listed surfaces retain hard-coded
  chrome with no independently replaceable style seam; completing them is
  additive Phase B work on the burndown to 1.0.0.
- **`Color` vocabulary differs.** *Gap.* Initializers use `alpha:` where
  SwiftUI uses `opacity:`, and mixing is `mixed(with:amount:method:)` rather
  than `mix(with:by:)`.
- **`.primary` and `.secondary` are semantic-role aliases; `Color.accentColor`
  is omitted.** *Ratified.* `.foregroundStyle(.primary)` and `.secondary`
  resolve through the host theme as aliases for the `foreground` and `muted`
  roles, matching SwiftUI's hierarchical-style spelling. They are shape
  styles, not `Color` statics: `Color` is a concrete value (animatable,
  codable, channel math), so a theme-deferred `Color.primary` cannot exist
  without breaking that contract. The accent story is the existing `.tint`
  role; the `Color.accentColor` spelling is not claimed.
- **`background(_ style:)` fills the view bounds only.** *Ratified.* There is
  no `ignoresSafeAreaEdges:` parameter and the fill does not bleed into safe
  areas, the restrained-chrome default; painting beyond bounds is expressed
  with explicit containers.
- **No `ColorScheme` axis.** *Ratified.* Views can read `colorSchemeContrast`
  and the raw `TerminalAppearance`, but there is no light/dark `ColorScheme`
  type. A terminal reports foreground/background colors, not a scheme; the
  appearance surface exposes what the host actually knows, and semantic roles
  absorb the light/dark decision in the theme.
- **`.opacity` cascades multiplicatively at draw extraction.** *Ratified
  (parity).* The effective opacity of every emitted draw command is the
  product of the `.opacity` factors on its ancestor chain including the
  node's own: `container.opacity(0.3)` fades the whole subtree, nested
  fades multiply, and an explicit `.opacity(1)` reset is impossible,
  matching SwiftUI. Same-node modifier chains compound through the metadata
  merge. Retained draw reuse verifies the inherited factor before serving a
  cached subtree, and animated fades write the overlay root only (the
  cascade reaches descendants at extraction). A `Canvas` fades its default
  foreground but not colors the drawing resolves internally, a residual
  *Gap* shared with the image path below.

## Surface extensions with no SwiftUI analog

These are ratified additions rather than changed semantics; they are listed so
the register is complete. Terminal-program embedding (`TerminalView`) and the
continuous-coordinate system are recorded as deliberate terminal-native
capabilities in the vision document. The others follow the same stance:

- `EnvironmentReader`, for reading environment values and actions inline.
- `TextFigure`, FIGlet banner text with embedded fonts.
- `PointerInputCapabilities`, `CellPixelMetrics`, and `PointerLocation` input
  metadata via `GeometryProxy`, recorded as metadata that must not change
  the base layout contract.
- `EnvironmentValues.requestTermination` and
  `EnvironmentValues.terminalHandoff`, recorded as runtime-injected verbs
  that expose host-owned actions without putting host mechanics in views.
- Per-side border styling (`BorderEdgeStyle`) and animatable perimeter
  gradients (`BorderBlend`).
- `ProgressView(value:total:barWidth:)`, a terminal-cell width control on an
  otherwise SwiftUI-shaped control.
- The deliberately public environment members `\.isFocused` (with a setter,
  for host integrations), `\.safeAreaInsets`, `\.terminalSize`,
  `\.controlProminence`, and `\.clipboardWriteAction`: host- and
  terminal-facing values SwiftUI keeps private or does not have.
- The `SwiftTUIProfiling` product and the host-contract surface
  (`SceneManifest`, `HostedSceneSession`, and peers).

## Accessibility

The semantic substrate, terminal cursor-follows-focus mode, Web/WASI ARIA tree,
SwiftUI-host overlay, and Android Compose semantics overlay all ship. They
present roles, labels, hints, live regions, and runtime-originated focus. The
shared node model does not yet carry assistive-technology activation,
adjustment, value/state, or focus-return routes. (The former linear accessible
*output mode* was removed as unusable; its renderer survives only as the
`SwiftTUITestSupport` assistive-output assertion seam.)

- **Assistive-technology interaction is one-way.** *Gap.* Focus flows runtime
  → VoiceOver/TalkBack/browser only. Assistive-technology-originated focus
  traversal is not fed back into SwiftTUI's runtime focus, and semantic nodes
  carry no activation, adjustment, or control-value route.
- **No WCAG conformance suite or automated screen-reader testing.** *Gap.*
  Unit tests and guardrail scripts cover semantic presentation. The
  coordination-root report
  `2026-08-13-006-preview-semantic-presentation-checklist.md` adds a WCAG
  2.2-referenced checklist, explicitly not a conformance claim; its
  candidate-pin browser, VoiceOver, TalkBack, and terminal observations remain
  pending.

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
- **Android runtime acceptance is not closed.** *Gap.* A connected arm64
  emulator/device instrumentation journey exists for the public Compose,
  JNI, and NDK host. The current candidate has not passed its state-changing
  repaint, tab-retention, and device-alpha acceptance, and connected runtime
  smoke is not a stable CI gate. `AndroidGallery` assembly and the NDK-free
  Kotlin JVM tests do not close that acceptance.
- **No `x86_64` Android packaging.** *Gap.* The framework, including the
  vendored `swift-png`/`JPEG` image path, cross-compiles for
  `x86_64-unknown-linux-android28` (the earlier `swift-png` SIMD build
  blocker was replaced by a scalar reimplementation), but `arm64-v8a` is the
  only ABI the `AndroidGallery` example currently packages.

## Terminal-program embedding

`TerminalView` and `TerminalProcessSession` over a pty ship on macOS and
Linux. The tabbed/split-pane workspace layer lives in the `terminal-workspace`
example app in `swift-tui-examples`.

- **No Sixel/Kitty graphics inside embedded panes.** *Gap.*
- **No Kitty keyboard protocol or OSC 99 notification namespacing.** *Gap.*
- **No pane-local selection/copy/scrollback mode.** *Gap.*
- **No process reattachment.** *Gap.* Reconnecting to a still-running child
  process after the host app restarts, and a daemon-backed session
  lifecycle, are not implemented.
- **No iOS or WASI builds of the embedding products.** *Gap.*

## Runtime and pipeline internals

The seven-phase pipeline, off-main frame-tail execution, and explicit
work-stack measurement and placement are complete.

- **Built-in layout is iterative; engine re-entry is a bounded compatibility
  boundary.** *Ratified.* Measurement and placement drive every built-in
  behavior through explicit heap work stacks
  (`LayoutEngine+MeasurementWorkStack.swift`,
  `LayoutEngine+PlacementWorkStack.swift`, enforced by
  `Scripts/check_layout_work_stack_guardrails.sh`), and the frame-tail
  worker's enlarged stack no longer exists: the worker is a stock dispatch
  queue. Native call-stack recursion survives only where author code
  re-enters the engine synchronously, at the custom-layout compatibility
  boundary (every `Layout` conformer, including `ScrollView`) and in
  hosted-collection (`List`/`Table`) windowed row measurement. Both share
  the depth budget recorded in the layout section, and the resolve-time
  `maxEngineReentryNestingDepth` aggregate routes deeper trees off the
  small-stack worker to the main-actor tail.
- **`ViewGraph` decomposition shipped; the residue is deliberate.**
  *Ratified.* `ViewGraph`'s stored state is grouped into nine value field
  groups with lifted operator types (`GraphCheckpointStore`,
  `GraphNodeIndexQuery`, the invalidation, dirty-evaluation, and lifecycle
  planners); the remaining mutation-heavy clusters stay extensions by
  assessment, because their private-state coupling makes stateless
  extraction net-negative. Dependency-aware body re-evaluation is the
  profile-gated memo layer (`memoizedReusableSnapshot` dispatching
  `MemoComparisonPlan` tiers, disabled under the stack-lean profile) plus
  reader-scoped environment toleration; its recorded residual is that
  state-slot and observable reads disqualify a node rather than comparing
  read values. Resolve threads an explicit `ResolveContext`, crossing into
  the graph layer through the typed `ReuseDecisionInputs` seam; the
  surviving ambient holders (view-node context, authoring context,
  environment storage, animation intent) are a measured design point priced
  by the stack-lean profile. Identity currency interns components
  (`IdentityComponent.interned`) and every `Identity` carries a mint-time
  cached hash with O(1) inequality; whole-value interning is declined
  because the identity key space is unbounded, so a global intern table
  would leak.
- **The retained frame index patches shape-stable frames and rebuilds on
  structural change.** *Ratified.* Frames whose trees keep the previous
  frame's shape (the dominant value-only class: state flips, animation
  ticks) derive the next index incrementally: structural tables carry over
  wholesale, paired walks prune wherever a subtree compares equal, and only
  changed nodes' entries are rewritten. Structural changes rebuild by
  design: `StructuralNodeKey`s are minted in per-frame walk order, so a
  shape change renumbers the key space and the rebuild is the patch.
  Duplicate runtime identities also force the rebuild arm, because
  positional pairing never routes through the identity-collapsing tables
  (the defect class of the reverted paired-walk proof). The debug
  byte-equivalence oracle now guards the live patch path: every patched
  frame is checked against a full rebuild in debug builds.

## WASI and browser execution

The `SwiftTUIWASI` runner, `web-surface` wire, and current WASI resolve
behavior are described by the per-host engine profiles in
`docs/HOSTS-AND-PLATFORMS.md`. This section records only what remains
divergent from the project's intent.

- **No per-tick frame emission under retained reuse.** *Gap.* When retained
  reuse is active (the full profile and the partial lean-profile option),
  reuse gates coalesce surface publications, so task-driven ticks that change
  the raster surface do not always produce a frame: in Chromium 0.1.9, Life
  emitted approximately one wire frame for four generations. The default lean
  profile masks this fault because it disables retained reuse. This fault
  must close before the full profile or JSPI main-thread mode becomes the
  WASI default.
- **Bounded-stack resolve is a profile mechanism, not architecture.** *Gap.*
  The chunked driver is a stack-lean profile mechanism, not a fully iterative
  engine. Resolve still recurses on the Swift call stack (built-in layout no
  longer does; see "Runtime and pipeline internals"), so stack budgets
  remain a per-engine constraint for resolve rather than a non-issue.

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
## Distribution

SwiftTUI ships as a SwiftPM source package: every consumer build resolves the
package and compiles the framework together with the app. SwiftUI ships as a
prebuilt platform framework that no app build ever compiles.

- **Consumers compile the framework in every build.** *Gap.* The build
  configuration applies to the framework as well as the app code, so the cost
  always lands somewhere: a release build optimizes SwiftTUI and is slow to
  compile, while a debug build compiles quickly and runs the unoptimized
  framework slowly. Developers arriving from SwiftUI have never had to choose
  between these, so the trade-off is a surprising first-run experience. A
  prebuilt SwiftTUI would remove it, but binary artifacts are inherently
  platform- and toolchain-specific (macOS, Linux, WASI, Android), so the
  shortfall is recorded here, not scheduled.

## Where divergences are recorded

This article is the project's single divergence-and-gap register; it absorbed
the former `docs/VISION-GAP.md` gap register, and its *Gap* entries are the
only recorded future-facing statements in this repository: shortfalls, not
plans. The vision document states the divergence policy and the scope
decisions. For a narrative orientation over this register (what transfers,
what to retrain, and what is missing, in reading order), see
<doc:Coming-From-SwiftUI>. Guide articles in this catalog carry the per-surface contracts:
<doc:AnyView> documents its own "Differences From SwiftUI" (state is keyed by
the erased payload type), <doc:Shapes> its "deliberately absent" list, and
<doc:State-Keying>, <doc:Dismissal-Is-Data>, <doc:Focus>, <doc:Collections>,
<doc:Geometry-And-Preferences>, and <doc:Pointer-And-Canvas> the rest.
Individual API documentation comments carry the divergences local to one
symbol, marked with headings such as "Terminal-faithful defaults".
