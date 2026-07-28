@_spi(Testing) import SwiftTUIPrimitives

/// Canonical bookkeeping carried by a committed resolved artifact for the
/// interactive registrations authored while that artifact was resolved.
///
/// This is not author-facing handler storage. `NodeHandlers` remains the
/// single source of truth for closures and registry restoration; the inventory
/// retains only sorted, de-duplicated identity currency for soundness checks.
package struct CommittedHandlerInventory: Equatable, Sendable {
  package let actionIdentities: [Identity]
  package let keyHandlerIdentities: [Identity]
  package let commandScopes: [Identity]
  package let dropScopes: [Identity]
  package let gestureRouteIdentities: [Identity]

  package init(
    actionIdentities: [Identity] = [],
    keyHandlerIdentities: [Identity] = [],
    commandScopes: [Identity] = [],
    dropScopes: [Identity] = [],
    gestureRouteIdentities: [Identity] = []
  ) {
    self.actionIdentities = Self.canonicalized(actionIdentities)
    self.keyHandlerIdentities = Self.canonicalized(keyHandlerIdentities)
    self.commandScopes = Self.canonicalized(commandScopes)
    self.dropScopes = Self.canonicalized(dropScopes)
    self.gestureRouteIdentities = Self.canonicalized(gestureRouteIdentities)
  }

  private static func canonicalized(_ identities: [Identity]) -> [Identity] {
    Set(identities).sorted { lhs, rhs in
      lhs.components.lexicographicallyPrecedes(rhs.components)
    }
  }
}

extension NodeHandlers {
  /// Identity-only projection of the five interactive registration families.
  ///
  /// Key identities unite bare key, key-press, and paste handlers. Command
  /// scopes omit empty tables, which publish no dispatchable command. Gesture
  /// route identities are recognizer keys only: general pointer and hover
  /// routes are broader interaction infrastructure and do not imply a gesture.
  package var committedHandlerInventory: CommittedHandlerInventory {
    CommittedHandlerInventory(
      actionIdentities: Array(action.registrations.keys),
      keyHandlerIdentities:
        Array(keyHandler.handlers.keys)
        + Array(keyHandler.keyPress.handlers.keys)
        + Array(keyHandler.paste.handlers.keys),
      commandScopes: command.keyCommandsByScope.compactMap { scope, table in
        table.isEmpty ? nil : scope
      },
      dropScopes: Array(dropDestination.handlersByScope.keys),
      gestureRouteIdentities: Array(gesture.recognizers.keys)
    )
  }
}
