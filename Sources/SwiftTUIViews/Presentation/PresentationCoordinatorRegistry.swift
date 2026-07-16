package import SwiftTUICore

// MARK: - Coordinator Registry

@MainActor
package final class PresentationCoordinatorBox<C: ManagedPresentationCoordinator>
where C.Item: PortalPresentationItem, C.Item.ID: Sendable {
  package struct Checkpoint: Sendable {
    fileprivate var coordinator: StoredPresentationCoordinatorCheckpoint<C.Item>?
  }

  private var coordinator: C?
  private weak var configuredInvalidator: (any Invalidating)?
  private var configuredInvalidationIdentity: Identity?

  package init() {}

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(
      coordinator: coordinator?.makeCheckpoint()
    )
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    guard let coordinatorCheckpoint = checkpoint.coordinator else {
      coordinator = nil
      return
    }

    instance().restoreCheckpoint(coordinatorCheckpoint)
  }

  package var zIndex: Int {
    C.zIndex
  }

  package var isActive: Bool {
    coordinator?.isActive ?? false
  }

  package var declaredSourceIdentities: Set<Identity> {
    coordinator?.declaredSourceIdentities ?? []
  }

  package var latestItem: C.Item? {
    coordinator?.latestItem
  }

  package func activeItem(
    id: C.Item.ID
  ) -> C.Item? {
    coordinator?.activeItem(id: id)
  }

  package func beginSynchronizing() {
    // Eagerly instantiate: the coordinator's store tracks the open pass
    // (`sync` buffers within one, so same-source declarations merge). A
    // lazily-created coordinator whose first `sync` arrives mid-pass would
    // miss the begin and fall back to eager per-call application — on a
    // family's first activation frame, chained same-source declarations
    // would overwrite each other again. An empty store is inactive.
    instance().beginSynchronizing()
  }

  package func sync(
    sourceIdentity: Identity,
    items: [C.Item]
  ) {
    let coordinator = instance()
    coordinator.sync(
      sourceIdentity: sourceIdentity,
      items: items
    )
  }

  package func endSynchronizing() {
    coordinator?.endSynchronizing()
  }

  package func setImperativeInvalidationTarget(
    identity: Identity,
    invalidator: (any Invalidating)?
  ) {
    configuredInvalidationIdentity = identity
    configuredInvalidator = invalidator
    coordinator?.setImperativeInvalidationTarget(
      identity: identity,
      invalidator: invalidator
    )
  }

  package func present(
    _ item: C.Item
  ) {
    instance().present(item)
  }

  package func dismiss(
    id: C.Item.ID
  ) {
    instance().dismiss(id: id)
  }

  package func overlayEntry() -> OverlayStackEntry? {
    guard let coordinator, coordinator.isActive, let item = coordinator.latestItem else {
      return nil
    }

    let stableID = "\(C.overlayKindName):\(item.portalEntryID.ownerStableKey)"
    return OverlayStackEntry(
      id: stableID,
      portalEntryID: item.portalEntryID,
      ordering: PortalOrdering(
        zIndex: C.zIndex,
        activationOrdinal: coordinator.latestActivationOrdinal ?? 0,
        stableTieBreaker: stableID
      ),
      kindName: C.overlayKindName,
      modalPolicy: coordinator.modalPolicy(for: item),
      acceptsEscape: coordinator.dismissAction(for: item) != nil,
      dismiss: coordinator.dismissAction(for: item),
      onDismiss: item.entryDismissObserver,
      payload: PortalAttachmentPayload(
        edge: PortalAttachmentEdge(
          portalEntryID: item.portalEntryID,
          modalPolicy: coordinator.modalPolicy(for: item)
        )
      ) {
        coordinator.makeBody()
      }
    )
  }

  private func instance() -> C {
    if let coordinator {
      return coordinator
    }

    let coordinator = C()
    if let configuredInvalidationIdentity {
      coordinator.setImperativeInvalidationTarget(
        identity: configuredInvalidationIdentity,
        invalidator: configuredInvalidator
      )
    }
    self.coordinator = coordinator
    return coordinator
  }
}

