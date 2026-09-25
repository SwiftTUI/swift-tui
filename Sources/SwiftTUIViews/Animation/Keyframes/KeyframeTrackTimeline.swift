import SwiftTUICore

/// The resolved, evaluable form of one track: segments in `AnimatableData`
/// space with every default (cubic tangents, spring durations) filled in at
/// construction. Pure value; sampled by `KeyframeTimeline`.
package struct KeyframeTrackTimeline<Value: Animatable> {
  package typealias Data = Value.AnimatableData

  package enum Interpolator {
    case linear(UnitCurve)
    /// Tangents in value units per second.
    case cubic(startTangent: Data, endTangent: Data)
    /// Start velocity in value units per second.
    case spring(Spring, startVelocity: Data)
    case move
  }

  package struct Segment {
    package var start: Data
    package var end: Data
    package var startTime: Duration
    package var duration: Duration
    package var interpolator: Interpolator
    /// Whether the start velocity/tangent was defaulted rather than
    /// authored; only defaulted starts accept a retrigger seed.
    package var startVelocityIsDefault: Bool
    /// A value of the property type to write sampled data into.
    package var template: Value

    package var endTime: Duration {
      startTime + duration
    }
  }

  package let initialValue: Value
  package let segments: [Segment]
  package let duration: Duration
  /// The authored keyframes, kept so a retrigger seed can re-resolve the
  /// defaults that depend on the first segment's velocity.
  private let specs: [KeyframeSegmentSpec<Value>]

  package init(initialValue: Value, specs: [KeyframeSegmentSpec<Value>]) {
    self.init(initialValue: initialValue, specs: specs, leadingVelocity: nil)
  }

  /// - Parameter leadingVelocity: the start velocity of a first cubic or
  ///   spring segment whose own start velocity is defaulted (a retrigger
  ///   seed); `nil` starts it at rest.
  private init(
    initialValue: Value,
    specs: [KeyframeSegmentSpec<Value>],
    leadingVelocity: Data?
  ) {
    self.initialValue = initialValue
    self.specs = specs

    // Keyframe points and times, index 0 being the initial value.
    var points: [Data] = [initialValue.animatableData]
    var durations: [Duration] = []
    for spec in specs {
      points.append(spec.to.animatableData)
      let duration: Duration
      switch spec.kind {
      case .spring(let spring, _):
        duration = spec.duration ?? spring.settlingDuration
      case .move:
        duration = .zero
      case .linear, .cubic:
        duration = spec.duration ?? .zero
      }
      durations.append(max(duration, .zero))
    }
    var times: [Duration] = [.zero]
    for duration in durations {
      times.append(times[times.count - 1] + duration)
    }

    // Catmull-Rom tangents (value per second) at every keyframe: rest at the
    // two ends, the neighbors' chord over their time span inside.
    let count = points.count
    var tangents: [Data] = Array(repeating: .zero, count: count)
    if count > 2 {
      for index in 1..<(count - 1) {
        let span = (times[index + 1] - times[index - 1]).totalSeconds
        tangents[index] = HermiteInterpolation.catmullRomTangent(
          previous: points[index - 1],
          next: points[index + 1],
          span: span
        )
      }
    }

    // Every velocity except a defaulted cubic side is fixed by its own
    // keyframe, so those sides are filled in a second pass.
    var segments: [Segment] = []
    segments.reserveCapacity(specs.count)
    for (offset, spec) in specs.enumerated() {
      let index = offset + 1
      let interpolator: Interpolator
      var startIsDefault = false
      switch spec.kind {
      case .linear(let curve):
        interpolator = .linear(curve)
      case .cubic(let startVelocity, let endVelocity):
        startIsDefault = startVelocity == nil
        interpolator = .cubic(
          startTangent: startVelocity?.animatableData ?? .zero,
          endTangent: endVelocity?.animatableData ?? .zero
        )
      case .spring(let spring, let startVelocity):
        startIsDefault = startVelocity == nil
        let leading = offset == 0 ? leadingVelocity : nil
        interpolator = .spring(
          spring, startVelocity: startVelocity?.animatableData ?? leading ?? .zero)
      case .move:
        interpolator = .move
      }
      segments.append(
        Segment(
          start: points[index - 1],
          end: points[index],
          startTime: times[index - 1],
          duration: durations[offset],
          interpolator: interpolator,
          startVelocityIsDefault: startIsDefault,
          template: spec.to
        )
      )
    }

    // SwiftUI's `CubicKeyframe` rule: adjacent defaulted cubic sides share
    // the Catmull-Rom tangent, and a defaulted side next to any other
    // velocity (another kind of keyframe, or an authored cubic side) takes
    // that segment's velocity at the shared keyframe. The track's two ends
    // rest unless the first segment is seeded.
    func isDefaultedCubicSide(_ offset: Int, start: Bool) -> Bool {
      guard case .cubic(let startVelocity, let endVelocity) = specs[offset].kind else {
        return false
      }
      return (start ? startVelocity : endVelocity) == nil
    }
    for offset in segments.indices {
      guard case .cubic(var startTangent, var endTangent) = segments[offset].interpolator else {
        continue
      }
      if isDefaultedCubicSide(offset, start: true) {
        if offset == 0 {
          startTangent = leadingVelocity ?? .zero
        } else if isDefaultedCubicSide(offset - 1, start: false) {
          startTangent = tangents[offset]
        } else {
          let previous = segments[offset - 1]
          startTangent = Self.sampleVelocity(previous, at: previous.endTime)
        }
      }
      if isDefaultedCubicSide(offset, start: false) {
        if offset == segments.count - 1 {
          endTangent = .zero
        } else if isDefaultedCubicSide(offset + 1, start: true) {
          endTangent = tangents[offset + 1]
        } else {
          let next = segments[offset + 1]
          endTangent = Self.sampleVelocity(next, at: next.startTime)
        }
      }
      segments[offset].interpolator = .cubic(startTangent: startTangent, endTangent: endTangent)
    }
    self.segments = segments
    duration = times[times.count - 1]
  }

  // MARK: - Sampling

  /// The value at `time`: the initial value before zero, the last keyframe
  /// at or after the track's end, the active segment's sample between.
  package func value(at time: Duration) -> Value {
    guard let last = segments.last else { return initialValue }
    if time < .zero { return initialValue }
    if time >= duration { return last.template }
    for segment in segments where time < segment.endTime {
      var result = segment.template
      result.animatableData = sample(segment, at: time)
      return result
    }
    return last.template
  }

  /// The velocity at `time` in value units per second; zero outside the
  /// track and across a move.
  package func velocity(at time: Duration) -> Data {
    guard !segments.isEmpty, time >= .zero, time < duration else { return .zero }
    for segment in segments where time < segment.endTime {
      return Self.sampleVelocity(segment, at: time)
    }
    return .zero
  }

  private func sample(_ segment: Segment, at time: Duration) -> Data {
    let local = time - segment.startTime
    let seconds = segment.duration.totalSeconds
    guard seconds > 0 else { return segment.end }
    let progress = min(max(local.totalSeconds / seconds, 0), 1)
    switch segment.interpolator {
    case .linear(let curve):
      return segment.start + (segment.end - segment.start).scaled(by: curve.value(at: progress))
    case .cubic(let startTangent, let endTangent):
      return HermiteInterpolation.value(
        from: segment.start,
        to: segment.end,
        startTangent: startTangent.scaled(by: seconds),
        endTangent: endTangent.scaled(by: seconds),
        at: progress
      )
    case .spring(let spring, let startVelocity):
      return spring.value(
        fromValue: segment.start,
        toValue: segment.end,
        initialVelocity: startVelocity,
        time: local
      )
    case .move:
      return segment.end
    }
  }

  private static func sampleVelocity(_ segment: Segment, at time: Duration) -> Data {
    let local = time - segment.startTime
    let seconds = segment.duration.totalSeconds
    guard seconds > 0 else { return .zero }
    let progress = min(max(local.totalSeconds / seconds, 0), 1)
    switch segment.interpolator {
    case .linear(let curve):
      return (segment.end - segment.start).scaled(by: curve.velocity(at: progress) / seconds)
    case .cubic(let startTangent, let endTangent):
      return HermiteInterpolation.derivative(
        from: segment.start,
        to: segment.end,
        startTangent: startTangent.scaled(by: seconds),
        endTangent: endTangent.scaled(by: seconds),
        at: progress
      ).scaled(by: 1 / seconds)
    case .spring(let spring, let startVelocity):
      return spring.velocity(
        fromValue: segment.start,
        toValue: segment.end,
        initialVelocity: startVelocity,
        time: local
      )
    case .move:
      return .zero
    }
  }

  // MARK: - Retrigger continuity

  /// A copy whose first segment starts with `velocity` when that segment is
  /// a cubic or spring keyframe with a defaulted start velocity. Other first
  /// segments (linear, move, an authored velocity) are returned unchanged.
  /// The copy is resolved afresh, so a defaulted cubic after a seeded spring
  /// takes the spring's seeded end velocity.
  package func seedingStartVelocity(_ velocity: Data) -> KeyframeTrackTimeline<Value> {
    guard let first = segments.first, first.startVelocityIsDefault else { return self }
    return KeyframeTrackTimeline(
      initialValue: initialValue, specs: specs, leadingVelocity: velocity)
  }
}
