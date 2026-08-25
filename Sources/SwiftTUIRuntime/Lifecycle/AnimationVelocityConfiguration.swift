import SwiftTUICore

/// Kill switch for the animation velocity channel (plan 2026-08-25-002
/// T4): built-in spring retarget continuity and `Transaction.tracksVelocity`
/// sampling. Test-settable latch over `SWIFTTUI_ANIMATION_VELOCITY`; the
/// gate latches on first read like every other feature gate, so an
/// in-process A/B flips this latch, not the environment.
@MainActor
package enum AnimationVelocityConfiguration {
  package static var isEnabled: Bool = FeatureGate.animationVelocity.initialIsEnabled()
}

/// A short ring of recent values written under `Transaction.tracksVelocity`
/// for one animated slot, mirroring `PointerVelocitySampler`: a windowed
/// estimate over real timestamps stays accurate even when intermediate
/// writes were coalesced away.
package struct SlotVelocitySampler: Sendable {
  private struct Sample: Sendable {
    var value: AnyAnimatable
    var time: MonotonicInstant
  }

  private let window: Duration
  private let capacity: Int
  private var samples: [Sample] = []

  package init(window: Duration = .milliseconds(100), capacity: Int = 16) {
    self.window = window
    self.capacity = capacity
  }

  package mutating func record(_ value: AnyAnimatable, at time: MonotonicInstant) {
    samples.append(Sample(value: value, time: time))
    if samples.count > capacity {
      samples.removeFirst(samples.count - capacity)
    }
  }

  /// The sampled velocity in progress units per second along the
  /// `from -> to` axis of the animation about to start, over the trailing
  /// window ending at `now`. `nil` with fewer than two usable samples, a
  /// degenerate interval, or an axis the samples cannot project onto.
  package func progressVelocity(
    from: AnyAnimatable,
    to: AnyAnimatable,
    at now: MonotonicInstant,
    minimumInterval: Duration = .milliseconds(1)
  ) -> Double? {
    guard samples.count >= 2 else { return nil }
    let cutoff = now.advanced(by: .zero - window)
    let windowed = samples.filter { $0.time >= cutoff }
    let span = windowed.count >= 2 ? windowed : samples
    guard let first = span.first, let last = span.last else { return nil }
    let interval = first.time.duration(to: last.time)
    guard interval >= minimumInterval else { return nil }
    let seconds = momentumSeconds(interval)
    guard seconds > 0,
      let projection = AnyAnimatable.progressProjection(
        of: (from: first.value, to: last.value),
        onto: (from: from, to: to)
      )
    else {
      return nil
    }
    return projection / seconds
  }
}
