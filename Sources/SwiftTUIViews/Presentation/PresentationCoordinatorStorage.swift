package import SwiftTUICore

// MARK: - Shared Item Storage

package struct TrackedPresentationItem<Item: Identifiable & Sendable>: Sendable
where Item.ID: Sendable {
  var item: Item
  var activationOrdinal: Int
}

@MainActor
package final class PresentationFamilyItemStore<Item: Identifiable & Sendable>
where Item.ID: Sendable {
  package struct Checkpoint: Sendable {
    fileprivate var declarativeItemsBySource: [Identity: [Item.ID: TrackedPresentationItem<Item>]]
    fileprivate var imperativeItemsByID: [Item.ID: TrackedPresentationItem<Item>]
    fileprivate var seenSources: Set<Identity>
    fileprivate var nextActivationOrdinal: Int
  }

  private var declarativeItemsBySource: [Identity: [Item.ID: TrackedPresentationItem<Item>]] = [:]
  private var imperativeItemsByID: [Item.ID: TrackedPresentationItem<Item>] = [:]
  private var seenSources: Set<Identity> = []
  private var nextActivationOrdinal = 0

  package init() {}

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(
      declarativeItemsBySource: declarativeItemsBySource,
      imperativeItemsByID: imperativeItemsByID,
      seenSources: seenSources,
      nextActivationOrdinal: nextActivationOrdinal
    )
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    declarativeItemsBySource = checkpoint.declarativeItemsBySource
    imperativeItemsByID = checkpoint.imperativeItemsByID
    seenSources = checkpoint.seenSources
    nextActivationOrdinal = checkpoint.nextActivationOrdinal
  }

  package func beginSynchronizing() {
    seenSources.removeAll(keepingCapacity: true)
  }

  package func sync(
    sourceIdentity: Identity,
    items: [Item]
  ) {
    seenSources.insert(sourceIdentity)

    guard !items.isEmpty else {
      declarativeItemsBySource[sourceIdentity] = [:]
      return
    }

    let previousItems = declarativeItemsBySource[sourceIdentity] ?? [:]
    var nextItems: [Item.ID: TrackedPresentationItem<Item>] = [:]
    for item in items {
      let activationOrdinal =
        previousItems[item.id]?.activationOrdinal
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

  package var latestItem: Item? {
    newestFirst.first
  }

  package var latestActivationOrdinal: Int? {
    mergedActiveItems()
      .values
      .max { lhs, rhs in
        if lhs.activationOrdinal != rhs.activationOrdinal {
          return lhs.activationOrdinal < rhs.activationOrdinal
        }
        return String(reflecting: lhs.item.id) < String(reflecting: rhs.item.id)
      }?
      .activationOrdinal
  }

  package var newestFirst: [Item] {
    mergedActiveItems()
      .values
      .sorted { lhs, rhs in
        if lhs.activationOrdinal != rhs.activationOrdinal {
          return lhs.activationOrdinal > rhs.activationOrdinal
        }
        return String(reflecting: lhs.item.id) < String(reflecting: rhs.item.id)
      }
      .map(\.item)
  }

  package var oldestFirst: [Item] {
    mergedActiveItems()
      .values
      .sorted { lhs, rhs in
        if lhs.activationOrdinal != rhs.activationOrdinal {
          return lhs.activationOrdinal < rhs.activationOrdinal
        }
        return String(reflecting: lhs.item.id) < String(reflecting: rhs.item.id)
      }
      .map(\.item)
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
    nextActivationOrdinal += 1
    return nextActivationOrdinal
  }
}

@MainActor
package struct StoredPresentationCoordinatorCheckpoint<Item: Identifiable & Sendable>: Sendable
where Item.ID: Sendable {
  fileprivate var itemStore: PresentationFamilyItemStore<Item>.Checkpoint
  fileprivate var invalidationIdentity: Identity?
}

@MainActor
package class StoredPresentationCoordinator<Item: Identifiable & Sendable>
where Item.ID: Sendable {
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

  package var latestItem: Item? {
    itemStore.latestItem
  }

  package var latestActivationOrdinal: Int? {
    itemStore.latestActivationOrdinal
  }

  package var itemsNewestFirst: [Item] {
    itemStore.newestFirst
  }

  package var itemsOldestFirst: [Item] {
    itemStore.oldestFirst
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
