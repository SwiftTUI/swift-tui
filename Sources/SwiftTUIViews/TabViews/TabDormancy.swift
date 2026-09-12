@_spi(Testing) import SwiftTUICore

private let tabDormantArchiveStateSlot = StateSlotOrdinals.tabDormantArchive
private let tabDormantLocatorStateSlot = tabDormantArchiveStateSlot - 1

package struct TabDormantKey: Hashable, Sendable {
  var value: AnyID
  var includeOptional: Bool
  var occurrence: Int

  package init(
    value: AnyID,
    includeOptional: Bool,
    occurrence: Int
  ) {
    self.value = value
    self.includeOptional = includeOptional
    self.occurrence = occurrence
  }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.value == rhs.value
      && lhs.includeOptional == rhs.includeOptional
      && lhs.occurrence == rhs.occurrence
  }

  package func hash(into hasher: inout Hasher) {
    hasher.combine(value)
    hasher.combine(includeOptional)
    hasher.combine(occurrence)
  }
}

private struct TabDormantEntityKey: Hashable, Sendable {
  var owner: TabDormantOwnerScope
  var value: AnyID
  var includeOptional: Bool
  var generation: UInt64
}

/// Authored, value-only identity for the active payload's structural child.
/// The enclosing TabView/content path supplies owner scope; the fields here
/// distinguish typed tags, optional matching, duplicates, and replacement
/// generations within that owner without depending on a graph-node lifetime.
package struct TabDormantPayloadStructuralIdentity: Hashable, Sendable {
  package var typedTagComponent: String
  package var includeOptional: Bool
  package var occurrence: Int
  package var generation: UInt64
}

/// Stable authored ownership for a TabView's lazy payload entities. Nested
/// TabViews inherit the nearest routed payload entity, so an enclosing dormant
/// archive can preseed the same inner payload routes without depending on a
/// raw graph-node allocation. The authored identity separates sibling owners
/// within that entity scope and changes with explicit owner replacement.
private struct TabDormantOwnerScope: Hashable, Sendable {
  var enclosingEntity: EntityIdentity?
  var rootOwner: StateOwnerHandle?
  var authoredIdentity: Identity
}

package struct DormantTabArchiveRefreshRequest: Sendable {
  package var owner: StateOwnerHandle
  package var key: TabDormantKey
  package var refreshToken: UInt64
  package var locator: DormantStateArchiveLocator

  package init(
    owner: StateOwnerHandle,
    key: TabDormantKey,
    refreshToken: UInt64,
    locator: DormantStateArchiveLocator
  ) {
    self.owner = owner
    self.key = key
    self.refreshToken = refreshToken
    self.locator = locator
  }
}

@MainActor
package struct DormantTabArchiveCommitRefresh {
  package var owner: StateOwnerHandle
  package var key: TabDormantKey
  package var refreshToken: UInt64
  package var archive: DormantStateArchive

  package init(
    owner: StateOwnerHandle,
    key: TabDormantKey,
    refreshToken: UInt64,
    archive: DormantStateArchive
  ) {
    self.owner = owner
    self.key = key
    self.refreshToken = refreshToken
    self.archive = archive
  }
}

package enum DormantTabArchiveRefreshPreferenceKey: PreferenceKey {
  package static let defaultValue: [DormantTabArchiveRefreshRequest] = []

  package static func reduce(
    value: inout [DormantTabArchiveRefreshRequest],
    nextValue: () -> [DormantTabArchiveRefreshRequest]
  ) {
    value.append(contentsOf: nextValue())
  }
}

@MainActor
private struct TabDormantRegistry {
  struct Entry {
    var key: TabDormantKey
    var archive: DormantStateArchive
    var pendingRefreshToken: UInt64?
  }

  struct Lifetime {
    var key: TabDormantKey
    var generation: UInt64
  }

  var activeKey: TabDormantKey?
  var entries: [Entry] = []
  var lifetimes: [Lifetime] = []
  var nextLifetimeGeneration: UInt64 = 0
  var nextRefreshToken: UInt64 = 0

  @discardableResult
  mutating func archive(
    _ archive: DormantStateArchive,
    for key: TabDormantKey
  ) -> UInt64 {
    let refreshToken = nextRefreshToken
    nextRefreshToken &+= 1
    if let index = entries.firstIndex(where: { $0.key == key }) {
      entries[index].archive = archive
      entries[index].pendingRefreshToken = refreshToken
    } else {
      entries.append(
        Entry(
          key: key,
          archive: archive,
          pendingRefreshToken: refreshToken
        )
      )
    }
    return refreshToken
  }

  func archive(for key: TabDormantKey) -> DormantStateArchive? {
    entries.first(where: { $0.key == key })?.archive
  }

  mutating func removeArchive(for key: TabDormantKey) {
    entries.removeAll { $0.key == key }
  }

