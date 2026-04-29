public import Core

/// A gesture that recognizes a press held for at least `minimumDuration`.
///
/// `Value == Bool` — matches SwiftUI's shape. The recognizer transitions
/// to `.ended` when the deadline fires while the pointer is still pressed,
/// and `.failed` when the pointer lifts early or moves beyond
/// `maximumDistance`.
///
/// ## Terminal-faithful defaults
///
/// `maximumDistance` defaults to `0` cells. Unlike SwiftUI's 10-point
/// default (continuous coordinates), any cell movement fails the
/// gesture. Pass a positive value to allow pointer drift.
public struct LongPressGesture: Gesture {
  public typealias Value = Bool
  public typealias Body = Never

  public let minimumDuration: Duration
  public let maximumDistance: Int

  public init(
    minimumDuration: Duration = .milliseconds(500),
    maximumDistance: Int = 0
  ) {
    self.minimumDuration = minimumDuration
    self.maximumDistance = maximumDistance
  }

  public static var _needsPointerCapture: Bool { true }

  public var body: Never { neverBody() }

  public func _makeRecognizer(
    context: GestureRecognizerBuildContext
  ) -> AnyGestureRecognizer {
    AnyGestureRecognizer(
      LongPressGestureRecognizer(
        minimumDuration: minimumDuration,
        maximumDistance: maximumDistance,
        requestDeadline: context.requestDeadline
      )
    )
  }
}

@MainActor
final class LongPressGestureRecognizer: GestureRecognizer {
  typealias Value = Bool

  let minimumDuration: Duration
  let maximumDistance: Int
  let requestDeadline: @MainActor @Sendable (MonotonicInstant) -> Void
  private(set) var phase: GestureRecognizerPhase = .possible
  private var pressStart: Point?
  private var deadline: MonotonicInstant?
  private var endedValue: Bool?

  init(
    minimumDuration: Duration,
    maximumDistance: Int,
    requestDeadline: @escaping @MainActor @Sendable (MonotonicInstant) -> Void
  ) {
    self.minimumDuration = minimumDuration
    self.maximumDistance = maximumDistance
    self.requestDeadline = requestDeadline
  }

  var isActive: Bool {
    pressStart != nil && !phase.isTerminal
  }

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    guard !phase.isTerminal else { return .ignored }
    let location = event.location.location
    switch event.kind {
    case .down(.primary):
      pressStart = location
      let target = event.timestamp.advanced(by: minimumDuration)
      deadline = target
      requestDeadline(target)
      return .handled
    case .dragged(.primary):
      guard let start = pressStart else { return .ignored }
      let dx = abs(location.x - start.x)
      let dy = abs(location.y - start.y)
      if dx > Double(maximumDistance) || dy > Double(maximumDistance) {
        phase = .failed
        return .failed
      }
      return .handled
    case .up(.primary):
      guard phase == .possible else {
        return .ignored
      }

      // Deadline wakes are scheduler-driven, so a legitimate long press can
      // still release before the runtime drains the pending deadline frame.
      // Honor the timestamp on the release event and finalize here when the
      // hold duration already crossed the scheduled threshold.
      if let deadline, event.timestamp >= deadline {
        phase = .ended
        endedValue = true
        return .handled
      }

      phase = .failed
      return .failed
    default:
      return .ignored
    }
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool {
    guard !phase.isTerminal,
      let deadline,
      instant >= deadline
    else { return false }
    phase = .ended
    endedValue = true
    return true
  }

  func currentValue() -> Bool? { endedValue }

  func tearDown() {
    if !phase.isTerminal {
      phase = .cancelled
    }
  }
}
