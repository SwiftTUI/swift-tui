package import SwiftTUICore

// MARK: - Shared Item Storage

/// Monotonic cross-family mint for presentation activation ordinals. Escape
/// dismissal unwinds by activation recency across coordinator families
/// (menu vs popover vs sheet), so ordinals must be comparable between
/// families — a per-store counter would tie every family's first entry.
@MainActor
package enum PresentationActivationOrdinalMint {
  private static var nextOrdinal = 0

  package static func next() -> Int {
    // Deliberately unbounded for the process lifetime: only relative order
    // matters, and an aborted frame's restore may skip minted values.
    nextOrdinal &+= 1
    return nextOrdinal
  }
}

package struct TrackedPresentationItem<Item: PortalPresentationItem>: Sendable {
  var item: Item
  var activationOrdinal: Int
}

package struct PresentationOverlayItem<Item: PortalPresentationItem>: Sendable {
  package var item: Item
  package var activationOrdinal: Int

  package init(
    item: Item,
    activationOrdinal: Int
  ) {
    self.item = item
    self.activationOrdinal = activationOrdinal
  }
}

@MainActor
package final class PresentationFamilyItemStore<Item: PortalPresentationItem> {
  package struct Checkpoint: Sendable {
    fileprivate var declarativeItemsBySource: [Identity: [Item.ID: TrackedPresentationItem<Item>]]
    fileprivate var imperativeItemsByID: [Item.ID: TrackedPresentationItem<Item>]
    fileprivate var seenSources: Set<Identity>
  }

  private var declarativeItemsBySource: [Identity: [Item.ID: TrackedPresentationItem<Item>]] = [:]
  private var imperativeItemsByID: [Item.ID: TrackedPresentationItem<Item>] = [:]
  private var seenSources: Set<Identity> = []

  /// Within-pass sync buffer. Chained modifiers on one chain node share a
  /// source identity but emit separate declarations, each calling `sync`
  /// once during a reconcile pass — applying eagerly would let the later
  /// declaration replace the earlier one's items wholesale. Buffering and
  /// applying once at `endSynchronizing()` merges them, and keeps
  /// activation-ordinal continuity reading the pre-pass entries. Transient
  /// between `beginSynchronizing()`/`endSynchronizing()` (reconcile runs
  /// synchronously between them), so none of this is checkpointed.
  private var isSynchronizing = false
  private var pendingPassItemsBySource: [Identity: [Item]] = [:]
  private var pendingPassSources: [Identity] = []

  package init() {}

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(
      declarativeItemsBySource: declarativeItemsBySource,
      imperativeItemsByID: imperativeItemsByID,
      seenSources: seenSources
    )
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    declarativeItemsBySource = checkpoint.declarativeItemsBySource
    imperativeItemsByID = checkpoint.imperativeItemsByID
    seenSources = checkpoint.seenSources
  }

  package func beginSynchronizing() {
    seenSources.removeAll(keepingCapacity: true)
    isSynchronizing = true
    pendingPassItemsBySource.removeAll(keepingCapacity: true)
    pendingPassSources.removeAll(keepingCapacity: true)
  }

  package func sync(
    sourceIdentity: Identity,
    items: [Item]
  ) {
    guard isSynchronizing else {
      seenSources.insert(sourceIdentity)
      applySync(sourceIdentity: sourceIdentity, items: items)
      return
    }

    if !seenSources.contains(sourceIdentity) {
      pendingPassSources.append(sourceIdentity)
    }
    seenSources.insert(sourceIdentity)
    pendingPassItemsBySource[sourceIdentity, default: []].append(contentsOf: items)
  }

  private func applySync(
    sourceIdentity: Identity,
    items: [Item],
    continuityItemsByStableKey: [String: TrackedPresentationItem<Item>]? = nil
  ) {
    guard !items.isEmpty else {
      declarativeItemsBySource[sourceIdentity] = [:]
      return
    }

    let previousItems = declarativeItemsBySource[sourceIdentity] ?? [:]
    var nextItems: [Item.ID: TrackedPresentationItem<Item>] = [:]
    for item in items {
      let activationOrdinal =
        previousItems[item.id]?.activationOrdinal
        ?? continuityItemsByStableKey?[item.portalEntryID.ownerStableKey]?.activationOrdinal
        ?? activeEntry(for: item.id)?.activationOrdinal
        ?? allocateActivationOrdinal()
      nextItems[item.id] = .init(
        item: item,
        activationOrdinal: activationOrdinal
      )
    }
    declarativeItemsBySource[sourceIdentity] = nextItems
  }

  package func endSynchronizing() {
    // Every source in this pass must recover activation continuity from the
    // same immutable pre-pass view. Applying a positional source reorder
    // in-place can otherwise overwrite the old source that a later item needs
    // for its lookup, spuriously reminting that surviving item's ordinal.
    let continuityItemsByStableKey = mergedActiveItems().values.reduce(
      into: [String: TrackedPresentationItem<Item>]()
    ) { itemsByStableKey, trackedItem in
      let stableKey = trackedItem.item.portalEntryID.ownerStableKey
      if let existing = itemsByStableKey[stableKey],
        existing.activationOrdinal > trackedItem.activationOrdinal
      {
        return
      }
      itemsByStableKey[stableKey] = trackedItem
    }
    for sourceIdentity in pendingPassSources {
      applySync(
        sourceIdentity: sourceIdentity,
        items: pendingPassItemsBySource[sourceIdentity] ?? [],
        continuityItemsByStableKey: continuityItemsByStableKey
      )
    }
    pendingPassItemsBySource.removeAll(keepingCapacity: true)
    pendingPassSources.removeAll(keepingCapacity: true)
    isSynchronizing = false

    let staleSources = declarativeItemsBySource.keys.filter { !seenSources.contains($0) }
    for sourceIdentity in staleSources {
      declarativeItemsBySource.removeValue(forKey: sourceIdentity)
    }

    let emptySources = declarativeItemsBySource.compactMap { sourceIdentity, items in
      items.isEmpty ? sourceIdentity : nil
    }
    for sourceIdentity in emptySources {
      declarativeItemsBySource.removeValue(forKey: sourceIdentity)
    }
  }

  package func presentImperatively(
    _ item: Item
  ) {
    let activationOrdinal =
      activeEntry(for: item.id)?.activationOrdinal
      ?? allocateActivationOrdinal()
    imperativeItemsByID[item.id] = .init(
      item: item,
      activationOrdinal: activationOrdinal
    )
  }

  package func dismissImperatively(
    id: Item.ID
  ) {
    imperativeItemsByID.removeValue(forKey: id)
  }

  package var isActive: Bool {
    !mergedActiveItems().isEmpty
  }

  /// Source identities with declaratively-synced items — the sources whose
  /// declaration emitters were active at the last reconcile. The frame head
  /// compares these against per-frame emitter observations (and against node
  /// liveness, for source-subtree removal) to decide whether a selective
  /// frame must escalate to a portal-root reconcile.
  package var declaredSourceIdentities: Set<Identity> {
    Set(declarativeItemsBySource.keys)
  }

  package var oldestFirst: [Item] {
    trackedOldestFirst.map(\.item)
  }

  package var trackedOldestFirst: [TrackedPresentationItem<Item>] {
    mergedActiveItems()
      .values
      .sorted { lhs, rhs in
        if lhs.activationOrdinal != rhs.activationOrdinal {
          return lhs.activationOrdinal < rhs.activationOrdinal
        }
        return String(reflecting: lhs.item.id) < String(reflecting: rhs.item.id)
      }
  }

  /// The currently-active item for `id`, if any. Deadline tasks armed at
  /// activation consult this at fire time so a re-synced item (same id, new
  /// dismissal target) dismisses through its current closure, not the one
  /// captured when the deadline started.
  package func activeItem(
    id: Item.ID
  ) -> Item? {
    activeEntry(for: id)?.item
  }

  private func mergedActiveItems() -> [Item.ID: TrackedPresentationItem<Item>] {
    var merged: [Item.ID: TrackedPresentationItem<Item>] = [:]

    for items in declarativeItemsBySource.values {
      for (itemID, trackedItem) in items {
        if let existing = merged[itemID],
          existing.activationOrdinal > trackedItem.activationOrdinal
        {
          continue
        }
        merged[itemID] = trackedItem
      }
    }

    for (itemID, trackedItem) in imperativeItemsByID {
      if let existing = merged[itemID],
        existing.activationOrdinal > trackedItem.activationOrdinal
      {
        continue
      }
      merged[itemID] = trackedItem
    }

    return merged
  }

  private func activeEntry(
    for itemID: Item.ID
  ) -> TrackedPresentationItem<Item>? {
    if let imperativeItem = imperativeItemsByID[itemID] {
      return imperativeItem
    }

    for items in declarativeItemsBySource.values {
      if let declarativeItem = items[itemID] {
        return declarativeItem
      }
    }

    return nil
  }

  private func allocateActivationOrdinal() -> Int {
    PresentationActivationOrdinalMint.next()
  }
}

