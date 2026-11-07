import SwiftTUIPrimitives

extension SemanticExtractor {
  /// Curates authored containers after primitive naming and action attribution.
  func applyingAccessibilityStructure(
    to original: [AccessibilityNode], structures: [Identity: AccessibilityStructure]
  ) -> [AccessibilityNode] {
    guard !structures.isEmpty else { return original }
    var nodes = original
    // Resolve parents before sorting. Reported identities deliberately omit
    // occurrences, so each parent token names its nearest preceding node in
    // extraction order. Keep those edges by index through grouping and sorting.
    var firstByIdentity: [Identity: Int] = [:]
    for index in nodes.indices {
      if firstByIdentity[nodes[index].identity] == nil {
        firstByIdentity[nodes[index].identity] = index
      }
    }
    var preceding: [Identity: Int] = [:]
    var childrenByIndex: [Int?: [Int]] = [:]
    for index in nodes.indices {
      let parent = nodes[index].parentIdentity.flatMap { preceding[$0] ?? firstByIdentity[$0] }
      childrenByIndex[parent, default: []].append(index)
      preceding[nodes[index].identity] = index
    }
    func structure(at index: Int) -> AccessibilityStructure? {
      structures[nodes[index].occurrenceIdentity ?? nodes[index].identity]
    }
    for parent in Array(childrenByIndex.keys) {
      childrenByIndex[parent]?.sort {
        let lhs = structure(at: $0)?.sortPriority ?? 0
        let rhs = structure(at: $1)?.sortPriority ?? 0
        return lhs == rhs ? $0 < $1 : lhs > rhs
      }
    }
    let order = orderingAccessibilityNodeIndices(childrenByIndex)
    let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
    var removed: Set<Int> = []
    // Parents precede descendants. Inner grouping must settle before an outer
    // merge. Tombstones avoid shifting the whole array for every child removal.
    for index in order.reversed() {
      let source = nodes[index]
      guard let structure = structure(at: index), let behavior = structure.children,
        behavior != .contain,
        !removed.contains(index)
      else { continue }
      var visited: Set<Int> = [index]
      var childIndices: [Int] = []
      var stack = (childrenByIndex[index] ?? []).reversed().map { $0 }
      while let child = stack.popLast() {
        guard !removed.contains(child), visited.insert(child).inserted else { continue }
        if structure.keepsVirtualChildren,
          structures[nodes[child].occurrenceIdentity ?? nodes[child].identity]?.isVirtual == true
        {
          continue
        }
        childIndices.append(child)
        stack.append(contentsOf: (childrenByIndex[child] ?? []).reversed())
      }
      if behavior == .combine {
        // Text-editing/selection widgets retain an independent native interaction surface.
        let retained = Set(
          childIndices.filter {
            guard let control = nodes[$0].control else { return false }
            let adjustable =
              control.actions.contains(.increment) || control.actions.contains(.decrement)
            return control.opensLink || control.selection != nil
              || control.actions.contains(.editText) || control.actions.contains(.selectText)
              || (control.actions.contains(.setValue) && !adjustable)
          })
        var labels: [String] = []
        var values: [String] = []
        var names = nodes[index].control?.customActions ?? []
        var usedNames = Set(names)
        var nextSuffix: [String: Int] = [:]
        var routes = nodes[index].combinedActions
        for childIndex in childIndices where !retained.contains(childIndex) {
          let child = nodes[childIndex]
          if let label = child.label, !label.isEmpty { labels.append(label) }
          if let value = child.readableValueDescription, !value.isEmpty { values.append(value) }
          guard let control = child.control else { continue }
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
            let route: AccessibilityCombinedAction
            if case .custom(let nested) = action, let preserved = child.combinedActions[nested] {
              route = preserved
            } else if let identity = child.actionIdentity, let owner = child.viewNodeID {
              route = AccessibilityCombinedAction(
                identity: identity, owner: owner, action: action,
                enabled: child.isEnabled, readOnly: child.properties?.readOnly == true)
            } else {
              continue
            }
            guard route.enabled, !route.readOnly else { continue }
            var name = title
            var duplicate = nextSuffix[title] ?? 2
            while !usedNames.insert(name).inserted {
              name = "\(title) (\(duplicate))"
              duplicate += 1
            }
            nextSuffix[title] = duplicate
            names.append(name)
            routes[name] = route
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
          nodes[index].typedActionTarget = .combined(host: source.identity, signature: signature)
        }
        for child in childIndices where retained.contains(child) {
          nodes[child].parentIdentity = source.identity
          childrenByIndex[index, default: []].append(child)
        }
        childIndices.removeAll { retained.contains($0) }
      }
      for child in childIndices {
        removed.insert(child)
        childrenByIndex[child] = nil
      }
      // Retained editors/links now belong directly to this container; virtual
      // subtrees excluded above remain intact. Preserve the existing read order.
      childrenByIndex[index] = Set(childrenByIndex[index] ?? [])
        .filter { !removed.contains($0) }.sorted {
          position[$0, default: 0] < position[$1, default: 0]
        }
    }
    return orderingAccessibilityNodeIndices(childrenByIndex)
      .filter { !removed.contains($0) }.map { nodes[$0] }
  }

  private func orderingAccessibilityNodeIndices(_ children: [Int?: [Int]]) -> [Int] {
    var ordered: [Int] = []
    var stack = (children[nil] ?? []).reversed().map { $0 }
    var visited: Set<Int> = []
    while let index = stack.popLast() {
      guard visited.insert(index).inserted else { continue }
      ordered.append(index)
      stack.append(contentsOf: (children[index] ?? []).reversed())
    }
    return ordered
  }
}
