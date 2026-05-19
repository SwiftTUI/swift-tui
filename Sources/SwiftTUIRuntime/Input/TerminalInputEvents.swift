import SwiftTUICore

/// A mouse button recognized by the input parser.
public enum MouseButton: Equatable, Sendable {
  case primary
  case middle
  case secondary
}

/// A normalized mouse event emitted by the terminal input parser.
public struct MouseEvent: Equatable, Sendable {
  /// Keyboard modifiers that accompanied the mouse event.
  public typealias Modifiers = EventModifiers

  /// The action represented by the mouse event.
  public enum Kind: Equatable, Sendable {
    case down(MouseButton)
    case up(MouseButton)
    case moved
    case dragged(MouseButton)
    case scrolled(deltaX: Int, deltaY: Int)
  }

  public var kind: Kind
  public var location: PointerLocation
  public var modifiers: Modifiers
  /// When the event occurred, on the runtime's monotonic clock.
  ///
  /// Threaded into the `LocalPointerEvent` the run loop dispatches, where
  /// gestures derive drag velocity from the interval between events. Tests
  /// stamp deterministic values so velocity does not depend on wall-clock
  /// spacing between scripted events.
  public var timestamp: MonotonicInstant

  public init(
    kind: Kind,
    location: PointerLocation,
    modifiers: Modifiers = [],
    timestamp: MonotonicInstant = .now()
  ) {
    self.kind = kind
    self.location = location
    self.modifiers = modifiers
    self.timestamp = timestamp
  }

  /// Builds a cell-only fallback event for the cell containing `location`.
  ///
  /// Callers with fractional input should pass a `PointerLocation` directly.
  public init(
    kind: Kind,
    location: Point,
    modifiers: Modifiers = [],
    timestamp: MonotonicInstant = .now()
  ) {
    self.init(
      kind: kind,
      location: .cellFallback(location.containingCell),
      modifiers: modifiers,
      timestamp: timestamp
    )
  }

  /// Equality deliberately ignores `timestamp`: it records *when* an event
  /// occurred, not *what* it is. Two events with the same kind, location, and
  /// modifiers are the same event — so a parser/coalescer test can assert the
  /// decoded events without pinning their wall-clock arrival times.
  public static func == (lhs: MouseEvent, rhs: MouseEvent) -> Bool {
    lhs.kind == rhs.kind
      && lhs.location == rhs.location
      && lhs.modifiers == rhs.modifiers
  }
}

/// A bracketed-paste burst emitted by the terminal between
/// `ESC[200~` and `ESC[201~`. The `content` is the raw payload with
/// no terminal framing — callers decide whether the bytes represent a
/// file drop (routed to `.dropDestination` destinations) or ordinary
/// pasted text (routed back as character `KeyPress` events).
public struct PasteEvent: Equatable, Sendable {
  public var content: String

  public init(content: String) {
    self.content = content
  }
}

/// A normalized terminal input event.
public enum InputEvent: Equatable, Sendable {
  case key(KeyPress)
  case mouse(MouseEvent)
  case paste(PasteEvent)
  case drop(paths: [DroppedPath], context: DropContext)

  /// Convenience for creating a key event with optional modifiers.
  public static func key(
    _ keyEvent: KeyEvent,
    modifiers: EventModifiers = []
  ) -> Self {
    .key(KeyPress(keyEvent, modifiers: modifiers))
  }
}
