public import SwiftTUICore

/// A gesture that delivers events to `first`; if first fails, the same
/// events flow to `second`. The value types of both gestures must match.
///
/// Canonical use: `TapGesture(count: 2).exclusively(before: TapGesture())`
/// to disambiguate double-tap from single-tap.
public struct ExclusiveGesture<First: Gesture, Second: Gesture>: Gesture
where First.Value == Second.Value {
  public typealias Value = First.Value
  public typealias Body = Never

  public static var _needsPointerCapture: Bool {
    First._needsPointerCapture || Second._needsPointerCapture
  }

  public let first: First
  public let second: Second

  public init(first: First, second: Second) {
    self.first = first
    self.second = second
  }

  public var body: Never { neverBody() }

  public func _makeRecognizer(
    context: GestureRecognizerBuildContext
  ) -> AnyGestureRecognizer {
    let firstRec = first._makeRecognizer(context: context)
    let secondRec = second._makeRecognizer(context: context)
    return AnyGestureRecognizer(
      ExclusiveGestureRecognizer<First.Value>(first: firstRec, second: secondRec)
    )
  }
}

extension Gesture {
  public func exclusively<Other: Gesture>(
    before other: Other
  ) -> ExclusiveGesture<Self, Other> where Self.Value == Other.Value {
    ExclusiveGesture(first: self, second: other)
  }
}

@MainActor
final class ExclusiveGestureRecognizer<V>: GestureRecognizer {
  typealias Value = V

  let first: AnyGestureRecognizer
  let second: AnyGestureRecognizer

  init(first: AnyGestureRecognizer, second: AnyGestureRecognizer) {
    self.first = first
    self.second = second
  }

  func adoptAuthoredCallbacks(from replacement: AnyObject) -> Bool {
    guard let other = replacement as? ExclusiveGestureRecognizer<V> else {
      return false
    }
    let firstAdopted = first.adoptAuthoredCallbacks(from: other.first)
    let secondAdopted = second.adoptAuthoredCallbacks(from: other.second)
    return firstAdopted && secondAdopted
  }

  var phase: GestureRecognizerPhase {
    // First wins if it ended.
    if first.phase == .ended { return .ended }
    // If first failed/cancelled, defer to second.
    if first.phase == .failed || first.phase == .cancelled {
      return second.phase
    }
    // First is still active (possible/began/changed) — report its phase.
    return first.phase
  }

  /// Either child being active keeps the composite active.
  var isActive: Bool { first.isActive || second.isActive }

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    // Deliver to first unless it's already terminal.
    if !first.phase.isTerminal {
      let d = first.handle(event: event)
      switch first.phase {
      case .ended:
        return .handled
      case .failed, .cancelled:
        // First gave up on this event — feed the same event to second.
        return second.handle(event: event)
      case .possible, .began, .changed:
        return d
      }
    }
    // First already terminal (typically .failed from a prior event):
    // deliver to second.
    return second.handle(event: event)
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool {
    let a = first.handleDeadline(at: instant)
    // Only forward to second if first has failed/cancelled — second is the
    // fallback that only runs when first gives up.
    let firstGaveUp = first.phase == .failed || first.phase == .cancelled
    let b = firstGaveUp ? second.handleDeadline(at: instant) : false
    return a || b
  }

  func currentValue() -> V? {
    if first.phase == .ended, let v: V = first.currentValue() { return v }
    if second.phase == .ended, let v: V = second.currentValue() { return v }
    return nil
  }

  func tearDown() {
    first.tearDown()
    second.tearDown()
  }
}
