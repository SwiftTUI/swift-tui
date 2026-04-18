public import Core

/// A gesture that recognizes a press held for at least `minimumDuration`.
///
/// `Value == Bool` — matches SwiftUI's shape. The recognizer transitions
/// to `.ended` when the deadline fires while the pointer is still pressed,
/// and `.failed` when the pointer lifts early or moves beyond
/// `maximumDistance`.
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

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    guard !phase.isTerminal else { return .ignored }
    switch event.kind {
    case .down(.primary):
      pressStart = event.location
      let target = event.timestamp.advanced(by: minimumDuration)
      deadline = target
      requestDeadline(target)
      return .handled
    case .dragged(.primary):
      guard let start = pressStart else { return .ignored }
      let dx = abs(event.location.x - start.x)
      let dy = abs(event.location.y - start.y)
      if dx > maximumDistance || dy > maximumDistance {
        phase = .failed
        return .failed
      }
      return .handled
    case .up(.primary):
      // Released before deadline fired (phase stayed .possible).
      if phase == .possible {
        phase = .failed
        return .failed
      }
      return .ignored
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
