import SwiftTUICore

/// A refreshed transition body may supply a new kernel for the same site.
struct RemovalCellPreparations: Sendable {
  private struct Site: Hashable {
    let identity: Identity
    let modifier: CellPreparationSite
  }
  private var bindings: [Site: any CellPreparationBinding] = [:]

  init(_ frozen: PlacedNode) {
    var pending = [frozen]
    while let node = pending.popLast() {
      for case .cellLayer(let pass) in node.drawEffects.ordered {
        guard case .prepared(let preparation) = pass.shader.program else { continue }
        bindings[Site(identity: node.identity, modifier: preparation.site)] = preparation
      }
      pending.append(contentsOf: node.children)
    }
  }

  mutating func bind(_ root: inout PlacedNode) -> Bool {
    var pending = [(node: root, assemble: false)]
    var results: [(node: PlacedNode, changed: Bool)] = []
    while let frame = pending.popLast() {
      var node = frame.node
      if !frame.assemble, !node.children.isEmpty {
        pending.append((node, true))
        for child in node.children.reversed() { pending.append((child, false)) }
        continue
      }
      let children = results.suffix(node.children.count)
      let childChanged = children.contains { $0.changed }
      if childChanged { node.children = children.map { $0.node } }
      results.removeLast(children.count)
      let changed = bindLocal(&node)
      results.append((node, changed || childChanged))
    }
    guard let result = results.first, result.changed else { return false }
    root = result.node
    return true
  }

  private mutating func bindLocal(_ node: inout PlacedNode) -> Bool {
    var changed = false
    for index in node.drawEffects.ordered.indices {
      guard case .cellLayer(let pass) = node.drawEffects.ordered[index],
        case .prepared(let preparation) = pass.shader.program
      else { continue }
      let site = Site(identity: node.identity, modifier: preparation.site)
      if let previous = bindings[site], let continued = preparation.continuing(previous) {
        node.drawEffects.ordered[index] = .cellLayer(.init(continued, offset: pass.offset))
      } else {
        bindings[site] = preparation
      }
      changed = true
    }
    return changed
  }
}