  mutating func updateDeclaredKeys(_ newDeclaredKeys: [TabDormantKey]) {
    entries.removeAll { entry in
      !newDeclaredKeys.contains(entry.key)
    }
    lifetimes.removeAll { lifetime in
      !newDeclaredKeys.contains(lifetime.key)
    }
    for key in newDeclaredKeys where !lifetimes.contains(where: { $0.key == key }) {
      lifetimes.append(
        Lifetime(key: key, generation: nextLifetimeGeneration)
      )
      nextLifetimeGeneration &+= 1
    }
  }

  func lifetimeGeneration(for key: TabDormantKey) -> UInt64? {
    lifetimes.first(where: { $0.key == key })?.generation
  }
}

/// Locator recipes are live-graph currency and must never enter a dormant
/// archive. Keeping them in a distinct transient slot lets the value-only tab
/// registry itself nest safely inside an enclosing tab's archive.
private struct TabDormantLocatorState {
  var activeKey: TabDormantKey?
  var activeLocator: DormantStateArchiveLocator?
}

/// Reads value-only archive snapshots for the tab owners that emitted a
/// departure request in this candidate. The completed-frame path calls this
/// while the suspended committed graph is still materialized, before the
/// prepared checkpoint replaces outgoing owners. Nothing is written here, so
/// a subsequently aborted candidate cannot mutate the committed registry.
@MainActor
package func captureDormantTabArchiveCommitRefreshes(
  in viewGraph: ViewGraph,
  requests: [DormantTabArchiveRefreshRequest]
) -> [DormantTabArchiveCommitRefresh] {
  var refreshedOwners: Set<StateOwnerHandle> = []
  var refreshes: [DormantTabArchiveCommitRefresh] = []
  for request in requests where refreshedOwners.insert(request.owner).inserted {
    refreshes.append(
      DormantTabArchiveCommitRefresh(
        owner: request.owner,
        key: request.key,
        refreshToken: request.refreshToken,
        archive: viewGraph.captureDormantStateArchive(using: request.locator)
      )
    )
  }
  return refreshes
}

/// Applies commit-authoritative value snapshots after the prepared graph is
/// materialized and immediately before frame finalization tears down outgoing
/// payload nodes. The archive contains no task, registration, observation, or
/// node references.
@MainActor
package func applyDormantTabArchiveCommitRefreshes(
  _ refreshes: [DormantTabArchiveCommitRefresh],
  in viewGraph: ViewGraph
) {
  for refresh in refreshes {
    guard
      refresh.owner.graphScope == viewGraph.stateGraphScopeID,
      let ownerNode = viewGraph.nodeForOwnerLifetimeID(refresh.owner.ownerLifetime)
    else {
      continue
    }
    var registry = loadTabDormantRegistry(from: ownerNode)
    guard
      let index = registry.entries.firstIndex(where: {
        $0.key == refresh.key && $0.pendingRefreshToken == refresh.refreshToken
      })
    else {
      continue
    }
    registry.entries[index].archive = refresh.archive
    registry.entries[index].pendingRefreshToken = nil
    storeTabDormantRegistry(registry, in: ownerNode)
  }
}

@MainActor
private func makeDormantArchiveLocatorSink(
  ownerNode: SwiftTUICore.ViewNode?,
  key: TabDormantKey?
) -> (@MainActor @Sendable (DormantStateArchiveLocator) -> Void)? {
  guard let ownerNode, let key else {
    return nil
  }
  return { [weak ownerNode] locator in
    guard let ownerNode else {
      return
    }
    let registry = loadTabDormantRegistry(from: ownerNode)
    guard registry.activeKey == key else {
      return
    }
    storeTabDormantLocatorState(
      TabDormantLocatorState(activeKey: key, activeLocator: locator),
      in: ownerNode
    )
  }
}

@MainActor
private func loadTabDormantRegistry(
  from ownerNode: SwiftTUICore.ViewNode
) -> TabDormantRegistry {
  withPersistentDormantStateSlot {
    ownerNode.stateSlot(
      ordinal: tabDormantArchiveStateSlot,
      seed: TabDormantRegistry()
    )
  }
}

@MainActor
private func storeTabDormantRegistry(
  _ registry: TabDormantRegistry,
  in ownerNode: SwiftTUICore.ViewNode
) {
  withPersistentDormantStateSlot {
    ownerNode.setStateSlotSilently(
      ordinal: tabDormantArchiveStateSlot,
      value: registry
    )
  }
}

@MainActor
private func loadTabDormantLocatorState(
  from ownerNode: SwiftTUICore.ViewNode
) -> TabDormantLocatorState {
  withTransientDormantStateSlot {
    ownerNode.stateSlot(
      ordinal: tabDormantLocatorStateSlot,
      seed: TabDormantLocatorState()
    )
  }
}

@MainActor
private func storeTabDormantLocatorState(
  _ locatorState: TabDormantLocatorState,
  in ownerNode: SwiftTUICore.ViewNode
) {
  withTransientDormantStateSlot {
    ownerNode.setStateSlotSilently(
      ordinal: tabDormantLocatorStateSlot,
      value: locatorState
    )
  }
}

