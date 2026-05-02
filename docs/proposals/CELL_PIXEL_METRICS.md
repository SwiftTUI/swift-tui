# Cell Pixel Metrics

Status: Shipped. Both stages are landed — `CellPixelMetrics` is public on `GeometryProxy` and `EnvironmentValues`, the runtime refreshes cell pixel size on `SIGWINCH`, the gallery physics toy uses a `Circle` subject, and the Braille rasterizer applies aspect correction to `Circle`/`Ellipse`/`Capsule` via `Rasterizer.subpixelCircleRadii`. DocC coverage lives in `Sources/Core/Core.docc/CellPixelMetrics.md` and `Sources/View/View.docc/AspectCorrectShapes.md`. Retained as the implementation record.
Related research: [CELL_PIXEL_GEOMETRY_RESEARCH.md](../CELL_PIXEL_GEOMETRY_RESEARCH.md)

## Problem

SwiftTUI measures authored geometry in integer cells. That stance is correct for layout, placement, and alignment. It is incomplete for motion, shape rendering, and image sizing, where a cell's pixel dimensions determine whether the output *looks* honest even when it is laid out correctly.

Three concrete symptoms, grounded in shipped code:

- The gallery physics toy (`Examples/gallery/Sources/GalleryDemoViews/FullScreen.swift`) hand-compensates for cell aspect by hardcoding `blockSize = Size(width: 6, height: 3)` so the ball looks square. Gravity, applied to `velocity.y` in cells, is roughly 2x faster visually than the equivalent horizontal impulse. Wall and floor bounce coefficients decay at different visible rates on each axis.
- A `Circle` drawn on a 2x4 Braille grid assumes sub-pixels are square. That holds when `cellPixelSize.aspectRatio == 2.0` (the 8x16 default) but fails on terminals with other aspect ratios — the "circle" becomes an ellipse.
- Image callers that want to pre-scale a PNG to the terminal's native pixel resolution must reach into `TerminalGraphicsCapabilities` themselves; there is no authoring-level path to that value.

The runtime already detects cell pixel dimensions. `TerminalGraphicsCapabilities.cellPixelSize: Size?` is populated on startup by a three-method fallback in `Sources/SwiftTUI/TerminalHost.swift`:

1. `ioctl(TIOCGWINSZ)` with `ws_xpixel`/`ws_ypixel`
2. `CSI 16 t` cell-pixel query
3. `CSI 14 t` text-area-pixels query divided by cell count

The value is threaded into the resolve environment as `package var EnvironmentValues.terminalCellPixelSize: Size` and consumed only by image rendering. No public API exposes it. Additionally, the current caching strategy in `POSIXTerminalHost.baselineGraphicsCapabilities()` re-reads the value only when the cached version is `nil`, so cell pixel size does not refresh across `SIGWINCH` events (font-size changes, monitor moves, pane resizes that change pixel-per-cell).

## Goal

Expose the already-detected cell pixel dimensions as a public, read-only `CellPixelMetrics` value on `GeometryProxy` and `EnvironmentValues`, with an honest confidence signal distinguishing reported values from the conventional fallback, and an honest refresh story across `SIGWINCH`. Deliver in two stages:

- **Stage 1** — publish the metric, refresh it correctly, migrate the physics toy to use it for motion and for adaptive rectangular sizing.
- **Stage 2** — land shape aspect correction in the Braille rasterizer so `Circle` / `Ellipse` / `Capsule` render honestly on terminals whose cells are not 2:1, and convert the physics toy's subject from a `Rectangle` to a `Circle` as the end-to-end demonstration.

Splitting lets stage 1 ship, be validated by the toy's motion improvement, and be critiqued on API shape before the rasterizer work commits to the same vocabulary.

The motivation survey in [CELL_PIXEL_GEOMETRY_RESEARCH.md](../CELL_PIXEL_GEOMETRY_RESEARCH.md) identifies ten potential consumers. This proposal covers the four with strongest fit (geometric honesty, physics and motion, image sizing, diagnostics). The conditional and deferred consumers either build on top of the same read-only type without additional framework surface, or belong in a different subsystem (pointer precision).

## Non-goals

Applies to both stages unless noted:

