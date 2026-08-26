# Changelog

All notable changes to SwiftTUI are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

SwiftTUI is pre-1.0: while the public surface is being proven, minor releases
may make source-breaking API adjustments. Pin with `.upToNextMinor`.

## [Unreleased]

### Added

- **Co-present matched geometry.** An `isSource: false` instance that shares
  a key with a source on the same screen is now rendered at the source's
  frame every frame — per its own `properties:` and `anchor:`, without an
  animation — and hit-tests and focuses where it is drawn, the SwiftUI rule
  a non-source badge relies on. Adoption is a placed-level override: the
  retained layout baseline and the incremental raster path are untouched, a
  key with zero or several sources adopts nothing, and a departing adoptee's
  exit overlay starts where it was drawn. A sole non-source keeps receiving
  the match when its key swaps to it.
- `Scripts/purge_downstream_build_products.sh <module>` removes the SwiftPM
  products of every module downstream of `<module>` (the surgical form of
  `Scripts/test_all.sh --clean`), and the repo gate prints the command when
  a step crashes by signal after a `SwiftTUIPrimitives`/`SwiftTUIGraph`/
  `SwiftTUICore` source changed since the previous gate.

### Fixed

- **A co-present non-source no longer flies in from its source** on an
  unrelated animated write: the controller plans no matched animation for a
  non-source whose key has a source in the same frame.
- **`PhaseAnimator` replayed its trigger-mode cycle on every dormant-tab
  return.** The animator now records the trigger it last ran for instead of a
  seen-once flag, so an unchanged trigger does not replay when the tab is
  shown again while a trigger that changed while the tab was dormant runs
  one cycle on re-mount.
- **Animator content read the enclosing view's `@State` seed.**
  `KeyframeAnimator`, `PhaseAnimator`, and `TimelineView` evaluate their
  `content` closure under the authoring context that created it, so a
  `@State` owned by the enclosing view reads (and writes) through its own
  owner during a run.

### Changed

- Internal: the retained-products and incremental-raster gates key on
  transient overlay decoration (exit overlays, insertion and matched
  offsets) instead of on the overlay snapshot being empty.

## [0.9.10] - 2026-08-25

### Added

- **Keyframe animation.** `KeyframeAnimator` (trigger and repeating modes),
  the `View.keyframeAnimator(...)` and `View.phaseAnimator(...)` modifier
  forms over `PlaceholderContentView`, `KeyframeTimeline`, `KeyframeTrack`,
  `LinearKeyframe`/`CubicKeyframe`/`SpringKeyframe`/`MoveKeyframe`, the
  `Keyframes` and `KeyframeTrackContent` protocols with their builders, and
  the `UnitCurve` and `Spring` value types (also accepted by
  `Animation.timingCurve(_:duration:)` and `Animation.spring(_:)`). A
  retriggered animator restarts from its current value and carries velocity
  into a leading cubic or spring keyframe.
- **Transactions.** `Transaction(animation:)`, the key-path
  `withTransaction(_:_:_:)`, `View.transaction(value:_:)`, the scoped
  `View.animation(_:body:)` and `View.transaction(_:body:)` forms,
  `Transaction.addAnimationCompletion(criteria:_:)` (any number of
  completions per transaction, each at its own barrier),
  `Animation.logicallyComplete(after:)`, and `Transaction.tracksVelocity`.
- **Matched geometry.** `matchedGeometryEffect(id:in:properties:anchor:isSource:)`
  gains `properties:` (`MatchedGeometryProperties`) and `anchor:`. The new
  parameters have defaults, so `matchedGeometryEffect(id:in:isSource:)` call
  sites keep compiling; the symbol itself (and
  `MatchedGeometryConfig.init`) is renamed in the public API baseline.

### Changed

- **Matched-geometry swaps play the pair's `.transition`s.** A swap used to
  consume both instances' transitions: the departing instance was cut on the
  swap frame and the arriving one appeared at full opacity. The departing
  instance's exit overlay now travels to the destination rect while its
  removal phase plays, and the arriving instance's insertion phase plays from
  the source rect, so `.transition(.opacity)` on both cross-fades the pair
  along one path (SwiftUI parity). Swaps without a registered transition are
  unchanged.
- **Matched geometry interpolates size (default `properties: .frame`).** A
  matched pair whose slots differ in size previously snapped to the
  destination size; it now resizes by bounds and clip at the placed level,
  with coextensive decoration descendants following. Pass
  `properties: .position` for the earlier translation-only behavior.
- **Retargeted built-in springs carry velocity.** A spring retargeted
  mid-flight continues with its current velocity instead of restarting at
  rest. `SWIFTTUI_ANIMATION_VELOCITY=0` restores the at-rest restart for one
  release.
- **Overlapping `withAnimation` completions all fire.** Completion
  registrations are list-valued per batch with per-closure barriers; a
  second registration on the same batch no longer replaces the first.
- **Spring completion requires the velocity to settle too.** A spring no
  longer reports completion at a zero crossing it is still moving through
  (an underdamped bounce, or a spring released toward its target), so
  bouncy springs finish where they actually come to rest.
- **Stroke borders keep the background beneath them.** A `stroke` or
  `strokeBorder` with no explicit `background:` no longer infers each edge
  cell's background from the neighbouring cell outside the ring. The glyph
  carries no background of its own and composites over whatever the cell
  already holds. A ring drawn over an un-inset fill now shows that fill
  (inset the fill by the stroke width, as the built-in control chrome does,
  to leave the ring on the surrounding surface), and a ring on bare surface
  stays bare. Explicit `BorderBackgroundStyle`s are unchanged. With no
  cross-cell read left in the rasterizer,
  `Rasterizer.strokeSamplingDamageClosure` (0.9.9) is removed.

### Fixed

- A highlighted or filled neighbour no longer bleeds into a control's border.
  A selected list row directly above a `TextField`, or a focused `Toggle` row
  above one, painted its background across the field's top edge because the
  edge sampled the row above it; a later-painted control below a ring did the
  same to the bottom edge. Same mechanism as swift-tui#5, now removed rather
  than replayed.

- Exit-transition `.removed` completions fire on the controller's own turn. Once the overlay had faded out, every following deadline frame was elided, and an elided frame runs no placed pass, so the purge that releases `.removed` waited for the next outside input. The purge now runs at the head tick after the one-turn hold (`AnimationController.applyInterpolations`).

## [0.9.9] - 2026-08-24

### Fixed

