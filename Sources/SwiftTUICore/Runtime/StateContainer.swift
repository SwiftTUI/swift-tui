/// Thread-safe storage for runtime state with invalidation support.
@MainActor
public final class StateContainer<State: Equatable & Sendable> {
  private var storage: State
  public weak var invalidator: (any Invalidating)?
  public let invalidationIdentities: Set<Identity>

  public init(
    initialState: State,
    invalidationIdentities: Set<Identity> = [
      Identity(components: [] as [IdentityComponent])
    ]
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
    requestInvalidation()
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
    requestInvalidation()
    return true
  }

  private func requestInvalidation() {
    let animationRequest = AnimationContextStorage.currentRequest
    let batchID = AnimationContextStorage.currentBatchID
    if animationRequest != .inherit || batchID != nil,
      let animationAware = invalidator as? any AnimationAwareInvalidating
    {
      animationAware.requestInvalidation(
        of: invalidationIdentities,
        animation: animationRequest,
        batchID: batchID
      )
    } else {
      invalidator?.requestInvalidation(of: invalidationIdentities)
    }
  }
}
