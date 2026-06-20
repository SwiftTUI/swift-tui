import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

/// Pure-physics coverage for the scroll-momentum (fling) integrator and the
/// release-velocity sampler — no `RunLoop`, no scheduler, no wall clock. The
/// controller is clock-agnostic: every step advances to an explicit instant, so
/// these tests are fully deterministic.
@MainActor
struct ScrollMomentumControllerTests {
  private func instant(_ milliseconds: Int) -> MonotonicInstant {
    MonotonicInstant.zero.advanced(by: .milliseconds(milliseconds))
  }

  /// Drives a controller from `now` in `frameInterval` steps until it settles
  /// (or the cap trips), summing the integer deltas it emits.
  private func drainToSettle(
    _ controller: ScrollMomentumController,
    from start: MonotonicInstant,
    frameInterval: Duration = .milliseconds(33),
    cap: Int = 2000
  ) -> (totalX: Int, totalY: Int, frames: Int, deltasY: [Int]) {
    var now = start
    var totalX = 0
    var totalY = 0
    var deltasY: [Int] = []
    var frames = 0
    while controller.hasActiveMomentum, frames < cap {
      now = now.advanced(by: frameInterval)
      for tick in controller.step(to: now) {
        totalX += tick.deltaX
        totalY += tick.deltaY
        deltasY.append(tick.deltaY)
      }
      frames += 1
    }
    return (totalX, totalY, frames, deltasY)
  }

  @Test("A flick glides in the velocity's direction, decelerates, then settles")
  func flingGlidesThenSettles() {
    let id = testIdentity("Scroll")
    let controller = ScrollMomentumController(
      configuration: .init(
        decelerationRetentionPerSecond: 0.1,
        minimumVelocity: 1.0,
        maximumVelocity: 1000.0
      )
    )
    #expect(
      controller.begin(
        identity: id,
        offsetVelocity: Vector(dx: 0, dy: 60),
        canScrollX: false,
        canScrollY: true,
        now: instant(0)
      )
    )

    let result = drainToSettle(controller, from: instant(0))

