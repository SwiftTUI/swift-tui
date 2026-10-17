/// A synchronous rehearsal's complete state declarations, including unread @State.
@MainActor
package final class HotReloadSchemaCapture {
  package init() {}
  package static var current: HotReloadSchemaCapture?
  private var slots: [NodeOwnerLifetimeID: [StateSlotIdentifier: String]] = [:]

  package func record<Value>(_ node: ViewNode, slot: StateSlotIdentifier, type: Value.Type) {
    slots[node.ownerLifetimeID, default: [:]][slot] = String(reflecting: type)
  }

  package func collect<Result>(_ body: () throws -> Result) rethrows -> Result {
    let prior = Self.current
    Self.current = self
    defer { Self.current = prior }
    return try body()
  }

  package func schemas(in graph: ViewGraph, rootedAt root: Identity) -> [HotReloadOwnerSchema] {
    graph.nodesByNodeID.values.compactMap { node in
      guard let identity = HotReloadReplay.relative(node.identity, to: root)
      else { return nil }
      var declarations = slots[node.ownerLifetimeID] ?? [:]
      for (identifier, slot) in node.stateSlots where slot.dormantPolicy.survivesDormancy {
        declarations[identifier] = slot.storedTypeDescription
      }
      guard !declarations.isEmpty else { return nil }
      return HotReloadOwnerSchema(
        identity: identity, slots: declarations,
        declarationNames: node.hotReloadDeclarationNames)
    }.sorted { $0.identity < $1.identity }
  }
}

extension ViewGraph {
  package func hasHotReloadValue(for identity: Identity, slot: StateSlotIdentifier) -> Bool {
    guard let replay = hotReloadReplay,
      let owner = HotReloadReplay.relative(identity, to: replay.destinationRoot)
    else { return false }
    return replay.pending[.init(owner: owner, slot: slot)]?.requiresDormantSchema == false
  }

  package func needsDormantHotReloadSchema(for identity: Identity) -> Bool {
    guard let replay = hotReloadReplay,
      let owner = HotReloadReplay.relative(identity, to: replay.destinationRoot)
    else { return false }
    return replay.pending.contains {
      $0.value.requiresDormantSchema
        && ($0.key.owner == owner || HotReloadReplay.differsByOneWrapper($0.key.owner, owner))
    }
  }

  package func validateDormantHotReloadSchema(
    for identity: Identity, slots: [StateSlotIdentifier: String], ambiguous: Bool,
    declarationNames: [StateSlotIdentifier: [String]] = [:]
  ) {
    guard var replay = hotReloadReplay,
      let owner = HotReloadReplay.relative(identity, to: replay.destinationRoot)
    else { return }
    let deferred = replay.pending.filter { $0.key.owner == owner && $0.value.requiresDormantSchema }
    guard !deferred.isEmpty else {
      // Dormant topology has not been rehearsed. Do not guess a destination
      // from whichever lazy owner happens to materialize first.
      let unmatched = replay.pending.filter {
        $0.value.requiresDormantSchema && HotReloadReplay.differsByOneWrapper($0.key.owner, owner)
      }
      for (address, entry) in unmatched {
        replay.pending.removeValue(forKey: address)
        replay.diagnostics.append(
          .init(
            address: entry.address,
            reason:
              "Inactive owner moved through a wrapper; destination uniqueness cannot be established"
          ))
      }
      hotReloadReplay = replay
      return
    }
    let schema = HotReloadOwnerSchema(
      identity: owner,
      slots: slots.mapValues { HotReloadTypeNames.canonical($0, aliases: replay.typeAliases) },
      declarationNames: declarationNames)
    let hasNames = deferred.values.contains { $0.declarationName != nil }
    let exactLegacySet =
      deferred.count == slots.count
      && deferred.allSatisfy {
        schema.slots[$0.key.slot] == $0.value.typeName
      }
    let matches =
      !ambiguous && (hasNames || exactLegacySet)
      ? HotReloadReplay.matchingSlots(Array(deferred.values), schema: schema) : []
    for address in deferred.keys { replay.pending.removeValue(forKey: address) }
    let accepted = Set(matches.map { $0.0.address })
    for (entry, slot) in matches {
      var validated = entry
      validated.requiresDormantSchema = false
      replay.pending[.init(owner: owner, slot: slot)] = validated
    }
    for entry in deferred.values where !accepted.contains(entry.address) {
      replay.diagnostics.append(
        .init(
          address: entry.address,
          reason: "Inactive owner declaration has no unambiguous compatible destination"))
    }
    hotReloadReplay = replay
  }
}
