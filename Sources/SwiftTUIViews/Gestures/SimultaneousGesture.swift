public import SwiftTUICore

/// A gesture combining two gestures that can recognize at the same time —
/// SwiftUI's `SimultaneousGesture`. Every event is delivered to both
/// children; the composite ends when either child ends, and fails only when
/// both children have given up.
public struct SimultaneousGesture<First: Gesture, Second: Gesture>: Gesture {
  /// The value of a simultaneous gesture: whichever children have
  /// recognized carry their values; the other side is `nil`.
  public struct Value {
    public var first: First.Value?
    public var second: Second.Value?

    public init(first: First.Value?, second: Second.Value?) {
      self.first = first
      self.second = second
    }
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
      SimultaneousGestureRecognizer<First, Second>(
        first: first._makeRecognizer(context: context),
        second: second._makeRecognizer(context: context)
      )
    )
  }
}

extension Gesture {
  /// Combines this gesture with another so both can recognize at once,
  /// matching SwiftUI's `simultaneously(with:)`.
  public func simultaneously<Other: Gesture>(
    with other: Other
  ) -> SimultaneousGesture<Self, Other> {
    SimultaneousGesture(self, other)
  }
}

@MainActor
final class SimultaneousGestureRecognizer<First: Gesture, Second: Gesture>: GestureRecognizer {
  typealias Value = SimultaneousGesture<First, Second>.Value

  let first: AnyGestureRecognizer
  let second: AnyGestureRecognizer

  init(first: AnyGestureRecognizer, second: AnyGestureRecognizer) {
    self.first = first
    self.second = second
  }

  func reArm() {
    first.reArm()
    second.reArm()
  }

  func adoptAuthoredCallbacks(from replacement: AnyObject) -> Bool {
    guard let other = replacement as? SimultaneousGestureRecognizer<First, Second>
    else {
      return false
    }
    let firstAdopted = first.adoptAuthoredCallbacks(from: other.first)
    let secondAdopted = second.adoptAuthoredCallbacks(from: other.second)
    return firstAdopted && secondAdopted
  }

  var phase: GestureRecognizerPhase {
    let phases = (first.phase, second.phase)
    // Either child recognizing recognizes the composite.
    if phases.0 == .ended || phases.1 == .ended { return .ended }
    // Both children giving up fails it; one giving up leaves the other's
    // phase in charge.
    switch phases {
    case (.failed, .failed), (.cancelled, .cancelled),
      (.failed, .cancelled), (.cancelled, .failed):
      return .failed
    case (.failed, let live), (.cancelled, let live),
      (let live, .failed), (let live, .cancelled):
      return live
    default:
      // Both live: report the more-progressed side.
      if phases.0 == .changed || phases.1 == .changed { return .changed }
      if phases.0 == .began || phases.1 == .began { return .began }
      return .possible
    }
  }

  var isActive: Bool { first.isActive || second.isActive }

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    var dispositions: [GestureRecognizerEventDisposition] = []
    if !first.phase.isTerminal {
      dispositions.append(first.handle(event: event))
    }
    if !second.phase.isTerminal {
      dispositions.append(second.handle(event: event))
    }
    if dispositions.contains(.handled) { return .handled }
    if !dispositions.isEmpty && dispositions.allSatisfy({ $0 == .failed }) {
      return .failed
    }
    return .ignored
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool {
    let a = first.handleDeadline(at: instant)
    let b = second.handleDeadline(at: instant)
    return a || b
  }

  func currentValue() -> Value? {
    let firstValue: First.Value? =
      first.phase == .ended ? first.currentValue(as: First.Value.self) : nil
    let secondValue: Second.Value? =
      second.phase == .ended ? second.currentValue(as: Second.Value.self) : nil
    guard firstValue != nil || secondValue != nil else { return nil }
    return Value(first: firstValue, second: secondValue)
  }

  func tearDown() {
    first.tearDown()
    second.tearDown()
  }
}
