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
  package var declarationNames: [StateSlotIdentifier: [String]] = [:]
}

package struct HotReloadSnapshot: Equatable, Sendable {
  package struct Entry: Equatable, Sendable {
    package var address: HotReloadSlotAddress
    package var typeName: String
    package var value: SnapshotValue?
    package var failure: String?
    package var isDormant = false
    package var participatesInSchema = true
    package var requiresDormantSchema = false
    package var declarationName: [String]? = nil
  }
  package var sourceRoot: Identity
  package var entries: [Entry]
  package var ambiguousOwners: Set<Identity> = []
}

package struct HotReloadReplay: Equatable, Sendable {
  package var typeAliases: [String: String]
  package var destinationRoot: Identity
  package var pending: [HotReloadSlotAddress: HotReloadSnapshot.Entry] = [:]
  package var diagnostics: [HotReloadDiagnostic] = []
  package var restoredCount = 0
  package var ownerMatches: [Identity: Identity] = [:]

  /// Build every match before exposing values to first body evaluation.
  package init(
    snapshot: HotReloadSnapshot, destinationRoot: Identity, owners: [HotReloadOwnerSchema],
    typeAliases: [String: String] = [:]
  ) {
    self.typeAliases = typeAliases
    var snapshot = snapshot
    for index in snapshot.entries.indices {
      snapshot.entries[index].typeName = HotReloadTypeNames.canonical(
        snapshot.entries[index].typeName, aliases: typeAliases)
    }
    let owners = owners.map { owner in
      HotReloadOwnerSchema(
        identity: owner.identity,
        slots: owner.slots.mapValues { HotReloadTypeNames.canonical($0, aliases: typeAliases) },
        declarationNames: owner.declarationNames)
    }
    self.destinationRoot = destinationRoot
    let sourceGroups = Dictionary(
      grouping: snapshot.entries.filter(\.participatesInSchema), by: { $0.address.owner })
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
      for (entry, slot) in Self.matchingSlots(entries, schema: schema) {
        guard entry.value != nil else { continue }
        pending[.init(owner: target, slot: slot)] = entry
        accepted.insert(entry.address)
      }
    }

    for entry in snapshot.entries where !accepted.contains(entry.address) {
      if entry.isDormant, targetGroups[entry.address.owner] == nil,
        !snapshot.ambiguousOwners.contains(entry.address.owner),
        sourceGroups[entry.address.owner]?.filter({ $0.address == entry.address }).count == 1,
        entry.value != nil
      {
        // Inactive payloads have no destination tree to rehearse. Keep only
        // exact keys; validate declarations when that payload first materializes.
        // A later non-exact owner reports the refusal instead of retaining a silent drop.
        var deferred = entry
        deferred.requiresDormantSchema = true
        pending[entry.address] = deferred
        continue
      }
      diagnostics.append(
        .init(
          address: entry.address,
          reason: entry.failure ?? "No unambiguous destination with a compatible slot schema"
        ))
    }
    sortDiagnostics()
  }

  /// Names identify authored declarations independently of source-line movement.
  /// Legacy/internal slots without labels retain exact or whole-group rank rules.
  package static func matchingSlots(
    _ entries: [HotReloadSnapshot.Entry], schema: HotReloadOwnerSchema
  ) -> [(HotReloadSnapshot.Entry, StateSlotIdentifier)] {
    var result: [(HotReloadSnapshot.Entry, StateSlotIdentifier)] = []
    let namedSources = Dictionary(
      grouping: entries.filter { $0.declarationName != nil }, by: { $0.declarationName! })
    let namedTargets = Dictionary(
      grouping: schema.declarationNames.keys, by: { schema.declarationNames[$0]! })
    for (name, sources) in namedSources {
      guard sources.count == 1, let entry = sources.first,
        let targets = namedTargets[name], targets.count == 1, let slot = targets.first,
        entry.typeName == schema.slots[slot]
      else { continue }
      result.append((entry, slot))
    }
    for path in Set(entries.filter { $0.declarationName == nil }.map { $0.address.slot.path }) {
      let old = entries.filter { $0.address.slot.path == path && $0.declarationName == nil }
        .sorted { $0.address.slot.ordinal < $1.address.slot.ordinal }
      let new = schema.slots.keys.filter { $0.path == path && schema.declarationNames[$0] == nil }
        .sorted { $0.ordinal < $1.ordinal }
      let exactSet = Set(old.map { $0.address.slot }) == Set(new)
      let canRank =
        old.count == new.count
        && old.allSatisfy { $0.address.slot.ordinal >= 0 }
        && new.allSatisfy { $0.ordinal >= 0 }
      if exactSet || canRank, old.count == new.count {
        // Reserve the whole legacy rank group before considering overlapping ordinals.
        if zip(old, new).allSatisfy({ $0.typeName == schema.slots[$1] }) {
          result.append(contentsOf: zip(old, new))
        }
      } else {
        for entry in old
        where new.contains(entry.address.slot)
          && entry.typeName == schema.slots[entry.address.slot]
        {
          result.append((entry, entry.address.slot))
        }
      }
    }
    return result
  }

  /// A conservative single-wrapper edit: never erase entity or indexed sibling identity.
  package static func differsByOneWrapper(_ lhs: Identity, _ rhs: Identity) -> Bool {
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
    guard pending[key]?.requiresDormantSchema == false else { return nil }
    return pending.removeValue(forKey: key)
  }

  package static func decode<Value>(
    _ entry: HotReloadSnapshot.Entry, typeAliases: [String: String] = [:]
  ) throws -> Value {
    guard
      entry.typeName
        == HotReloadTypeNames.canonical(String(reflecting: Value.self), aliases: typeAliases),
      let type = Value.self as? any Decodable.Type, let value = entry.value,
      let decoded = try SnapshotCoding.decode(type, from: value, limits: .hotReload) as? Value
    else { throw SnapshotCodingError.incompatibleContainer }
    return decoded
  }

  package mutating func finish(keepingDormant: Bool = false) -> [HotReloadDiagnostic] {
    for entry in pending.values where !keepingDormant || !entry.isDormant {
      diagnostics.append(
        .init(address: entry.address, reason: "Destination slot was never initialized"))
    }
    pending = keepingDormant ? pending.filter { $0.value.isDormant } : [:]
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

  package func rebasedIdentity(_ identity: Identity, from sourceRoot: Identity) -> Identity? {
    guard let relative = Self.relative(identity, to: sourceRoot) else { return nil }
    let source = ownerMatches.keys.filter { relative.components.starts(with: $0.components) }
      .max { $0.components.count < $1.components.count }
    let rebased: [String]
    if let source, let target = ownerMatches[source] {
      rebased = target.components + relative.components.dropFirst(source.components.count)
    } else {
      rebased = relative.components
    }
    return Identity(components: destinationRoot.components + rebased)
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
      let decoded: Value = try HotReloadReplay.decode(
        entry, typeAliases: hotReloadReplay?.typeAliases ?? [:])
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
    func capture(
      _ slot: AnyStateSlot, identifier: StateSlotIdentifier, identity: Identity,
      dormant: Bool, depth: Int, declarationName: [String]?
    ) {
      guard let owner = HotReloadReplay.relative(identity, to: root) else { return }
      let address = HotReloadSlotAddress(owner: owner, slot: identifier)
      do {
        let value = try slot.hotReloadValue()
        entries.append(
          .init(
            address: address, typeName: slot.storedTypeDescription, value: value,
            isDormant: dormant,
            participatesInSchema: slot.dormantPolicy.survivesDormancy,
            declarationName: declarationName))
      } catch {
        entries.append(
          .init(
            address: address, typeName: slot.storedTypeDescription,
            failure: String(describing: error),
            isDormant: dormant, participatesInSchema: slot.dormantPolicy.survivesDormancy,
            declarationName: declarationName))
      }
      let archives = slot.hotReloadNestedArchives()
      guard depth < 64 else {
        if !archives.isEmpty {
          entries.append(
            .init(
              address: address, typeName: slot.storedTypeDescription,
              failure: "Nested dormant archive depth exceeds 64", participatesInSchema: false))
        }
        return
      }
      for archive in archives {
        for record in archive.records {
          if let archivedOwner = HotReloadReplay.relative(record.identity, to: root),
            !record.stateSlots.isEmpty
          {
            ownerCounts[archivedOwner, default: 0] += 1
          }
          for (key, value) in record.stateSlots {
            capture(
              AnyStateSlot(restoringDormant: value), identifier: key, identity: record.identity,
              dormant: true, depth: depth + 1, declarationName: record.declarationNames[key])
          }
        }
      }
    }
    for node in nodesByNodeID.values.sorted(by: { $0.viewNodeID < $1.viewNodeID }) {
      guard let owner = HotReloadReplay.relative(node.identity, to: root) else { continue }
      if node.stateSlots.values.contains(where: \.isInitialized) {
        ownerCounts[owner, default: 0] += 1
      }
      for (identifier, slot) in node.stateSlots where slot.isInitialized {
        capture(
          slot, identifier: identifier, identity: node.identity, dormant: false, depth: 0,
          declarationName: node.hotReloadDeclarationNames[identifier])
      }
    }
    if hotReloadReplay?.destinationRoot == root {
      entries.append(contentsOf: hotReloadReplay?.pending.values.filter(\.isDormant) ?? [])
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
    _ snapshot: HotReloadSnapshot, at destinationRoot: Identity, owners: [HotReloadOwnerSchema],
    typeAliases: [String: String] = [:]
  ) throws {
    guard hotReloadReplay == nil,
      !snapshot.sourceRoot.components.starts(with: destinationRoot.components),
      !destinationRoot.components.starts(with: snapshot.sourceRoot.components),
      !nodesByNodeID.values.contains(where: {
        $0.identity.components.starts(with: destinationRoot.components)
      })
    else { throw HotReloadInstallationError.destinationIsNotFresh }
    hotReloadReplay = HotReloadReplay(
      snapshot: snapshot, destinationRoot: destinationRoot, owners: owners, typeAliases: typeAliases
    )
  }

  package func finishHotReloadReplay(keepingDormant: Bool = false) -> [HotReloadDiagnostic] {
    guard var replay = hotReloadReplay else { return [] }
    let diagnostics = replay.finish(keepingDormant: keepingDormant)
    hotReloadReplay = replay.pending.isEmpty ? nil : replay
    return diagnostics
  }
}

package enum HotReloadInstallationError: Error {
  case destinationIsNotFresh
}
