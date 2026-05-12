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
      let node = snapshot.accessibilityNodes.first(where: { $0.identity == focusedIdentity })
    else {
      return nil
    }

    return node.cursorAnchor ?? node.rect.origin
  }
}
