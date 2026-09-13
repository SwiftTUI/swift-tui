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
      return HotReloadOwnerSchema(identity: identity, slots: declarations)
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
    return replay.pending.contains { $0.key.owner == owner && $0.value.requiresDormantSchema }
  }

  package func validateDormantHotReloadSchema(
    for identity: Identity, slots: [StateSlotIdentifier: String], ambiguous: Bool
  ) {
    guard var replay = hotReloadReplay,
      let owner = HotReloadReplay.relative(identity, to: replay.destinationRoot)
    else { return }
    let deferred = replay.pending.filter { $0.key.owner == owner && $0.value.requiresDormantSchema }
    guard !deferred.isEmpty else { return }
    let compatible =
      !ambiguous && deferred.count == slots.count
      && deferred.allSatisfy {
        slots[$0.key.slot].map { HotReloadTypeNames.canonical($0, aliases: replay.typeAliases) } == $0.value.typeName
      }
    for (address, entry) in deferred {
      if compatible {
        replay.pending[address]?.requiresDormantSchema = false
      } else {
        replay.pending.removeValue(forKey: address)
        replay.diagnostics.append(
          .init(
            address: entry.address,
            reason: "Inactive owner declaration set changed; exact replay refused"))
      }
    }
    hotReloadReplay = replay
  }
}