- No `PixelPoint`, `PixelRect`, or `PixelSize` types.
- No pixel-denominated layout modifier such as `.frame(pixelWidth:pixelHeight:)`.
- No public setter on `GeometryProxy.cellPixelMetrics`, and no public injection API on `EnvironmentValues` for tests. Test harnesses inject via `StreamingTerminalHost(graphicsCapabilities:)` and a new `updateCellPixelSize` method.
- No pointer-coordinate pixel precision. That is a separate design living in the input pipeline and is explicitly deferred by `docs/VISION.md`.
- No derived opinion helpers such as `isHighDensity: Bool`. Raw metrics are exposed; classification is left to consumers.
- No changes to `Layout`, `Alignment`, placement, or the cell-denominated geometry types (`Size`, `Point`, `Rect`, `EdgeInsets`). Their semantics are unchanged.
- No re-running of the one-shot escape-sequence probes (`CSI 16 t`, `CSI 14 t`, Kitty support, sixel) on SIGWINCH. Only the cheap `ioctl` cell-pixel read is re-issued.
- **Stage 1 only:** no changes to the Shape rasterizer. `Circle` continues to render as it does today (true only when `aspectRatio == 2.0`). Stage 2 fixes that.

---

# Stage 1 — Metric exposure, SIGWINCH refresh, and isotropic physics

## Design

### Type

A single new public type in `Sources/Core/GeometryTypes.swift`:

```swift
/// Read-only display metrics describing how cells map to device pixels.
///
/// Advisory runtime metadata. SwiftTUI's layout, placement, and alignment
/// story remain cell-denominated; this type exists so authors can apply
/// aspect correction to shapes, motion, or image sizing without reinventing
/// the fallback.
public struct CellPixelMetrics: Equatable, Sendable {
  /// Width of a single cell in device pixels.
  public let width: Int
  /// Height of a single cell in device pixels.
  public let height: Int
  /// Confidence in the reported value.
  public let source: Source

  public init(width: Int, height: Int, source: Source) {
    self.width = width
    self.height = height
    self.source = source
  }

  /// Cell height divided by cell width. Conventionally ~2.0 for typical
  /// monospace fonts.
  public var aspectRatio: Double {
    Double(height) / Double(width)
  }

  public enum Source: Sendable, Equatable {
    /// The terminal reported its cell size via ioctl or an escape query.
    case reported
    /// No cell size was reported; this is the conventional 8x16 fallback.
    case estimated
  }

  /// Conventional 8x16 fallback used when the terminal did not report its
  /// cell size. Aspect ratio 2:1.
  public static let estimated = Self(width: 8, height: 16, source: .estimated)
}
```

Design choices:

- **Two-case `Source`, not three.** The runtime can distinguish `ioctl` / `CSI 16 t` / `CSI 14 t`-derived internally, but the only authoring decision that matters is "did the terminal tell us, or did we guess?" Two cases is enough. The enum (rather than a `Bool`) leaves room for a future `.testInjected` without a source break.
- **Stored `let` fields, computed `aspectRatio`.** Authors should not construct modified copies; aspect ratio is derivable and does not need to be stored.
- **Public memberwise initializer.** Required so consumers (and tests outside the package) can construct fixtures. The `GeometryProxy.init` default is `.estimated`, so most callers never touch the initializer directly.

### Proxy surface

`Sources/View/GeometryReading/GeometryReader.swift` — `GeometryProxy` gains a stored property:

```swift
public struct GeometryProxy: Equatable, Sendable {
  public var size: Size
  public var safeAreaInsets: EdgeInsets
  public var cellPixelMetrics: CellPixelMetrics

  public init(
    size: Size,
    safeAreaInsets: EdgeInsets = .zero,
    cellPixelMetrics: CellPixelMetrics = .estimated
  ) {
    self.size = size
    self.safeAreaInsets = safeAreaInsets
    self.cellPixelMetrics = cellPixelMetrics
  }
}
```

Same name on the proxy and the environment (`cellPixelMetrics`). No `proxy.cellMetrics` alias, no `proxy.pixelSize` convenience — both trivially computable from the one canonical property, and the narrower surface keeps the learning load lower.

### Environment surface

A new public environment key replaces the current `package var EnvironmentValues.terminalCellPixelSize: Size`.

