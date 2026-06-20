import SwiftTUICore

/// Floating-point seconds for a `Duration`, used by the momentum physics and the
/// velocity sampler. Mirrors the inline conversion the diagnostics formatters use
/// (`Double(components.seconds) + attoseconds * 1e-18`).
func momentumSeconds(_ duration: Duration) -> Double {
  let components = duration.components
  return Double(components.seconds) + Double(components.attoseconds) / 1e18
}

/// A short ring of recent pointer samples used to estimate the *release velocity*
/// that seeds scroll momentum.
///
/// Mirrors `DragGestureRecognizer.samples`: each sample is a continuous
/// cell-space `Point` plus the event timestamp. Sampling at the run loop's
/// captured-pan altitude is correct precisely *because* coalescing has already
/// happened by then — `MouseEvent.merged` collapses a `.dragged` burst to its
/// latest location **and** latest timestamp, so a windowed estimate over real
/// timestamps stays accurate even when intermediate samples were merged away.
/// `.down`/`.up` are never coalescible, so the release sample is always real.
package struct PointerVelocitySampler {
  private struct Sample {
    var location: Point
    var time: MonotonicInstant
  }

  /// Samples older than this (relative to the release instant) are ignored, so a
  /// long slow drag that ends in a flick reports the *flick's* velocity, not the
  /// whole-gesture average.
  private let window: Duration
  /// Cap on retained samples so a very long drag does not grow unbounded.
  private let capacity: Int
  private var samples: [Sample] = []

  package init(window: Duration = .milliseconds(100), capacity: Int = 16) {
    self.window = window
    self.capacity = capacity
  }

  /// Drops all history and seeds the first sample (call on `.down` / capture).
  package mutating func reset(location: Point, time: MonotonicInstant) {
    samples = [Sample(location: location, time: time)]
  }

  /// Appends a sample (call on each captured `.dragged` and on `.up`).
  package mutating func record(location: Point, time: MonotonicInstant) {
    samples.append(Sample(location: location, time: time))
    if samples.count > capacity {
      samples.removeFirst(samples.count - capacity)
    }
  }

  /// Clears all history.
  package mutating func clear() {
    samples.removeAll(keepingCapacity: true)
  }

  /// Estimates **pointer** velocity in cells/second over the trailing `window`
  /// ending at `now`.
  ///
  /// Returns `nil` when there are too few samples or the spanned interval is
  /// below `minimumInterval` — the latter guards the drag-threshold takeover,
  /// which synthesizes a `.down`+`.dragged` pair sharing one timestamp (Δt = 0).
  ///
  /// Scroll-*offset* velocity is the negation of this: the pan maps
  /// `offset = startOffset − (location − startLocation)`, so content follows the
  /// finger and momentum continues in the offset's direction of travel.
  package func velocity(
    at now: MonotonicInstant,
    minimumInterval: Duration = .milliseconds(1)
  ) -> Vector? {
    guard samples.count >= 2 else {
      return nil
    }
    let cutoff = now.advanced(by: .zero - window)
    let windowed = samples.filter { $0.time >= cutoff }
    // Fall back to the full retained history if the trailing window kept fewer
    // than two samples (e.g. one slow coalesced drag spanning the whole window).
    let span = windowed.count >= 2 ? windowed : samples
    guard let first = span.first, let last = span.last else {
      return nil
    }
    let interval = first.time.duration(to: last.time)
    guard interval >= minimumInterval else {
      return nil
    }
    let seconds = momentumSeconds(interval)
    guard seconds > 0 else {
      return nil
    }
    return Vector(
      dx: (last.location.x - first.location.x) / seconds,
      dy: (last.location.y - first.location.y) / seconds
    )
  }
}
