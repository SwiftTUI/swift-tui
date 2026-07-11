import SwiftTUICore

/// A first-class scroll-momentum (fling) physics integrator, keyed by scroll
/// route `Identity`.
///
/// This is the root fix for the deferred momentum work: momentum is a *physics
/// simulation*, not an animation tween, so it does **not** go through the
/// animation controller (which interpolates render-time slots, not layout
/// inputs). It is also not a view concern, so it does not live in `ScrollView`
/// (a `PrimitiveView` with no `body`). Instead the run loop ticks this controller
/// on the same 33 ms deadline cadence it uses for animations, and feeds the
/// resulting integer offset deltas through `LocalScrollPositionRegistry.scrollBy`
/// — the existing imperative, edge-clamping scroll-mutation API. No synthetic
/// `.scrolled` events are involved.
///
/// The controller is intentionally pure and clock-agnostic: it owns no scheduler,
/// no registry, and no wall clock. `step(to:)` advances to a caller-supplied
/// instant and returns the integer cell deltas to apply; the run loop performs
/// the registry write and reports edge stops back via `cancel(_:)`. That keeps
/// the physics unit-testable with no `RunLoop`.
@MainActor
package final class ScrollMomentumController {
  /// Tunable physics constants. Defaults aim for an iOS-like glide adapted to
  /// terminal cell granularity; tests construct a controller with explicit values
  /// for determinism.
  package struct Configuration: Sendable {
    /// Fraction of velocity retained after one full second of decay. Velocity
    /// decays as `v(t) = v₀ · retention^t`, an exponential with time-constant
    /// `τ = −1 / ln(retention)`; total glide distance ≈ `v₀ · τ`. The default
    /// `0.082` gives τ ≈ 0.4 s.
    package var decelerationRetentionPerSecond: Double
    /// Below this speed (cells/second, either axis) a route is considered settled
    /// and removed.
    package var minimumVelocity: Double
    /// Upper bound on seed velocity (cells/second, per axis) so an extreme flick
    /// on very tall content does not launch an absurd glide.
    package var maximumVelocity: Double

    package init(
      decelerationRetentionPerSecond: Double,
      minimumVelocity: Double,
      maximumVelocity: Double
    ) {
      self.decelerationRetentionPerSecond = decelerationRetentionPerSecond
      self.minimumVelocity = minimumVelocity
      self.maximumVelocity = maximumVelocity
    }

    package static let `default` = Configuration(
      decelerationRetentionPerSecond: 0.082,
      minimumVelocity: 2.0,
      maximumVelocity: 80.0
    )
  }

  /// One tick's integer offset delta for a route. The run loop applies nonzero
  /// deltas via `registry.scrollBy(x:y:scopeIdentity:)`.
  package struct Tick: Equatable {
    package var identity: Identity
    package var deltaX: Int
    package var deltaY: Int

    package init(identity: Identity, deltaX: Int, deltaY: Int) {
      self.identity = identity
      self.deltaX = deltaX
      self.deltaY = deltaY
    }
  }

  private struct Momentum {
    /// Offset velocity in cells/second (content moves with the finger, so this is
    /// the negation of the measured pointer velocity).
    var velocity: Vector
    /// Sub-cell offset accumulated but not yet applied. `ScrollPosition` is
    /// integer, so fractional motion is carried here until it crosses a cell —
    /// without this, sub-1-cell-per-tick velocity rounds to zero and the fling
    /// dies a frame early.
    var residual: Vector
    var lastTick: MonotonicInstant
    /// The source token of the binding registered under this route when the
    /// fling began (nil when the producer supplies none). Registrations
    /// rebuild every resolve pass, so replacement alone proves nothing; a
    /// CHANGED non-nil token proves the authored binding was swapped and the
    /// fling must retire instead of writing the replacement's binding.
    var bindingSourceID: AnyID?
  }

  private let configuration: Configuration
  private var active: [Identity: Momentum] = [:]

  package init(configuration: Configuration = .default) {
    self.configuration = configuration
  }

  /// Whether any route currently has live momentum.
  package var hasActiveMomentum: Bool {
    !active.isEmpty
  }

  /// Whether `identity` currently has live momentum.
  package func isActive(_ identity: Identity) -> Bool {
    active[identity] != nil
  }

  /// Seeds (or replaces) momentum for a scroll route.
  ///
  /// - Parameters:
  ///   - offsetVelocity: Desired offset velocity in cells/second (negated pointer
  ///     velocity). Each axis is capped to `maximumVelocity`.
  ///   - canScrollX/canScrollY: Whether the route can scroll that axis
  ///     (`content > viewport`). A non-scrollable axis is zeroed so a diagonal
  ///     flick on a single-axis view does not accumulate dead residual.
  /// - Returns: `true` when momentum started (some axis exceeds `minimumVelocity`).
  @discardableResult
  package func begin(
    identity: Identity,
    offsetVelocity: Vector,
    canScrollX: Bool,
    canScrollY: Bool,
    now: MonotonicInstant,
    bindingSourceID: AnyID? = nil
  ) -> Bool {
    let velocity = Vector(
      dx: canScrollX ? clampMagnitude(offsetVelocity.dx, to: configuration.maximumVelocity) : 0,
      dy: canScrollY ? clampMagnitude(offsetVelocity.dy, to: configuration.maximumVelocity) : 0
    )
    guard isAlive(velocity) else {
      active.removeValue(forKey: identity)
      return false
    }
    active[identity] = Momentum(
      velocity: velocity,
      residual: .zero,
      lastTick: now,
      bindingSourceID: bindingSourceID
    )
    return true
  }

  /// The identities of every route with live momentum.
  package var activeIdentities: [Identity] {
    Array(active.keys)
  }

  /// Retires `identity`'s momentum when its registered binding was swapped
  /// for a different authored binding — both the seeded and the current
  /// token must be non-nil and differ (a nil on either side means the
  /// producer supplies no identity, so replacement cannot be distinguished
  /// from an ordinary re-resolve and the fling is preserved).
  package func retireIfBindingChanged(
    identity: Identity,
    currentSourceID: AnyID?
  ) {
    guard let momentum = active[identity],
      let seeded = momentum.bindingSourceID,
      let currentSourceID,
      seeded != currentSourceID
    else {
      return
    }
    active.removeValue(forKey: identity)
  }

  /// Cancels momentum for an exact route identity (e.g. it hit a content edge or
  /// its registration disappeared).
  package func cancel(_ identity: Identity) {
    active.removeValue(forKey: identity)
  }

  /// Cancels momentum for any route that is `identity` or an ancestor of it —
  /// used to stop a fling when a fresh press / wheel lands inside that scroll
  /// view (touch-to-stop), since the press carries a descendant identity.
  package func cancel(forDescendant identity: Identity) {
    for route in active.keys
    where route == identity || route.isAncestor(of: identity) {
      active.removeValue(forKey: route)
    }
  }

  /// Cancels all momentum.
  package func cancelAll() {
    active.removeAll(keepingCapacity: true)
  }

  /// Advances every active route to `now` and returns the integer offset delta to
  /// apply this tick. Routes whose velocity decays below `minimumVelocity` are
  /// removed (after emitting their final delta). The caller applies nonzero
  /// deltas through the registry and calls `cancel(_:)` on any route the registry
  /// reports as clamped (edge) or missing.
  package func step(to now: MonotonicInstant) -> [Tick] {
    var ticks: [Tick] = []
    for (identity, var momentum) in active {
      let seconds = momentumSeconds(momentum.lastTick.duration(to: now))
      guard seconds > 0 else {
        // No time elapsed (or clock went backwards): leave the route untouched.
        continue
      }

      // Forward-Euler displacement using the pre-decay velocity, then decay.
      momentum.residual.dx += momentum.velocity.dx * seconds
      momentum.residual.dy += momentum.velocity.dy * seconds
      let decay = powDouble(configuration.decelerationRetentionPerSecond, seconds)
      momentum.velocity.dx *= decay
      momentum.velocity.dy *= decay
      momentum.lastTick = now

      let deltaX = Int(momentum.residual.dx.rounded(.towardZero))
      let deltaY = Int(momentum.residual.dy.rounded(.towardZero))
      momentum.residual.dx -= Double(deltaX)
      momentum.residual.dy -= Double(deltaY)

      ticks.append(Tick(identity: identity, deltaX: deltaX, deltaY: deltaY))

      if isAlive(momentum.velocity) {
        active[identity] = momentum
      } else {
        active.removeValue(forKey: identity)
      }
    }
    return ticks
  }

  private func isAlive(_ velocity: Vector) -> Bool {
    abs(velocity.dx) >= configuration.minimumVelocity
      || abs(velocity.dy) >= configuration.minimumVelocity
  }

  private func clampMagnitude(_ value: Double, to limit: Double) -> Double {
    min(max(value, -limit), limit)
  }
}
