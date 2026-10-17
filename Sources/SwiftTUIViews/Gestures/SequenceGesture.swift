public import SwiftTUICore

/// A gesture that requires `first` to complete before `second` receives
/// events (SwiftUI's `SequenceGesture`). The composite ends when `second`
/// ends. If either child fails, the whole sequence fails.
public struct SequenceGesture<First: Gesture, Second: Gesture>: Gesture {
  /// The value of a gesture sequence, with the same structure as SwiftUI.
  /// The value is `.first` while the first gesture is recognizing or has recognized.
  /// It is `.second` after the second stage starts.
  /// The value of the second stage is `nil` until that stage produces a value.
  public enum Value {
    case first(First.Value)
    case second(First.Value, Second.Value?)
  }

  public typealias Body = Never

  public static var _needsPointerCapture: Bool {
    First._needsPointerCapture || Second._needsPointerCapture
  }

  public let first: First
  public let second: Second

  public init(_ first: First, _ second: Second) {
    self.first = first
    self.second = second
  }

  public var body: Never { neverBody() }

  public func _makeRecognizer(
    context: GestureRecognizerBuildContext
  ) -> AnyGestureRecognizer {
    AnyGestureRecognizer(
      SequenceGestureRecognizer<First, Second>(
        first: first._makeRecognizer(context: context),
        second: second._makeRecognizer(context: context)
      )
    )
  }
}

extension Gesture {
  /// Sequences this gesture before another, matching SwiftUI's
  /// `sequenced(before:)`: the other gesture receives events only after
  /// this one completes.
  public func sequenced<Other: Gesture>(
    before other: Other
  ) -> SequenceGesture<Self, Other> {
    SequenceGesture(self, other)
  }
}

@MainActor
final class SequenceGestureRecognizer<First: Gesture, Second: Gesture>: GestureRecognizer {
  typealias Value = SequenceGesture<First, Second>.Value

  let first: AnyGestureRecognizer
  let second: AnyGestureRecognizer
  private var heldPress: LocalPointerEvent?

  init(first: AnyGestureRecognizer, second: AnyGestureRecognizer) {
    self.first = first
    self.second = second
  }

  func reArm() {
    guard phase.isTerminal else { return }
    first.reArm()
    second.reArm()
    heldPress = nil
  }

  func adoptAuthoredCallbacks(from replacement: AnyObject) -> Bool {
    guard let other = replacement as? SequenceGestureRecognizer<First, Second> else {
      return false
    }
    let firstAdopted = first.adoptAuthoredCallbacks(from: other.first)
    let secondAdopted = second.adoptAuthoredCallbacks(from: other.second)
    return firstAdopted && secondAdopted
  }

  var phase: GestureRecognizerPhase {
    switch first.phase {
    case .failed, .cancelled:
      return first.phase
    case .possible, .began, .changed:
      return first.phase
    case .ended:
      // Stage two: the sequence has begun even while `second` is still
      // `.possible` — the composite is committed to the second stage.
      switch second.phase {
      case .possible:
        return .began
      case .began, .changed, .ended, .failed, .cancelled:
        return second.phase
      }
    }
  }

  var isActive: Bool {
    if first.phase == .ended {
      return !second.phase.isTerminal
    }
    return first.isActive
  }

  /// A hold can recognize while the button remains down. The second stage
  /// inherits that press so its first release/motion has a matching origin.
  private func handOffHeldPress(at instant: MonotonicInstant) {
    guard first.phase == .ended, var press = heldPress else { return }
    heldPress = nil
    press.timestamp = instant
    _ = second.handle(event: press)
  }

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    if !first.phase.isTerminal {
      // Honor due recognition before the incoming release, even if the host
      // has not drained its scheduled deadline yet.
      if heldPress != nil, first.handleDeadline(at: event.timestamp), first.phase == .ended {
        handOffHeldPress(at: event.timestamp)
        return second.handle(event: event)
      }
      switch event.kind {
      case .down(.primary): heldPress = event
      case .up(.primary), .cancelled: heldPress = nil
      default: break
      }
      let disposition = first.handle(event: event)
      handOffHeldPress(at: event.timestamp)
      return disposition
    }
    guard first.phase == .ended, !second.phase.isTerminal else { return .ignored }
    return second.handle(event: event)
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool {
    if !first.phase.isTerminal {
      let changed = first.handleDeadline(at: instant)
      handOffHeldPress(at: instant)
      return changed
    }
    guard first.phase == .ended, !second.phase.isTerminal else { return false }
    return second.handleDeadline(at: instant)
  }

  func currentValue() -> Value? {
    guard let firstValue = first.recognizingValue(as: First.Value.self) else {
      return nil
    }
    guard first.phase == .ended else {
      return .first(firstValue)
    }
    if second.phase == .ended || second.phase == .began || second.phase == .changed {
      return .second(firstValue, second.currentValue(as: Second.Value.self))
    }
    return .first(firstValue)
  }

  func tearDown() {
    first.tearDown()
    second.tearDown()
    heldPress = nil
  }
}
