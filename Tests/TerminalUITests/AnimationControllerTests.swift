import Foundation
import Synchronization
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite("AnimationController snapshot extraction")
struct AnimationControllerSnapshotTests {
  @Test("extracts foregroundColor from local drawMetadata")
  func extractsLocalForegroundColor() throws {
    var drawMetadata = DrawMetadata()
    drawMetadata.baseStyle.foregroundStyle = .color(Color.red)

    let node = ResolvedNode(
      identity: Identity(components: [.named("test")]),
      kind: .view("Leaf"),
      drawMetadata: drawMetadata
    )

    let snapshot = AnimatableSnapshot.extract(from: node)
    #expect(snapshot.foregroundColor == Color.red)
  }

  @Test("falls back to environment snapshot when local drawMetadata has no foreground")
  func extractsForegroundFromEnvironmentFallback() throws {
    // Mirror the gallery case: a leaf (TextFigure) whose drawMetadata
    // is default but whose resolved environment carries the foreground
    // style set by an ancestor `.foregroundStyle(color)` modifier.
    var style = StyleEnvironmentSnapshot()
    style.foregroundStyle = .color(Color.blue)
    let environment = EnvironmentSnapshot(style: style)

    let node = ResolvedNode(
      identity: Identity(components: [.named("test")]),
      kind: .view("Leaf"),
      environmentSnapshot: environment,
      drawMetadata: DrawMetadata()
    )

    let snapshot = AnimatableSnapshot.extract(from: node)
    #expect(
      snapshot.foregroundColor == Color.blue,
      "environment-carried foreground styles must be extracted so `.foregroundStyle(color)` on non-Text views animates"
    )
  }

  @Test("extracts borderColor from drawMetadata.borderShapeStyle")
  func extractsBorderColor() throws {
    var drawMetadata = DrawMetadata()
    drawMetadata.borderShapeStyle = .color(Color.green)

    let node = ResolvedNode(
      identity: Identity(components: [.named("test")]),
      kind: .view("Leaf"),
      drawMetadata: drawMetadata
    )

    let snapshot = AnimatableSnapshot.extract(from: node)
    #expect(snapshot.borderColor == Color.green)
  }

  @Test("local drawMetadata takes priority over environment snapshot")
  func localDrawMetadataWinsOverEnvironment() throws {
    var style = StyleEnvironmentSnapshot()
    style.foregroundStyle = .color(Color.blue)
    let environment = EnvironmentSnapshot(style: style)

    var drawMetadata = DrawMetadata()
    drawMetadata.baseStyle.foregroundStyle = .color(Color.red)

    let node = ResolvedNode(
      identity: Identity(components: [.named("test")]),
      kind: .view("Leaf"),
      environmentSnapshot: environment,
      drawMetadata: drawMetadata
    )

    let snapshot = AnimatableSnapshot.extract(from: node)
    #expect(snapshot.foregroundColor == Color.red)
  }
}

final class FireCounter: Sendable {
  private let storage = Atomic<Int>(0)

  var count: Int {
    storage.load(ordering: .relaxed)
  }

  func increment() {
    storage.wrappingAdd(1, ordering: .relaxed)
  }
}

/// A deterministic CustomAnimation used by the custom-evaluation
/// tests.  `animate` returns `time_in_ms / 200` clamped to `[0, 1]`
/// for the first 200 ms, then nil.  Works for any VectorArithmetic V
/// because we only ever pass `Double` through the controller.
struct LinearCustomAnimation: CustomAnimation {
  let id: String

  func animate<V: VectorArithmetic>(
    value: V, time: Duration, context: inout AnimationContext<V>
  ) -> V? {
    let ms =
      Double(time.components.seconds) * 1000.0
      + Double(time.components.attoseconds) / 1e15
    if ms >= 200.0 { return nil }
    let progress = ms / 200.0
    var scaled = value
    scaled.scale(by: progress)
    return scaled
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.id == rhs.id
  }
}

