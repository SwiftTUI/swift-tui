import SwiftTUIPrimitives

extension SemanticExtractor {
  /// Curates authored containers after primitive naming and action attribution.
  func applyingAccessibilityStructure(
    to original: [AccessibilityNode], structures: [Identity: AccessibilityStructure]
  ) -> [AccessibilityNode] {
    guard !structures.isEmpty else { return original }
    var nodes = orderingAccessibilityNodes(original, structures: structures)
    var indexByIdentity: [Identity: Int] = [:]
    var childrenByIdentity: [Identity: [Int]] = [:]
    for index in nodes.indices {
      if indexByIdentity[nodes[index].identity] == nil {
        indexByIdentity[nodes[index].identity] = index
      }
      if let parent = nodes[index].parentIdentity {
        childrenByIdentity[parent, default: []].append(index)
      }
    }
    var removed: Set<Int> = []
    // Parents precede descendants. Inner grouping must settle before an outer
    // merge. Tombstones avoid shifting the whole array for every child removal.
    for source in original.reversed() {
      guard let structure = structures[source.identity], let behavior = structure.children,
        behavior != .contain, let index = indexByIdentity[source.identity],
        !removed.contains(index)
      else { continue }
      var visited: Set<Int> = [index]
      var childIndices: [Int] = []
      var stack = (childrenByIdentity[source.identity] ?? []).reversed().map { $0 }
      while let child = stack.popLast() {
        guard !removed.contains(child), visited.insert(child).inserted else { continue }
        if structure.keepsVirtualChildren, structures[nodes[child].identity]?.isVirtual == true {
          continue
        }
        childIndices.append(child)
        stack.append(contentsOf: (childrenByIdentity[nodes[child].identity] ?? []).reversed())
      }
      if behavior == .combine {
        let children = childIndices.map { nodes[$0] }
        // Text-editing/selection widgets retain an independent native interaction surface.
        let retained = Set(
          children.filter {
            $0.control?.actions.contains(.setValue) == true || $0.control?.opensLink == true
          }.map(\.identity))
        var labels: [String] = []
        var values: [String] = []
        var names = nodes[index].control?.customActions ?? []
        var usedNames = Set(names)
        var nextSuffix: [String: Int] = [:]
        var routes = nodes[index].combinedActions
        for child in children where !retained.contains(child.identity) {
          if let label = child.label, !label.isEmpty { labels.append(label) }
          if let value = child.properties?.valueDescription, !value.isEmpty { values.append(value) }
          guard let control = child.control, let identity = child.actionIdentity,
            let owner = child.viewNodeID
          else { continue }
          guard child.isEnabled, child.properties?.readOnly != true else { continue }
          let label = child.label ?? "Control"
          var operations: [(String, AccessibilityAction)] = []
          if control.actions.contains(.activate) { operations.append((label, .activate)) }
          if control.actions.contains(.increment) {
            operations.append(("Increase " + label, .increment))
          }
          if control.actions.contains(.decrement) {
            operations.append(("Decrease " + label, .decrement))
          }
          operations += control.customActions.map { ($0, .custom($0)) }
          for (title, action) in operations {
            var name = title
            var duplicate = nextSuffix[title] ?? 2
            while !usedNames.insert(name).inserted {
              name = "\(title) (\(duplicate))"
              duplicate += 1
            }
            nextSuffix[title] = duplicate
            names.append(name)
            if case .custom(let nested) = action, let route = child.combinedActions[nested] {
              routes[name] = route
            } else {
              routes[name] = AccessibilityCombinedAction(
                identity: identity, owner: owner, action: action,
                enabled: child.isEnabled, readOnly: child.properties?.readOnly == true)
            }
          }
        }
        if nodes[index].label == nil { nodes[index].label = labels.joined(separator: ", ") }
        if nodes[index].properties?.valueDescription == nil, !values.isEmpty {
          let value = AccessibilityProperties(valueDescription: values.joined(separator: ", "))
          nodes[index].properties = nodes[index].properties?.merging(value) ?? value
        }
        if !routes.isEmpty {
          let previous = nodes[index].control
          var actions = previous?.actions ?? []
          if !actions.contains(.custom) { actions.append(.custom) }
          nodes[index].control = .init(
            actions: actions, value: previous?.value, minimum: previous?.minimum,
            maximum: previous?.maximum, step: previous?.step, selection: previous?.selection,
            customActions: names, opensLink: previous?.opensLink ?? false)
          nodes[index].combinedActions = routes
          // A membership/lifetime change invalidates pending combined requests, including
          // duplicate labels whose display names would otherwise be reassigned.
          let signature = names.compactMap { name -> String? in
            guard let route = routes[name] else { return nil }
            return "\(route.owner.rawValue):\(route.identity.path):\(name)"
          }.joined(separator: "|")
          nodes[index].actionTarget = "combined:\(source.identity.path):\(signature)"
        }
        for child in childIndices where retained.contains(nodes[child].identity) {
          nodes[child].parentIdentity = source.identity
          childrenByIdentity[source.identity, default: []].append(child)
        }
        childIndices.removeAll { retained.contains(nodes[$0].identity) }
      }
      for child in childIndices {
        removed.insert(child)
        childrenByIdentity[nodes[child].identity] = nil
      }
      // Retained editors/links now belong directly to this container; virtual
      // subtrees excluded above remain intact. Preserve the existing read order.
      childrenByIdentity[source.identity] = Set(childrenByIdentity[source.identity] ?? [])
        .filter { !removed.contains($0) }.sorted()
    }
    return orderingAccessibilityNodes(
      nodes.indices.filter { !removed.contains($0) }.map { nodes[$0] }, structures: structures)
  }

  private func orderingAccessibilityNodes(
    _ nodes: [AccessibilityNode], structures: [Identity: AccessibilityStructure]
  ) -> [AccessibilityNode] {
    // Sort sibling subtrees as units. Equal priorities retain authored order.
    var children: [Identity?: [Int]] = [:]
    let identities = Set(nodes.map(\.identity))
    for index in nodes.indices {
      let parent = nodes[index].parentIdentity.flatMap { identities.contains($0) ? $0 : nil }
      children[parent, default: []].append(index)
    }
    for key in Array(children.keys) {
      children[key]?.sort {
        let lhs = structures[nodes[$0].identity]?.sortPriority ?? 0
        let rhs = structures[nodes[$1].identity]?.sortPriority ?? 0
        return lhs == rhs ? $0 < $1 : lhs > rhs
      }
    }
    var ordered: [AccessibilityNode] = []
    var stack = (children[nil] ?? []).reversed().map { $0 }
    var visited: Set<Int> = []
    while let index = stack.popLast() {
      guard visited.insert(index).inserted else { continue }
      ordered.append(nodes[index])
      stack.append(contentsOf: (children[nodes[index].identity] ?? []).reversed())
    }
    return ordered
  }
}