```swift
// Sources/View/Environment/CellPixelMetricsEnvironment.swift (new)
private enum CellPixelMetricsKey: EnvironmentKey {
  static let defaultValue: CellPixelMetrics = .estimated
}

extension EnvironmentValues {
  public var cellPixelMetrics: CellPixelMetrics {
    get { self[CellPixelMetricsKey.self] }
    set { self[CellPixelMetricsKey.self] = newValue }
  }
}
```

The existing `Sources/View/Environment/ImageEnvironment.swift` loses its `terminalCellPixelSize` declaration. The image pipeline's three internal callsites move to `cellPixelMetrics`.

### Runtime wiring

`Sources/SwiftTUI/RunLoop+Rendering.swift` `resolveContext(for:)` replaces the current write:

```swift
// before
effectiveEnvironmentValues.terminalCellPixelSize =
  terminalHost.graphicsCapabilities.cellPixelSize ?? .init(width: 8, height: 16)

// after
if let cellPixelSize = terminalHost.graphicsCapabilities.cellPixelSize {
  effectiveEnvironmentValues.cellPixelMetrics = CellPixelMetrics(
    width: cellPixelSize.width,
    height: cellPixelSize.height,
    source: .reported
  )
} else {
  effectiveEnvironmentValues.cellPixelMetrics = .estimated
}
```

`Sources/View/GeometryReading/GeometryReader.swift` `resolveElements(in:)` threads the environment value into the proxy:

```swift
let proxy = context.trackingObservableAccess {
  GeometryProxy(
    size: context.environmentValues.terminalSize,
    safeAreaInsets: context.environmentValues.safeAreaInsets,
    cellPixelMetrics: context.environmentValues.cellPixelMetrics
  )
}
```

### Responding to window size changes (SIGWINCH)

The runtime already responds to SIGWINCH by re-reading the surface size and scheduling a frame. Cell pixel dimensions must be refreshed on the same trigger, because font-size changes, monitor moves, and pane resizes all produce a SIGWINCH along with a genuine change in pixel-per-cell.

Three changes:

**1. `POSIXTerminalHost.baselineGraphicsCapabilities()` re-reads on every access.**

Today:

```swift
private func baselineGraphicsCapabilities() -> TerminalGraphicsCapabilities {
  var capabilities = capabilityProbe.cachedGraphicsCapabilities ?? .none
  if capabilities.cellPixelSize == nil {               // only when still nil
    capabilities.cellPixelSize = try? controller.cellPixelSize(of: outputFileDescriptor)
  }
  capabilityProbe.cachedGraphicsCapabilities = capabilities
  return capabilities
}
```

After:

```swift
private func baselineGraphicsCapabilities() -> TerminalGraphicsCapabilities {
  var capabilities = capabilityProbe.cachedGraphicsCapabilities ?? .none
  // Always attempt a fresh ioctl read. The syscall is cheap and its result
  // is authoritative when the kernel reports pixel dimensions. We only
  // fall back to the cached value if the fresh read returns nil, which
  // preserves previously-probed escape-sequence values.
  if let fresh = try? controller.cellPixelSize(of: outputFileDescriptor) {
    capabilities.cellPixelSize = fresh
  }
  capabilityProbe.cachedGraphicsCapabilities = capabilities
  return capabilities
}
```

The one-shot escape-sequence probes (`probeGraphicsCapabilitiesIfNeeded`) remain cached — those query *terminal support* (Kitty, sixel, color-register count), which does not change during a session. Only the cell-pixel-size read becomes live.

**2. `StreamingTerminalHost.updateCellPixelSize(_:)`.**

`StreamingTerminalHost` currently stores `graphicsCapabilities` as a `let` set at init. Hosted sessions have no way to simulate cell-pixel-size changes, which makes SIGWINCH testing impossible in-process.

Add:

```swift
package func updateCellPixelSize(_ cellPixelSize: Size?) {
  state.withLock { state in
    state.graphicsCapabilities.cellPixelSize = cellPixelSize
    state.lastSubmittedSurface = nil
  }
}
```

And move `graphicsCapabilities` into the locked `State` struct (currently `package let`), exposing it via `var graphicsCapabilities: TerminalGraphicsCapabilities { state.withLock(\.graphicsCapabilities) }`. The `lastSubmittedSurface = nil` line matches the existing pattern in `updateSurfaceSize`, forcing a full repaint on the next frame.