@MainActor
@Suite("Animation end-to-end pipeline integration")
struct AnimationPipelineIntegrationTests {
  @Test(
    "foreground color interpolates at distinct timestamps across the full pipeline"
  )
  func foregroundColorInterpolatesAtDistinctTimestamps() throws {
    // Stronger end-to-end assertion: drive two renders through
    // DefaultRenderer to seed the controller's active animation,
    // then apply interpolations manually at three explicit
    // timestamps (start, midpoint, end) on a copy of the resolved
    // tree and verify every sample produces a different foreground
    // color.  This pins the tick-frame code path that the gallery
    // relies on for visible color animation.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(1000))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("leaf")])

    // Seed: leaf with red foreground.
    var seedMetadata = DrawMetadata()
    seedMetadata.baseStyle.foregroundStyle = .color(Color.red)
    let seed = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Text"),
      drawMetadata: seedMetadata
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(seed, transaction: .init(), timestamp: t0)

    // Frame 2: leaf with blue foreground under an animate intent.
    var frame2Metadata = DrawMetadata()
    frame2Metadata.baseStyle.foregroundStyle = .color(Color.blue)
    let frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Text"),
      drawMetadata: frame2Metadata
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    func sampleForegroundColor(at elapsed: Duration) -> Color? {
      var tree = frame2
      _ = controller.applyInterpolations(
        to: &tree,
        at: t0.advanced(by: elapsed)
      )
      guard case .color(let color) = tree.drawMetadata.baseStyle.foregroundStyle
      else { return nil }
      return color
    }

    let atStart = sampleForegroundColor(at: .zero)
    let atMid = sampleForegroundColor(at: .milliseconds(500))
    let atLate = sampleForegroundColor(at: .milliseconds(900))

    #expect(atStart != nil)
    #expect(atMid != nil)
    #expect(atLate != nil)
    // All three samples must be distinct colors — if the pipeline
    // weren't interpolating, they would all equal blue (or red).
    #expect(
      atStart != atMid,
      "start and mid samples should differ for a 1000ms linear animation"
    )
    #expect(
      atMid != atLate,
      "mid and late samples should differ for a 1000ms linear animation"
    )
    #expect(
      atStart != atLate,
      "start and late samples should differ for a 1000ms linear animation"
    )
  }

  @Test(
    "withAnimation color mutation enqueues an active animation through the pipeline"
  )
  func colorAnimationEnqueuesThroughFullPipeline() throws {
    // Exercises the full render pipeline for an animated color
    // change: resolve → animation → measure → place →
    // applyPlacedOverlays → capturePlacedTree → semantics → draw
    // → raster. The test has no testable clock so it cannot pin
    // an exact interpolated colour, but it can assert that the
    // controller observed the diff and transitioned into an active
    // state (dominantActiveRequest != nil) after frame 2.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController

    let animation = Animation.linear(duration: .milliseconds(500))
    controller.register(animation)

    let rootIdentity = Identity(components: [.named("root")])

    // Frame 1: text with red foreground, no animation intent.
    _ = renderer.render(
      Text("Hello").foregroundStyle(Color.red),
      context: ResolveContext(identity: rootIdentity)
    )
    #expect(
      controller.dominantActiveRequest() == nil,
      "no animations should be in flight before the animated mutation"
    )

    // Frame 2: text with blue foreground under an explicit animate
    // transaction.  The controller's diff path should enqueue an
    // active animation for the foreground colour.
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    _ = renderer.render(
      Text("Hello").foregroundStyle(Color.blue),
      context: ResolveContext(
        identity: rootIdentity,
        transaction: transaction
      )
    )
    #expect(
      controller.dominantActiveRequest() != nil,
      "controller must hold an active animation after the animated colour change"
    )
  }

  @Test(
    "transition.opacity insertion + removal flows through applyPlacedOverlays"
  )
  func transitionRemovalIsInjectedAtPlacedLevel() throws {
    // Verifies the placed-level injection path (gap item 1): after
    // a transition-marked leaf is removed, the next frame should
    // re-inject it into the placed tree as a transient overlay
    // without the layout engine running on the removed subtree.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController

    let animation = Animation.linear(duration: .milliseconds(500))
    controller.register(animation)

    let rootIdentity = Identity(components: [.named("root")])
    let leafIdentity = Identity(components: [.named("root"), .named("leaf")])

    // Manually register the transition against the controller, then
    // seed the controller with a prior frame state by calling
    // processResolvedTree and capturePlacedTree directly — this
    // avoids needing a full view-layer transition modifier setup.
    controller.beginTransitionCollection()
    controller.registerTransition(for: leafIdentity, transition: AnyTransition.opacity)
    controller.finishTransitionCollection()

    // Seed: leaf present in the prior resolved + placed trees.
    let leafResolved = ResolvedNode(identity: leafIdentity, kind: .view("Leaf"))
    let priorResolved = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: [leafResolved]
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(priorResolved, transaction: .init(), timestamp: t0)

    let priorPlaced = PlacedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      bounds: Rect(origin: .zero, size: Size(width: 10, height: 1)),
      children: [
        PlacedNode(
          identity: leafIdentity,
          kind: .view("Leaf"),
          bounds: Rect(origin: .zero, size: Size(width: 5, height: 1))
        )
      ]
    )
    controller.capturePlacedTree(priorPlaced)

    // Now remove the leaf under an animation intent — this should
    // capture the placed snapshot and schedule a placed-level overlay.
    let nextResolved = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: []
    )
    controller.beginTransitionCollection()
    controller.finishTransitionCollection()
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(
      nextResolved,
      transaction: transaction,
      timestamp: t0.advanced(by: .milliseconds(1))
    )

    // Apply placed overlays to a fresh placed tree (no leaf present).
    var livePlaced = PlacedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      bounds: Rect(origin: .zero, size: Size(width: 10, height: 1)),
      children: []
    )
    controller.applyPlacedOverlays(
      to: &livePlaced,
      at: t0.advanced(by: .milliseconds(100))
    )

    // The removed leaf should now be back under root as a transient
    // child, with bounds matching the cached frozen placed snapshot.
    let overlay = livePlaced.children.first { $0.identity == leafIdentity }
    #expect(overlay != nil, "removed leaf should be re-injected at placed level")
    if let overlay {
      #expect(overlay.isTransient, "placed overlay must be transient")
      #expect(overlay.bounds.size.width == 5)
      #expect(overlay.bounds.size.height == 1)
    }
  }
}