- **DEBUG trap "incremental raster mismatch" under a stroked border ring**
  ([#5](https://github.com/SwiftTUI/swift-tui/issues/5)). A rectangle stroke
  with no explicit background (a `strokeBorder` overlay, a `.bordered` button,
  any `.border`) infers each edge cell's background from the neighbouring cell
  outside the ring. That read depends on paint order, and the incremental
  rasterizer replayed a ring whose edge row was dirty against a clean
  neighbour row holding the *previous* frame's final cells — so a border
  sitting directly above or below a later-painted control (a Button under a
  focus ring inside a sheet, in the report) repainted with a different
  background than a fresh raster and tripped the DEBUG oracle; release builds
  showed the stale cell instead. The rasterizer now closes the dirty set over
  the rows a repainting stroke edge samples, so both paths replay them in
  authored order.

## [0.9.8] - 2026-08-24

### Fixed

- **`Ctrl+C` reliably exits while a text input is focused.** A modified exit
  chord declined by the focused editor (nothing selected to copy) could fall
  through to a legacy key-event fallback that dropped the modifier, inserted
  a literal character, and swallowed the exit. The fallback path is gone: a
  modified press is either handled as the documented edit or exits.

### Performance

- **Resolve-path constants paid down.** Cached path hashes for the
  reconciliation layer's hottest keys (child identities now mint in constant
  time instead of re-hashing the whole path) and an allocation-free
  committed-value anchor walk with an equality early-out. Large-tree frames
  resolve 14-17% faster, retained-reuse frames up to 48% faster, with
  per-node cost flat across tree size.

### Changed

- **The default exit key is `Ctrl+C` (was `Ctrl+D`).** `ExitKeyBindings.default`
  now binds `Ctrl+C` alone; `Ctrl+D` no longer ends a session unless an app
  configures it with `WindowGroup.exitOnKey(.character("d"), modifiers: .ctrl)`.
  The terminal runs in raw mode, so `Ctrl+C` still arrives as a key press, not
  `SIGINT` — previously it was delivered to the app and, unhandled, did nothing,
  while `Ctrl+D` collided with half-page-down in pagers and delete-forward in
  line editors. Consumer `keyCommand`s and non-edit focused `onKeyPress`
  handlers keep precedence over the exit bindings, and `onTerminationRequest`
  can still cancel the exit. Under text-edit focus the rule is now: a
  *modified* exit chord reaches the focused editor first, but only as an edit —
  `Ctrl+C` copies a non-empty selection and the session continues, and with
  nothing selected it exits; a bare character configured as an exit key still
  exits before the editor can insert it. Correspondingly, a text input's
  `Ctrl+C` counts as handled only when there was a selection to copy (cut and
  paste still consume their chords unconditionally).

## [0.9.7] - 2026-08-22

### Fixed

- **A `@MainActor` app builds under the `ApproachableConcurrency` upcoming
  feature** (the Swift 6.4 `swift package init` default). `SwiftTUICommand`
  now restates `Decodable.init(from:)` as an explicitly `nonisolated`
  requirement, so a conformer's compiler-synthesized initializer -- and with
  it the type's `Decodable` conformance -- is inferred nonisolated instead of
  main-actor-isolated under `InferIsolatedConformances`. An isolated
  conformance cannot satisfy `ParsableArguments`' `Self: Decodable`, because
  that protocol refines `SendableMetatype`, so every `struct MyApp: App` used
  to fail with "main actor-isolated conformance of 'MyApp' to 'Decodable'
  cannot satisfy conformance requirement for a 'SendableMetatype' type
  parameter 'Self'". Apps need no change. A hand-written `init(from:)` on an
  `App` or `SwiftTUICommand` conformer must now be marked `nonisolated` (it is
  the initializer swift-argument-parser already calls from nonisolated code).
  `SwiftTUIArgumentsTests` now compiles with `ApproachableConcurrency`, so
  every command fixture exercises the consumer default. (swift-tui#6)
- **A selected `List` or `Table` row no longer loses focus across a snapshot
  rebuild.** `List` and `Table` stamp each row's role and selectability onto
  their own copy of the row at resolve time, and every row focus region is
  derived from that stamp; a frame served by `ViewNode.snapshotRebuilding`
  re-pulled each row's committed value without it, so the semantics pass
  emitted zero row focus regions, focus cleared, and the convergence render
  re-seated it on row 0 -- Down, an inert key, then Return activated row 0
  while the selection still showed the chosen row. The rebuild now carries
  the parent-authored stamp from the parent's committed slice onto the
  rebuilt child. (swift-tui#4)
- **`state.duplicateSlotClaim` no longer fires for a container whose update
  pass was reuse-served.** The dynamic-property update pass records a
  container's slot claims before the reuse door, and a reuse-served resolve
  never reached `beginEvaluation`'s per-evaluation reset — so the claim a
  served `ScrollView`, `TimelineView`, or popover-tip modifier left behind
  collided with its next evaluation's (legitimately new) box and reported
  phantom sharing. The claim window now opens at the update pass.
- **Dormant-tab archives accept SIMD vectors and Foundation value types.**
  `[SIMD2<Float>]` (its lanes reflect as a `Builtin.Vec…` leaf) and
  `Identifiable` rows keyed by `UUID` (an empty custom mirror) were rejected
  as non-value payloads, so `TabView` restarted that state on every return
  and reported `tab.dormantStateUnsupportedValue` on every departure. SIMD
  conformers are accepted as leaves and Foundation's value-type mirrors are
  trusted like the standard library's; Objective-C class wrappers are now
  rejected by metadata kind like every other class.
- **`TextEditor` no longer reports its measured-width scratch as
  unsupported dormant state.** The reference-typed carrier is declared
  transient for dormancy (framework-internal `@State` policy), so a
  departing tab neither archives nor warns about it.
- **A toolbar item that departs under a frontier-scoped frame is torn down
  and unpublished.** When the item set changes because the content changed
  (a `TabView` selection flip under a `.toolbar()` scope), the strip is
  rebuilt in the late-preference stage outside the dirty plan; the departed
  item's nodes stayed live, its action stayed in the live registry (the
  `registration-publication` residual `live=1 rebuilt=0`), and the presented
  strip lagged until some later root frame. The reconcile now schedules a
  follow-up frame rooted at the host so it re-applies through the normal
  plan.

### Changed

- **The memo-soundness alarm names the diverging node.** The
  `memo shadow oracle` detail now carries the node's identity path and view
  type instead of a bare field name.
- **The DEBUG incremental-raster mismatch trap names its evidence.** The
  `IncrementalRasterMismatch` assertion (and the `raster-damage` probe
  detail) now carries the damage rows the incremental path trusted and, for
  the first mismatched rows, the text each side produced -- or the columns
  whose cell styles differ, or which non-cell field diverged -- plus what the
  trap means and the `SWIFTTUI_SOUNDNESS_PROBE=0` opt-out. The journey from
  swift-tui#5 (a segmented row of `.bordered` Buttons changing selection) is
  pinned as a regression test that reaches the incremental rasterizer with
  zero oracle growth. (swift-tui#5)

## [0.9.6] - 2026-08-22

### Changed

- **`@State` ownership is now bound at capture time.** Closures created
  during body evaluation (actions, tasks, submit handlers, gesture
  closures) carry their state owner the way a `Binding` carries its
  accessors, instead of re-deriving ownership from the ambient dispatch
  context at fire time. A closure fired after a structural churn re-minted
  its owner's node (list reshape, unmount/remount) re-addresses through a
  fire-time identity refresh and observes the live occupant's state. This
  retires the silent-stale-`@State` corruption class for good: the
  registration-time ambient ladder (ancestor walk, sole-live-binding, and
  imperative mint tiers) is deleted, and an access nothing can serve reads
  the authored seed loudly — as a runtime issue and the new
  `state-seed-fallback` soundness violation — never another owner's slot
  silently. `SWIFTTUI_STATE_CAPTURE_BINDING=0` disables the bind pass as a
  diagnostic A/B lever. No public API changed.

## [0.9.5] - 2026-08-20

### Added

- **A modifier-less `.keyCommand` binding now says why it never fires.** The
  framework reserves bare keys for typing and built-in navigation and
  ignores such registrations (function keys excepted); that drop used to be
  silent. It now records a `keyCommand.modifierlessIgnored` runtime warning
  naming the command and the fix (add a modifier).

- **`state.duplicateSlotClaim` now names both claimants.** The warning
  reports each claiming wrapper (kind and value type), the node token, and
  the evaluation depth — enough to tell an app-side composed wrapper (fix:
  conform it to `DynamicProperty`) from two framework primitives routed
  through one node (a framework identity-aliasing defect to report).

### Fixed

- **Action closures no longer silently observe stale `@State`.** A handler
  registered with no ambient authoring context (`.onSubmit` and peers
  constructed outside a resolve pass) used to *clear* the dispatch context at
  fire time instead of preserving the caller's, so `@State` reads inside the
  closure silently fell back to the authored initial value — the field
  rendered the typed text while the submit closure read the seed. A nil
  registration snapshot now preserves the ambient dispatch context. Any
  imperative `@State` access that still bottoms out at the authored seed on
  a previously graph-bound box now records a `state.imperativeSeedFallback`
  runtime warning naming the declaration site, instead of failing silently.

- **`ScrollView(.vertical)` no longer forces its pane to the unwrapped text
  width.** In a horizontal layout (pane/sidebar shells), a stack measures
  each child's ideal with an unspecified cross dimension, so a vertical
  scroll view's text content measured unwrapped — and the scroll view then
  republished that unwrapped ideal as a hard structural *minimum*, making
  the pane rigid at the unwrapped width and painting it through the parent's
  border. The non-scrolling axis now reports the content's structural
  minimum instead (a `Text` keeps its zero horizontal minimum inside a
  vertical scroll view), so the pane compresses to the available width and
  the text wraps there. Plain vertical stacks were never affected.

- **The default `List` style no longer draws rows over its own border.** For
  box-drawing styles (`.automatic`/`.insetGrouped`), the top and bottom
  border rows were modeled as scrollable blank lines inside the row stream,
  so an overflowing list slid a real row onto the border row and the row
  erased the border's horizontal run (corner glyphs survived in the side
  columns). The vertical content insets are now layout-bearing — matching
  the horizontal axis, the `.wholeList` chrome scope, and what
  `measuredListIdealSize` already reserved — and the stroked box expands
  back into those reserved rows, with overflow indicators on their own
  lines inside the box. Scroll routing now publishes the inset content band
  for materialized (sectioned) lists too, so anchor arithmetic agrees with
  the drawn window. Behavior change: an overflowing boxed list shows the
  rows that actually fit inside its border (previously one row rendered
  under the border); non-overflowing lists are unchanged, and `.plain` is
  unaffected.

- **Runtime warnings no longer paint over the running app.** The terminal
  CLI's `RuntimeIssueSink.standardError` used to write straight to fd 2 —
  the same tty as the owned alternate screen — so each warning spliced into
  the frame it described (often inside the focused field, where
  `cursorFollowsFocus` parks the hardware cursor) and desynchronized the
  incremental-damage baseline until a full repaint. The sink is now
  screen-aware: while a terminal session owns the screen, issues append to
  `runtime-issues.log` in the active debug bundle (`SWIFTTUI_DEBUG_DIR` /
  `--debug`), or are held in a bounded buffer flushed to stderr after
  teardown restores the primary screen — including for sessions that end by
  throwing. Behavior without an owned screen is unchanged. One visible
  delta: `2>warnings.log` on an interactive session now captures the
  deferred issues at exit rather than live.

## [0.9.4] - 2026-08-18

### Changed

- **The published documentation is reorganized around app authors.** The
  combined DocC archive no longer publishes two plumbing modules whose types
  app code never names (`SwiftTUIPTYPrimitives`, `SwiftTUICLIAttach`); the
  intentional omissions are recorded in the archive manifest and mirrored in
  `.spi.yml`. The `SwiftTUI` umbrella catalog gains an All Guides index
  article that collects every developer guide by task, and its landing page
  curates it. The engine-layer landing pages (`SwiftTUIGraph`,
  `SwiftTUICore`, `SwiftTUIPrimitives`) now open by signposting that apps
  reach their vocabulary through re-export rather than direct imports. The
  Coming-From-SwiftUI and Runtime-Render-Pipeline articles cross-link their
  website counterparts. Reference documentation for every symbol that
  surfaces in app code is unchanged.

### Removed

- **The unimplemented verbosity surface is gone.** `--verbose`/`-v` and
  `--quiet` were advertised in every `SwiftTUICommand` app's `--help` (and
  `SWIFTTUI_VERBOSE`/`SWIFTTUI_QUIET` in the environment-variable reference)
  but never controlled any framework logging: the resolved
  `RuntimeConfiguration.verbosity` was only echoed into the debug-bundle
  manifest. The flags, the env vars, `RuntimeConfiguration.Verbosity`, the
  `verbosity` property/initializer parameter, and `Builder.verbosity(_:)`
  are removed rather than left as dead surface. Apps that want a verbosity
  flag can declare their own; the `--verbose`, `-v`, and `--quiet` names are
  no longer reserved by the framework.

## [0.9.3] - 2026-08-18

Chart fixture refresh only; no framework behaviour change.

### Fixed

- **swift-tui-charts' ascii preview fixtures track the 0.9.2 degradation
  map.** The 0.9.2 release candidate caught five stale `preview-ascii`
  fixtures in the charts repository: rendered against the pre-0.9.2 map,
  they still expected `?` where sparkline ramps, legend markers, heat
  strips, the calendar heatmap, and line-chart area fills now draw real
  ASCII. The fixtures are regenerated; framework code is unchanged from
  0.9.2.

## [0.9.2] - 2026-08-18

### Added

- **Windows is a supported terminal platform.** `import SwiftTUI` + `@main`
  builds and runs natively on Windows 10 1809+ (build 17763) / Windows
  Server 2019+ for `aarch64-` and `x86_64-unknown-windows-msvc`, with no
  platform conditional in app code. Terminal control drives the Win32 console
  directly: VT processing with the session owning the UTF-8 code pages (both
  console modes and both code pages restored on exit), input read as console
  records (`ReadConsoleInputW`) and re-linearized into the same VT byte
  stream the parser consumes on POSIX — which is what makes typed non-ASCII
  text reliable on every supported Windows version, where the console's
  byte-oriented read path is not — resize through the record pump, Ctrl+C
  in-band as `0x03`, and legacy-conhost mouse records translated to SGR so
  mouse works in both Windows Terminal and `conhost`. On Windows the
  `SwiftTUI` umbrella serves the terminal launch surface only: `--web`, PTY
  embedding, and `--attach` remain POSIX. About 5,400 tests run natively
  green, and a two-arch Windows CI lane (full build plus serial test lanes,
  warnings-as-errors) now guards the port.
- **Automatic stack-floor handling on Windows.** A default-linked Windows
  executable reserves 1 MiB of main-thread stack (POSIX mains get 8 MiB). At
  session start the runtime measures the reserve and arms the stack-lean
  resolve profile below the 8 MiB full-engine floor; a debug build that
  degrades emits a `windows.stack-floor-lean-profile` runtime issue naming
  the remedy (`swift build -Xlinker /STACK:16777216`). An explicit
  `SWIFTTUI_STACK_LEAN_PROFILE` value overrides the automatic choice.
- **Platform-aware terminal capability detection.** Detection now has
  per-platform arms. On Windows the platform is the signal — Unicode glyphs
  and 24-bit color by default, because the session controller owns VT
  processing and the UTF-8 code pages — while `NO_COLOR` still wins, an
  explicit foreign `TERM` reads like the POSIX arm, and `WT_SESSION` adds
  OSC 8 hyperlinks and synchronized output. POSIX detection is unchanged.
- **A total ASCII degradation map for box drawing.** Every glyph in the
  box-drawing (U+2500–U+257F) and block-elements (U+2580–U+259F) ranges plus
  `■` now has an ASCII fallback, on every platform — heavy half-stubs, tees,
  and crossings no longer degrade to `?` at the ascii glyph rung.

### Changed

- **The CLI layer is re-cut for portability; every existing import keeps
  working.** `SwiftTUICLI` split into the portable `SwiftTUITerminalCLI`
  (launch) and the POSIX-only `SwiftTUICLIAttach` (PTY + scene attach) over
  a new internal syscall facade, with `SwiftTUICLI` remaining as an
  `@_exported` compatibility facade. SwiftTerm is isolated behind the new
  `SwiftTUITerminalEmulation` target, and the PTY/SwiftTerm dependency edges
  are platform-conditional, so Windows builds never attempt them. Launch
  routing moved to `SwiftTUITerminalCLI.SwiftTUILauncher`;
  `WebHostCLIRunner` remains as a source-compatible facade (its formal
  deprecation is deferred to a later release).

### Fixed

- **A windowed-measurement worker crash under filtered parallel test runs
  (all platforms).** The retained lazy-stack snapshot could read a retained
  live source's measurement signature on the frame-tail worker; the guard
  now refuses retained-live-source reads off the main actor.
- **`Image(fileURLString:)` resolves drive-lettered file URLs on Windows.**
  The Foundation-free file-URL parser returned `/C:/…`-shaped paths, which
  the filesystem rejects; the Windows arm strips the leading slash.

## [0.9.1] - 2026-08-16

Android tooling fixes only; no framework behaviour change.

### Fixed

- **The `sh.swifttui.android` Gradle plugin no longer requires `swiftly` on
  `PATH`.** Both Swift tasks ran a bare `swiftly` command line, so an IDE
  launched from the desktop — which inherits the login daemon's `PATH`, not a
  shell profile's — failed with `Cannot run program "swiftly"` on machines
  where swiftly is installed and the same build succeeds from a terminal. The
  plugin now resolves an absolute launcher (`SWIFTLY_BIN_DIR`, then
  `~/.swiftly/bin`, then `PATH`) and reports the cause instead of surfacing the
  raw `IOException` when none is found. New `swiftTuiAndroidHost.swiftlyExecutable`
  names a launcher explicitly; it is never silently overridden by a discovered one.

- **The plugin no longer mirrors a swift-tui checkout it happened to find.**
  `swiftTuiCheckout` defaulted to the relative path `../../../swift-tui`, which
  resolves *outside* the consumer's project — so an unrelated clone sitting
  there silently replaced the tagged dependency the app's `Package.swift`
  declares. It is now opt-in through `SWIFTTUI_LOCAL_CHECKOUT`.

### Known issue

- The counter demo's `AndroidExample/SwiftPackage/Package.resolved` ships
  pinning `0.9.0`. The manifest requires `exact: "0.9.1"`, so SwiftPM
  re-resolves on first build; the tag was not moved to correct it.

## [0.9.0] - 2026-08-15

### Changed — source-breaking (0.9 preview readiness)

The preview-readiness closure deliberately narrows two extension points before
they become compatibility promises:

| Removed or changed | Replacement |
| --- | --- |
| `DynamicProperty.mutating update()` | `DynamicProperty.update(in:) -> DynamicPropertyUpdateResult`. The nonmutating contract supports reference-backed or composed graph storage, conservative reuse certification, and lifetime-scoped async invalidation. Plain value mutation now fails to conform instead of being silently discarded. |
| Public `Transition` / `TransitionContent` custom-transition authoring and `AnyTransition.init(_:)` | The implemented built-in `AnyTransition` palette: opacity, move, offset, combined, and asymmetric effects. |

### Changed — source-breaking (control-style Phase A)

Phase A of the control-style expansion empties the program's break inventory
(plan `2026-08-12-002`). Every removal below ships with its replacement in
the same release; there are no deprecated aliases or transitional overloads,
so each migration is a deterministic source edit.

| Removed | Replacement |
| --- | --- |
| `ListStyle`/`OutlineStyle` protocol shape (`resolvePresentation(for:)` entry point, new configurations, `Hashable` dropped); `CollectionStylePresentation`; `Table` reading `listStyle` | The `TableStyle` family (`tableStyle(_:)`, `TableStyleConfiguration`, `TableStylePresentation`, `AnyTableStyle`) plus rewritten list/outline built-ins; `ListStylePresentation` and `TableStylePresentation` replace the combined presentation |
| `ASCIIOutlineStyle`, `.outlineStyle(.ascii)`, `.asciiLineCompass` | None — glyph degradation is the rasterizer's fallback and was never a style-layer concern |
| `Spinner(set:stage:interval:)`, `Spinner(_:stage:interval:)`, public `Spinner.SpinnerSet` | `Spinner(stage:)` plus `spinnerStyle(_:)`; custom frames use `GlyphSpinnerStyle` |
| `.toolbar(style:)` | `.toolbar()` plus `toolbarStyle(_:)` on the toolbar host or any ancestor scope |
| `ToastStyle`'s entry point | Renamed to `@MainActor resolvePresentation(for:)`; the configuration additionally carries `styleEnvironment`, `terminalSize`, `stackIndex`, and `stackCount` |
| Public `PresentationChrome` and its case selection | The `SheetStyle` family (`.surface`, `.dropdown`) over a `defaultPresentation` baseline |
| `paletteSheet(_:isPresented:onDismiss:content:)` and public `ActivePaletteCommand` | Contentless `paletteSheet(_:isPresented:onDismiss:)` — the framework renders the palette (filter field, fuzzy-ranked rows, descriptions, disabled rows, empty-scope message). A public `PaletteStyle` for replacing that rendering is deliberately deferred; it is additive and arrives without a further break. |

### Fixed

- **`onChange` inside presented content no longer skips under the
  synchronous frame driver.** `onChange` is the only lifecycle family whose
  registration is conditional, so a convergence re-render that resets a
  node's recorded handlers without re-triggering left the committed change
  entry with nothing to dispatch. The retained handler store is the designed
  remedy and the asynchronous driver has always fed it; the synchronous
  driver — every synchronous test harness, and the Android host in `.sync`
  render mode — did not. Asynchronously-driven hosts were unaffected.

### Changed — behavior-breaking

- **Ambient propagation for `lineLimit`, `truncationMode`, `.opacity`,
  `underline`, and `strikethrough`.** The `View` modifiers stop being
  node-local no-ops on containers and adopt SwiftUI's ambient contract.
  `lineLimit(_:)`/`truncationMode(_:)`/`textWrappingStrategy(_:)` are now
  environment writes (public `\.lineLimit` and `\.truncationMode` readers
  included): `VStack { … }.lineLimit(1)` clamps every descendant text, the
  innermost write wins, and `.lineLimit(nil)` clears an inherited limit —
  previously a silent no-op. The raw authored value rides the environment;
  text layout clamps non-positive limits to one line (verified against
  macOS SwiftUI). `View.underline()`/`.strikethrough()` propagate the same
  way, with a directly-styled `Text` — including an explicit
  `.underline(false)` — winning over the inherited style. `TextEditor`
  ignores ambient text-layout attributes, matching SwiftUI. Layouts that
  relied on the container no-ops will change.
- **`.opacity` is a multiplicative draw cascade.** Every emitted draw
  command now carries the product of the `.opacity` factors on its ancestor
  chain including the node's own: `container.opacity(0.3)` fades the whole
  subtree, nested fades multiply (0.4 × 0.5 = 0.2), and the explicit-reset
  pattern (`.opacity(0.4)` … `.opacity(1)`) yields 0.4 instead of 1.0 —
  the same-node metadata merge multiplies instead of replacing. Shape
  fills, strokes, rules, borders, canvas foregrounds, list/table chrome, and
  still-image attachments now honor the factor too (a `.opacity` directly on
  a shape or image leaf was previously dropped). Image alpha is transported
  through terminal, browser/WASI, SwiftUI-host, and Android presentation;
  retained draw reuse verifies the inherited factor before serving a cached
  subtree, so an ancestor-only fade repaints descendants correctly.
- **List/Table rows honor authored text attributes.** Authored or ambient
  `lineLimit`/`truncationMode` now reach hosted rows and table cells
  (`Table`'s hosted cells default to single-line tail truncation instead of
  clobbering authored values), and the flattened payload boundary carries
  the attributes (`ListItemPayload`/`TableCellPayload` gain
  `lineLimit`/`truncationMode`). The default row limit remains 1. Flattened
  section chrome honors truncation but clamps limits above one with a
  `collection.unsupportedSectionChromeLineLimit` runtime issue.

### Removed

- **`View.erasedToAnyView`.** The convenience accessor duplicated
  `AnyView(_:)` while reading as an endorsement of stored erasure, which the
  AnyView policy discourages. Call `AnyView(myView)` directly where local
  branch unification genuinely needs it.
- **The `SwiftTUITerminalWorkspace` product.** The tabbed/split-pane workspace
  layer moved out of the framework and now lives in the
  [`terminal-workspace` example](https://github.com/SwiftTUI/swift-tui-examples/tree/main/terminal-workspace)
  in `swift-tui-examples`, built on the unchanged public `SwiftTUITerminal`
  surface. Apps that imported `SwiftTUITerminalWorkspace` can vendor that
  example's `TerminalWorkspace` target sources directly.

### Added

- **`Binding` projections and the optional-binding init family.**
  `Binding.animation(_:)` and `Binding.transaction(_:)` return bindings
  whose writes run inside a stored `Transaction`; the stored transaction is
  a public `transaction` property (SwiftUI's shape) and propagates through
  `dynamicMember` member projections. Precedence is verified against real
  SwiftUI: an explicit ambient scope (`withAnimation`/`withTransaction`)
  wins over the stored transaction; the stored transaction governs writes
  made outside any explicit scope — which is how every built-in control
  writes, so `Toggle(isOn: $flag.animation(.default))` animates with no
  per-control changes. New initializers: `init?(_:)` (optional unwrap; nil
  base fails construction, and a read after the base became nil traps with
  a diagnostic — SwiftUI traps there too), `init(_:)` (optional wrap; nil
  writes are ignored, matching SwiftUI), and `init(projectedValue:)`.
- **`Transaction.isContinuous`.** Author-facing continuity metadata:
  transforms installed with `.transaction(_:)` observe it on both the
  authored channel and `withTransaction`-scoped writes. The framework
  neither sets nor consumes it yet; it carries no animation intent, so a
  continuity-only transaction does not defeat frame elision or the
  controller's resolved-tree skip.
- **Custom `TransactionKey` values.** The `EnvironmentKey` shape for
  transactions: declare a key with a `defaultValue`, then read or write
  `transaction[MyKey.self]`. `Value` requires `Hashable & Sendable`
  (narrowed from SwiftUI's unconstrained associated type; recorded in the
  divergence register). Key values ride authored transforms and scoped
  writes, and participate in retained-reuse equivalence — a per-frame-
  varying key value destroys retained reuse below the writer, the same
  hazard class as an unequatable environment value.
- **`GestureState` reset transactions.** `init(wrappedValue:resetTransaction:)`,
  `init(initialValue:resetTransaction:)`, and the `reset:` closure variants
  (`(Value, inout Transaction) -> Void`, receiving the value being reset).
  The reset transaction governs the end-of-gesture seed reset exclusively —
  verified against SwiftUI: a transaction mutated in the `updating` body
  does not carry over to the reset, and without a reset transaction the
  reset snaps. Resolve-time resets (recognizer teardown, subtree removal)
  never animate.

- **`DynamicProperty` — a total custom-property-wrapper extension point.**
  `update(in:)` runs nested-first before the graph's sole retained-reuse door
  on every body and primitive evaluation surface. Its result certifies
  `unchanged`, reports `changed`, or defaults third-party storage to
  conservative `uncertified`; a transitive subtree bit carries that decision
  through retained reuse without walking the live graph. Built-in wrappers
  preserve the cheap certified path and path-qualified composed storage.
  `DynamicPropertyContext` supplies a graph/node/generation-scoped async
  invalidation lease whose callbacks become inert after supersession,
  rollback, wrapper departure, subtree removal, or graph retirement.

- **Dormant `TabView` state.** Deselecting a tab tears down its body, render
  tree, tasks, registrations, gestures, and observation edges while archiving
  only persistent graph-owned value slots. Reselecting the same stable tag
  within the same tab-owner lifetime restores state before body evaluation;
  inactive bodies remain unevaluated, and removed tags or owner replacement
  evict the archive. Persistent slots that contain a class, task/native object,
  closure/binding, unmanaged reference, or pointer are not retained across the
  dormant seam; the runtime emits `tab.dormantStateUnsupportedValue` with a
  remedy to use recursively value-only state or hoist ownership above the tab.

### Changed — preview behavior

- **Stable captured output is separate from accessibility reduce motion.**
  CI/non-TTY detection and the new stable-output option make built-in animated
  presentation deterministic without changing what app code reads from
  `accessibilityReduceMotion`. Only explicit user/host reduce-motion input sets
  the accessibility preference; built-in animation consults the combined
  rendering policy.

- **Picker degradation is fail-loud.** A tagged, unmodified `Text` remains the
  lossless option shape. Unsupported option structure or modifiers keep their
  extracted text and tag routing but emit one deduplicated
  `picker.unrepresentableOptionContent` runtime issue per option identity.

- **Live ancestor `GestureMask` changes refresh retained descendants.** The
  exact suppression scope now participates in reuse currency, so ordinary,
  high-priority, and simultaneous recognizer installation/removal matches a
  fresh resolve even when the descendant body is retained.

- **Animation completion criteria now have distinct barriers.**
  `.logicallyComplete` fires when every carrier reaches its final value;
  `.removed` waits until every exit overlay is drained. Both remain immediate
  for empty or disabled batches and fire exactly once.

- **Default fill and border behavior aligns with the preview contract.**
  `Path.contains` and implicit rendering use nonzero fill unless `.evenOdd` is
  explicit. Unlabeled/default `border` placement is inset and does not expand
  sibling allocation; `.outset` remains explicit.

### Fixed

- **`Gesture.updating(_:body:)`'s `inout Transaction` is honored.** The
  body's transaction was previously a discarded stand-in; mutations now
  govern the during-gesture `@GestureState` write (setting
  `transaction.animation` animates it). The transaction arrives inert on
  every update — no preset animation, `isContinuous` not auto-set —
  matching a SwiftUI probe (2026-08-05). The two doc warnings that
  promised the discard are removed.
- **The memo shadow-oracle's wrapper-storage classifier no longer drifts.**
  The diagnostic comparator now classifies property-wrapper storage by
  `DynamicProperty` conformance instead of a hard-coded five-name prefix
  list that omitted `Namespace`, `Bindable`, `FocusedValue`, and
  `FocusedBinding` — and would have omitted every custom wrapper.
  Diagnostic-only: production memo reuse is `Equatable`-gated and
  unaffected.

### Changed

- **Wheel scroll over a `List` or `Table` moves the viewport instead of
  stepping the selection.** Viewport-backed collections now own an explicit
  scroll anchor, and the visible window is derived from it; the selection
  *follows* the window rather than *being* it. This matches SwiftUI. A
  consequence worth knowing: a non-selectable indexed collection can now
  scroll at all, and `ScrollViewProxy.scrollTo(id:)` reaches collection rows,
  neither of which was previously possible.

- **`ScrollView { List }` and `ScrollView { Table }` no longer realize the
  whole dataset per frame.** Realization is viewport-bounded at every dataset
  size. A 10,000-row table's first frame went from ~68 s to ~360 ms in the
  measured A/B.

### Changed (source-breaking)

- **`List` and `Table` now require `SelectionValue: Hashable & Sendable`**,
  narrowed from `Hashable`. In practice this mostly *removes* constraints:
  four `DataCollections` initializers and the `OutlineViews` extension already
  demanded `Sendable` by hand, and the peer `Tab` already required it, so those
  hand-written clauses are gone. Code selecting by a non-`Sendable` value type
  must make that type `Sendable`.

  Note for anyone upgrading with a warm build directory: moving the constraint
  onto the type parameter changes the mangled names of the affected
  initializers, so a stale `.build` produces *link* errors rather than compile
  errors. Clear it.

## [0.4.4] - 2026-07-29

### Fixed

- Build-hygiene fixes only; no behaviour change. `0.4.3` did not pass its own
  native gate — four warnings-as-errors defects and one test-harness race —
  because every build check in that series filtered compiler warnings out. The
  `0.4.3` tag was deliberately **not** moved: a moved tag trips SwiftPM's
  fingerprint tamper check on every machine that already resolved it.

## [0.4.3] - 2026-07-29

### Changed

- **A WebHost scene no longer exits when the browser tab closes.** A client
  disconnect is now connection-local: scene input stays alive, the session ends
  only on server or scene shutdown, and a reconnecting client is assigned a
  greater connection token and re-enters capability negotiation. Late callbacks
  from a superseded connection are ignored rather than acted on.

- **Delta wire records carry their baseline generation.** Records emitted by an
  encoding state now carry additive `epoch` and `gen` keys, and a delta also
  carries `baselineGen`, so a consumer can *reject* a stale, reordered, or
  non-contiguous delta instead of silently applying it to the wrong baseline.
  A `resync` uplink lets any consumer request a keyframe or an image
  re-transmission. All keys are additive-optional; undeclared streams are
  unchanged byte for byte.

## [0.4.2] - 2026-07-29

### Fixed

- Wire-contract and host-consumer fixes continuing the delivery-coupling work
  begun in `0.4.1`. No authoring-surface API change.

## [0.4.1] - 2026-07-29

### Changed

- **`Standard` and `FileOpenError` now each have one public identity.**
  The duplicate `SwiftTUIRuntime.Standard` and
  `SwiftTUIRuntime.FileOpenError` identities have been removed during the
  pre-0.9 API-hardening window. Unqualified uses under `import SwiftTUIRuntime`
  or `import SwiftTUI` are unchanged; module-qualified references should use
  `SwiftTUIViews.Standard` and `SwiftTUIViews.FileOpenError`.

- **An unknown wire token degrades one record instead of the session.** Host
  wire token vocabularies are now open-world: a value a newer encoder
  introduces no longer bricks every subsequent frame on a deployed client.

### Fixed

- **`.simultaneousGesture` no longer swallows control activation on a
  stationary click.** Recognizer role survives the RunLoop dispatch seam
  instead of collapsing to a Bool, so a simultaneous gesture recognizes
  *alongside* the control it was declared not to interfere with.
  `Button { … }.simultaneousGesture(DragGesture().onEnded { … })` now activates
  the button. The armed and captured activation paths were also unified, so
  they cannot diverge again — previously a `TapGesture` suppressed its button
  even when the tap *failed* on an off-target release.

- **`myapp < /dev/null` exits instead of parking forever.** The
  terminal-input-ended exit is now reachable in production; previously the
  event pump's stream only finished when both the input and signal streams
  ended, and the signal stream never ended.

- **Dispatched `AsyncParsableCommand` verbs actually run.** All three
  verb-dispatch launch layers now perform the async downcast; previously such a
  verb silently printed help and exited 0.

- **A gesture composed through `body` keeps pointer capture.** User-composed
  gestures wrapping a drag no longer lose capture and stop receiving motion.

## [0.4.0] - 2026-07-28

### Changed

- Internal pipeline and teardown work with no authoring-surface API change.

## [0.3.8] - 2026-07-27

### Added

- **A `SwiftTUICommand` can claim its own subcommand verbs from raw arguments.**
  A root command that declares an `@Argument` shadows its own subcommands,
  because swift-argument-parser parses the current command's arguments before it
  looks for a verb — `myapp info x.gif` means "open the file named `info`".
  Implement the new `swiftTUIRootSubcommand(forRawArguments:)` requirement,
  typically by delegating to the new `registeredSubcommand(forRawArguments:)`
  helper, and the verb wins. The default implementation returns `nil`, so an app
  that does not implement it is unchanged. Apps no longer need to hand-write a
  `static func main()` restating the framework's launch sequence.

  `completions` is resolved before the hook and cannot be shadowed. Only the
  first argument is examined, and a leading `-` disqualifies a match, so
  `--help`, `--version`, and the `--` terminator fall through by construction. A
  verb beats a same-named file with no filesystem probe; `myapp ./name` and
  `myapp -- name` are the escapes. Two attribution quirks are documented rather
  than papered over: `myapp help verb` stays shadowed (use `myapp verb --help`),
  and a dispatched verb's `--version` reports the verb's own version, failing
  with an unknown-flag error when the verb declares none.

### Fixed

- **A dispatched verb's usage text is attributed to the verb, not the root.**
  Errors carrying their own command stack were already correct, but two cases
  were not: `ParserError.noArguments` (a verb invoked with its required argument
  missing) is rendered against the type passed to `exit(withError:)`, and a
  `ValidationError` thrown from a verb's `run()` carries no stack at all. Both
  now render the verb's usage across all three launch layers.

## [0.3.7] - 2026-07-27

### Added

- **Terminal handoffs temporarily return the real terminal to an external
  operation.** `TerminalHandoffAction` suspends the runtime input reader,
  restores terminal modes and the primary screen, awaits an editor or other
  interactive operation, then re-enters raw mode and repaints. Calls outside a
  live terminal runtime fail explicitly instead of competing for the TTY.

## [0.3.5] - 2026-07-27

### Added

- **Host focus binding for embedded terminals.** `TerminalView.hostFocused`
  binds the framework-owned terminal input member to an enum-valued
  `@FocusState`, preserving host key interception and child forwarding without
  an application-owned forwarding wrapper.

## [0.3.4] - 2026-07-27

### Added

- **Host-owned key routing for embedded terminals.** `TerminalView` now offers
  an additive initializer whose routing closure can consume the original
  `KeyPress` before terminal-emulator conversion. The original initializer
  remains source-compatible and forwards every key to the child session.
- **Shared real-terminal journey support.** `SwiftTUITestSupport` now owns the
  PTY pair, bounded ANSI-visible-screen wait, exact-write helper, deadline, and
  cancellation-safe descriptor teardown used by downstream application tests.

### Changed

- **Nested custom and scrolling layouts keep their asynchronous measurement
  stack pointer-sized.** Measurement work items are indirect, preventing the
  released FilePreviewer/Sextant navigation path from exhausting a Dispatch
  worker stack during frame-tail layout.
- **Environment variables now use the single `SWIFTTUI_*` namespace.**
  Framework, host-wire, performance, fixture, and test-harness controls that
  previously used shorter or legacy project prefixes have been renamed without
  compatibility aliases.
- **Radial gradients now fall off in circles.** `RadialGradient` measured
  distance in raw cell space, so a gradient that was circular in cells painted
  as a roughly 2:1 vertical ellipse on screen. The sampler now scales vertical
  offsets by the cell aspect ratio from `CellPixelMetrics`, matching how
  `Circle`, `Ellipse`, and `Capsule` already correct curved geometry. Radii
  stay denominated in horizontal cells: the horizontal reach of an existing
  gradient is unchanged, and only the vertical over-reach is corrected. Fills
  that relied on the old vertical spread should roughly double `endRadius` to
  restore it.

## [0.2.0] - 2026-07-24

### Added

- **Mesh gradients.** `MeshGradient` is a public, animatable `ShapeStyle` for
  validated rectangular point-and-color grids. It renders through fills,
  strokes, borders, tiles, clipping, blending, retained rendering, terminal,
  WebHost/WASI, SwiftUI, and Android paths. Device-space and perceptual Oklab
  interpolation are available through the new `Gradient.ColorSpace` enum.
  Same-topology meshes interpolate points, colors, and background; incompatible
  topology or discrete settings snap to the target value.
- **Mesh performance scenario.** `TermUIPerf synthetic-mesh-gradient` measures
  static, retained, and animated mesh phases at configurable terminal sizes.
  The release implementation measured 0.96x the 3-stop linear-gradient CPU
  cost at 80×24 and 0.89x at 160×48 on the release host, with no dropped frames.

### Changed

- **Host wire styles are appearance-keyed and area-bounded.** Style lookup is
  now O(1), and a full v2 keyframe rebases the epoch before animated
  high-cardinality styles can grow transport state without bound.
- **Source compatibility note:** `AnyShapeStyle` gains the additive
  `meshGradient` case. Downstream exhaustive switches over this pre-1.0 public
  enum must handle the new case.

## [0.1.15] - 2026-07-22

### Added

- **Retained reuse under the stack-lean profile** (opt-in
  `SWIFTTUI_LEAN_RETAINED_REUSE=1`): the browser/WASI stack-lean resolve
  profile can now re-enable the retained-reuse gate alone — a reuse hit
  short-circuits the resolve descent, so it only ever shallows the frame
  relative to the lean baseline; memoized reuse and selective evaluation
  stay off. The runtime-registration restore walks are now explicit work
  lists (never per-level recursion), which is what keeps the reuse-hit
  restore inside the lean stack envelope for any tree depth. Measured on
  WebKit against the granular-observation WebExample: steady worker
  pipeline 27.6 → 10.8 ms/frame (resolve 20.5 → 5.5 ms). Browser hosts on
  stack-lean engines enable the flag by default via `@swifttui/web`
  0.1.15; terminal and native hosts are unaffected (the flag is inert
  outside the lean profile).

### Changed

- **WebHost browser bundle re-vendored at `swift-tui-web` 0.1.15**,
  carrying the lean-engine `SWIFTTUI_LEAN_RETAINED_REUSE=1` default.

## [0.1.13] - 2026-07-21

### Changed

- **WebHost browser bundle re-vendored at `swift-tui-web` 0.1.13.** The
  bundle gains hidden-scene suspension: a scene that cannot be seen
  (switched to the background, or any scene while the document is hidden)
  parks its WASI run loop between `poll_oneoff` waits and freezes its
  monotonic clock, so hidden scenes cost no CPU and resume burst-free
  with timers keeping their remaining time. Default on; embedders opt
  out via `suspendHiddenScenes: false` / `suspendWhenHidden: false`.

### Added

- **Presented-Progress Guard** (opt-in via
  `SWIFTTUI_PRESENTED_PROGRESS_GUARD`): with the guard on, a completed
  frame whose presentation diff against the last presented surface is
  non-empty is never drop-eligible
  (`FrameDropBlocker.undeliveredPresentationDamage`) — the bounded
  completed-frame starvation backstop becomes the invariant "undelivered
  pixels are never droppable", uniformly for every host. Value-identical
  rasters (all-zero damage) stay droppable, and the pre-start cancel arm
  is deliberately out of scope. Default off; the pre-committed drop-heavy
  browser rusage A/B (2026-07-21, docs/plans/2026-07-20-001 Stage 5)
  measured the guard eliminating every disposal at per-frame cost parity
  and byte-equivalent behavior under the shipped `async-no-cancel`
  default, but its plain-`.async` cadence (0.674 distinct-generation
  coverage vs the 0.72 fix band) failed the flip's benefit gate — the
  default flip is declined; the guard remains opt-in insurance.

## [0.1.12] - 2026-07-21

### Changed

- **WebHost browser bundle re-vendored at `swift-tui-web` 0.1.12.** No
  Swift source changes. The bundle exits the stack-lean hold on confirmed
  V8 workers (`SWIFTTUI_STACK_LEAN_PROFILE: "0"` by default; JSC and
  Gecko stay lean — Gecko by live measurement), riding 0.1.11's
  `async-no-cancel` disposal default. Live non-lean Chromium measures the
  same distinct-generation coverage as lean at roughly half the per-frame
  pipeline cost, with 100% damage-scoped delta frames in the steady
  window.

## [0.1.11] - 2026-07-20

### Added

- **`PerTickPresentCadenceTests`**: composed-runtime per-tick present
  cadence coverage for completed-frame disposal — an autonomous
  Life-shaped tick with deterministic held-tail supersession proves
  `async-no-cancel` presents every completed frame, with a non-lean
  `dropped_completed` red-proof naming the disposal layer, re-run under
  the stack-lean and chunked-resolve WASI-shaped profiles.

### Changed

- **WebHost browser bundle re-vendored at `swift-tui-web` 0.1.11.** No
  Swift source changes. The bundle's `BrowserWASIBridge` now defaults
  browser sessions to `SWIFTTUI_RENDER_MODE=async-no-cancel` (engine-blind,
  both execution modes): completed-frame disposal under supersession —
  not transport publication — was the 0.1.9 live coalescing, and
  ordered commits lift deployed Life distinct-generation coverage
  0.22 → 0.86 with per-frame cost unchanged. The `?renderMode=` page
  seam and caller environments still override.

## [0.1.10] - 2026-07-20

### Changed

- **WebHost browser bundle re-vendored at `swift-tui-web` 0.1.10.** No Swift
  source changes. The bundle brings the JSPI main-thread wasm execution mode
  (opt-in), holds the stack-lean profile as the default on every engine, and
  raises the packaged wasm linear-memory stack from 1 MiB to 16 MiB. Together
  these heal two live 0.1.9 Chromium regressions (an Animations-scene
  shadow-stack overflow, and Life frame-emission coalescing under the
  non-lean profile).

## [0.1.9] - 2026-07-20

### Changed

- **WebHost browser bundle re-vendored at `swift-tui-web` 0.1.9.** No Swift
  source changes. The bundle adds engine-family detection with an
  engine-differentiated stack-lean default (later reverted in 0.1.10) and
  JSPI capability detection.

## [0.1.8] - 2026-07-20

### Added

- **WASI stack-lean resolve profile** (`SWIFTTUI_STACK_LEAN_PROFILE`):
  default-on for WASI builds, opt-in natively. Swaps per-level task-local
  ambient binds for MainActor save/restore slots and disables retained-reuse,
  memoized reuse, and selective evaluation, bounding the resolve descent's
  stack cost for JavaScriptCore's worker thread-stack budget.
- **Depth-capped chunked resolve** (`DeferredResolveDriver`): a
  drain-and-rerun fixpoint that cuts the resolve descent at structural child
  edges past a depth limit (default K=6 under the lean profile;
  `SWIFTTUI_RESOLVE_DEPTH_LIMIT` tunes or force-enables it) and re-resolves
  deferred subtrees from a fresh shallow stack. This fixes the Safari/WebKit
  stack overflow that broke the browser demo on JavaScriptCore.

### Fixed

- **Lean-profile async ambient reads.** Under the stack-lean profile,
  ambient-context reads now fall back to the task-local slot
  (`leanCurrent ?? taskLocalCurrent`), restoring `.task`-closure visibility of
  authoring/environment context. Previously state writes from async tasks
  degraded to detached boxes and produced no frames (the frozen Game of
  Life).

## [0.1.7] - 2026-07-18

### Added

- **Gesture composition**: inter-tap timeout for multi-tap counts, exclusive
  gesture hand-off with replay, and `SimultaneousGesture`/`SequenceGesture`.
- **Typed navigation data paths** and **data-driven dismissal**;
  presentation surfaces now stack.
- **Node-hosted collection rows** and windowed lazy-stack realization:
  lazy stacks realize and measure only the scroll viewport's window, with
  drift correction pinned by tests.
- SwiftUI-parity wiring: object environment values, `withTransaction`,
  spring `initialVelocity`; off-main `@Observable` writes are marshaled
  instead of trapping.

### Changed

- Teardown reachability unified behind a single barrier entrypoint with
  census-adjudicated spares; legacy lifetime ledgers retired.
- Performance program: reuse-gate invalidation queries inverted to the
  invalidated set, unchanged-commit effect republication scoped to an owner
  index, animation deadline work scoped, collection baseline scenarios
  (`lazy-list-1k`, `table-1kx4`) added.

### Fixed

- A large fix batch from the gallery fuzz campaign, including: toolbar chrome
  proposal fill, adopted-slot conditional transitions, location-free drop
  dispatch fallback, node-backed style bodies with adopted authoring owners,
  superseded task starts in merged lifecycle plans, paired pointer-route
  release with departed gesture recognizers, and pass-stable `onChange`
  previous-value reads.

## [0.1.6] - 2026-07-13

### Removed

- **BREAKING: the `SwiftTUICharts` product moved to its own repository,
  [`SwiftTUI/swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts).**
  `swift-tui` no longer declares a `SwiftTUICharts` product or target. Keep
  your `import SwiftTUICharts` lines as they are, add the new package
  dependency, and change the product's `package:` identity:

  ```swift
  dependencies: [
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "<version>"),
    .package(url: "https://github.com/SwiftTUI/swift-tui-charts.git", exact: "<version>"),
  ],
  // in the target:
  .product(name: "SwiftTUICharts", package: "swift-tui-charts"),
  ```

### Added

- `AccessibilityVisualContent` is now public, and the public
  `SemanticMetadata` initializer accepts `accessibilityVisualContent:`, so
  external view libraries can participate in the missing-label accessibility
  diagnostics contract.
- The published `SwiftTUIViews` product re-exports `SwiftTUICore` (which
  re-exports `SwiftTUIGraph` and `SwiftTUIPrimitives`), making
  `import SwiftTUIViews` a self-sufficient authoring surface for external
  view libraries — the same re-export shape `SwiftTUIRuntime` already had.

### Changed

- The absorbed Vendor targets are renamed with a `SwiftTUIVendor` prefix
  (`UnixSignals` → `SwiftTUIVendorUnixSignals`, `SwiftFiglet` →
  `SwiftTUIVendorFiglet`, `EmbeddedFonts` → `SwiftTUIVendorFigletEmbeddedFonts`,
  `GIF`/`JPEG`/`PNG` → `SwiftTUIVendor{GIF,JPEG,PNG}`, the `figlet` executable →
  `SwiftTUIVendorFigletCLI`). SwiftPM requires target names to be unique across
  the whole package graph, so under their upstream names these targets collided
  with packages that ship the originals (e.g. swift-service-lifecycle's
  `UnixSignals`). No public product changes name; the vendored modules were
  never importable by consumers.
- Documented that `DefaultRenderer.render(_:)` is a one-shot snapshot/preview
  entry point and is **not** focus/press-reuse-safe across successive calls
  (focus/press state is excluded from the reuse snapshot and protected by the
  run loop's suppression scope, which the one-shot path does not compute) — drive
  interactive rendering through the run loop. Clarified the `EquatableView`
  documentation: it wraps an already-`Equatable` `Content` and relocates the
  reuse boundary onto its own node; prefer conforming the boundary view to
  `Equatable` directly unless a distinct boundary node is needed.
- Added a DEBUG memoization diagnostic (`SWIFTTUI_MEMO_TRACE` → `inert_equatable`)
  that flags an `Equatable` / `.equatable()` boundary which is never memo-reused
  because it reads `@State`/`@Observable`/focus state — surfacing a silently inert
  opt-in. The reflective comparator path is now DEBUG-only (the production gate is
  `Equatable`-only); no public API change.

## [0.0.21] - 2026-06-17

### Added

- **`EquatableView` and `View.equatable()`** (SwiftUI parity). Wrapping a
  read-free boundary view (or conforming it to `Equatable`) lets the renderer
  reuse its whole committed subtree via a single `==` when the value is
  unchanged, instead of re-evaluating it under an invalidated ancestor. `==` is
  a correctness contract — see the `EquatableView` docs.

### Changed

- **Memoized-body reuse is on by default.** When a node reached under an
  invalidated ancestor is `Equatable`-equal to its previous value, reads no
  `@State`/`@Observable`/focus state, and passes the retained-reuse guards, its
  committed subtree is reused instead of recomputed. The gate is `Equatable`-only
  (a true opt-in): inert on views that do not conform to `Equatable` (measured
  within noise on non-opt-in trees), a large `resolve` win on those that do. Set
  `SWIFTTUI_MEMO_REUSE=0` to disable.

## [0.0.19] - 2026-06-10

Lockstep release across the SwiftTUI org. Headline: a first preview of the
host-managed Android surface.

### Added

- **Android host (early preview).** A new `SwiftTUIAndroidHost` library
  product and target under `Platforms/Android`: hosts SwiftTUI scenes behind
  a `swift_tui_android_*` C ABI for JNI/Compose embedders, publishing
  semantic host frames — styled cells, terminal colors,
  underline/strikethrough decorations, image attachment records and
  payloads, accessibility nodes and announcements, focus presentation, and
  preferred layout size — as versioned JSON snapshots. Verified rendering
  the gallery example on an arm64-v8a emulator. IME composition, clipboard,
  link opening, and precise drag/scroll gestures remain follow-up work.
- A platform-neutral `HostedSurfaceSizeNegotiator` in `SwiftTUIRuntime`,
  shared by the SwiftUI and Android hosts for hosted-surface size
  negotiation.
- Ordered raster presentation layers.
- GIF blend-behavior test coverage.
- A complete copy-pasteable `Package.swift` example in the README.
- README disclosure of the `#12` run-loop memory-corruption known issue.

### Changed

- Broad Android compatibility across core, runtime, profiling, and terminal
  I/O (`canImport(Android)` paths); the package cross-builds for
  `aarch64-unknown-linux-android28` with the official Swift Android SDK.
- Presentation sheets render with single-line full-bleed chrome.
- `perf(termui)`: sheet-open-latency benchmark plus gated additive-overlay
  raster reuse.
- README: the web packages are now installed from npm
  (`npm install @swifttui/web @swifttui/build`); the GitHub-release tarball URLs
  are documented as a secondary, pin-a-release-asset option.
- `docs/VISION-GAP.md` restored at `HEAD` (five docs link to it) and brought
  current: npm publishing and still-`Image` blend-mode precomposition are now
  recorded as shipped.

## [0.0.18] - 2026-06-07

Lockstep release across the SwiftTUI org, reconciling a prior version skew (a
solo `0.0.17` tag carrying the breaking `Canvas`/`CanvasContext` redesign that
the rest of the org had not followed). Includes the image-blend-mode
precomposition work (still images), cache hardening, and glyph-aware backdrops.

See the GitHub releases for the full per-tag history:
<https://github.com/SwiftTUI/swift-tui/releases>.

[Unreleased]: https://github.com/SwiftTUI/swift-tui/compare/0.9.0...HEAD
[0.9.0]: https://github.com/SwiftTUI/swift-tui/releases/tag/0.9.0
[0.3.4]: https://github.com/SwiftTUI/swift-tui/releases/tag/0.3.4
[0.0.18]: https://github.com/SwiftTUI/swift-tui/releases/tag/0.0.18
