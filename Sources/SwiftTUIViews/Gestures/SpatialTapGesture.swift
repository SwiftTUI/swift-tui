public import SwiftTUICore

/// A tap gesture that carries the tap location in its value.
///
/// `Value.location` is resolved via the configured `coordinateSpace`
/// `.local` subtracts the `targetRect` origin. `.global` uses the raw terminal point.
/// This behavior matches the SwiftUI `SpatialTapGesture` shape.
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
        coordinateSpace: coordinateSpace,
        requestDeadline: context.requestDeadline
      )
    )
  }
}

@MainActor
final class SpatialTapGestureRecognizer: GestureRecognizer {
  typealias Value = SpatialTapGesture.Value

  private let tap: TapGestureRecognizer
  var requiredCount: Int { tap.requiredCount }
  private(set) var coordinateSpace: CoordinateSpace
  var phase: GestureRecognizerPhase { tap.phase }
  var isActive: Bool { tap.isActive }
  private var lastTerminalLocation: Point?
  private var lastPointer: PointerLocation?
  private var lastTargetRect: CellRect = CellRect(origin: .zero, size: .zero)
  private var lastNamedCoordinateSpaces: [NamedCoordinateSpace: CellRect] = [:]

  init(
    count: Int,
    coordinateSpace: CoordinateSpace,
    requestDeadline: @escaping @MainActor @Sendable (MonotonicInstant) -> Void = { _ in }
  ) {
    tap = TapGestureRecognizer(
      count: count,
      interTapWindow: TapGesture.effectiveInterTapWindow,
      requestDeadline: requestDeadline
    )
    self.coordinateSpace = coordinateSpace
  }

  func reArm() {
    guard phase.isTerminal else { return }
    tap.reArm()
    lastTerminalLocation = nil
    lastPointer = nil
  }

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    guard !phase.isTerminal else { return .ignored }
    let disposition = tap.handle(event: event)
    if phase == .ended {
      lastTerminalLocation = event.location.location
      lastPointer = event.location
      lastTargetRect = event.targetRect
      lastNamedCoordinateSpaces = event.namedCoordinateSpaces
    }
    return disposition
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool {
    tap.handleDeadline(at: instant)
  }

  func adoptAuthoredCallbacks(from replacement: AnyObject) -> Bool {
    guard let other = replacement as? SpatialTapGestureRecognizer,
      tap.adoptAuthoredCallbacks(from: other.tap)
    else { return false }
    coordinateSpace = other.coordinateSpace
    return true
  }

  func currentValue() -> SpatialTapGesture.Value? {
    guard let loc = lastTerminalLocation,
      let pointer = lastPointer
    else { return nil }
    return SpatialTapGesture.Value(
      location: coordinateSpace.resolve(
        terminalPoint: loc,
        targetRect: lastTargetRect,
        namedCoordinateSpaces: lastNamedCoordinateSpaces
      ),
      pointer: pointer
    )
  }

  func tearDown() {
    tap.tearDown()
  }
}