@MainActor
package struct StoredPresentationCoordinatorCheckpoint<Item: PortalPresentationItem>: Sendable {
  fileprivate var itemStore: PresentationFamilyItemStore<Item>.Checkpoint
  fileprivate var invalidationIdentity: Identity?
}

@MainActor
package class StoredPresentationCoordinator<Item: PortalPresentationItem> {
  package let itemStore = PresentationFamilyItemStore<Item>()

  private weak var imperativeInvalidator: (any Invalidating)?
  private var invalidationIdentity: Identity?

  package init() {}

  package func makeCheckpoint() -> StoredPresentationCoordinatorCheckpoint<Item> {
    StoredPresentationCoordinatorCheckpoint(
      itemStore: itemStore.makeCheckpoint(),
      invalidationIdentity: invalidationIdentity
    )
  }

  package func restoreCheckpoint(
    _ checkpoint: StoredPresentationCoordinatorCheckpoint<Item>
  ) {
    itemStore.restoreCheckpoint(checkpoint.itemStore)
    invalidationIdentity = checkpoint.invalidationIdentity
  }

  package func setImperativeInvalidationTarget(
    identity: Identity,
    invalidator: (any Invalidating)?
  ) {
    invalidationIdentity = identity
    imperativeInvalidator = invalidator
  }

  package func beginSynchronizing() {
    itemStore.beginSynchronizing()
  }

  package func sync(
    sourceIdentity: Identity,
    items: [Item]
  ) {
    itemStore.sync(
      sourceIdentity: sourceIdentity,
      items: items
    )
  }

  package func endSynchronizing() {
    itemStore.endSynchronizing()
  }

  package var isActive: Bool {
    itemStore.isActive
  }

  package var declaredSourceIdentities: Set<Identity> {
    itemStore.declaredSourceIdentities
  }

  package var itemsOldestFirst: [Item] {
    itemStore.oldestFirst
  }

  package var overlayItemsOldestFirst: [PresentationOverlayItem<Item>] {
    itemStore.trackedOldestFirst.map {
      PresentationOverlayItem(
        item: $0.item,
        activationOrdinal: $0.activationOrdinal
      )
    }
  }

  package func activeItem(
    id: Item.ID
  ) -> Item? {
    itemStore.activeItem(id: id)
  }

  package func present(
    _ item: Item,
    message: String
  ) {
    guard PresentationMutationGuard.allowMutation(message) else {
      return
    }
    itemStore.presentImperatively(item)
    requestInvalidation()
  }

  package func dismiss(
    id: Item.ID,
    message: String
  ) {
    guard PresentationMutationGuard.allowMutation(message) else {
      return
    }
    itemStore.dismissImperatively(id: id)
    requestInvalidation()
  }

  private func requestInvalidation() {
    guard let invalidationIdentity else {
      return
    }
    imperativeInvalidator?.requestInvalidation(of: [invalidationIdentity])
  }
}
