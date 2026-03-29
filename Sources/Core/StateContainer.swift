import Synchronization

/// Thread-safe storage for runtime state with invalidation support.
public final class StateContainer<State: Equatable & Sendable> {
  private let storage: Mutex<State>
  public weak var invalidator: (any Invalidating)?
  public let invalidationIdentities: Set<Identity>

  public init(
    initialState: State,
    invalidationIdentities: Set<Identity> = [Identity(components: [])]
  ) {
    storage = Mutex(initialState)
    self.invalidationIdentities = invalidationIdentities
  }

  public var state: State {
    storage.withLock { $0 }
  }

  @discardableResult
  public func replace(with newState: State) -> Bool {
    let didChange = storage.withLock { state in
      guard newState != state else {
        return false
      }
      state = newState
      return true
    }
    guard didChange else {
      return false
    }
    invalidator?.requestInvalidation(of: invalidationIdentities)
    return true
  }

  @discardableResult
  public func mutate(_ update: (inout State) -> Void) -> Bool {
    let didChange = storage.withLock { state in
      var candidate = state
      update(&candidate)
      guard candidate != state else {
        return false
      }
      state = candidate
      return true
    }
    guard didChange else {
      return false
    }
    invalidator?.requestInvalidation(of: invalidationIdentities)
    return true
  }
}
