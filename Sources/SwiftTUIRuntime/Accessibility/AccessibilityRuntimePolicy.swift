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
  @_spi(Host) @_spi(Runners) public var runtimeFocusIdentity: Identity {
    actionIdentity ?? occurrenceIdentity ?? identity
  }
}

extension Identity {
  /// Whether this identity distinguishes a later occurrence of a repeated entity.
  /// Hosts must not infer occurrence semantics by parsing the displayed path.
  @_spi(Host) public var hasPresentationOccurrence: Bool {
    typedComponents.contains(where: \.hasEntityOccurrence)
  }
}

extension AccessibilityNode {
  /// Stable presentation identity for this occurrence, distinct from the opaque
  /// action target and from the runtime keyboard-focus identity of a row selector.
  @_spi(Host) public var presentationIdentity: Identity {
    let focus = runtimeFocusIdentity
    return focus != identity && focus.hasPresentationOccurrence ? focus : identity
  }
}
