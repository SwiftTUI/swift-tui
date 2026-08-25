import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Stage T0 pins for the velocity channel (plan 2026-08-25-002 §6, T4):
/// built-in spring retarget continuity behind `SWIFTTUI_ANIMATION_VELOCITY`,
/// `Transaction.tracksVelocity` sampling into a release spring, and the
/// explicitness of a velocity-only write.
@MainActor
@Suite(.serialized)
struct AnimationVelocityChannelTests {
  private static func leaf(_ identity: Identity, opacity: Double) -> ResolvedNode {
    var metadata = DrawMetadata()
    metadata.baseStyle.explicitOpacity = opacity
    return ResolvedNode(identity: identity, kind: .view("Leaf"), drawMetadata: metadata)
  }

  private static func opacity(of tree: ResolvedNode) -> Double {
    tree.drawMetadata.baseStyle.explicitOpacity ?? -1
  }

  /// Ticks `tree` at `timestamp` and returns the interpolated opacity.
  private static func sample(
    _ controller: AnimationController,
    _ tree: ResolvedNode,
    at timestamp: MonotonicInstant
  ) -> Double {
    var ticked = tree
    _ = controller.applyInterpolations(to: &ticked, at: timestamp)
    return opacity(of: ticked)
  }

  // MARK: - Retarget continuity

