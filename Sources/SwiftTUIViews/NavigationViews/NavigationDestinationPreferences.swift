package import SwiftTUICore

// Navigation-destination preference plumbing.
//
// `.navigationDestination(...)` modifiers do not push views directly. They
// publish a `NavigationDestinationDeclaration` (or, on dismissal, a
// `NavigationDestinationPopEntry`) through a `PreferenceKey` so an enclosing
// `NavigationStack` can collect every declaration in its subtree and resolve
// the active destination chain. These are the value and key types carrying
// that information up the view tree.
//
// Split out of `NavigationStack.swift` so that file stays focused on the
// `NavigationStack` view, the destination modifiers, and the chain-resolution
// machinery. `navigationDestinationPopAction` stays behind: it depends on the
// file-scoped `private` `scopeDepth` helper.

@MainActor
package struct NavigationDestinationDeclaration: Sendable {
  package var sourceIdentity: Identity
  package var declarationIdentity: Identity
  package var instance: NavigationDestinationInstance?

  package init(
    sourceIdentity: Identity,
    declarationIdentity: Identity,
    instance: NavigationDestinationInstance?
  ) {
    self.sourceIdentity = sourceIdentity
    self.declarationIdentity = declarationIdentity
    self.instance = instance
  }
}

package struct NavigationDestinationDeclarationPreferenceValue: Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  package var declarations: [NavigationDestinationDeclaration] = []

  package var description: String {
    debugDescription
  }

  package var debugDescription: String {
    let sourcePaths = declarations.map(\.sourceIdentity.path)
    return "NavigationDestinationDeclarationPreferenceValue(\(sourcePaths))"
  }
}

package enum NavigationDestinationDeclarationPreferenceKey: PreferenceKey {
  package static let defaultValue = NavigationDestinationDeclarationPreferenceValue()

  package static func reduce(
    value: inout NavigationDestinationDeclarationPreferenceValue,
    nextValue: () -> NavigationDestinationDeclarationPreferenceValue
  ) {
    value.declarations.append(contentsOf: nextValue().declarations)
  }
}

@MainActor
package struct NavigationDestinationInstance: Sendable {
  package var identity: Identity
  package var payload: PortalContentPayload
  package var dismiss: @MainActor @Sendable () -> Void

  package init(
    identity: Identity,
    payload: PortalContentPayload,
    dismiss: @escaping @MainActor @Sendable () -> Void
  ) {
    self.identity = identity
    self.payload = payload
    self.dismiss = dismiss
  }
}

@MainActor
package struct NavigationDestinationPopEntry: Sendable {
  package var scopeIdentity: Identity
  package var dismiss: @MainActor @Sendable () -> Void

  package init(
    scopeIdentity: Identity,
    dismiss: @escaping @MainActor @Sendable () -> Void
  ) {
    self.scopeIdentity = scopeIdentity
    self.dismiss = dismiss
  }
}

package struct NavigationDestinationPopPreferenceValue: Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  package var entries: [NavigationDestinationPopEntry] = []

  package var description: String {
    debugDescription
  }

  package var debugDescription: String {
    let paths = entries.map(\.scopeIdentity.path)
    return "NavigationDestinationPopPreferenceValue(\(paths))"
  }
}

package enum NavigationDestinationPopPreferenceKey: PreferenceKey {
  package static let defaultValue = NavigationDestinationPopPreferenceValue()

  package static func reduce(
    value: inout NavigationDestinationPopPreferenceValue,
    nextValue: () -> NavigationDestinationPopPreferenceValue
  ) {
    value.entries.append(contentsOf: nextValue().entries)
  }
}
