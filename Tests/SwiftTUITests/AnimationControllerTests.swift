import Foundation
import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

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

  @Test("removal snapshots carry transient-removal edge role")
  func removalSnapshotsCarryTransientRemovalEdgeRole() throws {
    let child = ResolvedNode(
      identity: testIdentity("RemovalSnapshot", "Child"),
      kind: .view("Child")
    )
    let root = ResolvedNode(
      identity: testIdentity("RemovalSnapshot"),
      kind: .view("Root"),
      children: [child]
    )

    let snapshot = AnimationTransitionOverlay.resolvedRemovalSnapshot(
      from: root,
      applying: .identity
    )
    let snapshotChild = try #require(snapshot.children.first)

    #expect(snapshot.isTransient)
    #expect(snapshot.structuralEdgeRole == .transientRemovalOverlay)
    #expect(snapshot.surfaceComposition.role == .transientRemovalOverlay)
    #expect(snapshotChild.isTransient)
    #expect(snapshotChild.structuralEdgeRole == .transientRemovalOverlay)
    #expect(snapshotChild.surfaceComposition.role == .transientRemovalOverlay)
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

// MARK: - AnyAnimatable type erasure

@MainActor
@Suite("AnyAnimatable type erasure")
struct AnyAnimatableTests {

  @Test("Wraps a Double and round-trips the value")
  func wrapsDouble() {
    let wrapped = AnyAnimatable(Double(1.5))
    #expect(wrapped.unwrap(as: Double.self) == 1.5)
  }

  @Test("Equality holds when wrapped types and values match")
  func equalitySameTypeSameValue() {
    #expect(AnyAnimatable(Double(1.0)) == AnyAnimatable(Double(1.0)))
    #expect(AnyAnimatable(Color.red) == AnyAnimatable(Color.red))
  }

  @Test("Equality is false when wrapped types differ")
  func equalityDifferentTypes() {
    #expect(AnyAnimatable(Double(1.0)) != AnyAnimatable(Int(1)))
  }

  @Test("Equality is false when values differ")
  func equalityDifferentValues() {
    #expect(AnyAnimatable(Double(1.0)) != AnyAnimatable(Double(2.0)))
  }

  @Test("interpolated between same-type values produces intermediate value")
  func interpolateSameType() {
    let from = AnyAnimatable(Double(0.0))
    let to = AnyAnimatable(Double(10.0))
    let halfway = from.interpolated(to: to, progress: 0.5)
    #expect(halfway?.unwrap(as: Double.self) == 5.0)
  }

  @Test("interpolated returns nil when wrapped types mismatch")
  func interpolateTypeMismatch() {
    let from = AnyAnimatable(Double(0.0))
    let to = AnyAnimatable(Int(10))
    let halfway = from.interpolated(to: to, progress: 0.5)
    #expect(halfway == nil)
  }

  @Test("Wraps a Color and interpolation uses OKLab perceptual path")
  func colorInterpolation() {
    let from = AnyAnimatable(Color.red)
    let to = AnyAnimatable(Color.blue)
    let halfway = from.interpolated(to: to, progress: 0.5)
    let unwrapped = halfway?.unwrap(as: Color.self)
    #expect(unwrapped != nil)
    let expected = Color.red.interpolated(to: .blue, progress: 0.5, method: .perceptual)
    if let c = unwrapped {
      #expect(abs(c.red - expected.red) < 0.001)
      #expect(abs(c.green - expected.green) < 0.001)
      #expect(abs(c.blue - expected.blue) < 0.001)
    }
  }

  @Test("Wraps a LinearGradient and interpolates endpoints + stops")
  func linearGradientInterpolation() {
    let from = AnyAnimatable(
      LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
    )
    let to = AnyAnimatable(
      LinearGradient(colors: [.blue, .red], startPoint: .topTrailing, endPoint: .bottomLeading)
    )
    let halfway = from.interpolated(to: to, progress: 0.5)
    let g = halfway?.unwrap(as: LinearGradient.self)
    #expect(g != nil)
    if let g {
      #expect(abs(g.startPoint.x - 0.5) < 0.001)
    }
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

/// Records observations from a stateful CustomAnimation so tests can
/// pin the call-path through `sample()` during retarget.  Class with
/// reference identity so a single instance is shared across every
/// invocation of the animation, regardless of how many copies of the
/// CustomAnimation struct the controller makes.
final class StateRecorder: Sendable {
  private let observed = Atomic<Int>(0)
  private let calls = Atomic<Int>(0)

  /// Most recent counter value the CustomAnimation read from
  /// `context.state` BEFORE incrementing it.
  var lastObserved: Int {
    observed.load(ordering: .relaxed)
  }

  /// Total number of times the CustomAnimation's `animate(...)` was
  /// invoked.
  var callCount: Int {
    calls.load(ordering: .relaxed)
  }

  func record(observed value: Int) {
    self.observed.store(value, ordering: .relaxed)
    calls.wrappingAdd(1, ordering: .relaxed)
  }
}

/// CustomAnimation that increments a counter in `context.state` on
/// every call and reports the counter it observed (before
/// incrementing) to a shared ``StateRecorder``.  Used by the retarget
/// state-survival test to verify the controller threads
/// `customState` through `sample(_:at:)`.
struct RecordingCustomAnimation: CustomAnimation {
  static let counterKey = "RecordingCustomAnimation.counter"

  let id: String
  let recorder: StateRecorder

  func animate<V: VectorArithmetic>(
    value: V, time: Duration, context: inout AnimationContext<V>
  ) -> V? {
    let current: Int = context.state[Self.counterKey] ?? 0
    recorder.record(observed: current)
    context.state[Self.counterKey] = current + 1

    let ms =
      Double(time.components.seconds) * 1000.0
      + Double(time.components.attoseconds) / 1e15
    // Long window so retargets land well inside the active phase.
    if ms >= 1_000.0 { return nil }
    let progress = ms / 1_000.0
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
    "matchedGeometryEffect: swap between identities triggers a translation animation"
  )
  func matchedGeometryTriggersTranslationAnimation() throws {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController

    // Manual sink install: DefaultRenderer doesn't wire the sinks
    // (RunLoop does at startup).
    AnimationRegistrationStorage.currentSink = controller
    TransitionRegistrationStorage.currentSink = controller
    defer {
      AnimationRegistrationStorage.currentSink = nil
      TransitionRegistrationStorage.currentSink = nil
    }

    let animation = Animation.linear(duration: .milliseconds(1_000_000))
    controller.register(animation)

    let rootIdentity = Identity(components: [.named("root")])

    // Frame 1: hero sits in slot A (column 0).
    _ = renderer.render(
      HStack(spacing: 1) {
        Text("hero").matchedGeometryEffect(id: "hero")
        Text("other")
      },
      context: ResolveContext(identity: rootIdentity),
      proposal: ProposedSize(width: .finite(40), height: .finite(3))
    )
    #expect(controller.activeMatchedGeometryCount == 0)
    #expect(
      controller.previousMatchedGeometryKeyCount > 0,
      "frame 1 should have recorded matched geometry bounds, got \(controller.previousMatchedGeometryKeyCount)"
    )

    // Frame 2: a different view with the SAME matched-geometry key
    // appears in slot B (column N).  The swap is conditional — we
    // reorder the children so the hero's identity path changes.
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    _ = renderer.render(
      HStack(spacing: 1) {
        Text("other")
        Text("hero").matchedGeometryEffect(id: "hero")
      },
      context: ResolveContext(identity: rootIdentity, transaction: transaction),
      proposal: ProposedSize(width: .finite(40), height: .finite(3))
    )

    #expect(
      controller.activeMatchedGeometryCount > 0,
      "matched geometry animation should be enqueued after the swap, got \(controller.activeMatchedGeometryCount)"
    )
    #expect(
      controller.lastTickResult.hasPendingWork,
      "frame 2 should report active animation"
    )
  }

  @Test(
    "matchedGeometryEffect: isSource: false does not contribute bounds to the match"
  )
  func matchedGeometryIsSourceFalseDoesNotContribute() throws {
    // When a view is tagged with isSource: false, the
    // capturePlacedTree walker skips it and no bounds are recorded
    // for the key.  A subsequent frame that inserts a different
    // view with the same key has no source to animate from, so no
    // match fires.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    AnimationRegistrationStorage.currentSink = controller
    TransitionRegistrationStorage.currentSink = controller
    defer {
      AnimationRegistrationStorage.currentSink = nil
      TransitionRegistrationStorage.currentSink = nil
    }

    let animation = Animation.linear(duration: .milliseconds(1_000_000))
    controller.register(animation)

    let rootIdentity = Identity(components: [.named("root")])

    // Frame 1: hero tagged isSource: false.  The controller
    // should NOT record its bounds.
    _ = renderer.render(
      HStack(spacing: 1) {
        Text("hero").matchedGeometryEffect(id: "hero", isSource: false)
        Text("other")
      },
      context: ResolveContext(identity: rootIdentity),
      proposal: ProposedSize(width: .finite(40), height: .finite(3))
    )
    #expect(
      controller.previousMatchedGeometryKeyCount == 0,
      "non-source view should not contribute bounds, got \(controller.previousMatchedGeometryKeyCount)"
    )

    // Frame 2: swap children.  No source bounds available → no
    // match should fire.
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    _ = renderer.render(
      HStack(spacing: 1) {
        Text("other")
        Text("hero").matchedGeometryEffect(id: "hero", isSource: false)
      },
      context: ResolveContext(identity: rootIdentity, transaction: transaction),
      proposal: ProposedSize(width: .finite(40), height: .finite(3))
    )
    #expect(
      controller.activeMatchedGeometryCount == 0,
      "non-source swap should not enqueue a match, got \(controller.activeMatchedGeometryCount)"
    )
  }

  @Test(
    "matchedGeometryEffect: @Namespace allocates a stable ID per view instance"
  )
  func matchedGeometryNamespaceIsStableAcrossRenders() throws {
    // Direct check of the Namespace allocator: two fresh Namespace
    // values should have distinct IDs, mirroring how SwiftUI
    // allocates a new namespace per @Namespace property.
    let first = MatchedGeometryNamespaceAllocator.next()
    let second = MatchedGeometryNamespaceAllocator.next()
    #expect(first != second)
    #expect(first.rawValue != 0, "allocator should not collide with .default")
    #expect(second.rawValue != 0)
  }

  @Test(
    "matchedGeometryEffect: at progress 0 the new identity renders at the source bounds"
  )
  func matchedGeometryRendersAtSourceAtProgressZero() throws {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    AnimationRegistrationStorage.currentSink = controller
    TransitionRegistrationStorage.currentSink = controller
    defer {
      AnimationRegistrationStorage.currentSink = nil
      TransitionRegistrationStorage.currentSink = nil
    }

    let animation = Animation.linear(duration: .milliseconds(1_000_000))
    controller.register(animation)

    let rootIdentity = Identity(components: [.named("root")])

    // Frame 1: hero at slot 0.
    _ = renderer.render(
      HStack(spacing: 1) {
        Text("hero").matchedGeometryEffect(id: "hero")
        Text("other")
      },
      context: ResolveContext(identity: rootIdentity),
      proposal: ProposedSize(width: .finite(40), height: .finite(3))
    )

    // Frame 2: hero at slot 1 (children swapped), under animate intent.
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    let frame2 = renderer.render(
      HStack(spacing: 1) {
        Text("other")
        Text("hero").matchedGeometryEffect(id: "hero")
      },
      context: ResolveContext(identity: rootIdentity, transaction: transaction),
      proposal: ProposedSize(width: .finite(40), height: .finite(3))
    )

    // Find any node tagged with the hero matched-geometry key in
    // the post-overlay placed tree.  At progress ~0 the hero
    // translation should carry it back to slot 0 (the source).
    let heroBounds = Self.findBoundsForMatchedKey(frame2.placedTree, keyID: "hero")
    #expect(heroBounds != nil)
    if let heroBounds {
      // Slot 0 is column 0, slot 1 is roughly column 6+ (after
      // "other" and the 1-cell spacing).  At progress 0 the hero's
      // bounds should be near column 0, not near column 6.
      #expect(
        heroBounds.origin.x < 5,
        "at progress 0 hero should appear at its previous slot (column 0), got x=\(heroBounds.origin.x)"
      )
    }
  }

  private static func findBoundsForMatchedKey(
    _ node: PlacedNode,
    keyID: String
  ) -> CellRect? {
    if let config = node.matchedGeometry, config.key.id == keyID {
      return node.bounds
    }
    for child in node.children {
      if let found = findBoundsForMatchedKey(child, keyID: keyID) {
        return found
      }
    }
    return nil
  }

  @Test(
    ".position(x:y:) places the child centered at the given point"
  )
  func positionPlacesCenterAtGivenPoint() throws {
    // Verifies the new .position LayoutBehavior + modifier wires
    // through the layout engine correctly: the wrapper takes the
    // full proposed space and the child is placed centered at
    // (x, y) within that space.
    let renderer = DefaultRenderer()
    let rootIdentity = Identity(components: [.named("root")])

    let frame = renderer.render(
      Text("hi").position(x: 20, y: 5),
      context: ResolveContext(identity: rootIdentity),
      proposal: ProposedSize(width: .finite(80), height: .finite(24))
    )

    // Walk the placed tree looking for the Position wrapper and
    // verify its child is centered at (20, 5).
    let positionChildBounds = Self.findPositionContainerChildBounds(
      frame.placedTree
    )
    #expect(positionChildBounds != nil)
    if let bounds = positionChildBounds {
      // Text "hi" measures as 2x1, so its origin should be at
      // (20 - 2/2, 5 - 1/2) = (19, 5).  Integer division floor.
      let expectedX = 20 - bounds.size.width / 2
      let expectedY = 5 - bounds.size.height / 2
      #expect(
        bounds.origin.x == expectedX,
        "position child origin.x should be \(expectedX), got \(bounds.origin.x)"
      )
      #expect(
        bounds.origin.y == expectedY,
        "position child origin.y should be \(expectedY), got \(bounds.origin.y)"
      )
    }
  }

  private static func findPositionContainerChildBounds(_ placed: PlacedNode) -> CellRect? {
    if case .view(let name) = placed.kind, name == "Position" {
      return placed.children.first?.bounds
    }
    for child in placed.children {
      if let found = findPositionContainerChildBounds(child) {
        return found
      }
    }
    return nil
  }

  @Test(
    ".position(x:y:) animates when coordinates change under withAnimation"
  )
  func positionAnimatesThroughPipeline() throws {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let animation = Animation.linear(duration: .milliseconds(1_000_000))
    controller.register(animation)

    let rootIdentity = Identity(components: [.named("root")])

    // Frame 1: position at (10, 5).
    _ = renderer.render(
      Text("hi").position(x: 10, y: 5),
      context: ResolveContext(identity: rootIdentity),
      proposal: ProposedSize(width: .finite(80), height: .finite(24))
    )
    #expect(controller.activeAnimationCount == 0)

    // Frame 2: position at (40, 15) under animate intent.
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    _ = renderer.render(
      Text("hi").position(x: 40, y: 15),
      context: ResolveContext(identity: rootIdentity, transaction: transaction),
      proposal: ProposedSize(width: .finite(80), height: .finite(24))
    )
    #expect(
      controller.activeAnimationCount >= 1,
      "position change should enqueue at least one slot animation, got \(controller.activeAnimationCount)"
    )
    #expect(controller.lastTickResult.hasPendingWork)
  }

  @Test(
    "probe: composed .offset + .frame animate together under one withAnimation"
  )
  func probeComposedOffsetAndFrameAnimation() throws {
    // Probe: can we animate BOTH offset and frame simultaneously
    // via a single withAnimation state change?  Both OffsetView and
    // FrameView/FlexibleFrameView produce distinct ResolvedNodes with
    // distinct layoutBehavior variants, so the controller should
    // enqueue animations on BOTH identities in the same batch.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let animation = Animation.linear(duration: .milliseconds(1_000_000))
    controller.register(animation)

    let rootIdentity = Identity(components: [.named("root")])

    // Frame 1: narrow frame at origin offset.
    _ = renderer.render(
      Text("hello")
        .frame(maxWidth: .finite(10), alignment: .leading)
        .offset(x: 0, y: 0),
      context: ResolveContext(identity: rootIdentity)
    )
    #expect(
      controller.activeAnimationCount == 0,
      "no animations should be active before the animated state change"
    )

    // Frame 2: wider frame AND non-zero offset under one animate intent.
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    _ = renderer.render(
      Text("hello")
        .frame(maxWidth: .finite(40), alignment: .leading)
        .offset(x: 20, y: 0),
      context: ResolveContext(identity: rootIdentity, transaction: transaction)
    )

    // Should have enqueued at least 2 animations: frameWidth + offsetX.
    #expect(
      controller.activeAnimationCount >= 2,
      "expected frameWidth + offsetX to both enqueue, got \(controller.activeAnimationCount)"
    )
    #expect(
      controller.lastTickResult.hasPendingWork,
      "frame 2 should report active animations"
    )
  }

  @Test(
    "probe: .offset(x:y:) animates when numeric args change under withAnimation"
  )
  func probeOffsetAnimationThroughPipeline() throws {
    // Probe: does .offset(x:y:) animate when its numeric arguments
    // change under withAnimation?  The controller's diff + applyValue
    // path should enqueue offsetX/offsetY animations and the layout
    // engine should reflow the child bounds every tick.
    //
    // End-to-end via DefaultRenderer so we catch any retained-reuse
    // cache interaction.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let animation = Animation.linear(duration: .milliseconds(1_000_000))
    controller.register(animation)

    let rootIdentity = Identity(components: [.named("root")])

    // Frame 1: offset (0, 0) → baseline.
    _ = renderer.render(
      Text("hello").offset(x: 0, y: 0),
      context: ResolveContext(identity: rootIdentity)
    )

    // Frame 2: offset (20, 0) under animate intent.
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    let frame2 = renderer.render(
      Text("hello").offset(x: 20, y: 0),
      context: ResolveContext(identity: rootIdentity, transaction: transaction)
    )

    // If the diff+applyValue path works, the controller should now
    // hold an active offsetX animation.
    #expect(
      controller.activeAnimationCount > 0,
      "frame 2 should enqueue an offsetX animation, got count=\(controller.activeAnimationCount)"
    )
    #expect(
      controller.lastTickResult.hasPendingWork,
      "frame 2 should report hasPendingWork after offset change"
    )

    // The placed tree should carry the interpolated offset (at
    // progress ~0 it matches the previous offset, so the bounds
    // should approximately equal frame 1's child bounds, not the
    // new layout's (20, 0).  The key test is whether the interpolation
    // machinery is engaged at all.
    let frame2Offset = Self.findOffsetContainerChildBounds(frame2.placedTree)
    #expect(frame2Offset != nil)
    if let frame2Offset {
      // At progress 0 with from=0, to=20, interpolated=0.
      // Child origin should be at (0, 0), not (20, 0).
      #expect(
        frame2Offset.origin.x == 0,
        "at progress 0, offset child should still be at x=0 (interpolated from=0), got \(frame2Offset.origin.x)"
      )
    }

    // Frame 3: same tree as frame 2 (tick frame, no state change).
    // The active animation should still be running and the bounds
    // should still reflect the interpolated (not the final) offset.
    let frame3 = renderer.render(
      Text("hello").offset(x: 20, y: 0),
      context: ResolveContext(identity: rootIdentity)
    )
    let frame3Offset = Self.findOffsetContainerChildBounds(frame3.placedTree)
    #expect(frame3Offset != nil)
    if let frame3Offset {
      #expect(
        frame3Offset.origin.x < 20,
        "frame 3 tick should still be interpolating, not yet at 20 (got \(frame3Offset.origin.x))"
      )
    }
    #expect(
      controller.lastTickResult.hasPendingWork,
      "frame 3 tick should still report active animation"
    )
    _ = frame3
  }

  /// Walks a placed tree looking for a node whose kind is "Offset"
  /// and returns its single child's bounds.  Used by the offset
  /// animation probe to verify the child has been placed at the
  /// interpolated offset.
  private static func findOffsetContainerChildBounds(_ placed: PlacedNode) -> CellRect? {
    if case .view(let name) = placed.kind, name == "Offset" {
      return placed.children.first?.bounds
    }
    for child in placed.children {
      if let found = findOffsetContainerChildBounds(child) {
        return found
      }
    }
    return nil
  }

  @Test(
    "insertion offset animation survives across tick frames and completes cleanly"
  )
  func insertionOffsetAnimationCompletes() throws {
    // Regression for the "slide-in hitches and sticks partway
    // through until you click" gallery bug.  The insertion offset
    // animation state must survive across tick frames (no accidental
    // purges) and progress monotonically toward zero delta.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController

    AnimationRegistrationStorage.currentSink = controller
    TransitionRegistrationStorage.currentSink = controller
    defer {
      AnimationRegistrationStorage.currentSink = nil
      TransitionRegistrationStorage.currentSink = nil
    }

    let surfaceSize = CellSize(width: 40, height: 5)
    let proposal = ProposedSize(
      width: .finite(surfaceSize.width),
      height: .finite(surfaceSize.height)
    )

    // Very long duration so consecutive renderer.render calls at
    // microsecond-apart real time produce different delta values.
    let animation = Animation.linear(duration: .milliseconds(1_000_000))
    controller.register(animation)

    let rootIdentity = Identity(components: [.named("root")])

    // Frame 1: slide not shown.
    _ = renderer.render(
      VStack(alignment: .leading, spacing: 0) {
      },
      context: ResolveContext(identity: rootIdentity),
      proposal: proposal
    )

    // Frame 2: slide appears under animate intent.  Insertion animation
    // should be enqueued.
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    let frame2 = renderer.render(
      VStack(alignment: .leading, spacing: 0) {
        Text("hello").transition(.slide)
      },
      context: ResolveContext(identity: rootIdentity, transaction: transaction),
      proposal: proposal
    )

    let frame2TextBounds = Self.findTextBounds(frame2.placedTree, text: "hello")
    #expect(
      frame2TextBounds?.origin.x == -surfaceSize.width,
      "slide insertion should start a full surface width offscreen, got \(String(describing: frame2TextBounds?.origin.x))"
    )

    // Verify the insertion animation was enqueued on frame 2.
    let frame2Count = controller.activeInsertionOffsetCount
    #expect(
      frame2Count > 0,
      "insertion offset animation should be enqueued after frame 2, got \(frame2Count)"
    )

    // Frame 3: same tree, no state change — this is a tick frame.
    // The insertion animation state should persist.
    let frame3 = renderer.render(
      VStack(alignment: .leading, spacing: 0) {
        Text("hello").transition(.slide)
      },
      context: ResolveContext(identity: rootIdentity),
      proposal: proposal
    )
    let frame3Count = controller.activeInsertionOffsetCount
    #expect(
      frame3Count > 0,
      "insertion offset animation should still be in flight after frame 3, got \(frame3Count)"
    )
    // Even with insertion-offset entries populated in the unified
    // activeAnimations map, the controller must report hasPendingWork
    // via lastTickResult on tick frames — otherwise the run loop
    // stops scheduling deadlines and the animation hitches partway
    // through.
    #expect(
      controller.lastTickResult.hasPendingWork,
      "frame 3 tick should report hasPendingWork=true while the insertion is still in flight"
    )
    #expect(
      controller.lastTickResult.nextDeadline != nil,
      "frame 3 tick should carry a nextDeadline for the in-flight insertion"
    )
    _ = frame2
    _ = frame3
  }

  @Test(
    "removal overlays do not accumulate across tick frames"
  )
  func removalOverlaysDoNotAccumulateAcrossTickFrames() throws {
    // Regression for the "slide-out leaves render artefacts"
    // gallery bug: `applyPlacedOverlays` used to mutate the placed
    // tree in place, and the retained frame-tail state committed the
    // mutated tree to the retained cache.  Subsequent tick frames
    // then reused that cached tree via `retainedPlacement` and
    // `applyPlacedOverlays` injected ANOTHER overlay on top,
    // growing the tree each tick and leaving ghosted artefacts
    // visible after the animation completed.
    //
    // The fix stores the BASELINE (pre-overlay) placed tree into
    // the retained frame store so future tick frames start from
    // the canonical layout.  This test drives three consecutive
    // renders through DefaultRenderer, manually installing the
    // transition sink (RunLoop does this at startup; DefaultRenderer
    // alone does not) and then asserts the placed tree's transient
    // count stays bounded across renders.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController

    // Manually install the sinks that RunLoop would install at
    // startup — DefaultRenderer.render alone does not wire them.
    AnimationRegistrationStorage.currentSink = controller
    TransitionRegistrationStorage.currentSink = controller
    defer {
      AnimationRegistrationStorage.currentSink = nil
      TransitionRegistrationStorage.currentSink = nil
    }

    let animation = Animation.linear(duration: .milliseconds(2000))
    controller.register(animation)

    let rootIdentity = Identity(components: [.named("root")])

    // Frame 1: show a single Text child with .transition(.opacity).
    _ = renderer.render(
      VStack(alignment: .leading, spacing: 0) {
        Text("hello").transition(.opacity)
      },
      context: ResolveContext(identity: rootIdentity)
    )

    // Frame 2: remove the child under an animate transaction.
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    let frame2 = renderer.render(
      VStack(alignment: .leading, spacing: 0) {
        // empty — Text removed
      },
      context: ResolveContext(identity: rootIdentity, transaction: transaction)
    )
    let frame2TransientCount = Self.countTransientNodes(frame2.placedTree)

    // If the controller didn't capture any removal, skip the rest
    // of the test — this suite's scope is just the retained-reuse
    // accumulation bug, not transition registration reliability.
    guard frame2TransientCount > 0 else {
      Issue.record(
        "removal detection did not produce a transient overlay; transition registration flow is not exercising this test case"
      )
      return
    }

    // Frame 3: same view tree (tick frame).  Without the fix, the
    // retained cache contains frame 2's placed tree (including the
    // transient overlay) and applyPlacedOverlays injects another
    // overlay on top → transient count >= 2.
    let frame3 = renderer.render(
      VStack(alignment: .leading, spacing: 0) {
      },
      context: ResolveContext(identity: rootIdentity)
    )
    let frame3TransientCount = Self.countTransientNodes(frame3.placedTree)

    // Frame 4: another tick — any accumulation bug compounds.
    let frame4 = renderer.render(
      VStack(alignment: .leading, spacing: 0) {
      },
      context: ResolveContext(identity: rootIdentity)
    )
    let frame4TransientCount = Self.countTransientNodes(frame4.placedTree)

    #expect(
      frame2TransientCount == frame3TransientCount,
      "tick frame 3 should have the same transient count as frame 2, got \(frame3TransientCount) vs \(frame2TransientCount)"
    )
    #expect(
      frame3TransientCount == frame4TransientCount,
      "tick frame 4 should have the same transient count as frame 3, got \(frame4TransientCount) vs \(frame3TransientCount)"
    )
  }

  private static func countTransientNodes(_ node: PlacedNode) -> Int {
    var total = node.isTransient ? 1 : 0
    for child in node.children {
      total += countTransientNodes(child)
    }
    return total
  }

  private static func findTextBounds(_ node: PlacedNode, text: String) -> CellRect? {
    if case .text(let rendered) = node.drawPayload, rendered == text {
      return node.bounds
    }
    for child in node.children {
      if let found = findTextBounds(child, text: text) {
        return found
      }
    }
    return nil
  }

  @Test(
    "drawMetadata changes reach the placed tree across retained-layout reuse"
  )
  func drawMetadataChangesReachPlacedTreeAcrossRetainedReuse() throws {
    // Regression for the gallery bug: the layout engine's retained-
    // placement cache deliberately ignores drawMetadata in its
    // equivalence check (so visual-only mutations don't invalidate
    // layout reuse).  Before the fix the cached PlacedNode was
    // returned wholesale with the PREVIOUS frame's drawMetadata,
    // so animation-controller color interpolation never reached the
    // raster pass.  After the fix refreshDrawMetadata copies visual
    // metadata from the current resolved tree onto the cached
    // placed node.
    //
    // This test drives two renders through DefaultRenderer with
    // different `foregroundStyle` colors but otherwise identical
    // view trees.  The second render should carry the NEW color in
    // its placed tree — not the cached color from the first render.
    let renderer = DefaultRenderer()
    let rootIdentity = Identity(components: [.named("root")])

    let frame1 = renderer.render(
      Text("Hello").foregroundStyle(Color.red),
      context: ResolveContext(identity: rootIdentity)
    )
    let frame1Color = Self.extractTextForegroundColor(frame1.placedTree)
    #expect(
      frame1Color == Color.red,
      "frame 1 should render red, got \(String(describing: frame1Color))"
    )

    // Second render with blue.  Layout is unchanged (same Text,
    // same string).  Before the fix, retainedPlacement returns the
    // cached red placed node.  After the fix, refreshDrawMetadata
    // copies blue from the current resolved tree.
    let frame2 = renderer.render(
      Text("Hello").foregroundStyle(Color.blue),
      context: ResolveContext(identity: rootIdentity)
    )
    let frame2Color = Self.extractTextForegroundColor(frame2.placedTree)
    #expect(
      frame2Color == Color.blue,
      "frame 2 should render blue after retained-reuse refresh, got \(String(describing: frame2Color))"
    )
  }

  private static func extractTextForegroundColor(_ placed: PlacedNode) -> Color? {
    if case .text = placed.drawPayload {
      if case .color(let color) = placed.drawMetadata.baseStyle.foregroundStyle {
        return color
      }
    }
    for child in placed.children {
      if let found = extractTextForegroundColor(child) {
        return found
      }
    }
    return nil
  }

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
    "an in-flight property animation follows its entity across an identity-changing move (G10a)"
  )
  func propertyAnimationFollowsEntityAcrossMove() throws {
    // G10a: a property animation is keyed by the owning entity (`ViewNodeID`),
    // captured at registration, so when the entity is re-parented to a new
    // structural `Identity` (e.g. an `.id`-keyed view moved between containers,
    // its lifetime preserved by the EntityRoutingTable) the in-flight
    // interpolation continues on the moved node instead of snapping/resetting.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(1000))
    controller.register(animation)

    let entityNodeID = ViewNodeID(rawValue: 777)
    let identityInA = Identity(components: [.named("containerA"), .named("leaf")])
    let identityInB = Identity(components: [.named("containerB"), .named("leaf")])

    // Seed: leaf in container A, fully opaque, owned by `entityNodeID`.
    var seedMetadata = DrawMetadata()
    seedMetadata.baseStyle.explicitOpacity = 1.0
    let seed = ResolvedNode(
      viewNodeID: entityNodeID,
      identity: identityInA,
      kind: .view("Text"),
      drawMetadata: seedMetadata
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(seed, transaction: .init(), timestamp: t0)

    // Frame 2: same entity, opacity animating toward 0 — registers a property
    // animation owned by `entityNodeID` at identity A.
    var fadeMetadata = DrawMetadata()
    fadeMetadata.baseStyle.explicitOpacity = 0.0
    let fading = ResolvedNode(
      viewNodeID: entityNodeID,
      identity: identityInA,
      kind: .view("Text"),
      drawMetadata: fadeMetadata
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(fading, transaction: transaction, timestamp: t0)

    // The entity has now moved to container B: a DIFFERENT `Identity`, the SAME
    // `ViewNodeID`, presented at its own baseline opacity (1.0) with no local
    // animation knowledge. Applying interpolations mid-flight must drive this
    // moved node's opacity from the animation that was registered at identity A.
    var movedMetadata = DrawMetadata()
    movedMetadata.baseStyle.explicitOpacity = 1.0
    var moved = ResolvedNode(
      viewNodeID: entityNodeID,
      identity: identityInB,
      kind: .view("Text"),
      drawMetadata: movedMetadata
    )

    let tick = controller.applyInterpolations(
      to: &moved,
      at: t0.advanced(by: .milliseconds(500))
    )

    guard let movedOpacity = moved.drawMetadata.baseStyle.explicitOpacity else {
      Issue.record("moved node lost its opacity slot")
      return
    }
    // Followed the entity: mid-flight value, not the moved node's 1.0 baseline
    // (which is what an identity-keyed lookup would have left untouched) and not
    // snapped to the 0.0 target.
    #expect(movedOpacity < 0.999, "animation did not follow the entity to its new identity")
    #expect(movedOpacity > 0.001, "animation snapped instead of interpolating")
    // The moved node's *current* identity must be in the redraw set so it
    // repaints under the live run loop, even though the animation was keyed at A.
    #expect(tick.redrawIdentities.contains(identityInB))
  }

  @Test(
    "withAnimation color mutation enqueues an active animation through the pipeline"
  )
  func colorAnimationEnqueuesThroughFullPipeline() throws {
    // Exercises the full render pipeline for an animated color
    // change: resolve → animation → measure → place →
    // applyPlacedOverlays → capturePlacedTree → semantics → draw
    // → raster. The test has no testable clock so it cannot pin
    // an exact interpolated color, but it can assert that the
    // controller observed the diff and transitioned into an active
    // state (activeAnimationCount > 0) after frame 2.
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
      controller.activeAnimationCount == 0,
      "no animations should be in flight before the animated mutation"
    )

    // Frame 2: text with blue foreground under an explicit animate
    // transaction.  The controller's diff path should enqueue an
    // active animation for the foreground color.
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
      controller.activeAnimationCount > 0,
      "controller must hold an active animation after the animated color change"
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
    let leafNodeID = ViewNodeID(rawValue: 2)

    // Manually register the transition against the controller, then
    // seed the controller with a prior frame state by calling
    // processResolvedTree and capturePlacedTree directly — this
    // avoids needing a full view-layer transition modifier setup.
    controller.beginTransitionCollection()
    controller.registerTransition(
      for: leafIdentity,
      viewNodeID: leafNodeID,
      transition: AnyTransition.opacity
    )
    controller.finishTransitionCollection()

    // Seed: leaf present in the prior resolved + placed trees.
    let leafResolved = ResolvedNode(
      viewNodeID: leafNodeID,
      identity: leafIdentity,
      kind: .view("Leaf")
    )
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
      bounds: CellRect(origin: .zero, size: CellSize(width: 10, height: 1)),
      children: [
        PlacedNode(
          identity: leafIdentity,
          kind: .view("Leaf"),
          bounds: CellRect(origin: .zero, size: CellSize(width: 5, height: 1))
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
      bounds: CellRect(origin: .zero, size: CellSize(width: 10, height: 1)),
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

  @Test(
    "structural first-appearance does not fire insertion transition"
  )
  func structuralFirstAppearanceSkipsInsertionTransition() throws {
    // When a parent and child appear together (e.g. tab switch),
    // the child's .transition(.opacity) must NOT fire — the whole
    // subtree is a structural mount, not a conditional toggle.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(500))
    controller.register(animation)

    let rootIdentity = Identity(components: [.named("root")])
    let parentIdentity = Identity(components: [.named("root"), .named("parent")])
    let leafIdentity = Identity(
      components: [.named("root"), .named("parent"), .named("leaf")]
    )
    let leafNodeID = ViewNodeID(rawValue: 3)

    // Frame 1: only root exists (simulates a different tab active).
    let frame1 = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: []
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    // Frame 2: parent + leaf appear together under an animate
    // transaction.  Register a .opacity transition on the leaf.
    controller.beginTransitionCollection()
    controller.registerTransition(
      for: leafIdentity,
      viewNodeID: leafNodeID,
      transition: AnyTransition.opacity
    )
    controller.finishTransitionCollection()

    let leafNode = ResolvedNode(
      viewNodeID: leafNodeID,
      identity: leafIdentity,
      kind: .view("Leaf")
    )
    let parentNode = ResolvedNode(
      identity: parentIdentity,
      kind: .view("Parent"),
      children: [leafNode]
    )
    let frame2 = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: [parentNode]
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(
      frame2,
      transaction: transaction,
      timestamp: t0.advanced(by: .milliseconds(1))
    )

    // No insertion animation should have been enqueued for the leaf
    // because its parent was also freshly inserted.
    #expect(
      controller.activeAnimationCount == 0,
      "structural first-appearance must not enqueue insertion animations, got \(controller.activeAnimationCount)"
    )
  }

  @Test(
    "structural bulk-unmount does not fire removal transition"
  )
  func structuralBulkUnmountSkipsRemovalTransition() throws {
    // When a multi-child container and its descendants disappear
    // together (e.g. tab switch), the descendant’s .transition()
    // removal must NOT fire — the whole subtree was unmounted, not
    // a conditional toggle.  The walk-up stops at the multi-child
    // container and the guard rejects it because the container is
    // not a surviving identity.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(500))
    controller.register(animation)

    let rootIdentity = Identity(components: [.named("root")])
    let containerIdentity = Identity(components: [.named("root"), .named("container")])
    let leafIdentity = Identity(
      components: [.named("root"), .named("container"), .named("leaf")]
    )
    let leafNodeID = ViewNodeID(rawValue: 4)
    let siblingIdentity = Identity(
      components: [.named("root"), .named("container"), .named("sibling")]
    )

    // Frame 1: root → container(2 children: leaf + sibling).
    // Register .opacity transition on the leaf.
    controller.beginTransitionCollection()
    controller.registerTransition(
      for: leafIdentity,
      viewNodeID: leafNodeID,
      transition: AnyTransition.opacity
    )
    controller.finishTransitionCollection()

    let leafNode = ResolvedNode(
      viewNodeID: leafNodeID,
      identity: leafIdentity,
      kind: .view("Leaf")
    )
    let siblingNode = ResolvedNode(identity: siblingIdentity, kind: .view("Sibling"))
    let containerNode = ResolvedNode(
      identity: containerIdentity,
      kind: .view("Container"),
      children: [leafNode, siblingNode]
    )
    let frame1 = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: [containerNode]
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    // Frame 2: container + all children gone (bulk unmount) under
    // an animate transaction.  No removal overlay should be created.
    controller.beginTransitionCollection()
    controller.finishTransitionCollection()

    let frame2 = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: []
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(
      frame2,
      transaction: transaction,
      timestamp: t0.advanced(by: .milliseconds(1))
    )

    // The removal overlay map should be empty — the walk-up stopped
    // at the multi-child container and the guard rejected it.
    var tree = frame2
    let result = controller.applyInterpolations(
      to: &tree,
      at: t0.advanced(by: .milliseconds(50))
    )
    #expect(
      tree.children.isEmpty,
      "bulk unmount must not inject a removal overlay, got \(tree.children.count) children"
    )
    #expect(
      !result.hasPendingWork,
      "no animations should be in flight after a bulk unmount"
    )
  }

  @Test(
    "conditional toggle still fires insertion transition when parent is stable"
  )
  func conditionalToggleFiresInsertionTransition() throws {
    // When only the child is inserted (parent already present),
    // the insertion animation must fire — this is the normal
    // withAnimation { showFigure.toggle() } path.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(500))
    controller.register(animation)

    let rootIdentity = Identity(components: [.named("root")])
    let leafIdentity = Identity(components: [.named("root"), .named("leaf")])
    let leafNodeID = ViewNodeID(rawValue: 2)

    // Frame 1: root exists, leaf absent.
    let frame1 = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: []
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    // Frame 2: leaf appears under root with an animate transaction.
    controller.beginTransitionCollection()
    controller.registerTransition(
      for: leafIdentity,
      viewNodeID: leafNodeID,
      transition: AnyTransition.opacity
    )
    controller.finishTransitionCollection()

    let leafNode = ResolvedNode(
      viewNodeID: leafNodeID,
      identity: leafIdentity,
      kind: .view("Leaf")
    )
    let frame2 = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: [leafNode]
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(
      frame2,
      transaction: transaction,
      timestamp: t0.advanced(by: .milliseconds(1))
    )

    // The insertion animation must fire because only the leaf is new
    // (root was already present).
    #expect(
      controller.activeAnimationCount > 0,
      "conditional toggle must enqueue an insertion animation"
    )
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

    #expect(result.hasPendingWork)

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
    let leafNodeID = ViewNodeID(rawValue: 2)

    let leaf = ResolvedNode(
      viewNodeID: leafNodeID,
      identity: leafIdentity,
      kind: .view("Leaf")
    )
    let root = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: [leaf]
    )
    controller.beginTransitionCollection()
    controller.registerTransition(
      for: leafIdentity,
      viewNodeID: leafNodeID,
      transition: AnyTransition.opacity
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
    let leafNodeID = ViewNodeID(rawValue: 2)

    let surfaceSize = CellSize(width: 20, height: 5)

    // Leaf already has a .offset(x: 5, y: 0) layout.  The removal
    // transition is .move(edge: .trailing), which adds the surface width.
    let leaf = ResolvedNode(
      viewNodeID: leafNodeID,
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
      viewNodeID: leafNodeID,
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

    // Apply near the end of the removal. With .move(edge: .trailing),
    // the transition offset is based on the surface width and composes
    // with the leaf's existing offset of 5.
    let tEnd = t1.advanced(by: .milliseconds(180))
    _ = controller.applyInterpolations(
      to: &frame2,
      at: tEnd,
      surfaceSize: surfaceSize
    )

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
    // At progress ~0.9, modifier offsetX = 20 * 0.9 = 18. Composed
    // with the original 5 -> 23.
    #expect(
      x >= 20, "composed offset should include the existing 5 and transition offset, got \(x)")
    #expect(y == 0)
  }

  @Test(
    "insertion transition offset translates placed bounds on intrinsic leaves"
  )
  func insertionOffsetTranslatesPlacedBounds() throws {
    // Regression for the "slide-in is instantaneous" gallery bug:
    // applyValue for offsetX/offsetY only mutates nodes whose
    // layoutBehavior is already .offset, so .transition(.move(edge:))
    // on a Text (or any intrinsic-layout leaf) silently did nothing.
    // The fix routes insertion offsets through a placed-level pass
    // that translates matching bounds regardless of layoutBehavior.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(1000))
    controller.register(animation)

    let rootIdentity = Identity(components: [.named("root")])
    let leafIdentity = Identity(components: [.named("root"), .named("leaf")])
    let leafNodeID = ViewNodeID(rawValue: 2)

    // Frame 0: root alone — seeds previousIdentities so the leaf
    // insertion on frame 1 is a conditional toggle, not a structural
    // first-appearance.
    let seedRoot = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: []
    )
    let tSeed = MonotonicInstant.now()
    controller.processResolvedTree(seedRoot, transaction: .init(), timestamp: tSeed)

    // Frame 1: leaf appears with .transition(.move(edge: .leading)).
    controller.beginTransitionCollection()
    controller.registerTransition(
      for: leafIdentity,
      viewNodeID: leafNodeID,
      transition: AnyTransition.move(edge: .leading)
    )
    controller.finishTransitionCollection()

    let leaf = ResolvedNode(
      viewNodeID: leafNodeID,
      identity: leafIdentity,
      kind: .view("Leaf")
    )
    let root = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: [leaf]
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    let t0 = tSeed.advanced(by: .milliseconds(1))
    controller.processResolvedTree(root, transaction: transaction, timestamp: t0)

    // Build a synthetic placed tree that matches what LayoutEngine
    // would produce: the leaf at bounds (0, 0, 5, 1), root at
    // (0, 0, 20, 5).
    var placed = PlacedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      bounds: CellRect(origin: .zero, size: CellSize(width: 20, height: 5)),
      children: [
        PlacedNode(
          identity: leafIdentity,
          kind: .view("Leaf"),
          bounds: CellRect(origin: .zero, size: CellSize(width: 5, height: 1))
        )
      ]
    )

    // Apply placed overlays at t0.  The move(edge: .leading) transition
    // resolves against the 20-column surface. At progress 0, the
    // leaf's bounds should be translated by (-20, 0) -> origin.x = -20.
    controller.applyPlacedOverlays(to: &placed, at: t0)

    let leafAtStart = placed.children.first
    #expect(leafAtStart != nil)
    #expect(
      leafAtStart?.bounds.origin.x == -20,
      "insertion at t=0 should translate leaf by the transition's initial offset, got \(String(describing: leafAtStart?.bounds.origin.x))"
    )

    // Halfway through the animation, delta should be -10.
    var placedHalf = PlacedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      bounds: CellRect(origin: .zero, size: CellSize(width: 20, height: 5)),
      children: [
        PlacedNode(
          identity: leafIdentity,
          kind: .view("Leaf"),
          bounds: CellRect(origin: .zero, size: CellSize(width: 5, height: 1))
        )
      ]
    )
    controller.applyPlacedOverlays(
      to: &placedHalf,
      at: t0.advanced(by: .milliseconds(500))
    )
    let leafAtHalf = placedHalf.children.first
    #expect(
      leafAtHalf?.bounds.origin.x ?? 0 == -10
        || leafAtHalf?.bounds.origin.x ?? 0 == -9
        || leafAtHalf?.bounds.origin.x ?? 0 == -11,
      "insertion halfway should translate by approx -10, got \(String(describing: leafAtHalf?.bounds.origin.x))"
    )

    // Well past the animation end, delta should be 0 (final position).
    var placedDone = PlacedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      bounds: CellRect(origin: .zero, size: CellSize(width: 20, height: 5)),
      children: [
        PlacedNode(
          identity: leafIdentity,
          kind: .view("Leaf"),
          bounds: CellRect(origin: .zero, size: CellSize(width: 5, height: 1))
        )
      ]
    )
    controller.applyPlacedOverlays(
      to: &placedDone,
      at: t0.advanced(by: .milliseconds(1500))
    )
    let leafAtEnd = placedDone.children.first
    #expect(
      leafAtEnd?.bounds.origin.x == 0,
      "insertion after end should translate to final position (no delta), got \(String(describing: leafAtEnd?.bounds.origin.x))"
    )
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
    let leafNodeID = ViewNodeID(rawValue: 2)

    let leaf = ResolvedNode(
      viewNodeID: leafNodeID,
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
      viewNodeID: leafNodeID,
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
    _ = controller.applyInterpolations(
      to: &frame2,
      at: tMid,
      surfaceSize: CellSize(width: 20, height: 10)
    )

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
    let leafNodeID = ViewNodeID(rawValue: 2)

    // Frame 0: root alone — seeds previousIdentities so the leaf
    // insertion on frame 1 is a conditional toggle, not a structural
    // first-appearance.
    let seedRoot = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: []
    )
    let tSeed = MonotonicInstant.now()
    controller.processResolvedTree(seedRoot, transaction: .init(), timestamp: tSeed)

    // Frame 1: leaf inserted with .opacity transition under
    // withAnimation intent → starts the fade-in.
    controller.beginTransitionCollection()
    controller.registerTransition(
      for: leafIdentity,
      viewNodeID: leafNodeID,
      transition: AnyTransition.opacity
    )
    controller.finishTransitionCollection()

    let frame1 = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: [
        ResolvedNode(
          viewNodeID: leafNodeID,
          identity: leafIdentity,
          kind: .view("Leaf")
        )
      ]
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    let t0 = tSeed.advanced(by: .milliseconds(1))
    controller.processResolvedTree(frame1, transaction: transaction, timestamp: t0)

    // Frame 2: at t=100ms (midway), the leaf disappears.
    // The transition registration is NOT re-emitted because the
    // branch is gone, so the controller must use the previous frame's
    // transition map to detect the removal.
    let frame2 = ResolvedNode(
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

  @Test("frame-head transaction defers batch completion until commit")
  func frameHeadTransactionDefersBatchCompletionUntilCommit() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(100))
    controller.register(animation)

    let batchID = AnimationBatchID(8_001)
    let fireCount = FireCounter()
    controller.registerCompletion(batchID: batchID) {
      fireCount.increment()
    }

    let leafIdentity = Identity(components: [.named("transaction-leaf")])
    var frame1Metadata = DrawMetadata()
    frame1Metadata.baseStyle.explicitOpacity = 1.0
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      drawMetadata: frame1Metadata
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    let checkpoint = controller.beginFrameHeadTransaction()

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

    let past = t0.advanced(by: .milliseconds(200))
    _ = controller.applyInterpolations(to: &frame2, at: past)
    #expect(fireCount.count == 0)

    controller.commitFrameHeadTransaction(checkpoint)
    #expect(fireCount.count == 1)
  }

  @Test("frame-head transaction abort restores batch completion state")
  func frameHeadTransactionAbortRestoresBatchCompletionState() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(100))
    controller.register(animation)

    let batchID = AnimationBatchID(8_002)
    let fireCount = FireCounter()
    controller.registerCompletion(batchID: batchID) {
      fireCount.increment()
    }

    let leafIdentity = Identity(components: [.named("aborted-transaction-leaf")])
    var frame1Metadata = DrawMetadata()
    frame1Metadata.baseStyle.explicitOpacity = 1.0
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      drawMetadata: frame1Metadata
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

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

    let checkpoint = controller.beginFrameHeadTransaction()
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)
    let past = t0.advanced(by: .milliseconds(200))
    _ = controller.applyInterpolations(to: &frame2, at: past)
    #expect(fireCount.count == 0)

    controller.abortFrameHeadTransaction(checkpoint)
    #expect(fireCount.count == 0)
    #expect(controller.activeAnimationCount == 0)

    var committedFrame = frame2
    controller.processResolvedTree(committedFrame, transaction: transaction, timestamp: t0)
    _ = controller.applyInterpolations(to: &committedFrame, at: past)
    #expect(fireCount.count == 1)
  }

  @Test(
    "withAnimation completion fires after duration even when no tracked property changes"
  )
  func completionClosureFiresAfterDurationForStrandedBatch() throws {
    // Regression guard for the stranded-completion bug: when a
    // `withAnimation(...) { } completion: {}` scope wraps changes the
    // controller doesn't track as an ``AnimatableProperty`` (e.g.
    // gradient internals, pattern fills, untracked shape styles),
    // the batch still needs to fire its completion on time —
    // otherwise ``PhaseAnimator`` stalls awaiting a continuation
    // that never resumes.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(100))
    controller.register(animation)

    let batchID = AnimationBatchID(7_010)
    let fireCount = FireCounter()
    controller.registerCompletion(batchID: batchID) {
      fireCount.increment()
    }

    // Frame 1: a bare leaf with no animatable properties populated.
    let leafIdentity = Identity(components: [.named("untracked-leaf")])
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf")
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    // Frame 2: same leaf, same (empty) animatable snapshot — but
    // the transaction carries a batched animation intent.  Nothing
    // about this frame bumps any ``AnimatableProperty`` slot, so
    // the batch is stranded the instant it is opened.
    var frame2 = frame1
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    transaction.animationBatchID = batchID
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    // Halfway through the 100 ms duration: completion must not have
    // fired yet.  This is the distinguishing assertion — prior to
    // the drain fix, the completion never fires at all; we must
    // also make sure the drain does not fire *eagerly* at t0.
    let halfway = t0.advanced(by: .milliseconds(50))
    _ = controller.applyInterpolations(to: &frame2, at: halfway)
    #expect(fireCount.count == 0)

    // Past the duration: the drain fires exactly once.
    let past = t0.advanced(by: .milliseconds(200))
    var frame3 = frame2
    _ = controller.applyInterpolations(to: &frame3, at: past)
    #expect(fireCount.count == 1)

    // Subsequent ticks must not re-fire — the drained entry has to
    // be removed from both ``pendingEmptyBatchCompletions`` and
    // ``completionClosures`` in a single pass.
    var frame4 = frame3
    _ = controller.applyInterpolations(to: &frame4, at: past.advanced(by: .milliseconds(50)))
    #expect(fireCount.count == 1)
  }

  @Test("frame-head transaction defers stranded completion until commit")
  func frameHeadTransactionDefersStrandedCompletionUntilCommit() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(100))
    controller.register(animation)

    let batchID = AnimationBatchID(8_003)
    let fireCount = FireCounter()
    controller.registerCompletion(batchID: batchID) {
      fireCount.increment()
    }

    let leafIdentity = Identity(components: [.named("stranded-transaction-leaf")])
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf")
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    var frame2 = frame1
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    transaction.animationBatchID = batchID

    let checkpoint = controller.beginFrameHeadTransaction()
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)
    _ = controller.applyInterpolations(
      to: &frame2,
      at: t0.advanced(by: .milliseconds(200))
    )
    #expect(fireCount.count == 0)

    controller.commitFrameHeadTransaction(checkpoint)
    #expect(fireCount.count == 1)
  }

  @Test(
    "withAnimation(nil) completion fires immediately for stranded batch"
  )
  func completionClosureFiresImmediatelyForDisabledStrandedBatch() throws {
    // `withAnimation(nil) { ... } completion: { ... }` disables
    // animation but still expects the completion to fire once the
    // body returns.  The drain path treats `.disabled` as zero
    // duration so the completion fires on the next tick.
    let controller = AnimationController()
    let batchID = AnimationBatchID(7_011)
    let fireCount = FireCounter()
    controller.registerCompletion(batchID: batchID) {
      fireCount.increment()
    }

    let leafIdentity = Identity(components: [.named("disabled-leaf")])
    let frame1 = ResolvedNode(identity: leafIdentity, kind: .view("Leaf"))
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    // Frame 2: disabled animation request, same empty snapshot.
    var frame2 = frame1
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .disabled
    transaction.animationBatchID = batchID
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    // Tick at t0 itself should drain the zero-duration entry — the
    // deadline equals the timestamp, so the first tick fires the
    // completion.
    _ = controller.applyInterpolations(to: &frame2, at: t0)
    #expect(fireCount.count == 1)
  }

  @Test(
    "stranded batch drain surfaces a nextDeadline with empty redrawIdentities"
  )
  func strandedBatchDrainSurfacesWakeupDeadline() throws {
    // Contract pin: a pure-drain tick must carry
    // `hasPendingWork = true` and a concrete `nextDeadline` so
    // the run loop can reschedule itself — but its
    // `redrawIdentities` set will be empty because the drain
    // isn't tied to any visible view.  The run loop's wake-up logic
    // at ``RunLoop+Rendering.swift`` must treat an empty
    // ``redrawIdentities`` as "schedule unconditionally" for the
    // drain to actually drive itself forward in a real render loop.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(500))
    controller.register(animation)

    let batchID = AnimationBatchID(7_013)
    controller.registerCompletion(batchID: batchID) {}

    let leafIdentity = Identity(components: [.named("drain-surface-leaf")])
    let frame1 = ResolvedNode(identity: leafIdentity, kind: .view("Leaf"))
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    let frame2 = frame1
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    transaction.animationBatchID = batchID
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    // Tick well before the drain's deadline: the result must carry
    // pending work + a nextDeadline, and redrawIdentities must be
    // empty because the drain doesn't belong to any view.
    var working = frame2
    let tick = controller.applyInterpolations(
      to: &working,
      at: t0.advanced(by: .milliseconds(50))
    )
    #expect(tick.hasPendingWork)
    #expect(tick.nextDeadline != nil)
    #expect(tick.redrawIdentities.isEmpty)
  }

  @Test(
    "withAnimation(.repeatForever) stranded batch never fires completion"
  )
  func completionClosureSuppressedForForeverStrandedBatch() throws {
    // SwiftUI never fires completions for `.repeatForever` — the
    // drain must treat infinite animations as a hard no-fire.  We
    // also verify the closure is dropped from
    // ``completionClosures`` so it doesn't leak indefinitely.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(100)).repeatForever()
    controller.register(animation)

    let batchID = AnimationBatchID(7_012)
    let fireCount = FireCounter()
    controller.registerCompletion(batchID: batchID) {
      fireCount.increment()
    }

    let leafIdentity = Identity(components: [.named("forever-leaf")])
    let frame1 = ResolvedNode(identity: leafIdentity, kind: .view("Leaf"))
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    let frame2 = frame1
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    transaction.animationBatchID = batchID
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    // Walk far into the future — the closure must never fire.
    let past = t0.advanced(by: .milliseconds(10_000))
    var frame3 = frame2
    _ = controller.applyInterpolations(to: &frame3, at: past)
    #expect(fireCount.count == 0)
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

    #expect(result.hasPendingWork)
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
    #expect(!finalResult.hasPendingWork)
  }

  @Test(
    "CustomAnimation state survives retarget through sample()"
  )
  func customAnimationStateSurvivesRetarget() throws {
    // Pin the call path that the controller's `sample(_:at:)` helper
    // uses when an animation is interrupted mid-flight: the existing
    // animation's `customState` MUST be threaded through
    // `anim.evaluate(elapsed:state:)` so a stateful
    // ``CustomAnimation`` sees the bookkeeping it accumulated on the
    // previous tick instead of a fresh empty state.
    //
    // The recorder captures every counter value the CustomAnimation
    // observes via `context.state`; the test then asserts that the
    // sample-time call (issued during retarget) saw a value > 0 —
    // proving state was carried forward rather than reset.
    let recorder = StateRecorder()
    let animation = Animation(
      RecordingCustomAnimation(id: "retarget-pin", recorder: recorder)
    )
    let controller = AnimationController()
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("retarget-leaf")])

    // Frame 1: opacity 1.0 (baseline snapshot, no animation yet).
    var frame1Metadata = DrawMetadata()
    frame1Metadata.baseStyle.explicitOpacity = 1.0
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      drawMetadata: frame1Metadata
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    // Frame 2: opacity 0.0 under the recording custom animation.
    // This enqueues the active animation.
    var frame2Metadata = DrawMetadata()
    frame2Metadata.baseStyle.explicitOpacity = 0.0
    let frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      drawMetadata: frame2Metadata
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    // Tick 1: drive the animation so the CustomAnimation accumulates
    // counter == 1 in its state, and the controller writes it back to
    // the active animation's `customState`.
    let tick1 = t0.advanced(by: .milliseconds(60))
    var tickFrame1 = frame2
    _ = controller.applyInterpolations(to: &tickFrame1, at: tick1)
    let observedAfterTick1 = recorder.lastObserved
    let callsAfterTick1 = recorder.callCount

    // Sanity: at least one call landed and counter advanced past 0.
    #expect(callsAfterTick1 >= 1)
    #expect(observedAfterTick1 == 0, "first call observes empty state")

    // Tick 2: drive again so state is well-populated.
    let tick2 = t0.advanced(by: .milliseconds(80))
    var tickFrame2 = tickFrame1
    _ = controller.applyInterpolations(to: &tickFrame2, at: tick2)
    let observedAfterTick2 = recorder.lastObserved
    #expect(
      observedAfterTick2 >= 1,
      "second call must see counter incremented by the first tick — \(observedAfterTick2)"
    )

    // Frame 3 — RETARGET: same identity, NEW target opacity, NEW
    // animation request.  This forces `sample(existing, at:)` to run
    // because the slot already has an in-flight animation.  At sample
    // time, the controller must thread the existing customState into
    // `anim.evaluate(elapsed:state:)` — if it doesn't, the recording
    // CustomAnimation sees a fresh empty state and the recorder's
    // observation drops back to 0.
    let observationsBeforeRetarget = recorder.lastObserved
    var frame3Metadata = DrawMetadata()
    frame3Metadata.baseStyle.explicitOpacity = 0.5
    let frame3 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      drawMetadata: frame3Metadata
    )
    let retargetAt = t0.advanced(by: .milliseconds(100))
    var retargetTransaction = TransactionSnapshot()
    retargetTransaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(
      frame3,
      transaction: retargetTransaction,
      timestamp: retargetAt
    )

    // The retarget path calls sample() once on the in-flight
    // animation.  The recorder's most-recent observation must reflect
    // the carried-forward counter from tick 2 (>= observationsBeforeRetarget),
    // not a fresh zero.
    #expect(
      recorder.lastObserved >= observationsBeforeRetarget,
      "sample() during retarget must thread customState — observed \(recorder.lastObserved), expected >= \(observationsBeforeRetarget)"
    )
    #expect(
      recorder.callCount > callsAfterTick1,
      "sample() must invoke the CustomAnimation during retarget"
    )
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
    #expect(result.hasPendingWork)

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

    #expect(result.hasPendingWork)
    #expect(result.redrawIdentities.contains(leafIdentity))

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
    let leafNodeID = ViewNodeID(rawValue: 2)
    controller.beginTransitionCollection()
    controller.registerTransition(
      for: leafIdentity,
      viewNodeID: leafNodeID,
      transition: AnyTransition.opacity
    )
    controller.finishTransitionCollection()

    // Frame 1: parent has the leaf as a child.
    let leaf = ResolvedNode(
      viewNodeID: leafNodeID,
      identity: leafIdentity,
      kind: .view("Leaf")
    )
    let root = ResolvedNode(
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
    #expect(tickResult.hasPendingWork)

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
    let leafNodeID = ViewNodeID(rawValue: 3)

    // Register the transition on the leaf (that's where
    // TransitionViewModifier attaches it).
    controller.beginTransitionCollection()
    controller.registerTransition(
      for: leafIdentity,
      viewNodeID: leafNodeID,
      transition: AnyTransition.opacity
    )
    controller.finishTransitionCollection()

    // Frame 1: overlay → padding → leaf present.
    let leaf = ResolvedNode(
      viewNodeID: leafNodeID,
      identity: leafIdentity,
      kind: .view("Leaf")
    )
    let padding = ResolvedNode(
      identity: paddingIdentity,
      kind: .view("Padding"),
      children: [leaf]
    )
    let overlay = ResolvedNode(
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
    #expect(result.hasPendingWork)

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
    let leafNodeID = ViewNodeID(rawValue: 2)
    controller.beginTransitionCollection()
    controller.registerTransition(
      for: leafIdentity,
      viewNodeID: leafNodeID,
      transition: AnyTransition.opacity
    )
    controller.finishTransitionCollection()

    // Frame 1: leaf present.
    let leaf = ResolvedNode(
      viewNodeID: leafNodeID,
      identity: leafIdentity,
      kind: .view("Leaf")
    )
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
    #expect(preResetTick.hasPendingWork)

    // Reset while the removal is still in flight.
    controller.reset()

    // A new tree with a completely different identity should NOT see
    // the pre-reset leaf re-injected.
    let freshIdentity = Identity(components: [.named("fresh")])
    var fresh = ResolvedNode(identity: freshIdentity, kind: .view("Fresh"))
    controller.processResolvedTree(fresh, transaction: .init(), timestamp: t0)
    let result = controller.applyInterpolations(to: &fresh, at: t0)

    #expect(!result.hasPendingWork)
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
    let leafNodeID = ViewNodeID(rawValue: 2)
    controller.beginTransitionCollection()
    controller.registerTransition(
      for: leafIdentity,
      viewNodeID: leafNodeID,
      transition: AnyTransition.opacity
    )
    controller.finishTransitionCollection()

    // Frame 1: leaf present.
    let leaf = ResolvedNode(
      viewNodeID: leafNodeID,
      identity: leafIdentity,
      kind: .view("Leaf")
    )
    let root = ResolvedNode(
      identity: Identity(components: [.named("root")]),
      kind: .view("Root"),
      children: [leaf]
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(root, transaction: .init(), timestamp: t0)

    // Frame 2: leaf removed with animation intent.  No re-registration
    // because the branch is gone from the resolved tree.
    let root2 = ResolvedNode(
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

    #expect(!result.hasPendingWork)
    #expect(result.nextDeadline == nil)
    #expect(
      !treeCopy.children.contains(where: { $0.identity == leafIdentity }),
      "purged removal should not be re-injected after the animation completes"
    )
  }
}

// MARK: - Phase 3 parity with the pre-rewrite enum-dispatch model

/// Pins the Phase 3 AnimatableSlot + AnyAnimatable rewrite against the
/// pre-rewrite AnimatableProperty + AnimatableValue enum-dispatch
/// model.  Each test sets up a simple two-frame animation scenario on
/// a single slot, runs the controller halfway through a 200 ms linear
/// curve, and asserts that the interpolated value lands on the
/// expected midpoint — same assertion style, same tolerance, same
/// scenarios as the old tests.
@MainActor
@Suite("Phase 3 parity: value interpolation")
struct Phase3ParityTests {

  @Test(
    "Phase 3 parity: opacity animation produces the same interpolated values as the pre-rewrite enum-dispatch model"
  )
  func phase3OpacityParity() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("parity-leaf")])
    var frame1Metadata = DrawMetadata()
    frame1Metadata.baseStyle.explicitOpacity = 1.0
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      drawMetadata: frame1Metadata
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

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

    let halfway = t0.advanced(by: .milliseconds(100))
    _ = controller.applyInterpolations(to: &frame2, at: halfway)
    let opacity = frame2.drawMetadata.baseStyle.explicitOpacity
    #expect(opacity != nil)
    if let opacity {
      #expect(abs(opacity - 0.5) < 0.05)
    }
  }

  @Test(
    "Phase 3 parity: foreground color animation produces the same interpolated values as the pre-rewrite enum-dispatch model"
  )
  func phase3ColorParity() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("parity-leaf")])
    var frame1Metadata = DrawMetadata()
    frame1Metadata.baseStyle.foregroundStyle = .color(Color.red)
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      drawMetadata: frame1Metadata
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    var frame2Metadata = DrawMetadata()
    frame2Metadata.baseStyle.foregroundStyle = .color(Color.blue)
    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      drawMetadata: frame2Metadata
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    let halfway = t0.advanced(by: .milliseconds(100))
    _ = controller.applyInterpolations(to: &frame2, at: halfway)

    guard case .color(let interpolated) = frame2.drawMetadata.baseStyle.foregroundStyle
    else {
      Issue.record("apply must preserve the foreground color variant")
      return
    }
    // Perceptual OKLab halfway between red and blue — matches the old
    // pre-Phase-3 controller's interpolation method.
    let expected = Color.red.interpolated(to: .blue, progress: 0.5, method: .perceptual)
    #expect(abs(interpolated.red - expected.red) < 0.05)
    #expect(abs(interpolated.green - expected.green) < 0.05)
    #expect(abs(interpolated.blue - expected.blue) < 0.05)
  }

  @Test(
    "Phase 3 parity: padding animation interpolates all four edges at once and matches the old per-edge enum-dispatch model"
  )
  func phase3PaddingParity() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("parity-leaf")])
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .padding(EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20))
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    let halfway = t0.advanced(by: .milliseconds(100))
    _ = controller.applyInterpolations(to: &frame2, at: halfway)

    guard case .padding(let insets) = frame2.layoutBehavior else {
      Issue.record("apply must preserve the padding layoutBehavior")
      return
    }
    // Integer truncation means 0 → 20 at halfway lands on 10.
    #expect(abs(insets.top - 10) <= 1)
    #expect(abs(insets.leading - 10) <= 1)
    #expect(abs(insets.bottom - 10) <= 1)
    #expect(abs(insets.trailing - 10) <= 1)
  }

  @Test(
    "Phase 3 parity: offset animation interpolates both axes via a single AnimatablePair slot"
  )
  func phase3OffsetParity() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("parity-leaf")])
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .offset(x: 0, y: 0)
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .offset(x: 20, y: 40)
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    let halfway = t0.advanced(by: .milliseconds(100))
    _ = controller.applyInterpolations(to: &frame2, at: halfway)

    guard case .offset(let x, let y) = frame2.layoutBehavior else {
      Issue.record("apply must preserve the offset layoutBehavior")
      return
    }
    #expect(abs(x - 10) <= 1)
    #expect(abs(y - 20) <= 1)
  }

  @Test(
    "Phase 3 parity: position animation interpolates both axes via a single AnimatablePair slot"
  )
  func phase3PositionParity() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("parity-leaf")])
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .position(x: 0, y: 0)
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .position(x: 20, y: 40)
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    let halfway = t0.advanced(by: .milliseconds(100))
    _ = controller.applyInterpolations(to: &frame2, at: halfway)

    guard case .position(let x, let y) = frame2.layoutBehavior else {
      Issue.record("apply must preserve the position layoutBehavior")
      return
    }
    #expect(abs(x - 10) <= 1)
    #expect(abs(y - 20) <= 1)
  }

  @Test("Phase 3 parity: offset X-only change halfway")
  func phase3OffsetXOnlyParity() throws {
    // High-risk regression class after the offset slot collapse
    // (two int slots → one AnimatablePair<Int, Int> slot): a single-axis
    // change must drive ONLY the changing axis and leave the other
    // exactly at its starting value.  The unchanged-axis assertion uses
    // exact equality so any drift is caught immediately.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("parity-offset-x-leaf")])
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .offset(x: 0, y: 10)
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    // Change ONLY x.
    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .offset(x: 20, y: 10)
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    let halfway = t0.advanced(by: .milliseconds(100))
    _ = controller.applyInterpolations(to: &frame2, at: halfway)

    guard case .offset(let x, let y) = frame2.layoutBehavior else {
      Issue.record("expected offset layout behavior")
      return
    }
    // X should be halfway between 0 and 20 (~10).
    #expect(abs(x - 10) <= 1)
    // Y should remain at 10 (unchanged) — exact equality on purpose.
    #expect(y == 10)
  }

  @Test("Phase 3 parity: offset Y-only change halfway")
  func phase3OffsetYOnlyParity() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("parity-offset-y-leaf")])
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .offset(x: 10, y: 0)
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    // Change ONLY y.
    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .offset(x: 10, y: 40)
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    let halfway = t0.advanced(by: .milliseconds(100))
    _ = controller.applyInterpolations(to: &frame2, at: halfway)

    guard case .offset(let x, let y) = frame2.layoutBehavior else {
      Issue.record("expected offset layout behavior")
      return
    }
    // X should remain at 10 (unchanged) — exact equality on purpose.
    #expect(x == 10)
    // Y should be halfway between 0 and 40 (~20).
    #expect(abs(y - 20) <= 1)
  }

  @Test("Phase 3 parity: position X-only change halfway")
  func phase3PositionXOnlyParity() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("parity-position-x-leaf")])
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .position(x: 0, y: 10)
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .position(x: 20, y: 10)
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    let halfway = t0.advanced(by: .milliseconds(100))
    _ = controller.applyInterpolations(to: &frame2, at: halfway)

    guard case .position(let x, let y) = frame2.layoutBehavior else {
      Issue.record("expected position layout behavior")
      return
    }
    #expect(abs(x - 10) <= 1)
    #expect(y == 10)
  }

  @Test("Phase 3 parity: position Y-only change halfway")
  func phase3PositionYOnlyParity() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("parity-position-y-leaf")])
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .position(x: 10, y: 0)
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .position(x: 10, y: 40)
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    let halfway = t0.advanced(by: .milliseconds(100))
    _ = controller.applyInterpolations(to: &frame2, at: halfway)

    guard case .position(let x, let y) = frame2.layoutBehavior else {
      Issue.record("expected position layout behavior")
      return
    }
    #expect(x == 10)
    #expect(abs(y - 20) <= 1)
  }

  @Test(
    "Phase 3 parity: frame width animation interpolates the int slot without disturbing the height slot"
  )
  func phase3FrameWidthParity() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("parity-leaf")])
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .frame(width: 10, height: 5, alignment: .center)
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .frame(width: 30, height: 5, alignment: .center)
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    let halfway = t0.advanced(by: .milliseconds(100))
    _ = controller.applyInterpolations(to: &frame2, at: halfway)

    guard case .frame(let width, let height, _) = frame2.layoutBehavior else {
      Issue.record("apply must preserve the frame layoutBehavior")
      return
    }
    #expect(width != nil)
    if let width {
      #expect(abs(width - 20) <= 1)
    }
    #expect(height == 5, "height must not drift when only width animates")
  }

  @Test(
    "Phase 3 parity: frame height animation interpolates the int slot without disturbing the width slot"
  )
  func phase3FrameHeightParity() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("parity-leaf")])
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .frame(width: 10, height: 0, alignment: .center)
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .frame(width: 10, height: 20, alignment: .center)
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    let halfway = t0.advanced(by: .milliseconds(100))
    _ = controller.applyInterpolations(to: &frame2, at: halfway)

    guard case .frame(let width, let height, _) = frame2.layoutBehavior else {
      Issue.record("apply must preserve the frame layoutBehavior")
      return
    }
    #expect(width == 10, "width must not drift when only height animates")
    #expect(height != nil)
    if let height {
      #expect(abs(height - 10) <= 1)
    }
  }

  @Test(
    "Phase 3 parity: border color animation produces the same interpolated values as the pre-rewrite enum-dispatch model"
  )
  func phase3BorderColorParity() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("parity-leaf")])
    var frame1Metadata = DrawMetadata()
    frame1Metadata.borderShapeStyle = .color(Color.red)
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      drawMetadata: frame1Metadata
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

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

    let halfway = t0.advanced(by: .milliseconds(100))
    _ = controller.applyInterpolations(to: &frame2, at: halfway)

    guard case .color(let interpolated) = frame2.drawMetadata.borderShapeStyle else {
      Issue.record("apply must preserve the border color variant")
      return
    }
    let expected = Color.red.interpolated(to: .blue, progress: 0.5, method: .perceptual)
    #expect(abs(interpolated.red - expected.red) < 0.05)
    #expect(abs(interpolated.green - expected.green) < 0.05)
    #expect(abs(interpolated.blue - expected.blue) < 0.05)
  }

  @Test(
    "Phase 3 parity: border blend phase animation interpolates the double slot as before"
  )
  func phase3BorderBlendPhaseParity() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("parity-leaf")])
    let blend = BorderBlend([.red, .blue])
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .border(
        BorderSet.single,
        placement: .outset,
        foreground: nil,
        background: nil,
        blend: blend,
        blendPhase: 0.0,
        sides: .all
      )
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      layoutBehavior: .border(
        BorderSet.single,
        placement: .outset,
        foreground: nil,
        background: nil,
        blend: blend,
        blendPhase: 1.0,
        sides: .all
      )
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    let halfway = t0.advanced(by: .milliseconds(100))
    _ = controller.applyInterpolations(to: &frame2, at: halfway)

    guard
      case .border(_, _, _, _, _, let interpolatedPhase, _) = frame2.layoutBehavior
    else {
      Issue.record("apply must preserve the border layoutBehavior")
      return
    }
    #expect(abs(interpolatedPhase - 0.5) < 0.05)
  }
}
