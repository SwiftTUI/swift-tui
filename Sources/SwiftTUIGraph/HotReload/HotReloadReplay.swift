/// A slot address relative to one reload root. Owner lifetimes never cross generations.
package struct HotReloadSlotAddress: Hashable, Sendable {
  package var owner: Identity
  package var slot: StateSlotIdentifier
}

package struct HotReloadDiagnostic: Equatable, Sendable {
  package var address: HotReloadSlotAddress
  package var reason: String
}

/// Complete authored slot declarations for one destination owner.
package struct HotReloadOwnerSchema: Equatable, Sendable {
  package var identity: Identity
  package var slots: [StateSlotIdentifier: String]
}

package struct HotReloadSnapshot: Equatable, Sendable {
  package struct Entry: Equatable, Sendable {
    package var address: HotReloadSlotAddress
    package var typeName: String
    package var value: SnapshotValue?
    package var failure: String?
  }
  package var sourceRoot: Identity
  package var entries: [Entry]
  package var ambiguousOwners: Set<Identity> = []
}

package struct HotReloadReplay: Equatable, Sendable {
  package var destinationRoot: Identity
  package var pending: [HotReloadSlotAddress: HotReloadSnapshot.Entry] = [:]
  package var diagnostics: [HotReloadDiagnostic] = []
  package var restoredCount = 0
  package var ownerMatches: [Identity: Identity] = [:]

  /// Build every match before exposing values to first body evaluation.
  package init(
    snapshot: HotReloadSnapshot, destinationRoot: Identity, owners: [HotReloadOwnerSchema]
  ) {
    self.destinationRoot = destinationRoot
    let sourceGroups = Dictionary(grouping: snapshot.entries, by: { $0.address.owner })
    let targetGroups = Dictionary(grouping: owners, by: \.identity)
    var availableSources = Set(sourceGroups.keys)
    var availableTargets = Set(targetGroups.keys)
    var matches: [Identity: Identity] = [:]

    // Reserve exact owners globally, even if their slot schemas are incompatible.
    // A failed exact owner must never donate its state to a nearby wrapper.
    for owner in availableSources.intersection(availableTargets).sorted() {
      matches[owner] = owner
      availableSources.remove(owner)
      availableTargets.remove(owner)
    }
    let candidates = Dictionary(
      uniqueKeysWithValues: availableSources.map { source in
        (source, availableTargets.filter { Self.differsByOneWrapper(source, $0) })
      })
    for source in availableSources.sorted() {
      guard let targets = candidates[source], targets.count == 1, let target = targets.first,
        candidates.values.filter({ $0.contains(target) }).count == 1
      else { continue }
      matches[source] = target
    }

    var accepted: Set<HotReloadSlotAddress> = []
    for source in matches.keys.sorted() {
      guard let target = matches[source], let entries = sourceGroups[source],
        let schemas = targetGroups[target], schemas.count == 1
      else { continue }
      let schema = schemas[0]
      guard !snapshot.ambiguousOwners.contains(source) else { continue }
      // Multiple graph owners may share a flattened structural identity.
      // Their duplicate addresses are ambiguity, never mergeable state.
      let sourceSlots = Dictionary(grouping: entries, by: { $0.address.slot })
      guard sourceSlots.values.allSatisfy({ $0.count == 1 }) else { continue }
      ownerMatches[source] = target
      let paths = Set(entries.map { $0.address.slot.path })
      for path in paths {
        let old = entries.filter { $0.address.slot.path == path }
          .sorted { $0.address.slot.ordinal < $1.address.slot.ordinal }
        let new = schema.slots.keys.filter { $0.path == path }.sorted { $0.ordinal < $1.ordinal }
        let exactSet = Set(old.map { $0.address.slot }) == Set(new)
        // Synthetic runtime slots have no declaration-rank meaning.
        let canRank =
          old.count == new.count
          && old.allSatisfy { $0.address.slot.ordinal >= 0 }
          && new.allSatisfy { $0.ordinal >= 0 }
        guard exactSet || canRank, old.count == new.count else { continue }
        guard zip(old, new).allSatisfy({ entry, slot in entry.typeName == schema.slots[slot] })
        else { continue }
        for (entry, slot) in zip(old, new) {
          guard entry.value != nil else { continue }
          pending[.init(owner: target, slot: slot)] = entry
          accepted.insert(entry.address)
        }
      }
    }
    for entry in snapshot.entries where !accepted.contains(entry.address) {
      diagnostics.append(
        .init(
          address: entry.address,
          reason: entry.failure ?? "No unambiguous destination with a compatible slot schema"
        ))
    }
    sortDiagnostics()
  }

  /// A conservative single-wrapper edit: never erase entity or indexed sibling identity.
  private static func differsByOneWrapper(_ lhs: Identity, _ rhs: Identity) -> Bool {
    let shorter = lhs.components.count < rhs.components.count ? lhs.components : rhs.components
    let longer = lhs.components.count < rhs.components.count ? rhs.components : lhs.components
    guard longer.count == shorter.count + 1 else { return false }
    for index in longer.indices {
      let component = longer[index]
      guard !component.contains("["), !component.contains("]") else { continue }
      if Array(longer[..<index]) + Array(longer[(index + 1)...]) == shorter { return true }
    }
    return false
  }

  package mutating func value<Value>(for identity: Identity, slot: StateSlotIdentifier) -> Value? {
    guard let entry = takeEntry(for: identity, slot: slot) else { return nil }
    do {
      let decoded: Value = try Self.decode(entry)
      restoredCount += 1
      return decoded
    } catch {
      diagnostics.append(.init(address: entry.address, reason: "Decode failed: \(error)"))
      return nil
    }
  }

  package mutating func takeEntry(
    for identity: Identity, slot: StateSlotIdentifier
  ) -> HotReloadSnapshot.Entry? {
    guard let owner = Self.relative(identity, to: destinationRoot) else { return nil }
    let key = HotReloadSlotAddress(owner: owner, slot: slot)
    return pending.removeValue(forKey: key)
  }

  package static func decode<Value>(_ entry: HotReloadSnapshot.Entry) throws -> Value {
    guard entry.typeName == String(reflecting: Value.self),
      let type = Value.self as? any Decodable.Type, let value = entry.value,
      let decoded = try SnapshotCoding.decode(type, from: value) as? Value
    else { throw SnapshotCodingError.incompatibleContainer }
    return decoded
  }

  package mutating func finish() -> [HotReloadDiagnostic] {
    for entry in pending.values {
      diagnostics.append(
        .init(address: entry.address, reason: "Destination slot was never initialized"))
    }
    pending.removeAll()
    sortDiagnostics()
    return diagnostics
  }

  private mutating func sortDiagnostics() {
    diagnostics.sort {
      ($0.address.owner.path, $0.address.slot.path.description, $0.address.slot.ordinal, $0.reason)
        < (
          $1.address.owner.path, $1.address.slot.path.description, $1.address.slot.ordinal,
          $1.reason
        )
    }
  }

  package static func relative(_ identity: Identity, to root: Identity) -> Identity? {
    guard identity.components.starts(with: root.components) else { return nil }
    return Identity(components: Array(identity.components.dropFirst(root.components.count)))
  }
}

