package import SwiftTUICore

@MainActor
package final class PresentationPortalState {
  package struct Checkpoint: Sendable {
    fileprivate var registry: PresentationCoordinatorRegistry.Checkpoint
  }

  private var registry = PresentationCoordinatorRegistry()

  package init() {}

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(registry: registry.makeCheckpoint())
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    registry.restoreCheckpoint(checkpoint.registry)
  }

  package func makeDraft() -> PresentationPortalDraft {
    PresentationPortalDraft(
      liveState: self,
      checkpoint: makeCheckpoint()
    )
  }

  fileprivate func publish(
    _ draft: PresentationPortalDraft
  ) {
    registry = draft.registry
  }

  package func injectHandles(
    into environmentValues: inout EnvironmentValues,
    hostIdentity: Identity,
    invalidator: (any Invalidating)?
  ) {
    registry.injectHandles(
      into: &environmentValues,
      hostIdentity: hostIdentity,
      invalidator: invalidator
    )
  }

  package func reconcile(
    _ declarations: [PresentationCoordinatorDeclaration]
  ) {
    registry.reconcile(declarations)
  }

  package func overlayEntries() -> [OverlayStackEntry] {
    registry.overlayEntries()
  }

  package func dismissStack() -> DismissStack {
    registry.dismissStack()
  }
}

@MainActor
package final class PresentationPortalDraft {
  private let liveState: PresentationPortalState
  fileprivate let registry = PresentationCoordinatorRegistry()
  private var didCommit = false
  private var didDiscard = false

  fileprivate init(
    liveState: PresentationPortalState,
    checkpoint: PresentationPortalState.Checkpoint
  ) {
    self.liveState = liveState
    registry.restoreCheckpoint(checkpoint.registry)
  }

  package func injectHandles(
    into environmentValues: inout EnvironmentValues,
    hostIdentity: Identity,
    invalidator: (any Invalidating)?
  ) {
    precondition(!didCommit && !didDiscard)
    registry.injectHandles(
      into: &environmentValues,
      hostIdentity: hostIdentity,
      invalidator: invalidator
    )
  }

  package func reconcile(
    _ declarations: [PresentationCoordinatorDeclaration]
  ) {
    precondition(!didCommit && !didDiscard)
    registry.reconcile(declarations)
  }

  package func overlayEntries() -> [OverlayStackEntry] {
    precondition(!didCommit && !didDiscard)
    return registry.overlayEntries()
  }

  package func dismissStack() -> DismissStack {
    precondition(!didCommit && !didDiscard)
    return registry.dismissStack()
  }

  package func commit() {
    precondition(!didCommit && !didDiscard)
    liveState.publish(self)
    didCommit = true
  }

  package func discard() {
    precondition(!didCommit && !didDiscard)
    didDiscard = true
  }
}
