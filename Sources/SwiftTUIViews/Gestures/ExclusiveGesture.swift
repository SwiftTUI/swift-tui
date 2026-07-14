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
  /// The events delivered to `first` while it was still deciding (F158).
  /// `second` sees events only from `first`'s failure onward, so without a
  /// replay the fallback can never recognize anything whose evidence
  /// arrived earlier — the canonical double-tap-timeout hand-off delivers
  /// NO event at all (the failure is deadline-driven). Cleared once handed
  /// off, when `first` ends (no hand-off can happen), and on re-arm.
  private var bufferedPrefix: [LocalPointerEvent] = []
  private var didReplay = false

  init(first: AnyGestureRecognizer, second: AnyGestureRecognizer) {
    self.first = first
    self.second = second
  }

  func reArm() {
    first.reArm()
    second.reArm()
    bufferedPrefix.removeAll(keepingCapacity: true)
    didReplay = false
  }

  /// Hands the buffered prefix to `second` exactly once, at the moment
  /// `first` gives up.
  private func replayPrefixIntoSecond() {
    guard !didReplay else { return }
    didReplay = true
    let prefix = bufferedPrefix
    bufferedPrefix.removeAll(keepingCapacity: true)
    for buffered in prefix where !second.phase.isTerminal {
      _ = second.handle(event: buffered)
    }
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
        bufferedPrefix.removeAll(keepingCapacity: true)
        return .handled
      case .failed, .cancelled:
        // First gave up on this event — replay everything it consumed,
        // then feed the same event to second.
        replayPrefixIntoSecond()
        return second.handle(event: event)
      case .possible, .began, .changed:
        bufferedPrefix.append(event)
        return d
      }
    }
    // First already terminal (typically .failed from a prior event):
    // deliver to second.
    replayPrefixIntoSecond()
    return second.handle(event: event)
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool {
    let a = first.handleDeadline(at: instant)
    // Only forward to second if first has failed/cancelled — second is the
    // fallback that only runs when first gives up.
    let firstGaveUp = first.phase == .failed || first.phase == .cancelled
    guard firstGaveUp else { return a }
    // A deadline-driven failure (the double-tap window expiring) delivers
    // NO event — the replayed prefix is the fallback's whole input.
    replayPrefixIntoSecond()
    let b = second.handleDeadline(at: instant)
    return a || b || second.phase == .ended
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
