struct SceneLifecycle: Sendable {
  enum State: Sendable, Equatable {
    case created
    case rendering
    case suspended
  }

  private(set) var state: State

  init(isPrimary: Bool = false) {
    state = isPrimary ? .rendering : .created
  }

  /// Returns true if the state actually changed.
  mutating func clientAttached() -> Bool {
    switch state {
    case .created, .suspended:
      state = .rendering
      return true
    case .rendering:
      return false
    }
  }

  /// Returns true if the state actually changed.
  mutating func clientDetached() -> Bool {
    switch state {
    case .rendering:
      state = .suspended
      return true
    case .created, .suspended:
      return false
    }
  }
}