**3. `HostedSceneSession.resize(to:cellPixelSize:)` overload.**

`HostedSceneSession.resize(to: Size)` is the existing public entry point for simulating a resize from test harnesses and embedded hosts. Add an overload:

```swift
public func resize(
  to size: Size,
  cellPixelSize: Size? = nil
) {
  host.updateSurfaceSize(size)
  host.updateCellPixelSize(cellPixelSize)
  signalReader.send("SIGWINCH")
}
```

The existing `resize(to:)` remains; callers who do not care about cell-pixel-size simulation are not forced to think about it. The SIGWINCH emission is unchanged; the runtime's existing frame-on-SIGWINCH path picks up both new values together on the next resolve.

### Internal consumer migration

Three internal callsites are affected by the removal of `terminalCellPixelSize`:

- `Sources/View/Primitives/Image.swift:61` — currently reads a `Size`. Migrates to `environmentValues.cellPixelMetrics`, constructing a local `Size(width: metrics.width, height: metrics.height)` at the boundary where a `Size` is still needed by `ImageAssetRepository`. No behavior change.
- `Sources/SwiftTUI/RunLoop+Rendering.swift:311` — the write site, replaced as shown above.
- `Sources/View/Environment/ImageEnvironment.swift:20` — the `package var` declaration is deleted. `TerminalCellPixelSizeKey` is removed.

The `ImageAssetResolver` typealias and `ResolvedImageAsset.cellPixelSize` field retain their current `Size` parameter types. Those are image-pipeline internals that will not benefit from knowing the `source`; the conversion at the boundary is local and clear.

This is a breaking internal rename, not a deprecation. The framework is pre-release and the removed symbol is `package`-visibility.

## Testing

Five layers:

### Unit — `CellPixelMetrics` itself (`Tests/CoreTests/`)

- `aspectRatio` arithmetic for representative pairs (8x16 → 2.0, 6x12 → 2.0, 10x10 → 1.0).
- `Equatable` discriminates by all three fields including `source`.
- `.estimated` matches `CellPixelMetrics(width: 8, height: 16, source: .estimated)`.

### Unit — environment

- Default value of `EnvironmentValues.cellPixelMetrics` is `.estimated`.
- Round-trip: setting and reading preserves the value.

### Integration — `GeometryReader` (`Tests/SwiftTUITests/`)

- Given an environment override with a specific `cellPixelMetrics`, the proxy inside a `GeometryReader` observes the same value.
- Given no override, the proxy observes `.estimated`.
- The existing `GeometryReader` identity and observation-tracking tests continue to pass unchanged.

### Integration — runtime

- `StreamingTerminalHost` constructed with `graphicsCapabilities.cellPixelSize = Size(width: 12, height: 24)` publishes a resolve environment containing `CellPixelMetrics(width: 12, height: 24, source: .reported)` on the next frame.
- `StreamingTerminalHost` constructed with `graphicsCapabilities: .none` publishes `.estimated`.

### Integration — SIGWINCH refresh

- Construct a `HostedSceneSession` with `graphicsCapabilities.cellPixelSize = (8, 16)`. Assert the first resolve sees `CellPixelMetrics(8, 16, .reported)`.
- Call `session.resize(to: sameSize, cellPixelSize: Size(10, 20))`. Wait for the SIGWINCH-driven frame. Assert the next resolve sees `CellPixelMetrics(10, 20, .reported)`.
- Call `session.resize(to: sameSize, cellPixelSize: nil)`. Assert the resolve sees `.estimated`.
- For `POSIXTerminalHost`: via a `TerminalControlling` mock, verify `baselineGraphicsCapabilities()` reflects the latest `cellPixelSize` returned by the controller on each access, rather than holding the first value.

### Fixtures

No existing fixture snapshots should change. Image rendering on terminals without pixel detection continues to receive the 8x16 default, matching current behavior bit-for-bit.

## Gallery physics toy migration — stage 1 (rectangle with isotropic motion)

Shipped in the same commit as the API. Serves as the worked example in the proposal and as the first real consumer of `cellPixelMetrics`. The visible subject remains a `Rectangle` — stage 2 swaps it for a `Circle`.