@MainActor
@Suite("AnimationController property animations")
struct AnimationControllerPropertyTests {
  @Test(
    "flexibleFrame maxWidth animates via frameWidth + preserves other dimensions"
  )
  func flexibleFrameMaxWidthAnimates() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("leaf")])

    // Frame 1: flexibleFrame with maxWidth=100, minWidth=20 (so both
    // finite dimensions exist).  maxWidth takes priority.
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .flexibleFrame(
        minWidth: .finite(20),
        idealWidth: nil,
        maxWidth: .finite(100),
        minHeight: nil,
        idealHeight: nil,
        maxHeight: nil,
        alignment: .center
      )
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    // Extract sanity check.
    let extracted = AnimatableSnapshot.extract(from: frame1)
    #expect(
      extracted.frameWidth == 100,
      "maxWidth takes priority over minWidth in the extracted frameWidth"
    )

    // Frame 2: maxWidth → 200 under withAnimation.
    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .flexibleFrame(
        minWidth: .finite(20),
        idealWidth: nil,
        maxWidth: .finite(200),
        minHeight: nil,
        idealHeight: nil,
        maxHeight: nil,
        alignment: .center
      )
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    // Apply halfway.
    let halfway = t0.advanced(by: .milliseconds(100))
    let result = controller.applyInterpolations(to: &frame2, at: halfway)

    #expect(result.hasActiveAnimations)

    guard
      case .flexibleFrame(
        let newMin, _, let newMax,
        _, _, _,
        _
      ) = frame2.layoutBehavior
    else {
      Issue.record("apply must preserve the flexibleFrame shape, not collapse to frame")
      return
    }

    // minWidth must be preserved untouched.
    #expect(newMin == .finite(20), "minWidth must be preserved across apply")

    // maxWidth must be mid-interpolation: above 100, below 200, and not
    // equal to either endpoint.
    guard case .finite(let interpolatedMax) = newMax else {
      Issue.record("maxWidth should still be finite after interpolation")
      return
    }
    #expect(
      interpolatedMax > 100 && interpolatedMax < 200,
      "maxWidth should interpolate between endpoints, got \(interpolatedMax)"
    )
  }

  @Test(
    "injected removal overlay nodes are marked transient"
  )
  func removalOverlayIsMarkedTransient() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let rootIdentity = Identity(components: [.named("root")])
    let leafIdentity = Identity(components: [.named("root"), .named("leaf")])

    let leaf = ResolvedNode(identity: leafIdentity, kind: .view("Leaf"))
    let root = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: [leaf]
    )
    controller.beginTransitionCollection()
    controller.registerTransition(for: leafIdentity, transition: AnyTransition.opacity)
    controller.finishTransitionCollection()
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(root, transaction: .init(), timestamp: t0)

    var frame2 = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: []
    )
    controller.beginTransitionCollection()
    controller.finishTransitionCollection()
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    let t1 = t0.advanced(by: .milliseconds(100))
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t1)

    _ = controller.applyInterpolations(
      to: &frame2,
      at: t1.advanced(by: .milliseconds(50))
    )
    let overlayLeaf = frame2.children.first { $0.identity == leafIdentity }
    #expect(overlayLeaf != nil)
    if let overlayLeaf {
      #expect(
        overlayLeaf.isTransient,
        "removal overlay root must be marked transient so semantics/focus skip it"
      )
    }
  }

  @Test(
    "removal transition offset composes with an existing offset on the root"
  )
  func removalOffsetComposesWithExistingOffset() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let rootIdentity = Identity(components: [.named("root")])
    let leafIdentity = Identity(components: [.named("root"), .named("leaf")])

    // Leaf already has a .offset(x: 5, y: 0) layout.  The removal
    // transition is .move(edge: .trailing) which adds offsetX=10.
    // Expect the composed offset to be x=15.
    let leaf = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .offset(x: 5, y: 0)
    )
    let root = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: [leaf]
    )

    controller.beginTransitionCollection()
    controller.registerTransition(
      for: leafIdentity,
      transition: AnyTransition.move(edge: .trailing)
    )
    controller.finishTransitionCollection()
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(root, transaction: .init(), timestamp: t0)

    // Frame 2: leaf gone.
    var frame2 = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: []
    )
    controller.beginTransitionCollection()
    controller.finishTransitionCollection()
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    let t1 = t0.advanced(by: .milliseconds(200))
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t1)

    // Apply near the end of the removal — the transition progress
    // should be near 1, which with .move(edge:.trailing) yields
    // offsetX ≈ 10 for the transition modifier.  Composed with the
    // leaf's existing offset of 5, the injected leaf's layoutBehavior
    // should be .offset(x ≈ 15, y: 0).
    let tEnd = t1.advanced(by: .milliseconds(180))
    _ = controller.applyInterpolations(to: &frame2, at: tEnd)

    let injectedLeaf = frame2.children.first { $0.identity == leafIdentity }
    guard let injectedLeaf else {
      Issue.record("injected removal leaf should still be in the tree before purge")
      return
    }
    guard case .offset(let x, let y) = injectedLeaf.layoutBehavior else {
      Issue.record(
        "expected .offset layout on the injected leaf, got \(injectedLeaf.layoutBehavior)")
      return
    }
    // At progress ~0.9, modifier offsetX = 10 * 0.9 = 9. Composed
    // with the original 5 → 14.
    #expect(
      x >= 10, "composed offset should include the existing 5 and transition offset, got \(x)")
    #expect(y == 0)
  }

  @Test(
    "removal transition offset on a framed root wraps the root in an offset node"
  )
  func removalOffsetWrapsNonIntrinsicRoot() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let rootIdentity = Identity(components: [.named("root")])
    let leafIdentity = Identity(components: [.named("root"), .named("leaf")])

    let leaf = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .frame(width: 20, height: 10, alignment: .center)
    )
    let root = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: [leaf]
    )

    controller.beginTransitionCollection()
    controller.registerTransition(
      for: leafIdentity,
      transition: AnyTransition.move(edge: .trailing)
    )
    controller.finishTransitionCollection()
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(root, transaction: .init(), timestamp: t0)

    var frame2 = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: []
    )
    controller.beginTransitionCollection()
    controller.finishTransitionCollection()
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    let t1 = t0.advanced(by: .milliseconds(200))
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t1)

    let tMid = t1.advanced(by: .milliseconds(100))
    _ = controller.applyInterpolations(to: &frame2, at: tMid)

    // The leaf's frame layout must be preserved, so the injected
    // child should be an offset wrapper whose single child is the
    // original framed leaf.
    let injected = frame2.children.first
    guard let injected else {
      Issue.record("expected an injected wrapper child after removal")
      return
    }
    guard case .offset = injected.layoutBehavior else {
      Issue.record(
        "expected the wrapper root to be .offset, got \(injected.layoutBehavior)"
      )
      return
    }
    guard injected.children.count == 1 else {
      Issue.record("expected exactly one wrapped child, got \(injected.children.count)")
      return
    }
    let wrappedLeaf = injected.children[0]
    #expect(
      wrappedLeaf.identity == leafIdentity,
      "wrapped child should be the original leaf"
    )
    guard case .frame(let w, let h, _) = wrappedLeaf.layoutBehavior else {
      Issue.record("leaf's frame layout should be preserved under the wrapper")
      return
    }
    #expect(w == 20)
    #expect(h == 10)
  }

  @Test(
    "removal interrupting a mid-flight insertion fades from the displayed opacity"
  )
  func removalRetargetsFromMidInsertionOpacity() throws {
    // Step 1: enqueue an insertion via .transition(.opacity).
    // Step 2: midway through the fade-in, remove the leaf.
    // The removal entry should capture the mid-flight opacity as its
    // startOpacity so the exit continues from whatever is on screen
    // instead of snapping back to 1.0.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let rootIdentity = Identity(components: [.named("root")])
    let leafIdentity = Identity(components: [.named("root"), .named("leaf")])

    // Frame 1: leaf inserted with .opacity transition under
    // withAnimation intent → starts the fade-in.
    controller.beginTransitionCollection()
    controller.registerTransition(for: leafIdentity, transition: AnyTransition.opacity)
    controller.finishTransitionCollection()

    let frame1 = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: [ResolvedNode(identity: leafIdentity, kind: .view("Leaf"))]
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: transaction, timestamp: t0)

    // Frame 2: at t=100ms (midway), the leaf disappears.
    // The transition registration is NOT re-emitted because the
    // branch is gone, so the controller must use the previous frame's
    // transition map to detect the removal.
    var frame2 = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: []
    )
    controller.beginTransitionCollection()
    controller.finishTransitionCollection()
    var transaction2 = TransactionSnapshot()
    transaction2.animationRequest = .animate(animation.animationBox)
    let t1 = t0.advanced(by: .milliseconds(100))
    controller.processResolvedTree(frame2, transaction: transaction2, timestamp: t1)

    // Tick at t1 + 0ms — the removal should have just been captured
    // with startOpacity ~0.5 (mid-insertion value).  Render it.
    var tickTree = frame2
    _ = controller.applyInterpolations(to: &tickTree, at: t1)

    guard let injectedLeaf = tickTree.children.first(where: { $0.identity == leafIdentity })
    else {
      Issue.record("removal should re-inject the leaf into the tree")
      return
    }
    let capturedOpacity = injectedLeaf.drawMetadata.baseStyle.explicitOpacity
    #expect(capturedOpacity != nil)
    if let capturedOpacity {
      // startOpacity is ~0.5 (the insertion midpoint); at tick t1
      // removal progress is 0 so opacity = startOpacity ≈ 0.5.
      #expect(
        capturedOpacity > 0.3 && capturedOpacity < 0.7,
        "removal should start from the mid-insertion opacity, not snap to 1.0, got \(capturedOpacity)"
      )
    }

    // Half a removal-duration later, the opacity should have
    // progressed toward 0 but should still be strictly below the
    // starting mid-insertion value (never jumps UP).
    var laterTree = frame2
    _ = controller.applyInterpolations(
      to: &laterTree,
      at: t1.advanced(by: .milliseconds(100))
    )
    if let laterLeaf = laterTree.children.first(where: { $0.identity == leafIdentity }) {
      let laterOpacity = laterLeaf.drawMetadata.baseStyle.explicitOpacity
      if let laterOpacity, let capturedOpacity {
        #expect(
          laterOpacity < capturedOpacity,
          "removal opacity should decrease over time"
        )
      }
    }
  }

  @Test(
    "withAnimation completion closure fires once the batch drains"
  )
  func completionClosureFiresOnBatchDrain() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(100))
    controller.register(animation)

    let batchID = AnimationBatchID(42)
    let fireCount = FireCounter()
    controller.registerCompletion(batchID: batchID) {
      fireCount.increment()
    }

    let leafIdentity = Identity(components: [.named("leaf")])

    // Frame 1: opacity 1.0.
    var frame1Metadata = DrawMetadata()
    frame1Metadata.baseStyle.explicitOpacity = 1.0
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      drawMetadata: frame1Metadata
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    // Frame 2: opacity 0.0 under a batched animation.
    var frame2Metadata = DrawMetadata()
    frame2Metadata.baseStyle.explicitOpacity = 0.0
    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      drawMetadata: frame2Metadata
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    transaction.animationBatchID = batchID
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    // Halfway — closure must NOT have fired yet.
    let halfway = t0.advanced(by: .milliseconds(50))
    _ = controller.applyInterpolations(to: &frame2, at: halfway)
    #expect(fireCount.count == 0)

    // Past the end — closure should fire exactly once.
    let past = t0.advanced(by: .milliseconds(200))
    var frame3 = frame2
    _ = controller.applyInterpolations(to: &frame3, at: past)
    #expect(fireCount.count == 1)

    // Further ticks on the empty batch should not double-fire.
    var frame4 = frame3
    _ = controller.applyInterpolations(to: &frame4, at: past.advanced(by: .milliseconds(50)))
    #expect(fireCount.count == 1)
  }

  @Test(
    "CustomAnimation conformance drives interpolation via the controller"
  )
  func customAnimationIsEvaluatedByController() throws {
    let controller = AnimationController()
    let animation = Animation(LinearCustomAnimation(id: "test-linear"))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("leaf")])

    // Frame 1: opacity 1.0.
    var frame1Metadata = DrawMetadata()
    frame1Metadata.baseStyle.explicitOpacity = 1.0
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      drawMetadata: frame1Metadata
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    // Frame 2: opacity 0.0 under the custom animation.
    var frame2Metadata = DrawMetadata()
    frame2Metadata.baseStyle.explicitOpacity = 0.0
    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      drawMetadata: frame2Metadata
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    // Halfway through the custom animation's 200 ms window.
    let halfway = t0.advanced(by: .milliseconds(100))
    let result = controller.applyInterpolations(to: &frame2, at: halfway)

    #expect(result.hasActiveAnimations)
    let opacity = frame2.drawMetadata.baseStyle.explicitOpacity
    #expect(opacity != nil)
    if let opacity {
      // LinearCustomAnimation returns 0.5 at 100ms, so interpolated
      // opacity = 1.0 + (0.0 - 1.0) * 0.5 = 0.5.
      #expect(
        abs(opacity - 0.5) < 0.05,
        "custom animation should drive opacity halfway at t=100ms, got \(opacity)"
      )
    }

    // After the custom animation's window closes, the controller should
    // snap to the final value and mark the animation complete.
    var frame3 = frame2
    let past = t0.advanced(by: .milliseconds(300))
    let finalResult = controller.applyInterpolations(to: &frame3, at: past)
    #expect(!finalResult.hasActiveAnimations)
  }

  @Test(
    "padding edges animate independently and preserve untouched edges"
  )
  func paddingEdgesAnimateIndependently() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("leaf")])

    // Frame 1: uniform padding of 4 on all sides.
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .padding(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    // Frame 2: top grows to 20, others unchanged.
    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .padding(EdgeInsets(top: 20, leading: 4, bottom: 4, trailing: 4))
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    let halfway = t0.advanced(by: .milliseconds(100))
    let result = controller.applyInterpolations(to: &frame2, at: halfway)
    #expect(result.hasActiveAnimations)

    guard case .padding(let insets) = frame2.layoutBehavior else {
      Issue.record("apply must preserve the padding layoutBehavior")
      return
    }

    // Top must be mid-interpolation.
    #expect(
      insets.top > 4 && insets.top < 20,
      "top edge should interpolate between endpoints, got \(insets.top)"
    )
    // Leading/bottom/trailing must be untouched.
    #expect(insets.leading == 4)
    #expect(insets.bottom == 4)
    #expect(insets.trailing == 4)
  }

  @Test(
    "borderColor change under withAnimation is interpolated through the tree"
  )
  func borderColorAnimationIsInterpolated() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("leaf")])

    var frame1Metadata = DrawMetadata()
    frame1Metadata.borderShapeStyle = .color(Color.red)
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      drawMetadata: frame1Metadata
    )

    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    // Frame 2: border shifts red → blue under withAnimation.
    var frame2Metadata = DrawMetadata()
    frame2Metadata.borderShapeStyle = .color(Color.blue)
    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      drawMetadata: frame2Metadata
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    // Apply halfway through the 200 ms linear curve.
    let halfway = t0.advanced(by: .milliseconds(100))
    let result = controller.applyInterpolations(to: &frame2, at: halfway)

    #expect(result.hasActiveAnimations)
    #expect(result.affectedIdentities.contains(leafIdentity))

    // The interpolated border should not equal either endpoint — if
    // extraction or apply were broken it would snap to blue (the
    // new value) because the diff would collapse to .inherit → snap.
    guard case .color(let interpolated) = frame2.drawMetadata.borderShapeStyle else {
      Issue.record("border shape style should still be a color after interpolation")
      return
    }
    #expect(
      interpolated != Color.red && interpolated != Color.blue,
      "halfway interpolation should produce an intermediate color, not an endpoint"
    )
  }
}

