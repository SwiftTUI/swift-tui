/// Phase delivered to ``View/onPointerHover(_:)`` handlers.
public enum HoverPhase: Equatable, Sendable {
  /// The pointer entered the view's hit region at the supplied local point.
  case entered(Point)
  /// The pointer moved within the view's hit region at the supplied local point.
  case moved(Point)
  /// The pointer exited the view's hit region.
  case exited
}