@MainActor
private struct AnyPresentationCoordinatorBox {
  private let beginSynchronizingImpl: @MainActor () -> Void
  private let endSynchronizingImpl: @MainActor () -> Void
  private let overlayEntryImpl: @MainActor () -> OverlayStackEntry?
  private let declaredSourceIdentitiesImpl: @MainActor () -> Set<Identity>

  init<C>(
    _ box: PresentationCoordinatorBox<C>
  ) where C: ManagedPresentationCoordinator, C.Item: PortalPresentationItem, C.Item.ID: Sendable {
    beginSynchronizingImpl = {
      box.beginSynchronizing()
    }
    endSynchronizingImpl = {
      box.endSynchronizing()
    }
    overlayEntryImpl = {
      box.overlayEntry()
    }
    declaredSourceIdentitiesImpl = {
      box.declaredSourceIdentities
    }
  }

  @MainActor
  func beginSynchronizing() {
    beginSynchronizingImpl()
  }

  @MainActor
  func endSynchronizing() {
    endSynchronizingImpl()
  }

  @MainActor
  func overlayEntry() -> OverlayStackEntry? {
    overlayEntryImpl()
  }

  @MainActor
  func declaredSourceIdentities() -> Set<Identity> {
    declaredSourceIdentitiesImpl()
  }
}