@MainActor
@Suite("AnimationController removal injection")
struct AnimationControllerRemovalTests {
  @Test("removed identity with .opacity transition is re-injected into the tree")
  func removedIdentityIsReinjectedIntoTree() throws {
    let controller = AnimationController()
    let animation = Animation.easeInOut(duration: .milliseconds(200))
    controller.register(animation)

    // Register the transition for the soon-to-be-removed child.
    let leafIdentity = Identity(components: [.named("root"), .named("leaf")])
    controller.beginTransitionCollection()
    controller.registerTransition(for: leafIdentity, transition: AnyTransition.opacity)
    controller.finishTransitionCollection()

    // Frame 1: parent has the leaf as a child.
    let leaf = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf")
    )
    var root = ResolvedNode(
      identity: Identity(components: [.named("root")]),
      kind: .view("Root"),
      children: [leaf]
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(
      root,
      transaction: .init(),
      timestamp: t0
    )

    // Frame 2: leaf is gone; transaction carries a withAnimation intent.
    //
    // IMPORTANT: the real gallery case does NOT re-register the
    // transition on the frame where the view disappears — the branch
    // containing `.transition(.opacity)` is no longer evaluated, so
    // `TransitionViewModifier.resolveElements` never runs.  The
    // controller must carry the registration forward from the previous
    // frame to detect the removal correctly.
    var root2 = ResolvedNode(
      identity: Identity(components: [.named("root")]),
      kind: .view("Root"),
      children: []
    )
    controller.beginTransitionCollection()
    // (no registration — branch is gone)
    controller.finishTransitionCollection()
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(
      root2,
      transaction: transaction,
      timestamp: t0
    )

    // At t0 the apply pass should inject the removed leaf back into
    // the tree (it's still mid-animation).
    let tickResult = controller.applyInterpolations(to: &root2, at: t0)
    #expect(tickResult.hasActiveAnimations)

    let injectedChildren = root2.children
    #expect(
      injectedChildren.contains(where: { $0.identity == leafIdentity }),
      "removed leaf should be re-injected as a child of its previous parent"
    )