  @Test(
    "a spring retargeted mid-flight keeps moving in its direction; the latch off restarts at rest",
    arguments: [true, false]
  )
  func springRetargetCarriesVelocity(enabled: Bool) {
    let previousLatch = AnimationVelocityConfiguration.isEnabled
    AnimationVelocityConfiguration.isEnabled = enabled
    defer { AnimationVelocityConfiguration.isEnabled = previousLatch }

    let controller = AnimationController()
    let spring = Animation.spring(duration: .seconds(1), bounce: 0)
    controller.register(spring)
    let identity = testIdentity("VelocityRetarget", enabled ? "on" : "off")
    var animate = TransactionSnapshot()
    animate.animationRequest = .animate(spring.animationBox)
    let t0 = MonotonicInstant(offset: .seconds(400))

    controller.processResolvedTree(
      Self.leaf(identity, opacity: 0), transaction: .init(), timestamp: t0)
    let rising = Self.leaf(identity, opacity: 1)
    controller.processResolvedTree(rising, transaction: animate, timestamp: t0)
    let beforeRetarget = Self.sample(controller, rising, at: t0.advanced(by: .milliseconds(300)))
    #expect(beforeRetarget > 0.05 && beforeRetarget < 0.95, "\(beforeRetarget)")

    // Retarget back toward 0 while the curve is still rising.
    let retargetInstant = t0.advanced(by: .milliseconds(300))
    let falling = Self.leaf(identity, opacity: 0)
    controller.processResolvedTree(falling, transaction: animate, timestamp: retargetInstant)
    let seeded = controller.initialVelocity(forIdentity: identity, slot: .opacity)
    let shortlyAfter = Self.sample(
      controller, falling, at: retargetInstant.advanced(by: .milliseconds(16))
    )

    if enabled {
      // The outgoing curve was rising; along the replacement's falling axis
      // that is a velocity away from the new target, so the seed is negative.
      #expect(
        seeded != nil && seeded! < 0,
        "the outgoing velocity seeds the replacement: \(String(describing: seeded))")
      #expect(
        shortlyAfter > beforeRetarget,
        "with velocity carried the value keeps rising briefly: \(beforeRetarget) -> \(shortlyAfter)"
      )
    } else {
      #expect(seeded == nil)
      #expect(
        shortlyAfter <= beforeRetarget,
        "with the latch off the replacement restarts at rest: \(beforeRetarget) -> \(shortlyAfter)"
      )
    }
    // Either way the curve settles on its target.
    let settled = Self.sample(controller, falling, at: retargetInstant.advanced(by: .seconds(4)))
    #expect(settled == 0)
  }

  // MARK: - tracksVelocity writes

  @Test(
    "tracksVelocity writes followed by a spring write overshoot in the drag direction",
    arguments: [true, false]
  )
  func tracksVelocityWritesSeedTheReleaseSpring(enabled: Bool) {
    let previousLatch = AnimationVelocityConfiguration.isEnabled
    AnimationVelocityConfiguration.isEnabled = enabled
    defer { AnimationVelocityConfiguration.isEnabled = previousLatch }

    let controller = AnimationController()
    let spring = Animation.spring(duration: .seconds(1), bounce: 0)
    controller.register(spring)
    let identity = testIdentity("VelocityDrag", enabled ? "on" : "off")
    let t0 = MonotonicInstant(offset: .seconds(500))
    var tracking = TransactionSnapshot()
    tracking.tracksVelocity = true

    controller.processResolvedTree(
      Self.leaf(identity, opacity: 0.2), transaction: .init(), timestamp: t0)
    #expect(
      !controller.canSkipResolvedTreeProcessing(transaction: tracking),
      "a tracksVelocity write is explicit: the controller must see it"
    )
    // Three "drag" writes rising 0.2/50 ms = 4 per second, no animation.
    controller.processResolvedTree(
      Self.leaf(identity, opacity: 0.4), transaction: tracking,
      timestamp: t0.advanced(by: .milliseconds(50))
    )
    controller.processResolvedTree(
      Self.leaf(identity, opacity: 0.6), transaction: tracking,
      timestamp: t0.advanced(by: .milliseconds(100))
    )
    #expect(controller.activeAnimationCount == 0, "tracking writes snap")

    // Release: a spring back down to 0.3.
    var animate = TransactionSnapshot()
    animate.animationRequest = .animate(spring.animationBox)
    let release = t0.advanced(by: .milliseconds(120))
    let home = Self.leaf(identity, opacity: 0.3)
    controller.processResolvedTree(home, transaction: animate, timestamp: release)
    let seeded = controller.initialVelocity(forIdentity: identity, slot: .opacity)
    let shortlyAfter = Self.sample(controller, home, at: release.advanced(by: .milliseconds(16)))

    if enabled {
      #expect(seeded != nil, "the drag velocity seeds the release spring")
      #expect(
        shortlyAfter > 0.6,
        "a fast release overshoots in the drag direction before turning: \(shortlyAfter)"
      )
    } else {
      #expect(seeded == nil)
      #expect(shortlyAfter <= 0.6, "\(shortlyAfter)")
    }
    let settled = Self.sample(controller, home, at: release.advanced(by: .seconds(4)))
    #expect(settled == 0.3)
  }

  @Test("velocity rings are dropped with departed identities")
  func ringsPrunedWithDepartedIdentities() {
    let controller = AnimationController()
    let spring = Animation.spring(duration: .seconds(1), bounce: 0)
    controller.register(spring)
    let root = testIdentity("VelocityPrune", "Root")
    let identity = testIdentity("VelocityPrune", "Leaf")
    let t0 = MonotonicInstant(offset: .seconds(600))
    var tracking = TransactionSnapshot()
    tracking.tracksVelocity = true

    func frame(_ opacity: Double?) -> ResolvedNode {
      ResolvedNode(
        identity: root,
        kind: .view("Root"),
        children: opacity.map { [Self.leaf(identity, opacity: $0)] } ?? []
      )
    }
    controller.processResolvedTree(frame(0.2), transaction: .init(), timestamp: t0)
    controller.processResolvedTree(
      frame(0.4), transaction: tracking, timestamp: t0.advanced(by: .milliseconds(50))
    )
    controller.processResolvedTree(
      frame(0.6), transaction: tracking, timestamp: t0.advanced(by: .milliseconds(100))
    )
    // The leaf departs, then returns and releases into a spring: no stale
    // velocity from the earlier occupant may seed it.
    controller.processResolvedTree(
      frame(nil), transaction: .init(), timestamp: t0.advanced(by: .milliseconds(150)))
    controller.processResolvedTree(
      frame(0.6), transaction: .init(), timestamp: t0.advanced(by: .milliseconds(200)))
    var animate = TransactionSnapshot()
    animate.animationRequest = .animate(spring.animationBox)
    controller.processResolvedTree(
      frame(0.3), transaction: animate, timestamp: t0.advanced(by: .milliseconds(250)))
    #expect(controller.initialVelocity(forIdentity: identity, slot: .opacity) == nil)
  }

  // MARK: - Write path

  @Test(
    "writes under withTransaction(\\.tracksVelocity, true) reach the controller and seed the release"
  )
  func runtimeWritesSeedTheSpring() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("VelocityRuntimeRoot"),
      size: .init(width: 40, height: 6)
    ) {
      VelocityDragFixture()
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController
    // Each drag frame needs its own instant for the velocity ring: drive the
    // run loop's frame clock instead of waiting on the wall clock.
    let clock = VirtualFrameClock()
    harness.runLoop.frameClock = { clock.now }

    try withAnimationSinks(controller) {
      try harness.clickText("drag")
      clock.advance(by: .milliseconds(20))
      try harness.clickText("drag")
      clock.advance(by: .milliseconds(20))
      try harness.clickText("drag")
      clock.advance(by: .milliseconds(20))
      #expect(controller.activeAnimationCount == 0, "tracking writes snap")
      #expect(controller.velocitySamplerCount == 1, "the drag writes fill one slot ring")
      try harness.clickText("release")
      _ = try harness.renderAfterExternalMutation()
    }

    let offsetKey = try #require(
      controller.debugStateSnapshot().activeAnimationKeys.first { $0.scope == .property(.offset) }
    )
    let seeded = controller.initialVelocity(forIdentity: offsetKey.identity, slot: .offset)
    // The drag moved +x and the release springs back toward 0, so along the
    // release axis the drag velocity points away from the target: negative.
    #expect(
      seeded != nil && seeded! < 0,
      "the drag writes seeded the release spring: \(String(describing: seeded))")
  }
}

// MARK: - Fixtures

@MainActor
private final class VirtualFrameClock {
  private(set) var now = MonotonicInstant.now()

  func advance(by duration: Duration) {
    now = now.advanced(by: duration)
  }
}

@MainActor
private struct VelocityDragFixture: View {
  @State private var offsetX = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 1) {
        Button("drag") {
          withTransaction(\.tracksVelocity, true) {
            offsetX += 4
          }
        }
        Button("release") {
          withAnimation(.spring(duration: .seconds(1), bounce: 0)) {
            offsetX = 0
          }
        }
      }
      Text("marker").offset(x: offsetX, y: 0)
    }
  }
}