extension ViewGraph {
  package func restoredHotReloadValue<Value>(
    for identity: Identity, slot: StateSlotIdentifier
  ) -> Value? {
    // Claim under a short mutation, then release graph exclusivity before
    // application Decodable code runs. It may read or write other live state.
    guard let entry = hotReloadReplay?.takeEntry(for: identity, slot: slot) else { return nil }
    do {
      let decoded: Value = try HotReloadReplay.decode(entry)
      hotReloadReplay?.restoredCount += 1
      return decoded
    } catch {
      hotReloadReplay?.diagnostics.append(
        .init(address: entry.address, reason: "Decode failed: \(error)"))
      return nil
    }
  }

  package func captureHotReloadSnapshot(rootedAt root: Identity) -> HotReloadSnapshot {
    var entries: [HotReloadSnapshot.Entry] = []
    var ownerCounts: [Identity: Int] = [:]
    for node in nodesByNodeID.values.sorted(by: { $0.viewNodeID < $1.viewNodeID }) {
      guard let owner = HotReloadReplay.relative(node.identity, to: root) else { continue }
      if node.stateSlots.values.contains(where: \.isInitialized) {
        ownerCounts[owner, default: 0] += 1
      }
      for (identifier, slot) in node.stateSlots where slot.isInitialized {
        let address = HotReloadSlotAddress(owner: owner, slot: identifier)
        do {
          let value = try slot.hotReloadValue()
          entries.append(
            .init(address: address, typeName: slot.storedTypeDescription, value: value))
        } catch {
          entries.append(
            .init(
              address: address, typeName: slot.storedTypeDescription,
              failure: String(describing: error)
            ))
        }
      }
    }
    entries.sort {
      ($0.address.owner.path, $0.address.slot.path.description, $0.address.slot.ordinal)
        < ($1.address.owner.path, $1.address.slot.path.description, $1.address.slot.ordinal)
    }
    return HotReloadSnapshot(
      sourceRoot: root, entries: entries,
      ambiguousOwners: Set(ownerCounts.filter { $0.value > 1 }.map(\.key))
    )
  }

  package func installHotReloadReplay(
    _ snapshot: HotReloadSnapshot, at destinationRoot: Identity, owners: [HotReloadOwnerSchema]
  ) throws {
    guard hotReloadReplay == nil,
      !snapshot.sourceRoot.components.starts(with: destinationRoot.components),
      !destinationRoot.components.starts(with: snapshot.sourceRoot.components),
      !nodesByNodeID.values.contains(where: {
        $0.identity.components.starts(with: destinationRoot.components)
      })
    else { throw HotReloadInstallationError.destinationIsNotFresh }
    hotReloadReplay = HotReloadReplay(
      snapshot: snapshot, destinationRoot: destinationRoot, owners: owners)
  }

  package func finishHotReloadReplay() -> [HotReloadDiagnostic] {
    guard var replay = hotReloadReplay else { return [] }
    hotReloadReplay = nil
    return replay.finish()
  }
}

package enum HotReloadInstallationError: Error {
  case destinationIsNotFresh
}
