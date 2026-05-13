---
title: "refactor: host presentation damage"
type: refactor
status: shipped
date: 2026-05-13
depends_on:
  - "../HOST_RENDERING_PIPELINES.md"
  - "../RUNTIME.md"
  - "../PUBLIC_SURFACE_POLICY.md"
---

# Host Presentation Damage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to
> implement this plan task-by-task. Steps below are now marked complete. Commit
> after the plan first, then keep implementation commits scoped to green
> checkpoints.

> **Status:** Shipped. `PresentationDamage` is now a public host-presentation
> hint, damage-aware semantic presentation is wired through the runtime branch,
> SwiftUIHost uses damage for native dirty-rect invalidation, and WebHost/WASI
> encode damage so the browser canvas can redraw dirty rectangles only.

**Goal:** Promote retained-frame presentation damage into the shared host
presentation path, then use it to avoid unnecessary full redraw work in the CLI,
SwiftUI, local WebHost, and WASI Web hosts.

**Architecture:** Keep `RasterSurface` and `SemanticSnapshot` as the required
frame products. Promote `PresentationDamage` from terminal-only/package
optimization into an optional presentation hint: `nil` means the host must
present a full frame, while non-`nil` describes rows/ranges that can be used for
incremental presentation when the previous retained frame is compatible. Add a
damage-aware semantic host protocol so accessibility-capable hosts do not lose
damage at the current `SemanticPresentationSurface` branch.

**Tech Stack:** Swift 6.3 strict concurrency, SwiftPM package access and runner
SPI, Swift Testing, SwiftUI/AppKit/UIKit drawing, WASISurfaceBridge
`web-surface` JSON records, Bun TypeScript tests, public API baseline tooling,
and the repo-wide `bun run test` gate.

---

## Current State

- `DefaultRenderer` and `RunLoop` already compute `PresentationDamage`.
- `PresentationDamage` and `DamageAwarePresentationSurface` are currently
  package-level implementation seams.
- `FrameArtifacts.diagnostics.presentationDamage` exposes counts and full
  repaint flags publicly, but not the row/range damage payload itself.
- `RunLoop.presentCommittedFrame(...)` checks `SemanticPresentationSurface`
  before `DamageAwarePresentationSurface`, so SwiftUIHost, WebHost, and WASI
  Web receive semantics but lose the damage payload.
- `HostedRasterSurface` has a damage-aware overload, but the semantic overload
  is the path used by SwiftUIHost and it currently reports full-frame metrics.
- `WebSocketSurfaceTransport` and `WebSurfaceTransport` encode whole
  `web-surface` frames and report full-repaint metrics.
- `WebHostSceneRuntime` clears and redraws the full canvas for every surface
  frame, then remounts the accessibility tree.
- `NativeTerminalSurfaceView` invalidates and redraws the full native view for
  every `RasterSurface`.

## Non-Goals

- Do not invent a second renderer output model above `RasterSurface`.
- Do not add web patch/delta records as the first step. Web can receive full
  frame records plus damage metadata first, then use damage to reduce canvas
  redraw work.
- Do not make hosts depend on damage for correctness. Hosts must stay correct
  when damage is `nil` or ignored.
- Do not change app-authored APIs.
- Do not weaken terminal sanitization, accessibility extraction, or host
  package boundaries.

## Contract

`PresentationDamage?` is advisory host presentation metadata.

- `nil` means full presentation is required or damage is unknown.
- `PresentationDamage(textRows: [])` means no visual text rows changed; semantic
  or focus data may still have changed.
- A `TextRow` with an empty `columnRanges` array means the full row is dirty.
- A `TextRow` with ranges means only those cell ranges need redraw.
- `requiresFullTextRepaint` forces text/cell hosts to repaint all cells.
- `requiresFullGraphicsReplay` is currently terminal-oriented, but web/native
  hosts should treat it as a full image-layer redraw requirement.
- `graphicsInvalidation` remains package-only unless a later host proves it
  needs identity-level graphics invalidation publicly.

## File Map

### Modify

- `Sources/SwiftTUICore/Commit/PresentationDamage.swift`
  - Make `PresentationDamage` and `PresentationDamage.TextRow` public enough to
    appear in runner SPI and host callbacks.
  - Keep identity-level graphics invalidation package-only.
- `Sources/SwiftTUICore/Commit/FrameArtifacts.swift`
  - Expose `FrameArtifacts.presentationDamage` as the optional retained-frame
    presentation hint.
