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
        $0.runtimeFocusIdentity == focusedIdentity
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
  ///
  /// It keeps a later duplicate's `ID[x#n]` occurrence, which the reported
  /// ``AccessibilityNode/identity`` strips: a duplicate control's action
  /// identity is its own identity, a duplicate row's selector is its row
  /// route, and any other node in a later duplicate publishes its
  /// occurrence-qualified identity (STUI-1296). A unique node's runtime
  /// identity is its action identity or reported identity, as before.
  @_spi(Runners) public var runtimeFocusIdentity: Identity {
    actionIdentity ?? occurrenceIdentity ?? identity
  }
}