    // The injected leaf should carry a reduced opacity reflecting the
    // early point in the .opacity removal (progress ≈ 0 → still near 1).
    if let injected = injectedChildren.first(where: { $0.identity == leafIdentity }) {
      let opacity = injected.drawMetadata.baseStyle.explicitOpacity
      #expect(opacity != nil)
    }
  }

  @Test(
    "removal walks up disappearing ancestors to inject under a surviving parent"
  )
  func removalWalksUpToSurvivingAncestor() throws {
    // Mirrors the gallery case:
    //     Overlay { if showFigure { TextFigure().transition(.opacity).padding(1) } }
    // When `showFigure` becomes false, BOTH the PaddingView wrapper and
    // the TextFigure leaf disappear from the tree.  The transition is
    // registered on the TextFigure leaf, but the PaddingView is its
    // immediate parent — and the overlay is the surviving ancestor.
    // The controller must walk up, capture the PaddingView subtree, and
    // inject it under the overlay so the whole wrapped unit fades out
    // together.
    let controller = AnimationController()
    let animation = Animation.easeInOut(duration: .milliseconds(200))
    controller.register(animation)

    let overlayIdentity = Identity(components: [.named("overlay")])
    let paddingIdentity = Identity(components: [.named("overlay"), .named("padding")])
    let leafIdentity = Identity(
      components: [.named("overlay"), .named("padding"), .named("leaf")]
    )

    // Register the transition on the leaf (that's where
    // TransitionViewModifier attaches it).
    controller.beginTransitionCollection()
    controller.registerTransition(for: leafIdentity, transition: AnyTransition.opacity)
    controller.finishTransitionCollection()

    // Frame 1: overlay → padding → leaf present.
    let leaf = ResolvedNode(identity: leafIdentity, kind: .view("Leaf"))
    let padding = ResolvedNode(
      identity: paddingIdentity,
      kind: .view("Padding"),
      children: [leaf]
    )
    var overlay = ResolvedNode(
      identity: overlayIdentity,
      kind: .view("Overlay"),
      children: [padding]
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(overlay, transaction: .init(), timestamp: t0)

    // Frame 2: both padding and leaf disappear.  Overlay is the only
    // surviving ancestor.  The transition is NOT re-registered because
    // the branch containing `.transition(.opacity)` is gone from the
    // resolved tree — mirrors the real gallery behavior.
    var overlay2 = ResolvedNode(
      identity: overlayIdentity,
      kind: .view("Overlay"),
      children: []
    )
    controller.beginTransitionCollection()
    // (no registration — branch is gone)
    controller.finishTransitionCollection()
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(overlay2, transaction: transaction, timestamp: t0)

    let result = controller.applyInterpolations(to: &overlay2, at: t0)
    #expect(result.hasActiveAnimations)

    // Overlay should now have the padding subtree back as a child,
    // with the leaf inside it — NOT just the bare leaf.
    let injectedPadding = overlay2.children.first { $0.identity == paddingIdentity }
    #expect(
      injectedPadding != nil,
      "the whole padding subtree should be re-injected under the surviving overlay ancestor"
    )
    if let injectedPadding {
      #expect(
        injectedPadding.children.contains { $0.identity == leafIdentity },
        "the padding wrapper should still contain the original leaf"
      )

      // Opacity should cascade to the leaf so the text actually fades.
      if let reinjectedLeaf = injectedPadding.children.first(
        where: { $0.identity == leafIdentity }
      ) {
        #expect(reinjectedLeaf.drawMetadata.baseStyle.explicitOpacity != nil)
      }
    }
  }

  @Test(
    "reset clears transition and removal state so the next tick does not replay stale removals"
  )
  func resetClearsRemovalAndTransitionState() throws {
    // Regression for Item 16: a reset mid-removal used to leave
    // `removingIdentities` and `previousTreeRoot` alive, so the next
    // tick would try to re-inject a subtree from a now-stale tree.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("root"), .named("leaf")])
    controller.beginTransitionCollection()
    controller.registerTransition(for: leafIdentity, transition: AnyTransition.opacity)
    controller.finishTransitionCollection()

    // Frame 1: leaf present.
    let leaf = ResolvedNode(identity: leafIdentity, kind: .view("Leaf"))
    let root = ResolvedNode(
      identity: Identity(components: [.named("root")]),
      kind: .view("Root"),
      children: [leaf]
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(root, transaction: .init(), timestamp: t0)

    // Frame 2: leaf removed mid-animation.
    var root2 = ResolvedNode(
      identity: Identity(components: [.named("root")]),
      kind: .view("Root"),
      children: []
    )
    controller.beginTransitionCollection()
    controller.finishTransitionCollection()
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(root2, transaction: transaction, timestamp: t0)
    let preResetTick = controller.applyInterpolations(to: &root2, at: t0)
    #expect(preResetTick.hasActiveAnimations)

    // Reset while the removal is still in flight.
    controller.reset()

    // A new tree with a completely different identity should NOT see
    // the pre-reset leaf re-injected.
    let freshIdentity = Identity(components: [.named("fresh")])
    var fresh = ResolvedNode(identity: freshIdentity, kind: .view("Fresh"))
    controller.processResolvedTree(fresh, transaction: .init(), timestamp: t0)
    let result = controller.applyInterpolations(to: &fresh, at: t0)

    #expect(!result.hasActiveAnimations)
    #expect(
      !containsIdentity(fresh, leafIdentity),
      "pre-reset removal state must not leak into the post-reset tree"
    )
  }

  private func containsIdentity(_ node: ResolvedNode, _ identity: Identity) -> Bool {
    if node.identity == identity { return true }
    return node.children.contains { containsIdentity($0, identity) }
  }

  @Test("removal entry purges after the animation completes")
  func removalPurgesAfterAnimationCompletes() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(100))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("root"), .named("leaf")])
    controller.beginTransitionCollection()
    controller.registerTransition(for: leafIdentity, transition: AnyTransition.opacity)
    controller.finishTransitionCollection()

    // Frame 1: leaf present.
    let leaf = ResolvedNode(identity: leafIdentity, kind: .view("Leaf"))
    var root = ResolvedNode(
      identity: Identity(components: [.named("root")]),
      kind: .view("Root"),
      children: [leaf]
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(root, transaction: .init(), timestamp: t0)

    // Frame 2: leaf removed with animation intent.  No re-registration
    // because the branch is gone from the resolved tree.
    var root2 = ResolvedNode(
      identity: Identity(components: [.named("root")]),
      kind: .view("Root"),
      children: []
    )
    controller.beginTransitionCollection()
    // (no registration — branch is gone)
    controller.finishTransitionCollection()
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(root2, transaction: transaction, timestamp: t0)

    // Apply at t0 + 500 ms — well past the 100 ms linear duration — so
    // the controller should purge the entry and stop requesting frames.
    let past = t0.advanced(by: .milliseconds(500))
    var treeCopy = root2
    let result = controller.applyInterpolations(to: &treeCopy, at: past)

    #expect(!result.hasActiveAnimations)
    #expect(result.nextDeadline == nil)
    #expect(
      !treeCopy.children.contains(where: { $0.identity == leafIdentity }),
      "purged removal should not be re-injected after the animation completes"
    )
  }
}