@MainActor
package struct TabDormantRegistrySnapshot: Equatable, Sendable {
  package var archivedTabCount: Int
  package var archivedNodeCount: Int
  package var persistentSlotCount: Int
}

@MainActor
package func tabDormantRegistrySnapshot(
  in ownerNode: SwiftTUICore.ViewNode?
) -> TabDormantRegistrySnapshot {
  guard let ownerNode else {
    return .init(archivedTabCount: 0, archivedNodeCount: 0, persistentSlotCount: 0)
  }
  let registry = loadTabDormantRegistry(from: ownerNode)
  return TabDormantRegistrySnapshot(
    archivedTabCount: registry.entries.count,
    archivedNodeCount: registry.entries.reduce(into: 0) { $0 += $1.archive.records.count },
    persistentSlotCount: registry.entries.reduce(into: 0) {
      $0 += $1.archive.persistentSlotCount
    }
  )
}

/// Owns tab archive transitions, generation identity and locator intake.
/// The persistent registry and transient locator remain distinct checkpointed
/// slots; lowering never accesses their representation.
@MainActor
enum TabDormancy {
  struct Selection {
    var entityIdentity: EntityIdentity?
    var structuralIdentity: TabDormantPayloadStructuralIdentity?
    var refreshRequest: DormantTabArchiveRefreshRequest?
  }

  static func prepare(
    in context: ResolveContext, ownerNode: SwiftTUICore.ViewNode?,
    declaredDormantKeys: [TabDormantKey], selectedDormantKey: TabDormantKey?,
    selectedTagComponent: String?
  ) -> Selection {
    var selectedContentEntityIdentity: EntityIdentity?
    var selectedContentStructuralIdentity: TabDormantPayloadStructuralIdentity?
    var dormantArchiveRefreshRequest: DormantTabArchiveRefreshRequest?

    if let ownerNode {
      let enclosingEntity = ResolveEntityRouteStorage.current?.identity
      let dormantOwnerScope = TabDormantOwnerScope(
        enclosingEntity: enclosingEntity,
        rootOwner: enclosingEntity == nil ? ownerNode.stateOwnerHandle : nil,
        authoredIdentity: context.identity
      )
      var dormantRegistry = loadTabDormantRegistry(from: ownerNode)
      var locatorState = loadTabDormantLocatorState(from: ownerNode)
      dormantRegistry.updateDeclaredKeys(declaredDormantKeys)
      if let selectedDormantKey,
        let selectedTagComponent,
        let generation = dormantRegistry.lifetimeGeneration(for: selectedDormantKey)
      {
        selectedContentEntityIdentity = EntityIdentity(
          TabDormantEntityKey(
            owner: dormantOwnerScope,
            value: selectedDormantKey.value,
            includeOptional: selectedDormantKey.includeOptional,
            generation: generation
          ),
          occurrence: selectedDormantKey.occurrence
        )
        selectedContentStructuralIdentity = TabDormantPayloadStructuralIdentity(
          typedTagComponent: selectedTagComponent,
          includeOptional: selectedDormantKey.includeOptional,
          occurrence: selectedDormantKey.occurrence,
          generation: generation
        )
      }

      if dormantRegistry.activeKey != selectedDormantKey {
        if let departingKey = dormantRegistry.activeKey,
          declaredDormantKeys.contains(departingKey),
          locatorState.activeKey == departingKey,
          let activeLocator = locatorState.activeLocator,
          let viewGraph = context.viewGraph
        {
          let refreshToken = dormantRegistry.archive(
            viewGraph.captureDormantStateArchive(using: activeLocator),
            for: departingKey
          )
          if let owner = ownerNode.stateOwnerHandle {
            dormantArchiveRefreshRequest = .init(
              owner: owner,
              key: departingKey,
              refreshToken: refreshToken,
              locator: activeLocator
            )
          }
        }

        if let selectedDormantKey,
          let archive = dormantRegistry.archive(for: selectedDormantKey)
        {
          context.viewGraph?.restoreDormantStateArchive(archive)
          dormantRegistry.removeArchive(for: selectedDormantKey)
        }

        dormantRegistry.activeKey = selectedDormantKey
        locatorState = TabDormantLocatorState()
      }

      storeTabDormantRegistry(dormantRegistry, in: ownerNode)
      storeTabDormantLocatorState(locatorState, in: ownerNode)
    }
    return Selection(
      entityIdentity: selectedContentEntityIdentity,
      structuralIdentity: selectedContentStructuralIdentity,
      refreshRequest: dormantArchiveRefreshRequest)
  }

  static func makeLocatorSink(ownerNode: SwiftTUICore.ViewNode?, key: TabDormantKey?)
    -> (@MainActor @Sendable (DormantStateArchiveLocator) -> Void)?
  {
    makeDormantArchiveLocatorSink(ownerNode: ownerNode, key: key)
  }
}