Current anisotropic behavior in `FullScreenToyPhysics`:

- `blockSize = Size(width: 6, height: 3)` is hardcoded 2:1, tuned for typical cells.
- `gravityPerTick = 1` added to `velocity.y` in cell units; visually twice as fast as a horizontal impulse of the same magnitude.
- `DragGesture.velocity` reported in cells/second; the two components are added to `state.velocity` directly, producing a directionally biased release.
- Wall bounces (`wallBounceNumerator/Denominator = 7/8`) and floor bounces (`floorBounceNumerator/Denominator = 3/4`) are applied per-axis with the same fractions; decay is visibly asymmetric.

Migration — the physics type stops living in a pure cell space and starts taking `CellPixelMetrics` as a parameter, projecting pixel-isotropic intent into cells:

- `blockSize` becomes a function of `aspectRatio`. The width stays at `6` cells; the height becomes `Int((6.0 / aspectRatio).rounded())`. With `aspectRatio = 2.0`, that reproduces `(6, 3)`; on a terminal whose cells are closer to square, the block adapts.
- `gravityPerTick` applied to `velocity.y` is divided by `aspectRatio` so the visual downward acceleration matches the horizontal impulse magnitude.
- `DragGesture.velocity.y` is divided by `aspectRatio` before being folded into `state.velocity.y`, so diagonal flicks decompose symmetrically.
- Wall and floor bounce coefficients are unchanged. The bouncing *behavior* remains cell-denominated; the motion *producing* the bounces is now isotropic.

The physics struct signature changes from `step(_ state: inout State, in bounds: Size)` to `step(_ state: inout State, in bounds: Size, metrics: CellPixelMetrics)` (and similarly for `spawnState`, `displayPosition`, `applyRelease`, `blockSize`). The view layer reads `proxy.cellPixelMetrics` and threads it through alongside `bounds`.

`Examples/gallery/Tests/GalleryDemoViewsTests/PhysicsTabGestureTests.swift` adopts `.estimated` as the default test metric, so its numeric assertions remain unchanged.

---

# Stage 2 — Shape aspect correction and circular subject

## Problem

The Braille-subpixel rasterizer in `Sources/Core/Rasterizer.swift` uses a 2x4 subpixel grid per cell and assumes each subpixel is pixel-square. That assumption is implicit in the circle code:

```swift
case .circle:
  let radius = max(0, (min(subW, subH) - 1) / 2)
  canvas.strokeCircle(centerX: cx, centerY: cy, radius: radius)
```

This treats subpixel coordinates as isotropic. It is correct exactly when `cellPixelSize.aspectRatio == 2.0`, because that makes each subpixel `(cellW/2, cellH/4) = (cellW/2, cellW/2)` — i.e. square. For any other aspect ratio, sub-pixels are oblong and the resulting shape is an ellipse in screen pixels rather than a circle.

Affected shapes: `Circle`, `Ellipse`, `Capsule`. `Rectangle` and `RoundedRectangle` are cell-aligned and unaffected.

## Design

### Rasterizer change

The Braille rasterizer gains access to the current `CellPixelMetrics` via the `ResolveContext` that flows into the raster phase. The circle / ellipse / capsule branches in `Rasterizer.swift` convert between subpixel space and pixel space so that the emitted shape is true in pixels:

- A subpixel's pixel width is `cellPixelMetrics.width / 2`.
- A subpixel's pixel height is `cellPixelMetrics.height / 4`.
- For `Circle` — given a frame of `(cellW × cellH)` cells, compute the largest pixel-true diameter `d = min(cellW × cellPixelMetrics.width, cellH × cellPixelMetrics.height)`. Convert back to subpixel radii: `rxSubpixels = d / 2 / (cellPixelMetrics.width / 2)`, `rySubpixels = d / 2 / (cellPixelMetrics.height / 4)`. Draw an ellipse with those radii in subpixel space; because of the conversion it is visually a true circle.
- For `Ellipse` — semi-axes are the full half-frame in pixels (not the naive half-subpixels), converted back to subpixel coordinates using the same sub-pixel dimensions.
- For `Capsule` — the rounded caps use the radii computed as for Circle; the straight section uses the full cell-aligned extent.