@MainActor
package final class PresentationCoordinatorRegistry {
  package struct Checkpoint: Sendable {
    fileprivate var alert: PresentationCoordinatorBox<AlertPresentationCoordinator>.Checkpoint
    fileprivate var confirmationDialog:
      PresentationCoordinatorBox<ConfirmationDialogPresentationCoordinator>.Checkpoint
    fileprivate var sheet: PresentationCoordinatorBox<SheetPresentationCoordinator>.Checkpoint
    fileprivate var popover: PresentationCoordinatorBox<PopoverPresentationCoordinator>.Checkpoint
    fileprivate var menu: PresentationCoordinatorBox<MenuPresentationCoordinator>.Checkpoint
    fileprivate var toast: PresentationCoordinatorBox<ToastPresentationCoordinator>.Checkpoint
    fileprivate var reconciledDeclarationGenerations: [Identity: UInt64]
    fileprivate var sourceEnvironmentValuesBySource: [Identity: EnvironmentValues]
  }

  package let alert = PresentationCoordinatorBox<AlertPresentationCoordinator>()
  package let confirmationDialog = PresentationCoordinatorBox<
    ConfirmationDialogPresentationCoordinator
  >()
  package let sheet = PresentationCoordinatorBox<SheetPresentationCoordinator>()
  package let popover = PresentationCoordinatorBox<PopoverPresentationCoordinator>()
  package let menu = PresentationCoordinatorBox<MenuPresentationCoordinator>()
  package let toast = PresentationCoordinatorBox<ToastPresentationCoordinator>()
  private lazy var allBoxes = [
    AnyPresentationCoordinatorBox(alert),
    AnyPresentationCoordinatorBox(confirmationDialog),
    AnyPresentationCoordinatorBox(sheet),
    AnyPresentationCoordinatorBox(popover),
    AnyPresentationCoordinatorBox(menu),
    AnyPresentationCoordinatorBox(toast),
  ]

  /// The declaration mint generations observed by the most recent
  /// `reconcile`, per source. A reconcile whose incoming generations differ
  /// carries *re-built* declarations (fresh payload closures), which is the
  /// signal the overlay composition uses to refresh entry subtrees whose
  /// entry list is otherwise unchanged.
  private var reconciledDeclarationGenerations: [Identity: UInt64] = [:]

  /// The presenting declarations' captured environments observed by the most
  /// recent `reconcile`, per source. `overlayEntries()` attaches them so
  /// portal-hosted entry content resolves under the presenter's inherited
  /// environment. Same lifecycle as `reconciledDeclarationGenerations`:
  /// rebuilt wholesale from each reconcile's declarations.
  private var sourceEnvironmentValuesBySource: [Identity: EnvironmentValues] = [:]

  package init() {}

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(
      alert: alert.makeCheckpoint(),
      confirmationDialog: confirmationDialog.makeCheckpoint(),
      sheet: sheet.makeCheckpoint(),
      popover: popover.makeCheckpoint(),
      menu: menu.makeCheckpoint(),
      toast: toast.makeCheckpoint(),
      reconciledDeclarationGenerations: reconciledDeclarationGenerations,
      sourceEnvironmentValuesBySource: sourceEnvironmentValuesBySource
    )
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    alert.restoreCheckpoint(checkpoint.alert)
    confirmationDialog.restoreCheckpoint(checkpoint.confirmationDialog)
    sheet.restoreCheckpoint(checkpoint.sheet)
    popover.restoreCheckpoint(checkpoint.popover)
    menu.restoreCheckpoint(checkpoint.menu)
    toast.restoreCheckpoint(checkpoint.toast)
    reconciledDeclarationGenerations = checkpoint.reconciledDeclarationGenerations
    sourceEnvironmentValuesBySource = checkpoint.sourceEnvironmentValuesBySource
  }

  package func setImperativeInvalidationTarget(
    identity: Identity,
    invalidator: (any Invalidating)?
  ) {
    alert.setImperativeInvalidationTarget(identity: identity, invalidator: invalidator)
    confirmationDialog.setImperativeInvalidationTarget(identity: identity, invalidator: invalidator)
    sheet.setImperativeInvalidationTarget(identity: identity, invalidator: invalidator)
    toast.setImperativeInvalidationTarget(identity: identity, invalidator: invalidator)
  }

  /// Applies the frame's declarations and reports whether any of them was
  /// re-built since the previous reconcile (by mint generation). `true`
  /// means at least one source's payload closures are fresh, so composition
  /// must refresh overlay-entry subtrees even when the entry list matches.
  @discardableResult
  package func reconcile(
    _ declarations: [PresentationCoordinatorDeclaration]
  ) -> Bool {
    for box in allBoxes {
      box.beginSynchronizing()
    }

    for declaration in declarations {
      declaration.apply(self)
    }

    for box in allBoxes {
      box.endSynchronizing()
    }

    let generations = declarations.reduce(into: [Identity: UInt64]()) { map, declaration in
      map[declaration.sourceIdentity] = max(
        map[declaration.sourceIdentity] ?? 0,
        declaration.mintGeneration
      )
    }
    sourceEnvironmentValuesBySource = declarations.reduce(
      into: [Identity: EnvironmentValues]()
    ) { map, declaration in
      map[declaration.sourceIdentity] = declaration.sourceEnvironmentValues
    }
    let refreshed = generations != reconciledDeclarationGenerations
    reconciledDeclarationGenerations = generations
    return refreshed
  }

  package func overlayEntries() -> [OverlayStackEntry] {
    allBoxes
      .compactMap {
        $0.overlayEntry()
      }
      .map { entry in
        // Attach the presenting declaration's captured environment so the
        // overlay entry host resolves the entry's content under it. Entries
        // without a reconciled declaration (imperative presentations) keep
        // resolving under the portal host's environment.
        var entry = entry
        entry.sourceEnvironmentValues = entry.portalEntryID.flatMap { portalEntryID in
          sourceEnvironmentValuesBySource[portalEntryID.sourceIdentity]
        }
        return entry
      }
      .sorted { lhs, rhs in
        portalOrderingPrecedes(lhs.ordering, rhs.ordering)
      }
  }

  package func declaredSourceIdentities() -> Set<Identity> {
    allBoxes.reduce(into: Set<Identity>()) { union, box in
      union.formUnion(box.declaredSourceIdentities())
    }
  }

  package func dismissStack() -> DismissStack {
    DismissStack(
      entries: overlayEntries().compactMap { entry in
        guard let dismiss = entry.dismiss else {
          return nil
        }
        return DismissStackEntry(
          id: entry.id,
          ordering: entry.ordering,
          acceptsEscape: entry.acceptsEscape,
          dismiss: dismiss
        )
      }
    )
  }
}
