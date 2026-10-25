import SwiftTUICore

package struct AccessibilityRuntimePolicy: Equatable, Sendable {
  package init() {}

  package func focusedCursorPoint(
    in snapshot: SemanticSnapshot,
    focusedIdentity: Identity?
  ) -> CellPoint? {
    guard let focusedIdentity else {
      return nil
    }
    guard
      let node = snapshot.accessibilityNodes.first(where: {
        ($0.actionIdentity ?? $0.identity) == focusedIdentity
      })
    else {
      return nil
    }

    return node.cursorAnchor ?? node.rect.origin
  }
}

extension AccessibilityNode {
  /// The identity runtime keyboard focus uses for this node: its action
  /// identity when it has one (a collection row's selection control),
  /// otherwise its own identity. Native host adapters compare this with
  /// `SemanticHostFrame.focusedIdentity`, the rule the host wire applies.
  @_spi(Runners) public var runtimeFocusIdentity: Identity {
    actionIdentity ?? identity
  }
}
