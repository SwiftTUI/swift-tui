/// Thread-safe storage for runtime state with invalidation support.
@MainActor
public final class StateContainer<State: Equatable & Sendable> {
  private var storage: State
  public weak var invalidator: (any Invalidating)?
  public let invalidationIdentities: Set<Identity>

  public init(
    initialState: State,
    invalidationIdentities: Set<Identity> = [Identity(components: [])]
  ) {
    storage = initialState
    self.invalidationIdentities = invalidationIdentities
  }

  public var state: State {
    storage
  }

  @discardableResult
  public func replace(with newState: State) -> Bool {
    guard newState != storage else {
      return false
    }
    storage = newState
    invalidator?.requestInvalidation(of: invalidationIdentities)
    return true
  }

  @discardableResult
  public func mutate(_ update: (inout State) -> Void) -> Bool {
    var candidate = storage
    update(&candidate)
    guard candidate != storage else {
      return false
    }
    storage = candidate
    invalidator?.requestInvalidation(of: invalidationIdentities)
    return true
  }
}