The existing `strokeCircle` / `fillCircle` / `strokeEllipse` / `fillEllipse` canvas primitives already accept separate x and y radii (via the ellipse path). Circle is rewritten to delegate to the ellipse path with aspect-corrected radii; the dedicated circle primitive in `BrailleCanvas` remains available but is no longer used by the shape rasterizer.

### Fixture expectations

Existing `Circle` / `Ellipse` / `Capsule` fixture snapshots were captured against the current naive rasterizer. On a simulated 8x16 cell (the default `.estimated` metrics), the aspect-correct output is *identical* to the naive output, because the naive code is correct at that aspect. Fixtures on other metrics need to be recaptured.

The concrete plan: run the fixture regeneration with `.estimated` metrics only. Any fixture that changes visibly is a bug in the new rasterizer, not a legitimate change. Fixtures for aspect ratios other than 2.0 are added fresh as part of stage 2.

### Quantization caveat for sub-pixel dimensions

Because sub-pixel dimensions are computed via integer division (`metrics.width / 2`, `metrics.height / 4`), some non-default metrics produce the same sub-pixel aspect as 8x16. For example, 6x14 produces sub-pixels that are 3x3 — square — so the rasterizer output matches 8x16 even though the cell itself is different. Aspect correction produces visibly different output only when the integer-divided sub-pixel dimensions differ. This is worth keeping in mind when picking metrics for fixture coverage: 6x14 will not exercise the aspect-correction path even though its `aspectRatio` is not 2.0.

## Testing

### Unit — sub-pixel conversion

- Given `CellPixelMetrics(width: 8, height: 16)`, a `Circle` in an `(Nw, Nh)` cell frame produces subpixel radii `(Nw, Nh)` (matching current behavior).
- Given `CellPixelMetrics(width: 10, height: 20)`, the same frame produces subpixel radii scaled identically (ratio 2.0 is preserved — still a true circle).
- Given `CellPixelMetrics(width: 10, height: 16)`, the subpixel radii differ along x and y to compensate for the non-square sub-pixel.

### Integration — shape fixtures

- A new fixture suite renders `Circle`, `Ellipse`, `Capsule` at `.estimated` (8x16) and asserts the output matches existing fixtures bit-for-bit.
- Additional fixtures at `CellPixelMetrics(width: 10, height: 16)` and `CellPixelMetrics(width: 6, height: 14)` demonstrate that the shapes remain visually true and the fixtures are captured cleanly.

### Integration — gallery

- The physics toy's `FullScreenToyPhysics.blockSize` function is deleted. The subject becomes `Circle()` sized via `.frame(width: diameter, height: Int((Double(diameter) / aspectRatio).rounded()))`, where `diameter` is the cell-width of the shape. This re-uses the same aspect-correction math as the rectangle migration — but here the frame is handed to a `Circle`, whose rasterizer now also applies aspect correction internally, so the on-screen output is a true circle regardless of cell aspect.
- A gallery test asserts the toy's view builds and lays out without error on three metric fixtures (`.estimated`, `(10, 16)`, `(6, 14)`).

## Gallery physics toy migration — stage 2 (circular subject)

With the rasterizer corrected, the toy's subject changes:

```swift
// before (stage 1)
Rectangle()
  .frame(
    width: FullScreenToyPhysics.blockSize(metrics: cellMetrics).width,
    height: FullScreenToyPhysics.blockSize(metrics: cellMetrics).height
  )
  .foregroundStyle(.cyan)

// after (stage 2)
Circle()
  .frame(
    width: FullScreenToyPhysics.diameter,
    height: Int((Double(FullScreenToyPhysics.diameter) / cellMetrics.aspectRatio).rounded())
  )
  .foregroundStyle(.cyan)
```

`FullScreenToyPhysics.blockSize(metrics:)` is replaced by a single `diameter` constant (6 cells wide by default). The height is computed at the view layer from `cellPixelMetrics.aspectRatio`. The `Circle` rasterizer then applies its own aspect correction internally, so the on-screen ball is pixel-round regardless of the terminal's actual cell aspect.

The physics (gravity, gestures, bouncing) remains stage-1 code — it already lives in pixel-isotropic space. Stage 2 changes only the shape layer.

This is the end-to-end demonstration: the same terminal that previously rendered an oblong rectangular block with directionally biased motion now renders a true circular ball with symmetric motion on any terminal whose cell aspect it can detect.

