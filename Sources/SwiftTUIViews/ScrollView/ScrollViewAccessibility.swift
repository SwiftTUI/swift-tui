import SwiftTUICore

extension ResolvedNode {
  /// A sizing or decoration wrapper is not another scroll owner. Preserve the
  /// association between a viewport's authored name and its named operations.
  /// Authored semantic groups and multi-child layouts remain boundaries.
  package func applyingScrollAccessibilityLabel(_ label: String) -> Self? {
    var node = self
    var wrappers: [Self] = []
    while node.semanticMetadata.scrollRole == nil {
      guard node.children.count == 1,
        node.semanticMetadata.accessibilityRole == nil,
        node.semanticMetadata.accessibilityControl == nil,
        node.semanticMetadata.accessibilityStructure == nil
      else { return nil }
      switch node.layoutBehavior {
      case .frame, .flexibleFrame, .padding, .offset, .position, .border, .safeAreaIgnoring:
        wrappers.append(node)
        node = node.children[0]
      default: return nil
      }
    }
    guard node.semanticMetadata.scrollRole == .scrollView else { return nil }
    node.semanticMetadata.accessibilityLabel = label
    while var wrapper = wrappers.popLast() {
      wrapper.children = [node]
      node = wrapper
    }
    return node
  }
}

/// Named operations use the same clamped scroll owner as physical input.
/// They do not move keyboard focus, selection, or a nested sibling viewport.
package enum ScrollAccessibilityCommand: String, CaseIterable {
  case up = "Scroll up one page"
  case down = "Scroll down one page"
  case top = "Scroll to top"
  case bottom = "Scroll to bottom"
  case left = "Scroll left one page"
  case right = "Scroll right one page"
  case leading = "Scroll to left edge"
  case trailing = "Scroll to right edge"

  private var axis: Axis.Set {
    switch self {
    case .up, .down, .top, .bottom: .vertical
    case .left, .right, .leading, .trailing: .horizontal
    }
  }

  package static func names(for axes: Axis.Set) -> [String] {
    allCases.filter { axes.contains($0.axis) }.map(\.rawValue)
  }

  @MainActor
  package func perform(in registry: LocalScrollPositionRegistry, identity: Identity) -> Bool {
    switch self {
    case .top: return registry.scrollToEdge(.top, scopeIdentity: identity)
    case .bottom: return registry.scrollToEdge(.bottom, scopeIdentity: identity)
    case .leading: return registry.scrollToEdge(.leading, scopeIdentity: identity)
    case .trailing: return registry.scrollToEdge(.trailing, scopeIdentity: identity)
    default: break
    }
    guard let viewport = registry.viewportRect(scopeIdentity: identity) else { return false }
    let vertical = max(1, viewport.size.height - 1)
    let horizontal = max(1, viewport.size.width - 1)
    let delta: ScrollOffset
    switch self {
    case .up: delta = .init(y: -vertical)
    case .down: delta = .init(y: vertical)
    case .left: delta = .init(x: -horizontal)
    case .right: delta = .init(x: horizontal)
    default: return false
    }
    return registry.scrollBy(x: delta.x, y: delta.y, scopeIdentity: identity)
  }
}
