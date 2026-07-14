public import SwiftTUICore

/// A discrete gesture that recognizes `count` taps on a view.
///
/// `Value == Void` — TapGesture exposes no data beyond "it fired."
/// Use `SpatialTapGesture` if you need the tap location.
///
/// ## Terminal-faithful semantics
///
/// A single tap (`count: 1`) has no timing component: one on-target
/// down+up fires it regardless of press duration — terminals have no
/// OS-level tap coalescing, so this is the faithful translation to a
/// discrete-event environment.
///
/// A multi-tap sequence (`count >= 2`) bounds the gap BETWEEN taps with
/// ``interTapWindow`` (F158): a sequence whose next tap does not arrive
/// inside the window transitions to `.failed`. Without a failure path,
/// `TapGesture(count: 2).exclusively(before: TapGesture())` — the
/// canonical double-vs-single disambiguation — could never hand off to
/// its fallback.
public struct TapGesture: Gesture {
  /// The maximum gap between taps of a multi-tap sequence before the
  /// sequence fails. Matches the conventional desktop double-click
  /// interval closely enough for terminal input cadences.
  public static let interTapWindow: Duration = .milliseconds(350)

  /// Test seam: real-run-loop harnesses process scripted events far slower
  /// than interactive cadence (a DEBUG first render alone can exceed the
  /// window), so gesture-dispatch tests widen the window instead of
  /// depending on wall-clock timing. `nil` uses ``interTapWindow``.
  @MainActor package static var interTapWindowOverride: Duration?

  @MainActor static var effectiveInterTapWindow: Duration {
    interTapWindowOverride ?? interTapWindow
  }
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
    AnyGestureRecognizer(
      TapGestureRecognizer(
        count: count,
        interTapWindow: TapGesture.effectiveInterTapWindow,
        requestDeadline: context.requestDeadline
      )
    )
  }
}

@MainActor
final class TapGestureRecognizer: GestureRecognizer {
  typealias Value = Void

  private(set) var requiredCount: Int
  private(set) var phase: GestureRecognizerPhase = .possible
  private var completedTaps: Int = 0
  private var pressStart: Point?
  private let requestDeadline: @MainActor @Sendable (MonotonicInstant) -> Void
  /// Resolved at construction (from `TapGesture.effectiveInterTapWindow` in
  /// `_makeRecognizer`) so a mid-interaction recognizer keeps one window
  /// even if the test-seam override changes around it.
  private let interTapWindow: Duration
  /// The inter-tap window's expiry, armed after each completed tap of a
  /// multi-tap sequence that still needs more taps (F158). `nil` while no
  /// gap is being timed; single-tap recognizers never arm it.
  private var interTapDeadline: MonotonicInstant?

  init(
    count: Int,
    interTapWindow: Duration = TapGesture.interTapWindow,
    requestDeadline: @escaping @MainActor @Sendable (MonotonicInstant) -> Void = { _ in }
  ) {
    self.requiredCount = count
    self.interTapWindow = interTapWindow
    self.requestDeadline = requestDeadline
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

  func reArm() {
    guard phase.isTerminal else { return }
    phase = .possible
    completedTaps = 0
    pressStart = nil
    interTapDeadline = nil
  }

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    guard !phase.isTerminal else { return .ignored }
    let location = event.location.location

    switch event.kind {
    case .down(.primary):
      // Deadline wakes are scheduler-driven, so the next tap's `.down` can
      // arrive before the pending deadline frame drains. Honor the event
      // timestamp (the LongPress release pattern): a down outside the
      // inter-tap window fails the sequence at event time.
      if let interTapDeadline, event.timestamp >= interTapDeadline {
        phase = .failed
        return .failed
      }
      interTapDeadline = nil
      pressStart = location
      return .handled
    case .up(.primary):
      guard pressStart != nil else { return .ignored }
      if event.targetRect.contains(event.location.cell) {
        completedTaps += 1
        pressStart = nil
        if completedTaps >= requiredCount {
          phase = .ended
        } else {
          // More taps required: bound the gap to the next one (F158) so a
          // partial sequence can FAIL — the hand-off `ExclusiveGesture`'s
          // fallback depends on.
          let expiry = event.timestamp.advanced(by: interTapWindow)
          interTapDeadline = expiry
          requestDeadline(expiry)
        }
        return .handled
      } else {
        phase = .failed
        return .failed
      }
    case .dragged(.primary):
      if let start = pressStart {
        // Sub-cell slop (F128): pixel-precision pointers report fractional
        // jitter for any human press — failing on ANY movement made taps
        // unlandable on precise hosts. Movement inside one cell is a tap;
        // a full cell of travel is a drag.
        let dx = abs(location.x - start.x)
        let dy = abs(location.y - start.y)
        if dx >= 1 || dy >= 1 {
          phase = .failed
          return .failed
        }
      }
      return .handled
    default:
      return .ignored
    }
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool {
    guard !phase.isTerminal,
      let interTapDeadline,
      instant >= interTapDeadline
    else { return false }
    phase = .failed
    return true
  }

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
