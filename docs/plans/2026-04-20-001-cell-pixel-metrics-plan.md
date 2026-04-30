---
title: "feat: cell pixel metrics and shape aspect correction"
type: feature
status: shipped
date: 2026-04-20
---

> **Note:** Both stages have shipped. Task checkboxes below were not back-ticked when the work landed; the proposal at [../proposals/CELL_PIXEL_METRICS.md](../proposals/CELL_PIXEL_METRICS.md) is the implementation record.


# Cell Pixel Metrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a public `CellPixelMetrics` value on `GeometryProxy` and `EnvironmentValues`, refresh it on SIGWINCH, use it to make the gallery physics toy isotropic (Stage 1), then make `Circle`, `Ellipse`, and `Capsule` aspect-correct and swap the toy's subject to a `Circle` (Stage 2).

**Architecture:** The runtime already detects cell pixel size into `TerminalGraphicsCapabilities.cellPixelSize`. Stage 1 promotes that data to a public read-only type and fixes the refresh story (the current `TerminalHost` caches the first successful read and never re-reads). Stage 2 threads the value into the Braille rasterizer so the shape family can compute pixel-true radii instead of assuming square sub-pixels.

**Tech Stack:** Swift 6 strict concurrency, Swift Testing (`@Test` / `#expect`), `@MainActor`-isolated view tests, `@testable import Core / View / TerminalUI`, package-layered with `Core`, `View`, `TerminalUI`, and gallery example under `Examples/gallery/`.

**Spec:** [docs/proposals/CELL_PIXEL_METRICS.md](../proposals/CELL_PIXEL_METRICS.md)
**Research:** [docs/CELL_PIXEL_GEOMETRY_RESEARCH.md](../CELL_PIXEL_GEOMETRY_RESEARCH.md)

---

## Overview

Stage 1 is the foundation: a new type, two access points, the SIGWINCH-refresh fix, the internal migration of the image pipeline off the old `package` key, and the physics toy adopting the metric for motion and for adaptive rectangle sizing. Stage 1 ships independently.

Stage 2 extends the Braille-subpixel rasterizer's `Circle` / `Ellipse` / `Capsule` branches to consume `CellPixelMetrics` from the draw-time environment, so the emitted shape is pixel-true on terminals whose cells are not 2:1. The physics toy's visible subject changes from `Rectangle` to `Circle` as the end-to-end demonstration.

## Scope Boundaries

Match the spec's Non-goals section exactly:

- No `PixelPoint`, `PixelRect`, `PixelSize` types.
- No `.frame(pixelWidth:pixelHeight:)`-style modifier.
- No public setter on `GeometryProxy.cellPixelMetrics` or `EnvironmentValues.cellPixelMetrics`.
- No pointer pixel-precision work (out of scope per `docs/VISION.md`).
- No `isHighDensity`-style classifiers.
- No changes to `Layout`, `Alignment`, `Size`, `Point`, `Rect`, `EdgeInsets`.
- No re-running one-shot escape-sequence probes (`CSI 16 t`, `CSI 14 t`, Kitty support, sixel) on SIGWINCH — only the cheap `ioctl` is re-issued.
- **Stage 1 only:** no Shape rasterizer changes.

## File Structure

### New files

| File | Responsibility |
|------|---------------|
| `Sources/Core/CellPixelMetrics.swift` | The `CellPixelMetrics` public struct and its `Source` enum; kept out of the large `GeometryTypes.swift` for focus. |
| `Sources/View/Environment/CellPixelMetricsEnvironment.swift` | The public `EnvironmentValues.cellPixelMetrics` key. |
| `Tests/CoreTests/CellPixelMetricsTests.swift` | Unit tests for `CellPixelMetrics` equality, `aspectRatio`, and the `.estimated` constant. |
| `Tests/ViewTests/CellPixelMetricsEnvironmentTests.swift` | Unit tests for the environment key (default value, round-trip). |
| `Tests/TerminalUITests/CellPixelMetricsRefreshTests.swift` | SIGWINCH-driven refresh integration tests. |
| `Tests/CoreTests/RasterizerAspectCorrectionTests.swift` | Stage 2 — unit tests for the sub-pixel aspect math. |
| `Tests/TerminalUITests/Fixtures/circle-aspect-corrected/` | Stage 2 — new circle/ellipse/capsule fixtures at non-default metrics. |
| `Tests/TerminalUITests/CircleAspectFixtureTests.swift` | Stage 2 — fixture suite binding. |

### Modified files

| File | What changes |
|------|--------------|
| `Sources/View/GeometryReading/GeometryReader.swift` | `GeometryProxy` gains a stored `cellPixelMetrics` field; `GeometryReader.resolveElements` reads the env. |
| `Sources/View/Environment/ImageEnvironment.swift` | Remove `terminalCellPixelSize` key and typealias declaration. |
| `Sources/View/Primitives/Image.swift` | Migrate to `cellPixelMetrics`. |
| `Sources/TerminalUI/RunLoop+Rendering.swift` | Replace the env write with a `CellPixelMetrics` write carrying the right `source`. |
| `Sources/TerminalUI/TerminalHost.swift` | Change `TerminalHost.baselineGraphicsCapabilities()` to unconditionally re-read via `ioctl`. |
| `Sources/TerminalUI/StreamingTerminalHost.swift` | Move `graphicsCapabilities` into the locked state; add `updateCellPixelSize(_:)`. |
| `Sources/TerminalUI/HostedSceneSession.swift` | Add `resize(to:cellPixelSize:)` overload. |
| `Examples/gallery/Sources/GalleryDemoViews/FullScreen.swift` | Stage 1: physics struct takes `metrics:` param; adaptive `blockSize(metrics:)`. Stage 2: swap `Rectangle` → `Circle`; delete `blockSize`. |
| `Examples/gallery/Tests/GalleryDemoViewsTests/PhysicsTabGestureTests.swift` | Update call sites to pass `.estimated`. |
| `Tests/TerminalUITests/GeometryReaderSurfaceTests.swift` | Add an assertion that the proxy exposes the environment's metrics. |
| `Sources/Core/Styling.swift` | Stage 2: add `cellPixelMetrics` field to `StyleEnvironmentSnapshot`. |
| `Sources/View/Environment/Environment.swift` | Stage 2: populate `cellPixelMetrics` on `StyleEnvironmentSnapshot` construction. |
| `Sources/Core/Rasterizer.swift` | Stage 2: `Circle` / `Ellipse` / `Capsule` branches compute aspect-corrected radii. |

### Removed symbols

- `Sources/View/Environment/ImageEnvironment.swift` — `private enum TerminalCellPixelSizeKey` and `package var terminalCellPixelSize: Size`.

---

# Stage 1 — Metric exposure, SIGWINCH refresh, isotropic physics

## Task 1.1 — Create `CellPixelMetrics` type (TDD)

**Files:**
- Create: `Sources/Core/CellPixelMetrics.swift`
- Create: `Tests/CoreTests/CellPixelMetricsTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/CoreTests/CellPixelMetricsTests.swift
import Testing

@testable import Core

@Suite
struct CellPixelMetricsTests {
  @Test("aspect ratio is height divided by width")
  func aspectRatioDivision() {
    let m = CellPixelMetrics(width: 8, height: 16, source: .reported)
    #expect(m.aspectRatio == 2.0)
  }

  @Test("aspect ratio for square cells is 1.0")
  func aspectRatioSquare() {
    let m = CellPixelMetrics(width: 10, height: 10, source: .reported)
    #expect(m.aspectRatio == 1.0)
  }

  @Test("estimated default is 8x16 and flagged as estimated")
  func estimatedDefault() {
    #expect(CellPixelMetrics.estimated.width == 8)
    #expect(CellPixelMetrics.estimated.height == 16)
    #expect(CellPixelMetrics.estimated.source == .estimated)
    #expect(CellPixelMetrics.estimated.aspectRatio == 2.0)
  }

  @Test("equatable discriminates by source")
  func equatableDiscriminatesBySource() {
    let reported = CellPixelMetrics(width: 8, height: 16, source: .reported)
    let estimated = CellPixelMetrics(width: 8, height: 16, source: .estimated)
    #expect(reported != estimated)
  }

  @Test("equatable discriminates by width and height")
  func equatableDiscriminatesByDimensions() {
    let a = CellPixelMetrics(width: 8, height: 16, source: .reported)
    let b = CellPixelMetrics(width: 10, height: 16, source: .reported)
    #expect(a != b)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter CellPixelMetricsTests
```

