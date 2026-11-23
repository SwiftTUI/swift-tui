import SwiftTUICore

/// A refreshed transition body may supply a new kernel for the same site.
struct RemovalCellPreparations: Sendable {
  private struct Site: Hashable {
    let identity: Identity
    let position: Int
  }
  private var bindings: [Site: any CellPreparationBinding] = [:]

  init(_ frozen: PlacedNode) {
    var pending = [frozen]
    while let node = pending.popLast() {
      var position = 0
      for case .cellLayer(let pass) in node.drawEffects.ordered {
        guard case .prepared(let preparation) = pass.shader.program else { continue }
        bindings[Site(identity: node.identity, position: position)] = preparation
        position += 1
      }
      pending.append(contentsOf: node.children)
    }
  }

  mutating func bind(_ node: inout PlacedNode) -> Bool {
    var changed = false
    var position = 0
    for index in node.drawEffects.ordered.indices {
      guard case .cellLayer(let pass) = node.drawEffects.ordered[index],
        case .prepared(let preparation) = pass.shader.program
      else { continue }
      let site = Site(identity: node.identity, position: position)
      position += 1
      if let previous = bindings[site], let continued = preparation.continuing(previous) {
        node.drawEffects.ordered[index] = .cellLayer(.init(continued, offset: pass.offset))
      } else {
        bindings[site] = preparation
      }
      changed = true
    }
    for index in node.children.indices {
      if bind(&node.children[index]) { changed = true }
    }
    return changed
  }
}
