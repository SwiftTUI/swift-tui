/// Declares what kind of focus-driven interaction a view participates in.
public enum FocusInteractions: Equatable, Sendable {
  case automatic
  case activate
  case edit
}