---

## Public API delta

### Stage 1 additions

- `public struct CellPixelMetrics` in `Core`
- `public enum CellPixelMetrics.Source` in `Core`
- `public init(width:height:source:)` on `CellPixelMetrics`
- `public var aspectRatio: Double` on `CellPixelMetrics`
- `public static let estimated: CellPixelMetrics`
- `public var cellPixelMetrics: CellPixelMetrics` on `GeometryProxy`
- `public var cellPixelMetrics: CellPixelMetrics` on `EnvironmentValues`
- `public init(size:safeAreaInsets:cellPixelMetrics:)` on `GeometryProxy` (default for new parameter preserves source compatibility)
- `public func resize(to:cellPixelSize:)` overload on `HostedSceneSession`

### Stage 1 removals

- `package var terminalCellPixelSize: Size` on `EnvironmentValues` (internal only; three callsites migrated)
- `private enum TerminalCellPixelSizeKey` (internal only)

### Stage 1 internal changes

- `POSIXTerminalHost.baselineGraphicsCapabilities()` re-reads cell pixel size on every access rather than one-shot caching
- `StreamingTerminalHost.graphicsCapabilities` becomes state-locked (was `package let`), gains `updateCellPixelSize(_:)`

### Stage 2 additions

- None at the public API level. Stage 2 changes the Shape rasterizer's *behavior* but does not add or remove public surface.

### Stage 2 internal changes

- `Rasterizer` Braille-shape branches consume `CellPixelMetrics` to compute aspect-corrected sub-pixel coordinates for `Circle`, `Ellipse`, `Capsule`.
- New Core-level fixture suite for shape aspect correctness at non-default metrics.

No changes at any stage to `Layout`, `Alignment`, `Size`, `Point`, `Rect`, `EdgeInsets`.

---

## Documentation

Stage 1:

- `CellPixelMetrics` gains a DocC page under `Sources/Core/Core.docc/` explaining that the type is advisory runtime metadata, not layout data. The page links to the research memo.
- `GeometryProxy` DocC gains a short example showing `aspectRatio` use in a physics body.
- `docs/PUBLIC_API_INVENTORY.md` is updated to list the new additions.
- The SIGWINCH-refresh behavior is documented in `docs/RUNTIME.md` under the existing lifecycle section.

Stage 2:

- A new DocC article under `Sources/View/View.docc/` walks through the gallery physics toy at stage 2 as the worked example for `Circle` on non-default terminals.
- The `Circle`, `Ellipse`, `Capsule` DocC pages are updated to state that the shapes are aspect-correct using `cellPixelMetrics` from the resolve environment.

## Open questions for review

1. **Public initializer exposure.** The proposal exposes `CellPixelMetrics.init(width:height:source:)` publicly so that fixtures outside the package can construct values. An alternative is to keep the initializer `package` and require outside consumers to use `.estimated`. Confirm the public initializer is acceptable.
2. **Physics toy API signature.** Adding a `metrics:` parameter to `FullScreenToyPhysics.step` and friends is the simplest migration, but it threads the metric through every call site. An alternative is a stateful `FullScreenToyPhysics` instance with `metrics` on `init`. The gallery is not public API; either is fine. This proposal uses the parameter style for symmetry with the existing `bounds:` parameter — confirm.
3. **Scope of SIGWINCH refresh for `POSIXTerminalHost`.** The proposal re-issues only the cheap `ioctl` on every access to `baselineGraphicsCapabilities()`. It does *not* re-run `CSI 16 t` / `CSI 14 t` escape-sequence fallbacks, on the assumption that a terminal that supports those queries also reports pixel dimensions via `ioctl` (typical on macOS/Linux). Confirm that this is the right line to draw, or specify whether a bounded re-probe on SIGWINCH is wanted for terminals where only escape-sequence detection works.
4. **Fixture regeneration policy for stage 2.** Stage 2 adds new aspect-corrected fixtures at non-default metrics. The proposal does *not* delete or regenerate the existing 8x16 fixtures, on the basis that the new rasterizer is identical at that aspect. If a byte-level audit of existing fixtures during stage 2 finds any visible difference, that is a rasterizer regression and must be investigated rather than papered over with a regenerated fixture. Confirm.