Expected: compilation failure `cannot find 'CellPixelMetrics' in scope`.

- [ ] **Step 3: Create the type**

```swift
// Sources/Core/CellPixelMetrics.swift
/// Read-only display metrics describing how cells map to device pixels.
///
/// Advisory runtime metadata. TerminalUI's layout, placement, and alignment
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
    /// The terminal reported its cell size via `ioctl` or an escape query.
    case reported
    /// No cell size was reported; this is the conventional 8x16 fallback.
    case estimated
  }

  /// Conventional 8x16 fallback used when the terminal did not report its
  /// cell size. Aspect ratio 2:1.
  public static let estimated = Self(width: 8, height: 16, source: .estimated)
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter CellPixelMetricsTests
```

Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/CellPixelMetrics.swift Tests/CoreTests/CellPixelMetricsTests.swift
git commit -m "feat(core): introduce CellPixelMetrics type with estimated fallback"
```

---

## Task 1.2 — Public environment key for `cellPixelMetrics` (TDD)

**Files:**
- Create: `Sources/View/Environment/CellPixelMetricsEnvironment.swift`
- Create: `Tests/ViewTests/CellPixelMetricsEnvironmentTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/ViewTests/CellPixelMetricsEnvironmentTests.swift
import Testing

@testable import Core
@testable import View

@Suite
struct CellPixelMetricsEnvironmentTests {
  @Test("default environment value is .estimated")
  func defaultValue() {
    let values = EnvironmentValues()
    #expect(values.cellPixelMetrics == .estimated)
  }