    #expect(result.totalY > 0)  // glided in the +y direction
    #expect(result.totalX == 0)  // no horizontal drift on a vertical-only route
    #expect(!controller.hasActiveMomentum)  // settled
    // Deceleration: the offset only ever advances forward (never reverses).
    #expect(result.deltasY.allSatisfy { $0 >= 0 })
    // Stepping a settled controller produces nothing.
    #expect(controller.step(to: instant(100_000)).isEmpty)
  }

  @Test("Total glide distance approximates v0 * tau for exponential decay")
  func totalDistanceApproximatesProjection() {
    let id = testIdentity("Scroll")
    // retention 0.135/s -> tau = -1/ln(0.135) ~= 0.4993 s. v0 = 50 -> ~25 cells.
    let retention = 0.135
    let v0 = 50.0
    let controller = ScrollMomentumController(
      configuration: .init(
        decelerationRetentionPerSecond: retention,
        minimumVelocity: 0.5,
        maximumVelocity: 10_000.0
      )
    )
    #expect(
      controller.begin(
        identity: id,
        offsetVelocity: Vector(dx: 0, dy: v0),
        canScrollX: false,
        canScrollY: true,
        now: instant(0)
      )
    )
    let result = drainToSettle(controller, from: instant(0))
    // tau = -1 / ln(0.135) ~= 0.4994 s (hardcoded to avoid a math import here).
    let tau = 0.4994
    let projected = v0 * tau
    // Forward-Euler + the minimumVelocity cutoff leave a small shortfall; allow a
    // generous band so the test pins the physics without being brittle.
    #expect(Double(result.totalY) > projected * 0.7)
    #expect(Double(result.totalY) < projected * 1.15)
  }

  @Test("A release below the minimum velocity does not start momentum")
  func belowMinimumDoesNotStart() {
    let id = testIdentity("Scroll")
    let controller = ScrollMomentumController(
      configuration: .init(
        decelerationRetentionPerSecond: 0.1,
        minimumVelocity: 5.0,
        maximumVelocity: 1000.0
      )
    )
    #expect(
      !controller.begin(
        identity: id,
        offsetVelocity: Vector(dx: 0, dy: 3),
        canScrollX: false,
        canScrollY: true,
        now: instant(0)
      )
    )
    #expect(!controller.hasActiveMomentum)
  }

  @Test("A non-scrollable axis is zeroed at fling start")
  func nonScrollableAxisIsZeroed() {
    let id = testIdentity("Scroll")
    let controller = ScrollMomentumController(
      configuration: .init(
        decelerationRetentionPerSecond: 0.1,
        minimumVelocity: 1.0,
        maximumVelocity: 1000.0
      )
    )
    // A diagonal flick on a vertical-only route keeps only the vertical glide.
    #expect(
      controller.begin(
        identity: id,
        offsetVelocity: Vector(dx: 80, dy: 60),
        canScrollX: false,
        canScrollY: true,
        now: instant(0)
      )
    )
    let result = drainToSettle(controller, from: instant(0))
    #expect(result.totalX == 0)
    #expect(result.totalY > 0)
  }

  @Test("Seed velocity is capped to the configured maximum")
  func maximumVelocityCaps() {
    let id = testIdentity("Scroll")
    let maximum = 40.0
    let controller = ScrollMomentumController(
      configuration: .init(
        decelerationRetentionPerSecond: 0.5,
        minimumVelocity: 1.0,
        maximumVelocity: maximum
      )
    )
    #expect(
      controller.begin(
        identity: id,
        offsetVelocity: Vector(dx: 0, dy: 100_000),
        canScrollX: false,
        canScrollY: true,
        now: instant(0)
      )
    )
    // First 33 ms step at the capped 40 cells/s moves ~1.32 cells -> at most 2.
    let firstTick = controller.step(to: instant(33))
    let firstDeltaY = firstTick.first?.deltaY ?? 0
    #expect(firstDeltaY <= 2)
    #expect(firstDeltaY >= 1)
  }

  @Test("Sub-cell velocity still accumulates across frames into whole-cell moves")
  func subCellAccumulationCrossesCells() {
    let id = testIdentity("Scroll")
    // 15 cells/s at 33 ms = 0.495 cells/frame: every frame rounds toward zero,
    // but the residual must carry so the fling still advances.
    let controller = ScrollMomentumController(
      configuration: .init(
        decelerationRetentionPerSecond: 0.5,
        minimumVelocity: 0.25,
        maximumVelocity: 1000.0
      )
    )
    #expect(
      controller.begin(
        identity: id,
        offsetVelocity: Vector(dx: 0, dy: 15),
        canScrollX: false,
        canScrollY: true,
        now: instant(0)
      )
    )
    let result = drainToSettle(controller, from: instant(0))
    #expect(result.totalY >= 2)  // crossed at least a couple of cells via residual
  }

  @Test("cancel and cancel(forDescendant:) stop the right routes")
  func cancellation() {
    let outer = testIdentity("Outer")
    let innerChild = testIdentity("Outer", "Inner", "Row")
    let controller = ScrollMomentumController(
      configuration: .init(
        decelerationRetentionPerSecond: 0.5,
        minimumVelocity: 1.0,
        maximumVelocity: 1000.0
      )
    )
    controller.begin(
      identity: outer,
      offsetVelocity: Vector(dx: 0, dy: 50),
      canScrollX: false,
      canScrollY: true,
      now: instant(0)
    )
    #expect(controller.isActive(outer))
    // A press deep inside the scroll view (a descendant identity) stops it.
    controller.cancel(forDescendant: innerChild)
    #expect(!controller.isActive(outer))
    #expect(!controller.hasActiveMomentum)
  }
}

@MainActor
struct PointerVelocitySamplerTests {
  private func instant(_ milliseconds: Int) -> MonotonicInstant {
    MonotonicInstant.zero.advanced(by: .milliseconds(milliseconds))
  }

  @Test("Velocity is distance over time across the trailing window")
  func velocityOverWindow() throws {
    var sampler = PointerVelocitySampler()
    sampler.reset(location: Point(x: 0, y: 0), time: instant(0))
    sampler.record(location: Point(x: 0, y: 10), time: instant(50))
    let velocity = try #require(sampler.velocity(at: instant(50)))
    #expect(abs(velocity.dy - 200) < 0.001)  // 10 cells / 0.05 s
    #expect(abs(velocity.dx) < 0.001)
  }

  @Test("A zero-interval sample pair (takeover) yields no velocity")
  func zeroIntervalReturnsNil() {
    var sampler = PointerVelocitySampler()
    sampler.reset(location: Point(x: 0, y: 0), time: instant(100))
    sampler.record(location: Point(x: 0, y: 8), time: instant(100))
    #expect(sampler.velocity(at: instant(100)) == nil)
  }

  @Test("A single sample yields no velocity")
  func singleSampleReturnsNil() {
    var sampler = PointerVelocitySampler()
    sampler.reset(location: Point(x: 0, y: 0), time: instant(0))
    #expect(sampler.velocity(at: instant(0)) == nil)
  }

  @Test("Samples older than the window are excluded from the estimate")
  func windowExcludesOldSamples() throws {
    var sampler = PointerVelocitySampler(window: .milliseconds(100))
    sampler.reset(location: Point(x: 0, y: 0), time: instant(0))
    sampler.record(location: Point(x: 0, y: 5), time: instant(200))
    sampler.record(location: Point(x: 0, y: 10), time: instant(250))
    // Window [150, 250] keeps only the last two samples: (5 -> 10) over 50 ms.
    let velocity = try #require(sampler.velocity(at: instant(250)))
    #expect(abs(velocity.dy - 100) < 0.001)
  }
}
