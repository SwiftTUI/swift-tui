public import Core

/// A discrete gesture that recognizes `count` taps on a view.
///
/// `Value == Void` — TapGesture exposes no data beyond "it fired."
/// Use `SpatialTapGesture` if you need the tap location.
public struct TapGesture: Gesture {
  public typealias Value = Void
  public typealias Body = Never

  public let count: Int

  public init(count: Int = 1) {
    precondition(count >= 1, "TapGesture count must be >= 1")
    self.count = count
  }

  public static var _needsPointerCapture: Bool { false }

  public var body: Never { neverBody() }

  public func _makeRecognizer(
    context: GestureRecognizerBuildContext
  ) -> AnyGestureRecognizer {
    AnyGestureRecognizer(TapGestureRecognizer(count: count))
  }
}

@MainActor
final class TapGestureRecognizer: GestureRecognizer {
  typealias Value = Void

  let requiredCount: Int
  private(set) var phase: GestureRecognizerPhase = .possible
  private var completedTaps: Int = 0
  private var pressStart: Point?

  init(count: Int) {
    self.requiredCount = count
  }

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    guard !phase.isTerminal else { return .ignored }

    switch event.kind {
    case .down(.primary):
      pressStart = event.location
      return .handled
    case .up(.primary):
      guard pressStart != nil else { return .ignored }
      if event.targetRect.contains(event.location) {
        completedTaps += 1
        pressStart = nil
        if completedTaps >= requiredCount {
          phase = .ended
        }
        return .handled
      } else {
        phase = .failed
        return .failed
      }
    case .dragged(.primary):
      if let start = pressStart {
        let dx = abs(event.location.x - start.x)
        let dy = abs(event.location.y - start.y)
        if dx > 0 || dy > 0 {
          phase = .failed
          return .failed
        }
      }
      return .handled
    default:
      return .ignored
    }
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool { false }

  func currentValue() -> Void? {
    phase == .ended ? () : nil
  }

  func tearDown() {
    if !phase.isTerminal {
      phase = .cancelled
    }
  }
}
