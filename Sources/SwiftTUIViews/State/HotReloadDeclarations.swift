import SwiftTUICore

/// Reads declaration metadata without executing custom DynamicProperty updates.
@MainActor
package protocol HotReloadSlotDeclaring {
  func hotReloadDeclaration(path: StateSlotPath) -> (StateSlotIdentifier, String)?
}

@MainActor
package func validateDormantHotReloadDeclarations<Value>(in value: Value) {
  guard let context = currentAuthoringContext(),
    let owner = context.stateOwnerHandle,
    let node = liveAuthoringOwnerNode(stateOwnerHandle: owner),
    let graph = node.ownerGraph,
    graph.tracksHotReloadDeclarations || graph.needsDormantHotReloadSchema(for: node.identity)
  else { return }
  var slots: [StateSlotIdentifier: String] = [:]
  var names: [StateSlotIdentifier: [String]] = [:]
  var ambiguous = false
  func visit(_ value: Any, path: StateSlotPath, labels: [String], depth: Int) {
    guard depth < 64 else {
      ambiguous = true
      return
    }
    if let declaration = value as? any HotReloadSlotDeclaring {
      if let (slot, type) = declaration.hotReloadDeclaration(path: path) {
        if slots.updateValue(type, forKey: slot) != nil { ambiguous = true }
        names[slot] = labels
      }
      return
    }
    let traversalOwner = value as? any AdditionalDynamicPropertyUpdating
    for (index, child) in Mirror(reflecting: value).children.enumerated()
    where child.value is any DynamicProperty
      && traversalOwner?.ownsDynamicPropertyTraversal(ofStoredFieldAt: index) != true
    {
      if let declaration = child.value as? any HotReloadSlotDeclaring {
        if let (slot, type) = declaration.hotReloadDeclaration(path: path) {
          if slots.updateValue(type, forKey: slot) != nil { ambiguous = true }
          if let label = child.label { names[slot] = labels + [label] }
        }
      } else {
        visit(
          child.value, path: path.appending(index), labels: labels + [child.label ?? "#\(index)"],
          depth: depth + 1)
      }
    }
  }
  visit(value, path: .root, labels: [], depth: 0)
  // Transparent containers forward their actual authored payload separately.
  guard !slots.isEmpty || ambiguous else { return }
  node.hotReloadDeclarationNames.merge(names) { _, incoming in incoming }
  graph.validateDormantHotReloadSchema(
    for: node.identity, slots: slots, ambiguous: ambiguous, declarationNames: names)
}
