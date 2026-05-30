import Synchronization
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Regression guard for the `beforeOverlayApply` frame-tail render hook.
///
/// The hook (`FrameTailRenderHooks.beforeOverlayApply`) fires on the frame-tail
/// worker immediately before `applyPlacedAnimationOverlaySnapshot` decorates the
/// placed tree — i.e. just before the off-main `Boxed._modify` writes that the
/// run-loop memory-corruption investigation (`SwiftTUI/swift-tui#12`,
/// docs/KNOWN-TEST-FLAKES.md) is built around. Production default is `nil`
/// (no-op); these tests pin the wiring and ordering so the seam cannot silently
/// rot, and document the forced-repro experiment it exists to enable.
///
/// ## Forced-repro experiment (next deliberate step — not yet landed)
///
/// The seam exists so a test can *park* the worker inside the open box-mutation
/// window while the main actor concurrently reads the aliased
/// `AnimationController.previousPlacedRoot` (captured from the same
/// `layout.baselinePlaced` the worker decorates — see
/// `DefaultRendererFrameTailCoordinator.prepareAnimationOverlaySnapshot`). The
/// harness shape, mirroring `AsyncFrameTailBlockingGate`:
///   1. Drive a frame whose placed tree carries a *non-empty*
///      `PlacedAnimationOverlaySnapshot` (a `withAnimation` removal/opacity
///      transition; an empty overlay never calls `applyOpacityCascadingPlaced`,
///      so there is nothing to race — assert non-empty first).
///   2. `beforeOverlayApply` signals a `MainActorConditionSignal`/`AsyncEvent`
///      that the worker entered, then blocks on a release event behind a
///      *far-future hang-detection deadline* (never a fixed sleep — that would
///      trip `Scripts/check_test_sync_policies.sh`), holding the window open.
///   3. On main, tight-loop the removal-detection read
///      (`AnimationTreeQueries.findPlacedSubtree(in: previousPlacedRoot, …)`,
///      forcing `drawMetadata.heavyFields` snapshot reads) so it overlaps the
///      worker's `_modify`. Release, await, repeat N interleaves.
///   4. PASS criterion = process survival; a repro is a `SIGSEGV`/`SIGBUS`. Run
///      in **release/optimized** mode under
///      `Scripts/repeat_async_flake_registry.sh` with
///      `STUI_SWIFT_TEST_SERIALIZED=1`.
///
/// Open question the experiment settles empirically: whether `Boxed`'s
/// copy-on-write (`isKnownUniquelyReferenced` + non-atomic `_storage` store,
/// `Sources/SwiftTUICore/Support/Boxed.swift:36-43`) actually tears across the
/// main/worker seam, or whether the corruptor is instead the genuinely
/// unsynchronized `assumeIsolated` dictionary writes
/// (`ForEachIndexedChildSource.cache`, `LayoutProxyBox.cachedStates`) — the
/// second, stronger candidate, which needs a `ForEach`/`AnyLayout`-driven tree
/// reaching the worker and a different (layout-stage) parking seam.
@Suite("FrameTailOverlayApplyHook", .serialized)
@MainActor
struct FrameTailOverlayApplyHookTests {
  @Test("beforeOverlayApply fires on the frame tail, before beforeRaster")
  func beforeOverlayApplyFiresBeforeRaster() async {
    let renderer = DefaultRenderer()
    let order = Mutex<[String]>([])
    renderer.setFrameTailRenderHooks(
      .init(
        beforeOverlayApply: { order.withLock { $0.append("overlay") } },
        beforeRaster: { order.withLock { $0.append("raster") } }
      )
    )
    defer { renderer.setFrameTailRenderHooks(nil) }

    let draft = renderer.prepareFrameHeadForCancellationTesting(Text("hi"))
    await renderer.renderPreparedFrameTailForCancellationTesting(draft)

    // The overlay-apply seam must fire exactly once, on the same tail, strictly
    // before the raster seam — so a future repro can bracket the box mutation
    // that `beforeRaster` (which fires after the overlay write) cannot.
    #expect(order.withLock { $0 } == ["overlay", "raster"])
  }

  @Test("beforeOverlayApply defaults to a no-op (nil hook does not crash)")
  func beforeOverlayApplyDefaultsToNoOp() async {
    let renderer = DefaultRenderer()
    // No hooks installed: the nil default must render a frame tail without
    // firing or trapping (proves production behaviour is unchanged).
    let draft = renderer.prepareFrameHeadForCancellationTesting(Text("hi"))
    await renderer.renderPreparedFrameTailForCancellationTesting(draft)
  }
}
