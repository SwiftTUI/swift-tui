public import SwiftTUICore

/// A keyframe-defined function of time, sampled at any instant.
///
/// Matches SwiftUI's `KeyframeTimeline`. Every track is evaluated
/// independently: the timeline's ``duration`` is its longest track, and a
/// track that ends early holds its last keyframe. Durations are `Duration`
/// values, like the rest of the animation surface.
///
/// ```swift
/// struct Marker { var y = 0.0; var opacity = 1.0 }
///
/// let timeline = KeyframeTimeline(initialValue: Marker()) {
///   KeyframeTrack(\.y) {
///     CubicKeyframe(-3, duration: .milliseconds(400))
///     SpringKeyframe(0, spring: .bouncy)
///   }
///   KeyframeTrack(\.opacity) {
///     LinearKeyframe(0.4, duration: .milliseconds(200))
///     LinearKeyframe(1, duration: .milliseconds(600), timingCurve: .easeOut)
///   }
/// }
/// let midway = timeline.value(progress: 0.5)
/// ```
///
/// `KeyframeTimeline` has no runtime dependency; ``KeyframeAnimator`` drives
/// one from a task, and it is equally usable for static charts of a curve.
public struct KeyframeTimeline<Value> {
  package let initialValue: Value
  package let tracks: [AnyKeyframeTrack<Value>]

  /// The duration of the longest track.
  public let duration: Duration

  /// Creates a timeline from `initialValue` and the tracks `content` lists.
  public init(
    initialValue: Value,
    @KeyframesBuilder<Value> content: () -> some Keyframes<Value>
  ) {
    self.init(initialValue: initialValue, keyframes: content())
  }

  package init(initialValue: Value, keyframes: some Keyframes<Value>) {
    var tracks: [AnyKeyframeTrack<Value>] = []
    lowerKeyframes(keyframes, initialValue: initialValue, into: &tracks)
    self.init(initialValue: initialValue, tracks: tracks)
  }

  package init(initialValue: Value, tracks: [AnyKeyframeTrack<Value>]) {
    self.initialValue = initialValue
    self.tracks = tracks
    duration = tracks.map(\.duration).max() ?? .zero
  }

  /// The value at `time`.
  public func value(time: Duration) -> Value {
    var result = initialValue
    for track in tracks {
      track.apply(&result, time)
    }
    return result
  }

  /// The value at a fraction of ``duration``.
  public func value(progress: Double) -> Value {
    value(time: .seconds(duration.totalSeconds * progress))
  }

  // MARK: - Retrigger continuity

  /// This timeline with each track's first cubic or spring segment seeded by
  /// the velocity the matching track of `previous` carried at `time`, so a
  /// timeline rebuilt mid-flight continues without a velocity discontinuity.
  /// Tracks are matched by key path; unmatched tracks are unchanged.
  package func continuing(
    from previous: KeyframeTimeline<Value>,
    at time: Duration
  ) -> KeyframeTimeline<Value> {
    let seeded = tracks.map { track -> AnyKeyframeTrack<Value> in
      guard let match = previous.tracks.first(where: { $0.keyPath == track.keyPath }) else {
        return track
      }
      return track.continuing(match, time) ?? track
    }
    return KeyframeTimeline(initialValue: initialValue, tracks: seeded)
  }
}
