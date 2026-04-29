public import Core

/// A tap gesture that carries the tap location in its value.
///
/// `Value.location` is resolved via the configured `coordinateSpace`
/// (.local subtracts targetRect origin; .global uses the raw terminal
/// point). Matches SwiftUI's `SpatialTapGesture` shape.
public struct SpatialTapGesture: Gesture {
  public typealias Body = Never

  public struct Value: Equatable, Sendable {
    public var location: Point
    public var pointer: PointerLocation

    public init(
      location: Point,
      pointer: PointerLocation
    ) {
      self.location = location
      self.pointer = pointer
    }
  }

  public let count: Int
  public let coordinateSpace: CoordinateSpace

  public init(
    count: Int = 1,
    coordinateSpace: CoordinateSpace = .local
  ) {
    precondition(count >= 1, "SpatialTapGesture count must be >= 1")
    self.count = count
    self.coordinateSpace = coordinateSpace
  }

  public static var _needsPointerCapture: Bool { false }

  public var body: Never { neverBody() }

  public func _makeRecognizer(
    context: GestureRecognizerBuildContext
  ) -> AnyGestureRecognizer {
    AnyGestureRecognizer(
      SpatialTapGestureRecognizer(
        count: count,
        coordinateSpace: coordinateSpace
      )
    )
  }
}

@MainActor
final class SpatialTapGestureRecognizer: GestureRecognizer {
  typealias Value = SpatialTapGesture.Value

  let requiredCount: Int
  let coordinateSpace: CoordinateSpace
  private(set) var phase: GestureRecognizerPhase = .possible
  private var completedTaps = 0
  private var pressStart: Point?
  private var lastTerminalLocation: Point?
  private var lastPointer: PointerLocation?
  private var lastTargetRect: CellRect = CellRect(origin: .zero, size: .zero)

  init(count: Int, coordinateSpace: CoordinateSpace) {
    self.requiredCount = count
    self.coordinateSpace = coordinateSpace
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
      lastTargetRect = event.targetRect
      return .handled
    case .up(.primary):
      guard pressStart != nil else { return .ignored }
      if event.targetRect.contains(event.location.cell) {
        completedTaps += 1
        pressStart = nil
        if completedTaps >= requiredCount {
          phase = .ended
          lastTerminalLocation = location
          lastPointer = event.location
          lastTargetRect = event.targetRect
        }
        return .handled
      } else {
        phase = .failed
        return .failed
      }
    case .dragged(.primary):
      if let start = pressStart,
        location.x != start.x || location.y != start.y
      {
        phase = .failed
        return .failed
      }
      return .handled
    default:
      return .ignored
    }
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool { false }

  func currentValue() -> SpatialTapGesture.Value? {
    guard let loc = lastTerminalLocation,
      let pointer = lastPointer
    else { return nil }
    return SpatialTapGesture.Value(
      location: coordinateSpace.resolve(
        terminalPoint: loc,
        targetRect: lastTargetRect
      ),
      pointer: pointer
    )
  }

  func tearDown() {
    if !phase.isTerminal { phase = .cancelled }
  }
}
