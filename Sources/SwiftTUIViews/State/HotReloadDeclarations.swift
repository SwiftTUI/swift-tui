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
    graph.needsDormantHotReloadSchema(for: node.identity)
  else { return }
  var slots: [StateSlotIdentifier: String] = [:]
  var ambiguous = false
  func visit(_ value: Any, path: StateSlotPath, depth: Int) {
    guard depth < 64 else {
      ambiguous = true
      return
    }
    if let declaration = value as? any HotReloadSlotDeclaring {
      if let (slot, type) = declaration.hotReloadDeclaration(path: path) {
        if slots.updateValue(type, forKey: slot) != nil { ambiguous = true }
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
        }
      } else {
        visit(child.value, path: path.appending(index), depth: depth + 1)
      }
    }
  }
  visit(value, path: .root, depth: 0)
  // Transparent containers forward their actual authored payload separately.
  guard !slots.isEmpty || ambiguous else { return }
  graph.validateDormantHotReloadSchema(
    for: node.identity, slots: slots, ambiguous: ambiguous)
}
