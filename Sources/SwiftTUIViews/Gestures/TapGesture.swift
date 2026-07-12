public import SwiftTUICore

/// A discrete gesture that recognizes `count` taps on a view.
///
/// `Value == Void` — TapGesture exposes no data beyond "it fired."
/// Use `SpatialTapGesture` if you need the tap location.
///
/// ## Terminal-faithful semantics
///
/// Unlike SwiftUI on iOS/macOS, there is no inter-tap timeout:
/// two `.up` events on-target count as a double-tap regardless of
/// elapsed time between them. Terminals have no OS-level tap
/// coalescing, so this is the faithful translation of the recognizer
/// to a discrete-event environment. If your use case requires a
/// bounded interval, compose with your own timer externally.
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

  private(set) var requiredCount: Int
  private(set) var phase: GestureRecognizerPhase = .possible
  private var completedTaps: Int = 0
  private var pressStart: Point?

  init(count: Int) {
    self.requiredCount = count
  }

  /// A `.down` event sets `pressStart` but `phase` stays `.possible`
  /// until `requiredCount` taps complete — override so the registry
  /// preserves the recognizer across re-resolves during the press.
  ///
  /// `completedTaps > 0` keeps a partial multi-tap sequence (e.g. the first
  /// tap of a `count: 2` gesture) active *between* taps, when `pressStart` has
  /// been cleared by the preceding `.up`. Without it a re-resolve between the
  /// two taps tears the recognizer down and resets `completedTaps`, so the
  /// second tap starts from zero and the gesture never fires.
  var isActive: Bool {
    (pressStart != nil || completedTaps > 0) && !phase.isTerminal
  }

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    guard !phase.isTerminal else { return .ignored }
    let location = event.location.location

    switch event.kind {
    case .down(.primary):
      pressStart = location
      return .handled
    case .up(.primary):
      guard pressStart != nil else { return .ignored }
      if event.targetRect.contains(event.location.cell) {
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
        let dx = abs(location.x - start.x)
        let dy = abs(location.y - start.y)
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

  /// Adopts a re-authored tap count alongside the preserved partial
  /// sequence: a re-resolve between taps must retune the requirement for
  /// the sequence in flight.
  func adoptAuthoredCallbacks(from replacement: AnyObject) -> Bool {
    guard let other = replacement as? TapGestureRecognizer else {
      return false
    }
    requiredCount = other.requiredCount
    return true
  }

  func currentValue() -> Void? {
    phase == .ended ? () : nil
  }

  func tearDown() {
    if !phase.isTerminal {
      phase = .cancelled
    }
  }
}