- `Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`
  - Add a damage-aware semantic presentation protocol and shared raster-host
    metrics helper.
  - Keep CLI `TerminalHost` on the non-semantic damage-aware path.
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`
  - Dispatch to damage-aware semantic hosts before plain semantic hosts.
- `Sources/SwiftTUIRuntime/Scenes/HostedSceneSession.swift`
  - Thread damage through hosted semantic callbacks and use standardized
    raster-host metrics.
- `Sources/SwiftTUICore/Raster/Rasterizer.swift`
  - Retain image attachments from previous incremental frames when they do not
    intersect dirty rows.
- `Sources/SwiftTUICore/Raster/Rasterizer+Damage.swift`
  - Add helper predicates for attachment/dirty-row overlap.
- `Platforms/SwiftUI/Sources/SwiftUIHost/SwiftUIHostSceneHost.swift`
  - Store the latest presentation damage beside the latest surface and semantic
    snapshot.
- `Platforms/SwiftUI/Sources/SwiftUIHost/SwiftUIHostAppView.swift`
  - Pass surface and damage together to native views.
- `Platforms/SwiftUI/Sources/SwiftUIHost/NativeTerminalSurfaceView.swift`
  - Add damage-aware invalidation and dirty-rect-aware drawing on AppKit and
    UIKit.
- `Platforms/WebHost/Sources/SwiftTUIWebHost/WebSocketSurfaceTransport.swift`
  - Conform to the damage-aware semantic host protocol, encode damage metadata,
    and report standardized metrics.
- `Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift`
  - Encode optional damage metadata in `web-surface` frames and report
    standardized metrics.
- `Platforms/Web/src/WebHostSurfaceTransport.ts`
  - Add the `damage` field to the decoded frame schema and validators.
- `Platforms/Web/src/WebHostSceneRuntime.ts`
  - Avoid redundant canvas reallocations and redraw only damage rects when
    damage is present.
- `docs/HOST_RENDERING_PIPELINES.md`
  - Update host-pipeline documentation to describe optional presentation damage
    as shared retained-frame metadata.
- `docs/PUBLIC_API_INVENTORY.md`, `docs/PUBLIC_API_BASELINE.md`,
  `docs/.public-api-baseline.txt`
  - Regenerate because `PresentationDamage` becomes public API.

### Test

- `Tests/SwiftTUICoreTests/RasterizerTests.swift`
  - Lock retained image attachments across incremental dirty-row rasterization.
- `Tests/SwiftTUITests/InteractiveRuntimeTests.swift`
  - Lock that damage-aware semantic hosts receive non-`nil` damage on retained
    incremental frames and that CLI damage-aware hosts continue to receive
    damage.
- `Platforms/SwiftUI/Tests/SwiftUIHostTests/HostedSurfaceRegressionTests.swift`
  - Lock that hosted semantic callbacks receive damage after an incremental
    interaction.
- `Platforms/WASI/Tests/WASISurfaceBridgeTests/WebSurfaceTransportTests.swift`
  - Lock encoded `damage` JSON and damage-based metrics.
- `Platforms/WebHost/Tests/SwiftTUIWebHostTests/WebSocketSurfaceTransportTests.swift`
  - Lock WebSocket encoded `damage` JSON and damage-based metrics.
- `Platforms/Web/src/WebHostSceneRuntime.test.ts`
  - Lock that damage frames redraw only dirty rects and do not resize the canvas
    when dimensions are unchanged.
- `Platforms/Web/src/WebHostSurfaceTransport.test.ts`
  - Lock decoder validation for the optional `damage` payload if this file
    already owns transport decoding tests; otherwise add the check to the
    existing runtime test fixture path.

## Task 1: Promote Damage Into The Shared Presentation Contract

**Files:**

- Modify: `Sources/SwiftTUICore/Commit/PresentationDamage.swift`
- Modify: `Sources/SwiftTUICore/Commit/FrameArtifacts.swift`
- Modify: `Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`
- Modify: `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`
- Test: `Tests/SwiftTUITests/InteractiveRuntimeTests.swift`

- [x] **Step 1: Add semantic damage dispatch coverage**

Add a test host that conforms to the new protocol shape:

```swift
private final class SemanticDamageRecordingHost:
  PresentationSurface, DamageAwareSemanticPresentationSurface
{
  var receivedDamage: [PresentationDamage?] = []

  func present(
    _ surface: RasterSurface,
    semanticSnapshot: SemanticSnapshot,
    focusedIdentity: Identity?,
    damage: PresentationDamage?
  ) throws -> TerminalPresentationMetrics {
    receivedDamage.append(damage)
    return TerminalPresentationMetrics.rasterHostMetrics(
      for: surface,
      damage: damage
    )
  }
}
```

Drive a small retained runtime state change and assert that the first frame has
`nil` damage and the later state-change frame has non-`nil` damage with a
non-empty dirty-row set.

- [x] **Step 2: Make `PresentationDamage` public but keep graphics identity
internals package-only**

Expose:

```swift
public struct PresentationDamage: Equatable, Sendable
public struct PresentationDamage.TextRow: Equatable, Sendable
public var textRows: [TextRow]
public var requiresFullTextRepaint: Bool
public var requiresFullGraphicsReplay: Bool
public var dirtyRows: Set<Int>
public func columnRanges(for row: Int) -> [Range<Int>]?
```

Keep `graphicsInvalidation` and the initializer that accepts
`graphicsInvalidation` as `package`.

- [x] **Step 3: Expose `FrameArtifacts.presentationDamage`**

Make `FrameArtifacts.presentationDamage` public and document that it is an
optional presentation hint, not a correctness requirement.

- [x] **Step 4: Add the standard protocol and metrics helper**

Add:

```swift
@_spi(Runners) public protocol DamageAwareSemanticPresentationSurface:
  SemanticPresentationSurface
{
  @discardableResult
  func present(
    _ surface: RasterSurface,
    semanticSnapshot: SemanticSnapshot,
    focusedIdentity: Identity?,
    damage: PresentationDamage?
  ) throws -> TerminalPresentationMetrics
}
```

Add a package helper:

```swift
extension TerminalPresentationMetrics {
  package static func rasterHostMetrics(
    for surface: RasterSurface,
    damage: PresentationDamage?,
    bytesWritten: Int = 0,
    graphicsReplayScope: GraphicsReplayScope? = nil,
    graphicsAttachmentsReplayed: Int? = nil
  ) -> Self
}
```

The helper returns full-repaint metrics when `damage == nil` or
`damage.requiresFullTextRepaint`, and incremental metrics based on row/range
counts otherwise.

- [x] **Step 5: Update run-loop dispatch**

Change `presentCommittedFrame(...)` so the branch order is:

1. JSON output.
2. Linear accessibility output.
3. `DamageAwareSemanticPresentationSurface`.
4. `SemanticPresentationSurface`.
5. `DamageAwarePresentationSurface`.
6. Plain `PresentationSurface`.

- [x] **Step 6: Verify**

Run:

```bash
swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests
```

Expected: semantic damage dispatch coverage passes.

## Task 2: Preserve Complete Raster Surfaces Across Incremental Image Frames

**Files:**

- Modify: `Sources/SwiftTUICore/Raster/Rasterizer.swift`
- Modify: `Sources/SwiftTUICore/Raster/Rasterizer+Damage.swift`
- Test: `Tests/SwiftTUICoreTests/RasterizerTests.swift`

- [x] **Step 1: Add retained-image coverage**

Render a surface containing an image attachment, then render an incremental
dirty row outside that image. Assert the second `RasterSurface` still contains
the original image attachment.

- [x] **Step 2: Retain non-dirty previous attachments**

When `Rasterizer` starts from `previousSurface`, seed `imageAttachments` with
attachments whose `visibleBounds` do not overlap any dirty row. Continue to let
dirty-row painting append attachments in dirty regions.

- [x] **Step 3: Verify**

Run:

```bash
swiftly run swift test --filter SwiftTUICoreTests.RasterizerTests
```

Expected: retained-image coverage passes and existing rasterizer behavior
remains green.

## Task 3: Wire SwiftUIHost To Damage-Aware Presentation

**Files:**

- Modify: `Sources/SwiftTUIRuntime/Scenes/HostedSceneSession.swift`
- Modify: `Platforms/SwiftUI/Sources/SwiftUIHost/SwiftUIHostSceneHost.swift`
- Modify: `Platforms/SwiftUI/Sources/SwiftUIHost/SwiftUIHostAppView.swift`
- Modify: `Platforms/SwiftUI/Sources/SwiftUIHost/NativeTerminalSurfaceView.swift`
- Test: `Platforms/SwiftUI/Tests/SwiftUIHostTests/HostedSurfaceRegressionTests.swift`

- [x] **Step 1: Add hosted-session damage coverage**

Extend a hosted-session interaction test to capture semantic frames with damage
and assert that an interaction after the first frame supplies non-`nil` damage.

- [x] **Step 2: Thread damage through `HostedRasterSurface`**

Make `HostedRasterSurface` conform to
`DamageAwareSemanticPresentationSurface`. Its semantic `present` method should
submit the surface, invoke the semantic-frame callback with damage, and return
`TerminalPresentationMetrics.rasterHostMetrics(for:damage:)`.

- [x] **Step 3: Store damage in `SwiftUIHostSceneHost`**

Add an internal `latestPresentationDamage` property. Clear it on stop and set it
when receiving semantic frames.

- [x] **Step 4: Pass surface and damage together into native views**

Replace direct `view.surface = host.latestSurface` assignment with a method that
updates the surface and its matching damage in one call.

- [x] **Step 5: Add dirty-rect drawing**

In `NativeTerminalSurfaceView`, invalidate the full view when damage is `nil`,
the size changed, or full text repaint is required. Otherwise invalidate row or
range rects. Update `NativeRasterSurfaceRenderer.draw(...)` to accept the dirty
rect and only walk intersecting rows/cells/images.

- [x] **Step 6: Verify**

Run:

```bash
swiftly run swift test --package-path Platforms/SwiftUI --filter SwiftUIHostTests
```

Expected: SwiftUIHost tests pass.

## Task 4: Wire Web Transports And Browser Drawing To Damage

**Files:**

- Modify: `Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift`
- Modify: `Platforms/WebHost/Sources/SwiftTUIWebHost/WebSocketSurfaceTransport.swift`
- Modify: `Platforms/Web/src/WebHostSurfaceTransport.ts`
- Modify: `Platforms/Web/src/WebHostSceneRuntime.ts`
- Test: `Platforms/WASI/Tests/WASISurfaceBridgeTests/WebSurfaceTransportTests.swift`
- Test: `Platforms/WebHost/Tests/SwiftTUIWebHostTests/WebSocketSurfaceTransportTests.swift`
- Test: `Platforms/Web/src/WebHostSceneRuntime.test.ts`

- [x] **Step 1: Add transport damage coverage**

Add Swift tests that call semantic `present(..., damage:)`, decode the emitted
record text, and assert that the JSON contains:

```json
"damage":{"textRows":[[1,[[2,5]]]],"requiresFullTextRepaint":false,"requiresFullGraphicsReplay":false}
```

Also assert metrics are incremental with `linesTouched == 1` and
`cellsChanged == 3`.

- [x] **Step 2: Add browser runtime coverage**

Add a TypeScript test that first presents a full frame, then presents a second
frame with `damage.textRows` for one cell range. Assert the second draw does not
reassign `canvas.width`/`canvas.height`, does not clear the full canvas, and
does fill/redraw only the dirty rect.

- [x] **Step 3: Encode optional damage metadata**

Add a `damage:` parameter to `WebSurfaceFrameEncoder.encode(...)`, include the
optional JSON payload, and thread it through both WebSocket and WASI transports.

- [x] **Step 4: Update TypeScript schema and validators**

Add `WebHostSurfaceDamage` and `WebHostSurfaceDamageTextRow` types to
`WebHostSurfaceTransport.ts`, then update `isWebHostSurfaceFrame(...)`.

- [x] **Step 5: Redraw partial web frames**

Make `WebHostSceneRuntime.presentSurface(...)` pass `frame.damage` to `draw`.
Make `resizeCanvas()` return whether dimensions changed and skip assignment when
unchanged. In `draw`, full redraw on missing damage, full repaint flags, first
frame, or canvas resize; otherwise clear/fill and draw only damage rects.

- [x] **Step 6: Verify**

Run:

```bash
swiftly run swift test --filter WASISurfaceBridgeTests
swiftly run swift test --filter SwiftTUIWebHostTests
bun test --cwd Platforms/Web
```

Expected: Swift transport tests and browser runtime tests pass.

## Task 5: Standardize Docs And Public API Baseline

**Files:**

- Modify: `docs/HOST_RENDERING_PIPELINES.md`
- Modify: `docs/PUBLIC_API_INVENTORY.md`
- Modify: `docs/PUBLIC_API_BASELINE.md`
- Modify: `docs/.public-api-baseline.txt`
- Modify: `docs/plans/2026-05-13-001-host-presentation-damage-plan.md`

- [x] **Step 1: Update host rendering docs**

Document that retained interactive sessions may produce optional presentation
damage beside `RasterSurface` and `SemanticSnapshot`, and update the branch
order for damage-aware semantic hosts.

- [x] **Step 2: Regenerate public API inventory**

Run:

```bash
Scripts/generate_public_api_inventory.sh
Scripts/generate_public_api_inventory.sh --check
```

Expected: generated baseline includes `PresentationDamage` and
`PresentationDamage.TextRow`.

- [x] **Step 3: Mark the plan shipped**

Change this plan's front matter `status:` from `active` to `shipped` after all
implementation verification passes.

## Final Verification

Run the focused checks first:

```bash
swiftly run swift test --filter SwiftTUICoreTests.RasterizerTests
swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests
swiftly run swift test --package-path Platforms/SwiftUI --filter SwiftUIHostTests
swiftly run swift test --filter WASISurfaceBridgeTests
swiftly run swift test --filter SwiftTUIWebHostTests
bun test --cwd Platforms/Web
Scripts/generate_public_api_inventory.sh --check
git diff --check
```

Then run the repo gate:

```bash
bun run test
```

Expected: all focused checks pass, public API baseline is current, whitespace
check passes, and `bun run test` passes or any unrelated pre-existing blocker is
clearly isolated with focused checks green.