  @Test("custom environment value round-trips")
  func customValueRoundTrips() {
    var values = EnvironmentValues()
    let metrics = CellPixelMetrics(width: 12, height: 24, source: .reported)
    values.cellPixelMetrics = metrics
    #expect(values.cellPixelMetrics == metrics)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter CellPixelMetricsEnvironmentTests
```

Expected: compilation failure `value of type 'EnvironmentValues' has no member 'cellPixelMetrics'`.

- [ ] **Step 3: Add the environment key**

```swift
// Sources/View/Environment/CellPixelMetricsEnvironment.swift
public import Core

private enum CellPixelMetricsKey: EnvironmentKey {
  static let defaultValue: CellPixelMetrics = .estimated
}

extension EnvironmentValues {
  /// Read-only cell pixel dimensions for the current terminal surface,
  /// with a confidence flag distinguishing reported values from the
  /// conventional 8x16 fallback.
  public var cellPixelMetrics: CellPixelMetrics {
    get { self[CellPixelMetricsKey.self] }
    set { self[CellPixelMetricsKey.self] = newValue }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter CellPixelMetricsEnvironmentTests
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/View/Environment/CellPixelMetricsEnvironment.swift \
        Tests/ViewTests/CellPixelMetricsEnvironmentTests.swift
git commit -m "feat(view): publish cellPixelMetrics as EnvironmentValues key"
```

---

## Task 1.3 — Add `cellPixelMetrics` to `GeometryProxy` and `GeometryReader` (TDD)

**Files:**
- Modify: `Sources/View/GeometryReading/GeometryReader.swift`
- Modify: `Tests/TerminalUITests/GeometryReaderSurfaceTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/TerminalUITests/GeometryReaderSurfaceTests.swift`:

```swift
  @Test("geometry reader exposes the environment cellPixelMetrics")
  func geometryReaderExposesCellPixelMetrics() {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = Size(width: 40, height: 10)
    environmentValues.cellPixelMetrics = CellPixelMetrics(
      width: 10, height: 20, source: .reported
    )

    let artifacts = DefaultRenderer().render(
      GeometryReader { proxy in
        Text("Aspect \(Int(proxy.cellPixelMetrics.aspectRatio * 10))")
      },
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      )
    )

    // aspectRatio = 20/10 = 2.0; 2.0 * 10 = 20
    #expect(artifacts.rasterSurface.lines.contains("Aspect 20"))
  }

  @Test("geometry reader exposes .estimated when environment is default")
  func geometryReaderDefaultMetrics() {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = Size(width: 40, height: 10)

    let artifacts = DefaultRenderer().render(
      GeometryReader { proxy in
        Text(proxy.cellPixelMetrics.source == .estimated ? "est" : "rep")
      },
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      )
    )

    #expect(artifacts.rasterSurface.lines.contains("est"))
  }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter GeometryReaderSurfaceTests
```

Expected: compilation failure `value of type 'GeometryProxy' has no member 'cellPixelMetrics'`.

- [ ] **Step 3: Modify `GeometryReader.swift`**

Replace the whole file content:

```swift
public import Core

/// A terminal-native geometry proxy.
///
/// For now, the proxy reports the current terminal surface size from the
/// environment rather than a per-container local coordinate space.
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

/// Reads the current terminal geometry and maps it into authored content.
public struct GeometryReader<Content: View>: View, ResolvableView {
  private let content: (GeometryProxy) -> Content

  public init(
    @ViewBuilder content: @escaping (GeometryProxy) -> Content
  ) {
    self.content = content
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let proxy = context.trackingObservableAccess {
      GeometryProxy(
        size: context.environmentValues.terminalSize,
        safeAreaInsets: context.environmentValues.safeAreaInsets,
        cellPixelMetrics: context.environmentValues.cellPixelMetrics
      )
    }
    let view = context.trackingObservableAccess {
      content(proxy)
    }
    return view.resolveElements(in: context)
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter GeometryReaderSurfaceTests
```

Expected: all tests pass (including the pre-existing `geometryReaderExposesTerminalSurfaceSize`).

- [ ] **Step 5: Commit**

```bash
git add Sources/View/GeometryReading/GeometryReader.swift \
        Tests/TerminalUITests/GeometryReaderSurfaceTests.swift
git commit -m "feat(view): expose cellPixelMetrics on GeometryProxy"
```

---

## Task 1.4 — Migrate internal image pipeline off `terminalCellPixelSize`

**Files:**
- Modify: `Sources/View/Environment/ImageEnvironment.swift`
- Modify: `Sources/View/Primitives/Image.swift`

- [ ] **Step 1: Rewrite `ImageEnvironment.swift`, deleting the old key**

Before:

```swift
private enum TerminalCellPixelSizeKey: EnvironmentKey {
  static let defaultValue = Size(width: 8, height: 16)
}

package typealias ImageAssetResolver =
  @Sendable (ImageSource, [String], Size) -> ResolvedImageAsset?

extension EnvironmentValues {
  public var imageResourceRoots: [String] {
    get { self[ImageResourceRootsKey.self] }
    set { self[ImageResourceRootsKey.self] = newValue }
  }

  package var terminalCellPixelSize: Size {
    get { self[TerminalCellPixelSizeKey.self] }
    set { self[TerminalCellPixelSizeKey.self] = newValue }
  }
}
```

After:

```swift
package import Core

private enum ImageResourceRootsKey: EnvironmentKey {
  static let defaultValue: [String] = []
}

package typealias ImageAssetResolver =
  @Sendable (ImageSource, [String], Size) -> ResolvedImageAsset?

extension EnvironmentValues {
  public var imageResourceRoots: [String] {
    get { self[ImageResourceRootsKey.self] }
    set { self[ImageResourceRootsKey.self] = newValue }
  }
}
```

- [ ] **Step 2: Migrate `Image.swift:61`**

Before (line ~61):

```swift
context.environmentValues.terminalCellPixelSize
```

After:

```swift
Size(
  width: context.environmentValues.cellPixelMetrics.width,
  height: context.environmentValues.cellPixelMetrics.height
)
```

Use Grep to locate the exact line number in the current tree before editing; the surrounding context is a call into `ImageAssetResolver` that wants a `Size`.

- [ ] **Step 3: Build to verify migration compiles**

```bash
swift build
```

Expected: clean build. Any remaining `terminalCellPixelSize` reference will fail with `value of type 'EnvironmentValues' has no member 'terminalCellPixelSize'`.

- [ ] **Step 4: Run the existing image tests**

```bash
swift test --filter Image
```

Expected: all image tests pass; behavior unchanged because the resolved `Size` for default metrics is still `Size(8, 16)`.

- [ ] **Step 5: Commit**

```bash
git add Sources/View/Environment/ImageEnvironment.swift \
        Sources/View/Primitives/Image.swift
git commit -m "refactor(view): migrate image pipeline to cellPixelMetrics"
```

---

## Task 1.5 — Runtime publishes `cellPixelMetrics` per frame

**Files:**
- Modify: `Sources/TerminalUI/RunLoop+Rendering.swift`

- [ ] **Step 1: Locate the existing env write**

Use Grep to confirm the current line (~311):

```bash
```
```
Grep `terminalCellPixelSize` under `Sources/TerminalUI/RunLoop+Rendering.swift`. Expected: one match in `resolveContext(for:)`.

- [ ] **Step 2: Replace the env write**

Before:

```swift
effectiveEnvironmentValues.terminalCellPixelSize =
  terminalHost.graphicsCapabilities.cellPixelSize ?? .init(width: 8, height: 16)
```

After:

```swift
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

- [ ] **Step 3: Build and run the full test suite**

```bash
swift build
swift test
```

Expected: clean build. All existing tests pass — this change is observationally a no-op on default-capability hosts because `.estimated` has the same numeric dimensions as the old fallback.

- [ ] **Step 4: Commit**

```bash
git add Sources/TerminalUI/RunLoop+Rendering.swift
git commit -m "feat(runtime): publish CellPixelMetrics each frame with source flag"
```

---

## Task 1.6 — Fix `TerminalHost` SIGWINCH staleness (TDD)

**Files:**
- Modify: `Sources/TerminalUI/TerminalHost.swift`
- Create/Modify: `Tests/TerminalUITests/CellPixelMetricsRefreshTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/TerminalUITests/CellPixelMetricsRefreshTests.swift
import Testing

@testable import Core
@testable import TerminalUI

@Suite
struct CellPixelMetricsRefreshTests {
  /// Mock controller whose reported cellPixelSize can be changed between reads
  /// to simulate a SIGWINCH refresh.
  final class MutableController: TerminalControlling, @unchecked Sendable {
    nonisolated(unsafe) var pixelSize: Size? = Size(width: 8, height: 16)

    func isATTY(_: Int32) -> Bool { true }
    func getAttributes(from _: Int32) throws -> termios { termios() }
    func setAttributes(_: termios, on _: Int32) throws {}
    func windowSize(of _: Int32) throws -> Size { Size(width: 80, height: 24) }
    func cellPixelSize(of _: Int32) throws -> Size? { pixelSize }
    func getFileStatusFlags(of _: Int32) throws -> Int32 { 0 }
    func setFileStatusFlags(_: Int32, on _: Int32) throws {}
    func write(_: String, to _: Int32) throws {}
    func read(from _: Int32, maxBytes _: Int, timeoutMilliseconds _: Int) throws -> [UInt8] { [] }
  }

  @Test("baselineGraphicsCapabilities reflects the latest ioctl read on each access")
  func baselineRefreshes() {
    let controller = MutableController()
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: Size(width: 80, height: 24),
      controller: controller
    )

    #expect(host.graphicsCapabilities.cellPixelSize == Size(width: 8, height: 16))

    controller.pixelSize = Size(width: 10, height: 20)

    #expect(host.graphicsCapabilities.cellPixelSize == Size(width: 10, height: 20))
  }

  @Test("baselineGraphicsCapabilities preserves cached value on transient ioctl failure")
  func baselinePreservesCachedOnFailure() {
    let controller = MutableController()
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: Size(width: 80, height: 24),
      controller: controller
    )
    _ = host.graphicsCapabilities  // prime cache with (8, 16)

    controller.pixelSize = nil

    #expect(host.graphicsCapabilities.cellPixelSize == Size(width: 8, height: 16))
  }
}
```

Note: `TerminalHost.init(..., controller:)` is `package`-visible. If the current initializer does not accept an injected controller, add one in this task's Step 2.

- [ ] **Step 2: Run tests to verify the first fails, second may also fail**

```bash
swift test --filter CellPixelMetricsRefreshTests
```

Expected: `baselineRefreshes` fails with the old cached value still returned. `baselinePreservesCachedOnFailure` passes (the existing code already preserves the cached value when controller fails).

- [ ] **Step 3: Fix `baselineGraphicsCapabilities()`**

Locate the method in `Sources/TerminalUI/TerminalHost.swift` (currently at ~line 1169):

Before:

```swift
private func baselineGraphicsCapabilities() -> TerminalGraphicsCapabilities {
  var capabilities = capabilityProbe.cachedGraphicsCapabilities ?? .none
  if capabilities.cellPixelSize == nil {
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
  // Always attempt a fresh ioctl read. The syscall is cheap and its
  // result is authoritative when the kernel reports pixel dimensions.
  // We only fall back to the cached value if the fresh read returns
  // nil, which preserves previously-probed escape-sequence values
  // (CSI 16 t / CSI 14 t) across frames.
  if let fresh = try? controller.cellPixelSize(of: outputFileDescriptor) {
    capabilities.cellPixelSize = fresh
  }
  capabilityProbe.cachedGraphicsCapabilities = capabilities
  return capabilities
}
```

- [ ] **Step 4: Run tests to verify both pass**

```bash
swift test --filter CellPixelMetricsRefreshTests
```

Expected: both tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TerminalUI/TerminalHost.swift \
        Tests/TerminalUITests/CellPixelMetricsRefreshTests.swift
git commit -m "fix(runtime): refresh cellPixelSize on every baseline read"
```

---

## Task 1.7 — `StreamingTerminalHost.updateCellPixelSize` (TDD)

**Files:**
- Modify: `Sources/TerminalUI/StreamingTerminalHost.swift`
- Modify: `Tests/TerminalUITests/CellPixelMetricsRefreshTests.swift`

- [ ] **Step 1: Append a failing test**

```swift
  @Test("StreamingTerminalHost surface reflects updated cellPixelSize")
  func streamingHostUpdateCellPixelSize() {
    let host = StreamingTerminalHost(
      surfaceSize: Size(width: 80, height: 24),
      graphicsCapabilities: TerminalGraphicsCapabilities(
        cellPixelSize: Size(width: 8, height: 16)
      ),
      outputHandler: { _ in }
    )

    #expect(host.graphicsCapabilities.cellPixelSize == Size(width: 8, height: 16))

    host.updateCellPixelSize(Size(width: 12, height: 24))

    #expect(host.graphicsCapabilities.cellPixelSize == Size(width: 12, height: 24))
  }

  @Test("StreamingTerminalHost clears cell pixel size on nil update")
  func streamingHostClearsCellPixelSize() {
    let host = StreamingTerminalHost(
      surfaceSize: Size(width: 80, height: 24),
      graphicsCapabilities: TerminalGraphicsCapabilities(
        cellPixelSize: Size(width: 10, height: 20)
      ),
      outputHandler: { _ in }
    )

    host.updateCellPixelSize(nil)

    #expect(host.graphicsCapabilities.cellPixelSize == nil)
  }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter CellPixelMetricsRefreshTests
```

Expected: compilation failure `'StreamingTerminalHost' has no member 'updateCellPixelSize'` and potentially `graphicsCapabilities` becoming mutable.

- [ ] **Step 3: Modify `StreamingTerminalHost.swift`**

Move `graphicsCapabilities` from a stored `let` into the locked `State`:

Before (the relevant section at top of the type):

```swift
private struct State: Sendable {
  var surfaceSize: Size
  var renderStyle: TerminalRenderStyle
  var lastSubmittedSurface: RasterSurface?
}

private let state: Mutex<State>
...
package let capabilityProfile: TerminalCapabilityProfile
package let graphicsCapabilities: TerminalGraphicsCapabilities
```

After:

```swift
private struct State: Sendable {
  var surfaceSize: Size
  var renderStyle: TerminalRenderStyle
  var graphicsCapabilities: TerminalGraphicsCapabilities
  var lastSubmittedSurface: RasterSurface?
}

private let state: Mutex<State>
...
package let capabilityProfile: TerminalCapabilityProfile

package var graphicsCapabilities: TerminalGraphicsCapabilities {
  state.withLock(\.graphicsCapabilities)
}
```

Update the initializer to seed `graphicsCapabilities` in the State rather than storing directly:

Before (the init body):

```swift
self.capabilityProfile = capabilityProfile
self.graphicsCapabilities = graphicsCapabilities
...
state = Mutex(
  State(
    surfaceSize: surfaceSize,
    renderStyle: ...,
    lastSubmittedSurface: nil
  )
)
```

After:

```swift
self.capabilityProfile = capabilityProfile
...
state = Mutex(
  State(
    surfaceSize: surfaceSize,
    renderStyle: ...,
    graphicsCapabilities: graphicsCapabilities,
    lastSubmittedSurface: nil
  )
)
```

Add the update method alongside `updateSurfaceSize`:

```swift
package func updateCellPixelSize(_ cellPixelSize: Size?) {
  state.withLock { state in
    state.graphicsCapabilities.cellPixelSize = cellPixelSize
    state.lastSubmittedSurface = nil
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter CellPixelMetricsRefreshTests
```

Expected: both new tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TerminalUI/StreamingTerminalHost.swift \
        Tests/TerminalUITests/CellPixelMetricsRefreshTests.swift
git commit -m "feat(runtime): make StreamingTerminalHost graphicsCapabilities live"
```

---

## Task 1.8 — `HostedSceneSession.resize(to:cellPixelSize:)` overload (TDD)

**Files:**
- Modify: `Sources/TerminalUI/HostedSceneSession.swift`
- Modify: `Tests/TerminalUITests/CellPixelMetricsRefreshTests.swift`

- [ ] **Step 1: Append a failing test**

```swift
  @Test("HostedSceneSession.resize carries cellPixelSize into the host")
  @MainActor
  func hostedResizeUpdatesCellPixelSize() async {
    let session = HostedSceneSession(
      descriptor: .init(id: .init(rawValue: "test"), registryEntry: .empty),
      sessionName: "test",
      initialSize: Size(width: 80, height: 24),
      capabilityProfile: .trueColor,
      appearance: nil,
      theme: nil,
      runScene: { _, _, _ in .normal(.userRequested) },
      onOutput: { _ in }
    )

    session.resize(to: Size(width: 80, height: 24), cellPixelSize: Size(width: 12, height: 24))

    #expect(session.hostGraphicsCapabilitiesForTesting.cellPixelSize == Size(width: 12, height: 24))
  }
```

Add a small `package` accessor on `HostedSceneSession` for testing in the same edit:

```swift
package var hostGraphicsCapabilitiesForTesting: TerminalGraphicsCapabilities {
  host.graphicsCapabilities
}
```

(Using `hostGraphicsCapabilitiesForTesting` avoids leaking the `host` field directly and makes the test intent explicit.)

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter CellPixelMetricsRefreshTests
```

Expected: compilation failure `argument 'cellPixelSize' of 'resize(to:cellPixelSize:)' not declared`.

- [ ] **Step 3: Add the overload**

In `Sources/TerminalUI/HostedSceneSession.swift`, after the existing `resize(to:)`:

```swift
public func resize(
  to size: Size,
  cellPixelSize: Size?
) {
  host.updateSurfaceSize(size)
  host.updateCellPixelSize(cellPixelSize)
  signalReader.send("SIGWINCH")
}
```

Also add the testing accessor declared in Step 1.

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter CellPixelMetricsRefreshTests
```

Expected: test passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/TerminalUI/HostedSceneSession.swift \
        Tests/TerminalUITests/CellPixelMetricsRefreshTests.swift
git commit -m "feat(runtime): HostedSceneSession.resize accepts cellPixelSize"
```

---

## Task 1.9 — End-to-end SIGWINCH refresh integration test

**Files:**
- Modify: `Tests/TerminalUITests/CellPixelMetricsRefreshTests.swift`

- [ ] **Step 1: Append the integration test**

This test renders through a `GeometryReader` across a simulated resize, asserting the proxy observes the new metrics on the next frame.

```swift
  @Test("SIGWINCH-driven refresh surfaces new metrics in the next GeometryReader proxy")
  @MainActor
  func sigwinchRefreshSurfacesInProxy() async {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = Size(width: 40, height: 10)
    environmentValues.cellPixelMetrics = CellPixelMetrics(
      width: 8, height: 16, source: .reported
    )

    let first = DefaultRenderer().render(
      GeometryReader { proxy in
        Text("w=\(proxy.cellPixelMetrics.width)")
      },
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      )
    )
    #expect(first.rasterSurface.lines.contains("w=8"))

    environmentValues.cellPixelMetrics = CellPixelMetrics(
      width: 12, height: 24, source: .reported
    )

    let second = DefaultRenderer().render(
      GeometryReader { proxy in
        Text("w=\(proxy.cellPixelMetrics.width)")
      },
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      )
    )
    #expect(second.rasterSurface.lines.contains("w=12"))
  }
```

- [ ] **Step 2: Run test to verify it passes**

```bash
swift test --filter CellPixelMetricsRefreshTests
```

Expected: passes (no production code changes needed — Tasks 1.1–1.5 already delivered the plumbing this test exercises).

- [ ] **Step 3: Commit**

```bash
git add Tests/TerminalUITests/CellPixelMetricsRefreshTests.swift
git commit -m "test(runtime): assert cellPixelMetrics refresh reaches GeometryReader proxy"
```

---

## Task 1.10 — Physics toy adopts `CellPixelMetrics` (Stage 1, rectangle subject)

**Files:**
- Modify: `Examples/gallery/Sources/GalleryDemoViews/FullScreen.swift`
- Modify: `Examples/gallery/Tests/GalleryDemoViewsTests/PhysicsTabGestureTests.swift`

- [ ] **Step 1: Update `FullScreenToyPhysics` signatures to accept metrics**

Replace the `blockSize` constant and thread `metrics: CellPixelMetrics` through `step`, `spawnState`, `displayPosition`, `applyRelease`, and the `maximumOrigin` helpers.

Key snippets (merge into the existing file — do not duplicate the physics constants; this is the delta only):

```swift
struct FullScreenToyPhysics {
  static let blockWidth = 6
  static let fixedScale = 16
  // ...existing constants unchanged...

  /// Height of the rectangular subject in cells, scaled so its *visual*
  /// aspect is square regardless of the terminal's cell aspect.
  static func blockSize(metrics: CellPixelMetrics) -> Size {
    let height = max(1, Int((Double(blockWidth) / metrics.aspectRatio).rounded()))
    return Size(width: blockWidth, height: height)
  }

  static func displayPosition(
    for state: State,
    dragOffset: Size,
    in bounds: Size,
    metrics: CellPixelMetrics
  ) -> Point {
    let dragged = FixedPoint(
      x: state.position.x + dragOffset.width * fixedScale,
      y: state.position.y + dragOffset.height * fixedScale
    )
    let clampedPoint = clamped(dragged, in: bounds, metrics: metrics)
    return Point(
      x: clampedPoint.x / fixedScale,
      y: clampedPoint.y / fixedScale
    )
  }

  static func applyRelease(
    to state: inout State,
    translation: Size,
    velocity: Size,
    in bounds: Size,
    metrics: CellPixelMetrics
  ) {
    state.position.x += translation.width * fixedScale
    state.position.y += translation.height * fixedScale
    state = clamped(state, in: bounds, metrics: metrics)
    state.velocity = releaseVelocity(from: velocity, metrics: metrics)
  }

  static func spawnState(
    in bounds: Size,
    metrics: CellPixelMetrics
  ) -> State {
    let maximumOrigin = maximumOrigin(in: bounds, metrics: metrics)
    return State(
      position: .init(
        x: maximumOrigin.x / 2,
        y: maximumOrigin.y
      ),
      velocity: .init(
        x: initialLaunchX,
        y: initialLaunchY
      )
    )
  }

  static func releaseVelocity(
    from gestureVelocity: Size,
    metrics: CellPixelMetrics
  ) -> FixedVelocity {
    FixedVelocity(
      x: fixedVelocityComponent(fromCellsPerSecond: gestureVelocity.width),
      y: fixedVelocityComponent(
        fromCellsPerSecond: Int(
          (Double(gestureVelocity.height) / metrics.aspectRatio).rounded()
        )
      )
    )
  }

  static func step(
    _ state: inout State,
    in bounds: Size,
    metrics: CellPixelMetrics
  ) {
    state = clamped(state, in: bounds, metrics: metrics)
    let maximumOrigin = maximumOrigin(in: bounds, metrics: metrics)

    if state.position.y == maximumOrigin.y && state.velocity.y == 0 {
      state.velocity.x = damped(
        state.velocity.x,
        numerator: floorFrictionNumerator,
        denominator: floorFrictionDenominator,
        zeroBelow: 1
      )
    } else {
      // Gravity is scaled by aspectRatio so the visible downward
      // acceleration matches the horizontal impulse magnitude.
      let scaledGravity = max(
        1,
        Int((Double(gravityPerTick) / metrics.aspectRatio).rounded())
      )
      state.velocity.y += scaledGravity
    }

    // ...remainder of step unchanged, using `maximumOrigin` captured above...
  }

  static func maximumOrigin(
    in bounds: Size,
    metrics: CellPixelMetrics
  ) -> FixedPoint {
    let block = blockSize(metrics: metrics)
    return FixedPoint(
      x: max(0, bounds.width - block.width) * fixedScale,
      y: max(0, bounds.height - block.height) * fixedScale
    )
  }

  static func clamped(
    _ state: State,
    in bounds: Size,
    metrics: CellPixelMetrics
  ) -> State {
    var state = state
    state.position = clamped(state.position, in: bounds, metrics: metrics)
    return state
  }

  private static func clamped(
    _ point: FixedPoint,
    in bounds: Size,
    metrics: CellPixelMetrics
  ) -> FixedPoint {
    let maximumOrigin = maximumOrigin(in: bounds, metrics: metrics)
    return FixedPoint(
      x: min(max(0, point.x), maximumOrigin.x),
      y: min(max(0, point.y), maximumOrigin.y)
    )
  }
}
```

All existing per-axis bounce code inside `step` stays unchanged — the `maximumOrigin` computed with `metrics:` is the only new input.

- [ ] **Step 2: Update `PhysicsTab` body**

The view reads `proxy.cellPixelMetrics` and threads it through every call:

```swift
var body: some View {
  GeometryReader { proxy in
    let bounds = proxy.size
    let metrics = proxy.cellPixelMetrics
    let playfieldBounds = FullScreenToyPhysics.playfieldBounds(from: bounds)
    let current = FullScreenToyPhysics.displayPosition(
      for: toyState,
      dragOffset: dragOffset,
      in: playfieldBounds,
      metrics: metrics
    )
    let block = FullScreenToyPhysics.blockSize(metrics: metrics)

    ZStack(alignment: .topLeading) {
      Rectangle()
        .frame(width: block.width, height: block.height)
        .offset(x: current.x, y: current.y)
        .foregroundStyle(.cyan)
        .gesture(dragGesture(in: playfieldBounds, metrics: metrics))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color.black)
    .task(id: FullScreenToyPhysics.BoundsID(size: playfieldBounds)) { @MainActor in
      await runToyLoop(in: playfieldBounds, metrics: metrics)
    }
  }
  .padding(2)
  .background(.tint)
}

private func dragGesture(
  in bounds: Size,
  metrics: CellPixelMetrics
) -> some Gesture {
  DragGesture()
    .updating($gestureIsActive) { _, state, _ in
      state = true
    }
    .updating($dragOffset) { value, state, _ in
      state = value.translation
    }
    .onEnded { value in
      FullScreenToyPhysics.applyRelease(
        to: &toyState,
        translation: value.translation,
        velocity: value.velocity,
        in: bounds,
        metrics: metrics
      )
    }
}

@MainActor
private func runToyLoop(
  in bounds: Size,
  metrics: CellPixelMetrics
) async {
  if !didSeedInitialPosition {
    toyState = FullScreenToyPhysics.spawnState(in: bounds, metrics: metrics)
    didSeedInitialPosition = true
  } else {
    toyState = FullScreenToyPhysics.clamped(toyState, in: bounds, metrics: metrics)
  }

  while !Task.isCancelled {
    try? await Task.sleep(nanoseconds: FullScreenToyPhysics.tickNanoseconds)
    guard !gestureIsActive else {
      continue
    }

    var next = toyState
    FullScreenToyPhysics.step(&next, in: bounds, metrics: metrics)
    guard next != toyState else {
      continue
    }
    toyState = next
  }
}
```

- [ ] **Step 3: Update the existing gesture test to pass `.estimated`**

In `Examples/gallery/Tests/GalleryDemoViewsTests/PhysicsTabGestureTests.swift`, add `metrics: .estimated` to every `FullScreenToyPhysics` call site. Locate with:

```bash
```
Grep `FullScreenToyPhysics\.(step\|spawnState\|applyRelease\|displayPosition\|clamped\|maximumOrigin)` in that file and append `, metrics: .estimated` to every call (and ensure `@testable import Core` is present).

- [ ] **Step 4: Build and run gallery tests**

```bash
cd Examples/gallery
swift build
swift test
cd ../..
```

Expected: build succeeds; existing gesture assertions remain numerically identical because `.estimated.aspectRatio == 2.0` matches the old implicit assumption.

- [ ] **Step 5: Commit**

```bash
git add Examples/gallery/Sources/GalleryDemoViews/FullScreen.swift \
        Examples/gallery/Tests/GalleryDemoViewsTests/PhysicsTabGestureTests.swift
git commit -m "feat(gallery): physics toy consumes CellPixelMetrics for isotropic motion"
```

---

## Task 1.11 — Stage 1 documentation

**Files:**
- Create: `Sources/Core/Core.docc/CellPixelMetrics.md`
- Modify: `docs/PUBLIC_API_INVENTORY.md`
- Modify: `docs/RUNTIME.md`

- [ ] **Step 1: Write the DocC article for `CellPixelMetrics`**

```markdown
# ``Core/CellPixelMetrics``

Read-only display metrics describing how terminal cells map to device pixels.

## Overview

TerminalUI measures layout in integer cells. `CellPixelMetrics` is advisory
runtime metadata that tells you how those cells map to pixels on the current
terminal — so you can apply aspect correction to shapes, motion, or image
sizing without reinventing the fallback.

Access via ``/View/GeometryProxy/cellPixelMetrics`` inside a `GeometryReader`,
or via ``/View/EnvironmentValues/cellPixelMetrics`` anywhere an environment
is available.

The value always has honest dimensions: either the terminal reported them
(`source == .reported`) or they are the conventional 8x16 fallback
(`source == .estimated`). Check `source` before making decisions that
require pixel accuracy.

## Topics

### Reading the metrics

- ``width``
- ``height``
- ``aspectRatio``
- ``source``

### Fallback value

- ``estimated``

### Related discussion

- [Cell Pixel Geometry Research](https://github.com/adamz/swift-terminal-ui/blob/main/docs/CELL_PIXEL_GEOMETRY_RESEARCH.md)
```

- [ ] **Step 2: Add the entries to `docs/PUBLIC_API_INVENTORY.md`**

Under the existing "Core geometry" section (locate with `grep -n "geometry" docs/PUBLIC_API_INVENTORY.md`), append:

```markdown
- **`CellPixelMetrics`** (`Core`): read-only display metrics describing how cells map to device pixels. Exposes `width`, `height`, `source` (`.reported` / `.estimated`), derived `aspectRatio`, and the `.estimated` fallback constant. Consumed via `GeometryProxy.cellPixelMetrics` and `EnvironmentValues.cellPixelMetrics`.
```

- [ ] **Step 3: Document the SIGWINCH refresh in `docs/RUNTIME.md`**

Under the existing lifecycle / resize section, add:

```markdown
### Cell pixel size refresh

`TerminalHost` re-reads `cellPixelSize` on every access to
`baselineGraphicsCapabilities()` via `ioctl(TIOCGWINSZ)` (a single cheap
syscall). Escape-sequence probes — `CSI 16 t`, `CSI 14 t`, Kitty support,
sixel capability — remain one-shot at startup; only cell pixel dimensions
are live. Hosted sessions can simulate a cell-pixel-size change in tests
via `HostedSceneSession.resize(to:cellPixelSize:)`.
```

- [ ] **Step 4: Verify docs build (if DocC check is part of `swift build`)**

```bash
swift build
```

Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Core.docc/CellPixelMetrics.md \
        docs/PUBLIC_API_INVENTORY.md \
        docs/RUNTIME.md
git commit -m "docs: publish CellPixelMetrics and SIGWINCH refresh story"
```

---

## Stage 1 checkpoint

At this point stage 1 is complete and shippable. Run the whole test suite:

```bash
swift test
```

Expected: clean. The gallery physics toy now applies aspect-corrected motion with an adaptive rectangular subject. Shape rendering is unchanged — `Circle` remains subpixel-naive until Stage 2.

---

# Stage 2 — Shape aspect correction and circular subject

## Task 2.1 — Extend `StyleEnvironmentSnapshot` with `cellPixelMetrics`

**Files:**
- Modify: `Sources/Core/Styling.swift`

- [ ] **Step 1: Add the field and initializer param**

In `StyleEnvironmentSnapshot` (around line 450), add a stored `cellPixelMetrics` alongside the existing lightweight fields. `CellPixelMetrics` is ~24 bytes — keep it out of `StyleHeavyFieldsStorage`.

Diff:

```swift
public struct StyleEnvironmentSnapshot: Equatable, Sendable {
  package var heavyFields: StyleHeavyFieldsStorage

  public var appearance: TerminalAppearance { heavyFields.appearance }
  public var theme: Theme { heavyFields.theme }
  public var foregroundStyle: AnyShapeStyle?
  public var tintStyle: AnyShapeStyle?
  public var isEnabled: Bool
  public var cellPixelMetrics: CellPixelMetrics       // NEW

  public init(
    appearance: TerminalAppearance = .fallback,
    theme: Theme? = nil,
    foregroundStyle: AnyShapeStyle? = nil,
    tintStyle: AnyShapeStyle? = nil,
    isEnabled: Bool = true,
    cellPixelMetrics: CellPixelMetrics = .estimated    // NEW
  ) {
    self.heavyFields = StyleHeavyFieldsStorage(
      appearance: appearance,
      theme: theme ?? appearance.synthesizedTheme()
    )
    self.foregroundStyle = foregroundStyle
    self.tintStyle = tintStyle
    self.isEnabled = isEnabled
    self.cellPixelMetrics = cellPixelMetrics
  }

  package init(
    heavyFields: StyleHeavyFieldsStorage,
    foregroundStyle: AnyShapeStyle?,
    tintStyle: AnyShapeStyle?,
    isEnabled: Bool,
    cellPixelMetrics: CellPixelMetrics = .estimated    // NEW
  ) {
    self.heavyFields = heavyFields
    self.foregroundStyle = foregroundStyle
    self.tintStyle = tintStyle
    self.isEnabled = isEnabled
    self.cellPixelMetrics = cellPixelMetrics
  }
}
```

- [ ] **Step 2: Build — expect compilation errors at snapshot construction sites**

```bash
swift build
```

Expected: compiler error at `Sources/View/Environment/Environment.swift:142` and `:149` — two `StyleEnvironmentSnapshot(...)` calls missing the new argument. They compile because the parameter has a default, but we want the callers explicit.

- [ ] **Step 3: Commit the snapshot shape change alone**

```bash
git add Sources/Core/Styling.swift
git commit -m "feat(core): add cellPixelMetrics to StyleEnvironmentSnapshot"
```

---

## Task 2.2 — Populate `cellPixelMetrics` into the resolve-time snapshot

**Files:**
- Modify: `Sources/View/Environment/Environment.swift`

- [ ] **Step 1: Thread the metric through both `StyleEnvironmentSnapshot` constructions**

In `EnvironmentValues.applying(to:reuseStyle:)` at `Sources/View/Environment/Environment.swift:~140`:

Before:

```swift
if reuseStyle {
  style = StyleEnvironmentSnapshot(
    heavyFields: snapshot.style.heavyFields,
    foregroundStyle: foregroundStyle,
    tintStyle: tintStyle,
    isEnabled: isEnabled
  )
} else {
  style = StyleEnvironmentSnapshot(
    appearance: terminalAppearance,
    theme: theme,
    foregroundStyle: foregroundStyle,
    tintStyle: tintStyle,
    isEnabled: isEnabled
  )
}
```

After:

```swift
if reuseStyle {
  style = StyleEnvironmentSnapshot(
    heavyFields: snapshot.style.heavyFields,
    foregroundStyle: foregroundStyle,
    tintStyle: tintStyle,
    isEnabled: isEnabled,
    cellPixelMetrics: cellPixelMetrics
  )
} else {
  style = StyleEnvironmentSnapshot(
    appearance: terminalAppearance,
    theme: theme,
    foregroundStyle: foregroundStyle,
    tintStyle: tintStyle,
    isEnabled: isEnabled,
    cellPixelMetrics: cellPixelMetrics
  )
}
```

- [ ] **Step 2: Build and run tests**

```bash
swift build
swift test
```

Expected: clean; no behavior change (rasterizer hasn't started consuming the new snapshot field yet, but the plumbing is verified live).

- [ ] **Step 3: Commit**

```bash
git add Sources/View/Environment/Environment.swift
git commit -m "feat(view): plumb cellPixelMetrics into draw-time StyleEnvironmentSnapshot"
```

---

## Task 2.3 — Unit tests for sub-pixel aspect math (TDD)

**Files:**
- Create: `Tests/CoreTests/RasterizerAspectCorrectionTests.swift`

- [ ] **Step 1: Define the math helper and failing tests**

We'll add a small `package`-visible helper to `Rasterizer.swift` in the next task. Right now, write tests that pin the expected mapping from `(frameCells, metrics)` to `(rxSubpixels, rySubpixels)`.

```swift
// Tests/CoreTests/RasterizerAspectCorrectionTests.swift
import Testing

@testable import Core

@Suite
struct RasterizerAspectCorrectionTests {
  /// At the default 8x16 metrics the subpixel aspect is square, so a
  /// circle's x and y radii in subpixel space are identical.
  @Test("8x16 metrics produce equal sub-pixel radii for a square frame")
  func squareFrameAtDefaultMetrics() {
    let radii = Rasterizer.subpixelCircleRadii(
      frameCells: Size(width: 6, height: 3),
      metrics: .estimated
    )
    // Frame pixel dims: 6*8=48 wide, 3*16=48 tall. Diameter=48. Radius=24px.
    // 24px / (8/2=4px per x-subpixel) = 6
    // 24px / (16/4=4px per y-subpixel) = 6
    #expect(radii.rx == 6)
    #expect(radii.ry == 6)
  }

  /// Cells stretched horizontally (10x16) mean y-subpixels are shorter;
  /// the y-radius in subpixels increases to compensate.
  @Test("stretched-width metrics widen the x-axis, extend y-radii in subpixels")
  func stretchedWidthMetrics() {
    let radii = Rasterizer.subpixelCircleRadii(
      frameCells: Size(width: 6, height: 6),
      metrics: CellPixelMetrics(width: 10, height: 16, source: .reported)
    )
    // Frame pixel dims: 6*10=60 wide, 6*16=96 tall. Diameter=60. Radius=30px.
    // 30px / (10/2=5px per x-subpixel) = 6
    // 30px / (16/4=4px per y-subpixel) = 7 (rounded from 7.5)
    #expect(radii.rx == 6)
    #expect(radii.ry == 7 || radii.ry == 8)
  }

  /// At aspectRatio=2.0 the rasterizer must produce the exact same
  /// subpixel radii as the pre-correction code so existing fixtures do
  /// not change.
  @Test("aspectRatio 2.0 is a no-op vs. the pre-correction formula")
  func aspectRatio2IsNoOp() {
    let frame = Size(width: 10, height: 5)
    let radii = Rasterizer.subpixelCircleRadii(
      frameCells: frame,
      metrics: .estimated
    )
    // Pre-correction: min(subW, subH) - 1 / 2 with subW=20, subH=20 → 9 or 10.
    // Post-correction: same answer because subpixels are square at 2.0.
    #expect(radii.rx == radii.ry)
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter RasterizerAspectCorrectionTests
```

Expected: compilation failure `type 'Rasterizer' has no member 'subpixelCircleRadii'`.

- [ ] **Step 3: Add the helper to `Rasterizer.swift`**

Add, near the top of `Rasterizer.swift`, a `package` static helper:

```swift
extension Rasterizer {
  package struct SubpixelRadii: Equatable {
    package let rx: Int
    package let ry: Int
  }

  /// Given a cell frame and the current cell-pixel metrics, computes the
  /// largest pixel-true circle's radii in Braille sub-pixel units.
  /// Sub-pixel dimensions are `cellPixelMetrics.width / 2` and
  /// `cellPixelMetrics.height / 4`.
  package static func subpixelCircleRadii(
    frameCells: Size,
    metrics: CellPixelMetrics
  ) -> SubpixelRadii {
    let subpixelPxWidth = max(1, metrics.width / 2)
    let subpixelPxHeight = max(1, metrics.height / 4)
    let pxWidth = frameCells.width * metrics.width
    let pxHeight = frameCells.height * metrics.height
    let diameterPx = max(0, min(pxWidth, pxHeight))
    let radiusPx = diameterPx / 2
    return SubpixelRadii(
      rx: radiusPx / subpixelPxWidth,
      ry: radiusPx / subpixelPxHeight
    )
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter RasterizerAspectCorrectionTests
```

Expected: all three tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Rasterizer.swift Tests/CoreTests/RasterizerAspectCorrectionTests.swift
git commit -m "feat(raster): add subpixel radius helper for aspect-corrected shapes"
```

---

## Task 2.4 — `Circle` rasterizer branch uses aspect-corrected radii

**Files:**
- Modify: `Sources/Core/Rasterizer.swift`

- [ ] **Step 1: Locate the circle branch**

Current code (around line 1040):

```swift
switch geometry {
case .circle:
  let radius = max(0, (min(subW, subH) - 1) / 2)
  if stroke {
    canvas.strokeCircle(centerX: cx, centerY: cy, radius: radius)
  } else {
    canvas.fillCircle(centerX: cx, centerY: cy, radius: radius)
  }
...
}
```

The surrounding function takes `environment: StyleEnvironmentSnapshot` — use it to read the metrics.

- [ ] **Step 2: Replace the circle branch**

```swift
case .circle:
  let radii = Self.subpixelCircleRadii(
    frameCells: Size(width: cellW, height: cellH),
    metrics: environment.cellPixelMetrics
  )
  // Delegate to the ellipse path since x and y radii may differ when
  // sub-pixels are non-square. The existing -1 clamp in the naive
  // path reflected inclusive bound semantics; preserve it here.
  let rx = max(0, radii.rx - 1)
  let ry = max(0, radii.ry - 1)
  if stroke {
    canvas.strokeEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
  } else {
    canvas.fillEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
  }
```

- [ ] **Step 3: Run the shape fixture tests**

```bash
swift test --filter CircleEllipseCapsule
```

Expected: all pre-existing circle fixtures at 8x16 pass unchanged, because `subpixelCircleRadii(frame, .estimated)` produces `rx == ry` equal to the old `min(subW, subH) / 2`.

- [ ] **Step 4: Commit**

```bash
git add Sources/Core/Rasterizer.swift
git commit -m "feat(raster): Circle computes aspect-corrected sub-pixel radii"
```

---

## Task 2.5 — `Ellipse` rasterizer branch uses aspect-corrected radii

**Files:**
- Modify: `Sources/Core/Rasterizer.swift`

- [ ] **Step 1: Locate the ellipse branch**

Current code (same switch as Task 2.4):

```swift
case .ellipse:
  let rx = max(0, (subW - 1) / 2)
  let ry = max(0, (subH - 1) / 2)
  if stroke {
    canvas.strokeEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
  } else {
    canvas.fillEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
  }
```

- [ ] **Step 2: Replace with aspect-corrected semi-axes**

```swift
case .ellipse:
  let metrics = environment.cellPixelMetrics
  let subpixelPxWidth = max(1, metrics.width / 2)
  let subpixelPxHeight = max(1, metrics.height / 4)
  let halfWidthPx = (cellW * metrics.width) / 2
  let halfHeightPx = (cellH * metrics.height) / 2
  let rx = max(0, halfWidthPx / subpixelPxWidth - 1)
  let ry = max(0, halfHeightPx / subpixelPxHeight - 1)
  if stroke {
    canvas.strokeEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
  } else {
    canvas.fillEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
  }
```

At `.estimated` metrics (8x16), `halfWidthPx/subpixelPxWidth = (cellW*8)/2/4 = cellW`, identical to the old `subW/2 = cellW` — so 8x16 fixtures are unchanged.

- [ ] **Step 3: Run shape tests**

```bash
swift test --filter CircleEllipseCapsule
```

Expected: all existing ellipse fixtures pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/Core/Rasterizer.swift
git commit -m "feat(raster): Ellipse computes aspect-corrected semi-axes"
```

---

## Task 2.6 — `Capsule` rasterizer branch uses aspect-corrected caps

**Files:**
- Modify: `Sources/Core/Rasterizer.swift`

- [ ] **Step 1: Locate the capsule branch**

The current Capsule branch calls a helper `drawCapsule(into:stroke:)`. Grep for its definition:

```bash
```
Grep `drawCapsule` in `Sources/Core/Rasterizer.swift`. Expected: one definition with access to `subW`, `subH` and the canvas.

- [ ] **Step 2: Extend `drawCapsule` to accept metrics**

The capsule is two semicircular caps joined by a rectangle. Update the helper signature:

```swift
private func drawCapsule(
  into canvas: inout BrailleCanvas,
  stroke: Bool,
  metrics: CellPixelMetrics
) {
  let subpixelPxWidth = max(1, metrics.width / 2)
  let subpixelPxHeight = max(1, metrics.height / 4)
  let cellW = canvas.width / 2          // derive cells from subpixel bounds
  let cellH = canvas.height / 4
  let pxWidth = cellW * metrics.width
  let pxHeight = cellH * metrics.height
  let radiusPx = min(pxWidth, pxHeight) / 2
  let rx = max(0, radiusPx / subpixelPxWidth - 1)
  let ry = max(0, radiusPx / subpixelPxHeight - 1)
  // Draw the left and right semicircular caps plus the straight
  // section in the middle. Existing capsule layout logic remains
  // in place; only the radii values change.
  // (Preserve whatever drawCapsule currently does for the straight
  // section and apply `rx`, `ry` to the cap endpoints.)
}
```

In the capsule branch at the switch, update the call:

```swift
case .capsule:
  drawCapsule(into: &canvas, stroke: stroke, metrics: environment.cellPixelMetrics)
```

Important: the actual shape of `drawCapsule`'s body depends on the current implementation — inspect it before this step and adjust. The critical change is that wherever it currently uses `min(subW, subH)` or subpixel-based radii, swap those for the pixel-based `rx` / `ry` computed above.

- [ ] **Step 3: Run shape tests**

```bash
swift test --filter CircleEllipseCapsule
```

Expected: pre-existing capsule fixtures still pass at 8x16.

- [ ] **Step 4: Commit**

```bash
git add Sources/Core/Rasterizer.swift
git commit -m "feat(raster): Capsule caps use aspect-corrected radii"
```

---

## Task 2.7 — Non-default-aspect fixture suite

**Files:**
- Create: `Tests/TerminalUITests/Fixtures/circle-aspect-corrected/6x6-at-8x16.txt`
- Create: `Tests/TerminalUITests/Fixtures/circle-aspect-corrected/6x6-at-10x16.txt`
- Create: `Tests/TerminalUITests/Fixtures/circle-aspect-corrected/6x6-at-6x14.txt`
- Create: `Tests/TerminalUITests/CircleAspectFixtureTests.swift`

- [ ] **Step 1: Generate baseline fixtures from the current rasterizer**

Use an ad-hoc test to print the rendered output for each metric and capture it manually the first time. The test itself reads the fixture file back and compares.

```swift
// Tests/TerminalUITests/CircleAspectFixtureTests.swift
import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct CircleAspectFixtureTests {
  @Test("circle renders true at 8x16 cells", arguments: [
    ("6x6-at-8x16", CellPixelMetrics(width: 8, height: 16, source: .reported)),
    ("6x6-at-10x16", CellPixelMetrics(width: 10, height: 16, source: .reported)),
    ("6x6-at-6x14", CellPixelMetrics(width: 6, height: 14, source: .reported)),
  ])
  func circleFixture(_ tuple: (String, CellPixelMetrics)) throws {
    let (name, metrics) = tuple
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = Size(width: 8, height: 8)
    environmentValues.cellPixelMetrics = metrics

    let artifacts = DefaultRenderer().render(
      Circle().frame(width: 6, height: 6).foregroundStyle(.cyan),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      )
    )
    let rendered = artifacts.rasterSurface.lines.joined(separator: "\n")

    let fixturePath = "Tests/TerminalUITests/Fixtures/circle-aspect-corrected/\(name).txt"
    let fixture = try String(contentsOfFile: fixturePath, encoding: .utf8)

    #expect(rendered == fixture.trimmingCharacters(in: .newlines))
  }
}
```

- [ ] **Step 2: Run to discover fixture paths; write fixtures on first failure**

```bash
swift test --filter CircleAspectFixtureTests
```

Expected: fails with "no such file". On each failure, run a one-off capture (see Step 3) and write the generated output to the target fixture path.

- [ ] **Step 3: Capture current output for each fixture**

Add a temporary test in a scratch target:

```swift
@Test("capture")
func capture() {
  var env = EnvironmentValues()
  env.terminalSize = Size(width: 8, height: 8)
  env.cellPixelMetrics = CellPixelMetrics(width: 10, height: 16, source: .reported)
  let artifacts = DefaultRenderer().render(
    Circle().frame(width: 6, height: 6).foregroundStyle(.cyan),
    context: .init(identity: testIdentity("Root"), environmentValues: env)
  )
  print(artifacts.rasterSurface.lines.joined(separator: "\n"))
}
```

Run, copy the output to `Tests/TerminalUITests/Fixtures/circle-aspect-corrected/6x6-at-10x16.txt`. Repeat for the other two metrics. Delete the temporary capture test before committing.

- [ ] **Step 4: Verify the fixture tests pass**

```bash
swift test --filter CircleAspectFixtureTests
```

Expected: all three fixture comparisons pass.

- [ ] **Step 5: Commit**

```bash
git add Tests/TerminalUITests/Fixtures/circle-aspect-corrected/ \
        Tests/TerminalUITests/CircleAspectFixtureTests.swift
git commit -m "test(raster): pin Circle output at non-default cell aspects"
```

---

## Task 2.8 — Physics toy swaps `Rectangle` for `Circle`

**Files:**
- Modify: `Examples/gallery/Sources/GalleryDemoViews/FullScreen.swift`
- Modify: `Examples/gallery/Tests/GalleryDemoViewsTests/PhysicsTabGestureTests.swift`

- [ ] **Step 1: Delete `blockSize(metrics:)`; introduce `diameter`**

Replace:

```swift
static func blockSize(metrics: CellPixelMetrics) -> Size {
  let height = max(1, Int((Double(blockWidth) / metrics.aspectRatio).rounded()))
  return Size(width: blockWidth, height: height)
}
```

With:

```swift
/// Cell-width of the circular subject. Height is derived at the view
/// layer from `cellPixelMetrics.aspectRatio` so the cell frame is
/// visually square; the `Circle` rasterizer then applies its own
/// sub-pixel aspect correction.
static let diameter = 6
```

Within `FullScreenToyPhysics`, wherever `blockSize(metrics: metrics)` was used for `maximumOrigin`, keep the existing height-via-aspect logic inline:

```swift
static func maximumOrigin(
  in bounds: Size,
  metrics: CellPixelMetrics
) -> FixedPoint {
  let height = max(1, Int((Double(diameter) / metrics.aspectRatio).rounded()))
  return FixedPoint(
    x: max(0, bounds.width - diameter) * fixedScale,
    y: max(0, bounds.height - height) * fixedScale
  )
}
```

- [ ] **Step 2: Swap the subject view**

In `PhysicsTab.body`:

```swift
let metrics = proxy.cellPixelMetrics
let height = max(1, Int((Double(FullScreenToyPhysics.diameter) / metrics.aspectRatio).rounded()))

ZStack(alignment: .topLeading) {
  Circle()
    .frame(width: FullScreenToyPhysics.diameter, height: height)
    .offset(x: current.x, y: current.y)
    .foregroundStyle(.cyan)
    .gesture(dragGesture(in: playfieldBounds, metrics: metrics))
}
```

- [ ] **Step 3: Update gallery tests**

Any place in `PhysicsTabGestureTests.swift` referring to `blockSize(metrics:)` becomes:

```swift
let height = max(1, Int((Double(FullScreenToyPhysics.diameter) / CellPixelMetrics.estimated.aspectRatio).rounded()))
let block = Size(width: FullScreenToyPhysics.diameter, height: height)
```

- [ ] **Step 4: Build and run gallery tests**

```bash
cd Examples/gallery
swift build
swift test
cd ../..
```

Expected: clean build, gesture tests pass with equivalent numerics (`blockWidth=6, height=3` at `.estimated`, same as stage 1).

- [ ] **Step 5: Commit**

```bash
git add Examples/gallery/Sources/GalleryDemoViews/FullScreen.swift \
        Examples/gallery/Tests/GalleryDemoViewsTests/PhysicsTabGestureTests.swift
git commit -m "feat(gallery): physics toy subject becomes an aspect-correct Circle"
```

---

## Task 2.9 — Stage 2 documentation

**Files:**
- Create: `Sources/View/View.docc/AspectCorrectShapes.md`
- Modify: `Sources/View/Shapes/Circle.swift` (doc comment)
- Modify: `Sources/View/Shapes/Ellipse.swift` (doc comment)
- Modify: `Sources/View/Shapes/Capsule.swift` (doc comment)

- [ ] **Step 1: Write the DocC article**

```markdown
# Aspect-correct shapes in terminals

TerminalUI's Braille-subpixel shape rasterizer consumes
``Core/CellPixelMetrics`` from the resolve environment so that
``Circle``, ``Ellipse``, and ``Capsule`` render honestly regardless of
the terminal's cell aspect ratio.

## The math in one paragraph

A Braille subpixel is `cellPixelMetrics.width / 2` pixels wide and
`cellPixelMetrics.height / 4` pixels tall. At the conventional 8x16 cell
these are both 4 pixels, so subpixels are square and circles "just work."
On terminals with different cell aspect — say 10x16 — subpixels are
oblong (5x4), and the rasterizer scales the x and y semi-axes
independently in subpixel units so the emitted pixel shape is true.

## Worked example

The gallery physics toy ships a circular subject whose cell-frame is
intentionally non-square at the authoring layer (6 cells wide,
`6/aspectRatio` cells tall). The ``Circle`` rasterizer then applies its
own aspect correction, producing a visually round ball on any terminal
whose cell dimensions it can read.

## Behavior at `.estimated` metrics

The aspect-correction formula collapses to the pre-correction code when
`cellPixelMetrics.aspectRatio == 2.0` (i.e. the conventional 8x16
fallback). That means fixtures captured against the old rasterizer at
default metrics remain bit-identical against the new code.
```

- [ ] **Step 2: Update shape DocC comments**

In each of `Circle.swift`, `Ellipse.swift`, `Capsule.swift`, extend the existing doc comment with one line:

```swift
/// A circular shape inscribed in its frame's shortest axis.
///
/// Aspect-corrected using ``Core/CellPixelMetrics`` from the resolve
/// environment so the emitted shape is pixel-true regardless of the
/// terminal's cell aspect ratio.
public struct Circle: InsettableShape, ResolvableView { ... }
```

(Analogous wording for `Ellipse` and `Capsule`.)

- [ ] **Step 3: Build**

```bash
swift build
```

Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add Sources/View/View.docc/AspectCorrectShapes.md \
        Sources/View/Shapes/Circle.swift \
        Sources/View/Shapes/Ellipse.swift \
        Sources/View/Shapes/Capsule.swift
git commit -m "docs(view): document aspect-correct Circle/Ellipse/Capsule"
```

---

## Stage 2 checkpoint

Run the whole suite one more time:

```bash
swift test
```

Expected: clean. Gallery physics toy now bounces a pixel-round ball with isotropic motion on any terminal. Existing fixtures unchanged at 8x16.

---

## Self-review checklist

Checked during plan writing; re-run before execution if the plan is edited:

- **Spec coverage.** Every section of `docs/proposals/CELL_PIXEL_METRICS.md` is mapped:
  - Type shape → Task 1.1
  - Proxy surface → Task 1.3
  - Environment surface → Task 1.2
  - Runtime wiring → Task 1.5
  - SIGWINCH refresh (three changes) → Tasks 1.6, 1.7, 1.8
  - Internal consumer migration → Task 1.4
  - Testing, stage-1 layers 1–5 → Tasks 1.1, 1.2, 1.3, 1.5, 1.9
  - Gallery physics toy stage 1 → Task 1.10
  - Documentation stage 1 → Task 1.11
  - Stage 2 rasterizer change → Tasks 2.1, 2.2, 2.3, 2.4, 2.5, 2.6
  - Stage 2 fixture policy → Task 2.7
  - Gallery physics toy stage 2 → Task 2.8
  - Documentation stage 2 → Task 2.9
- **Placeholder scan.** No TBD / TODO / "similar to Task N" / etc.
- **Type consistency.** Every task refers to the type as `CellPixelMetrics` (never `CellMetrics` or `DisplayMetrics`). Environment accessor is `cellPixelMetrics` (never `cellMetrics`) on both `GeometryProxy` and `EnvironmentValues`. `Source.reported` / `Source.estimated` used consistently. `.estimated` (static constant) used as fallback everywhere.
- **Scope separation.** Stage 1 can ship without stage 2 (the gallery stays `Rectangle`-based; no rasterizer changes; DocC is split). Stage 2 can ship without stage 1 only in principle — in practice it depends on `StyleEnvironmentSnapshot` carrying the metric, which is task 2.1, independent of any stage-1 code.
