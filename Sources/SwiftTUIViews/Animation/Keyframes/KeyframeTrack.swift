public import SwiftTUICore

// MARK: - KeyframeTrack

/// A sequence of keyframes that animate one ``Animatable`` property of a
/// value, addressed by key path.
///
/// Matches SwiftUI's `KeyframeTrack`. `Root` is the value type the timeline
/// animates and `TrackValue` the property's type (SwiftUI names the second
/// parameter `Value`; the name differs here only because the ``Keyframes``
/// conformance binds `Value` to `Root`, which is not spellable in Swift with
/// a same-named generic parameter).
///
/// ```swift
/// KeyframeTrack(\.offsetY) {
///   CubicKeyframe(-3, duration: .milliseconds(400))
///   CubicKeyframe(1, duration: .milliseconds(300))
///   SpringKeyframe(0, spring: .bouncy)
/// }
/// ```
public struct KeyframeTrack<Root, TrackValue: Animatable, Content: KeyframeTrackContent>: Keyframes
where Content.Value == TrackValue {
  public typealias Value = Root
  public typealias Body = Never

  package let keyPath: WritableKeyPath<Root, TrackValue>
  package let content: Content

  /// Creates a track for the property at `keyPath` from the keyframes in
  /// `content`.
  public init(
    _ keyPath: WritableKeyPath<Root, TrackValue>,
    @KeyframeTrackContentBuilder<TrackValue> content: () -> Content
  ) {
    self.keyPath = keyPath
    self.content = content()
  }

  package init(keyPath: WritableKeyPath<Root, TrackValue>, content: Content) {
    self.keyPath = keyPath
    self.content = content
  }
}

extension KeyframeTrack: KeyframesLowering {
  package func lowerKeyframes(
    initialValue: Root,
    into tracks: inout [AnyKeyframeTrack<Root>]
  ) {
    var specs: [KeyframeSegmentSpec<TrackValue>] = []
    lowerKeyframeTrackContent(content, into: &specs)
    let timeline = KeyframeTrackTimeline(
      initialValue: initialValue[keyPath: keyPath],
      specs: specs
    )
    tracks.append(AnyKeyframeTrack(keyPath: keyPath, timeline: timeline))
  }
}

// MARK: - AnyKeyframeTrack

/// One lowered track of a ``KeyframeTimeline``: the property it writes and
/// the typed timeline behind it, erased over the property type.
package struct AnyKeyframeTrack<Root> {
  package let keyPath: AnyKeyPath
  package let duration: Duration
  /// Writes the sampled value at `time` into `root`.
  package let apply: (inout Root, Duration) -> Void
  /// Returns this track re-seeded with the velocity the `previous` track
  /// carried at `time`, or `nil` when the two tracks animate different
  /// property types. Retrigger continuity (plan stage K3).
  package let continuing: (AnyKeyframeTrack<Root>, Duration) -> AnyKeyframeTrack<Root>?
  /// The typed `KeyframeTrackTimeline`, kept for `continuing` to open.
  package let typedTimeline: Any

  package init<TrackValue: Animatable>(
    keyPath: WritableKeyPath<Root, TrackValue>,
    timeline: KeyframeTrackTimeline<TrackValue>
  ) {
    self.keyPath = keyPath
    duration = timeline.duration
    typedTimeline = timeline
    apply = { root, time in
      root[keyPath: keyPath] = timeline.value(at: time)
    }
    continuing = { previous, time in
      guard
        let previousTimeline = previous.typedTimeline as? KeyframeTrackTimeline<TrackValue>
      else {
        return nil
      }
      let velocity = previousTimeline.velocity(at: time)
      return AnyKeyframeTrack(
        keyPath: keyPath,
        timeline: timeline.seedingStartVelocity(velocity)
      )
    }
  }
}
