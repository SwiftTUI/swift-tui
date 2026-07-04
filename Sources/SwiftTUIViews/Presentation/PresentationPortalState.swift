package import SwiftTUICore

@MainActor
package final class PresentationPortalState {
  package struct Checkpoint: Sendable {
    fileprivate var registry: PresentationCoordinatorRegistry.Checkpoint
  }

  private var registry = PresentationCoordinatorRegistry()
  private var imperativeHostIdentity: Identity?
  private weak var imperativeInvalidator: (any Invalidating)?
  /// Imperative present/dismiss operations applied to the live registry since
  /// the newest draft was checkpointed. A draft commit replaces the live
  /// registry wholesale with the draft's copy, so an operation that landed
  /// while that frame was in flight would be silently wiped by the publish —
  /// input actions dispatch concurrently with the async frame pipeline, which
  /// makes that window routine, not exotic. `publish` replays the operations
  /// recorded after the committing draft's floor onto the incoming registry
  /// (the same shape as the graph draft's state-mutation overlay).
  private var pendingImperativeOperations:
    [@MainActor (PresentationCoordinatorRegistry) -> Void] = []

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
      checkpoint: makeCheckpoint(),
      imperativeOperationFloor: pendingImperativeOperations.count
    )
  }

  fileprivate func publish(
    _ draft: PresentationPortalDraft
  ) {
    registry = draft.registry
    let missedOperations = pendingImperativeOperations[draft.imperativeOperationFloor...]
    if !missedOperations.isEmpty {
      retargetImperativeInvalidation()
      for operation in missedOperations {
        operation(registry)
      }
    }
    pendingImperativeOperations.removeAll(keepingCapacity: true)
  }

  /// Imperative present/dismiss handles route through this live state at call
  /// time. Env snapshots (and control action closures) captured by memo-reused
  /// subtrees outlive any single frame's draft registry, which is replaced
  /// wholesale at every commit — a handle bound to a draft's coordinator box
  /// goes silently dead after the next portal-root re-resolve. Binding to the
  /// live state keeps imperative presentation valid for the runtime's
  /// lifetime, and writing into the live registry (not an in-flight draft)
  /// survives frame aborts.
  package func injectHandles(
    into environmentValues: inout EnvironmentValues,
    hostIdentity: Identity,
    invalidator: (any Invalidating)?
  ) {
    imperativeHostIdentity = hostIdentity
    imperativeInvalidator = invalidator
    environmentValues.alertPresentationCoordinator = PresentationCoordinatorHandle(
      snapshotLabel: "AlertPresentation",
      present: { [weak self] item in
        self?.presentImperatively(item, on: \.alert)
      },
      dismiss: { [weak self] itemID in
        self?.dismissImperatively(id: itemID, on: \.alert)
      }
    )
    environmentValues.confirmationDialogPresentationCoordinator = PresentationCoordinatorHandle(
      snapshotLabel: "ConfirmationDialogPresentation",
      present: { [weak self] item in
        self?.presentImperatively(item, on: \.confirmationDialog)
      },
      dismiss: { [weak self] itemID in
        self?.dismissImperatively(id: itemID, on: \.confirmationDialog)
      }
    )
    environmentValues.sheetPresentationCoordinator = PresentationCoordinatorHandle(
      snapshotLabel: "SheetPresentation",
      present: { [weak self] item in
        self?.presentImperatively(item, on: \.sheet)
      },
      dismiss: { [weak self] itemID in
        self?.dismissImperatively(id: itemID, on: \.sheet)
      }
    )
    environmentValues.toastPresentationCoordinator = PresentationCoordinatorHandle(
      snapshotLabel: "ToastPresentation",
      present: { [weak self] item in
        self?.presentImperatively(item, on: \.toast)
      },
      dismiss: { [weak self] itemID in
        self?.dismissImperatively(id: itemID, on: \.toast)
      }
    )
  }

  private func presentImperatively<C: ManagedPresentationCoordinator>(
    _ item: C.Item,
    on box: KeyPath<PresentationCoordinatorRegistry, PresentationCoordinatorBox<C>>
  ) where C.Item: PortalPresentationItem, C.Item.ID: Sendable {
    applyImperatively { registry in
      registry[keyPath: box].present(item)
    }
  }

  private func dismissImperatively<C: ManagedPresentationCoordinator>(
    id itemID: C.Item.ID,
    on box: KeyPath<PresentationCoordinatorRegistry, PresentationCoordinatorBox<C>>
  ) where C.Item: PortalPresentationItem, C.Item.ID: Sendable {
    applyImperatively { registry in
      registry[keyPath: box].dismiss(id: itemID)
    }
  }

  private func applyImperatively(
    _ operation: @escaping @MainActor (PresentationCoordinatorRegistry) -> Void
  ) {
    retargetImperativeInvalidation()
    operation(registry)
    pendingImperativeOperations.append(operation)
  }

  /// The current (live) registry's boxes are re-created on every draft
  /// publish, so the imperative invalidation target is re-applied at call
  /// time rather than at handle-injection time.
  private func retargetImperativeInvalidation() {
    guard let imperativeHostIdentity else {
      return
    }
    registry.setImperativeInvalidationTarget(
      identity: imperativeHostIdentity,
      invalidator: imperativeInvalidator
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
  /// Count of live-state imperative operations already baked into this
  /// draft's checkpoint; `publish` replays only the operations past it.
  fileprivate let imperativeOperationFloor: Int
  private var didCommit = false
  private var didDiscard = false

  fileprivate init(
    liveState: PresentationPortalState,
    checkpoint: PresentationPortalState.Checkpoint,
    imperativeOperationFloor: Int
  ) {
    self.liveState = liveState
    self.imperativeOperationFloor = imperativeOperationFloor
    registry.restoreCheckpoint(checkpoint.registry)
  }

  package func injectHandles(
    into environmentValues: inout EnvironmentValues,
    hostIdentity: Identity,
    invalidator: (any Invalidating)?
  ) {
    precondition(!didCommit && !didDiscard)
    // Handles bind to the live state, not this draft's registry — see
    // ``PresentationPortalState/injectHandles(into:hostIdentity:invalidator:)``.
    liveState.injectHandles(
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
