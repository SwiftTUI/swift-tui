public import SwiftTUICore

// Semantic environment actions and their environment keys.
//
// These public action values are the runtime-injected verbs a view can pull
// out of the environment: open a link, reset focus, write/read the clipboard.
// Each ships as an inert `.placeholder` until a run loop installs the live
// implementation (see `RunLoop+EnvironmentActions.swift` in SwiftTUIRuntime).
//
// Split out of `Environment.swift` so that file stays focused on the
// environment storage and `ResolveContext`. Each action's private
// `EnvironmentKey` and its `EnvironmentValues` accessor travel with it.

public struct OpenLinkAction: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  package let isPlaceholder: Bool
  package let authoringContext: ImperativeAuthoringContextSnapshot?
  private let handler: @MainActor @Sendable (LinkDestination) -> Bool

  @MainActor
  public init(
    _ handler: @escaping @MainActor @Sendable (LinkDestination) -> Bool
  ) {
    let authoringContext = currentImperativeAuthoringContextSnapshot()
    snapshotLabel = "OpenLinkAction.custom"
    isPlaceholder = false
    self.authoringContext = authoringContext
    self.handler = { destination in
      withImperativeAuthoringContext(authoringContext) {
        handler(destination)
      }
    }
  }

  @discardableResult
  @MainActor
  public func callAsFunction(
    _ destination: LinkDestination
  ) -> Bool {
    handler(destination)
  }

  public var description: String {
    snapshotLabel
  }

  public var debugDescription: String {
    snapshotLabel
  }

  package init(
    snapshotLabel: String,
    isPlaceholder: Bool,
    authoringContext: ImperativeAuthoringContextSnapshot? = nil,
    handler: @escaping @MainActor @Sendable (LinkDestination) -> Bool
  ) {
    self.snapshotLabel = snapshotLabel
    self.isPlaceholder = isPlaceholder
    self.authoringContext = authoringContext
    self.handler = handler
  }

  package static let placeholder = Self(
    snapshotLabel: "OpenLinkAction.default",
    isPlaceholder: true,
    handler: { _ in false }
  )
}

private enum OpenLinkActionKey: EnvironmentKey {
  static let defaultValue = OpenLinkAction.placeholder
}

/// A semantic action that asks the runtime to reevaluate default focus in a
/// namespace-scoped focus region.
public struct ResetFocusAction: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  package let isPlaceholder: Bool
  private let handler: @MainActor @Sendable (Namespace.ID) -> Bool

  @MainActor
  public init(
    _ handler: @escaping @MainActor @Sendable (Namespace.ID) -> Bool
  ) {
    snapshotLabel = "ResetFocusAction.custom"
    isPlaceholder = false
    self.handler = handler
  }

  @discardableResult
  @MainActor
  public func callAsFunction(
    in namespace: Namespace.ID
  ) -> Bool {
    handler(namespace)
  }

  @discardableResult
  @MainActor
  public func callAsFunction(
    _ namespace: Namespace.ID
  ) -> Bool {
    handler(namespace)
  }

  public var description: String {
    snapshotLabel
  }

  public var debugDescription: String {
    snapshotLabel
  }

  package init(
    snapshotLabel: String,
    isPlaceholder: Bool,
    handler: @escaping @MainActor @Sendable (Namespace.ID) -> Bool
  ) {
    self.snapshotLabel = snapshotLabel
    self.isPlaceholder = isPlaceholder
    self.handler = handler
  }

  package static let placeholder = Self(
    snapshotLabel: "ResetFocusAction.default",
    isPlaceholder: true,
    handler: { _ in false }
  )
}

private enum ResetFocusActionKey: EnvironmentKey {
  static let defaultValue = ResetFocusAction.placeholder
}

/// A semantic action that asks the active host to place text on the clipboard.
public struct ClipboardWriteAction: Sendable, CustomStringConvertible, CustomDebugStringConvertible
{
  package let snapshotLabel: String
  package let isPlaceholder: Bool
  private let handler: @MainActor @Sendable (String) -> Bool

  @MainActor
  public init(
    _ handler: @escaping @MainActor @Sendable (String) -> Bool
  ) {
    snapshotLabel = "ClipboardWriteAction.custom"
    isPlaceholder = false
    self.handler = handler
  }

  @discardableResult
  @MainActor
  public func callAsFunction(
    _ text: String
  ) -> Bool {
    handler(text)
  }

  public var description: String {
    snapshotLabel
  }

  public var debugDescription: String {
    snapshotLabel
  }

  package init(
    snapshotLabel: String,
    isPlaceholder: Bool,
    handler: @escaping @MainActor @Sendable (String) -> Bool
  ) {
    self.snapshotLabel = snapshotLabel
    self.isPlaceholder = isPlaceholder
    self.handler = handler
  }

  package static let placeholder = Self(
    snapshotLabel: "ClipboardWriteAction.default",
    isPlaceholder: true,
    handler: { _ in false }
  )
}

private enum ClipboardWriteActionKey: EnvironmentKey {
  static let defaultValue = ClipboardWriteAction.placeholder
}

package struct ClipboardReadAction: Sendable, CustomStringConvertible, CustomDebugStringConvertible
{
  package let snapshotLabel: String
  package let isPlaceholder: Bool
  private let handler: @MainActor @Sendable () -> String?

  @MainActor
  package func callAsFunction() -> String? {
    handler()
  }

  package var description: String {
    snapshotLabel
  }

  package var debugDescription: String {
    snapshotLabel
  }

  package init(
    snapshotLabel: String,
    isPlaceholder: Bool,
    handler: @escaping @MainActor @Sendable () -> String?
  ) {
    self.snapshotLabel = snapshotLabel
    self.isPlaceholder = isPlaceholder
    self.handler = handler
  }

  package static let placeholder = Self(
    snapshotLabel: "ClipboardReadAction.default",
    isPlaceholder: true,
    handler: { nil }
  )
}

private enum ClipboardReadActionKey: EnvironmentKey {
  static let defaultValue = ClipboardReadAction.placeholder
}

// Framework-supplied action carriers are rebuilt around stable runtime verbs
// every frame. Their package labels are an explicit semantic proof; public
// custom actions deliberately compare unequal so a changed closure capture can
// never hide behind the shared `*.custom` debug label.
extension OpenLinkAction: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self,
      snapshotLabel != "OpenLinkAction.custom",
      other.snapshotLabel != "OpenLinkAction.custom"
    else {
      return false
    }
    return snapshotLabel == other.snapshotLabel
      && isPlaceholder == other.isPlaceholder
  }
}

extension ResetFocusAction: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self,
      snapshotLabel != "ResetFocusAction.custom",
      other.snapshotLabel != "ResetFocusAction.custom"
    else {
      return false
    }
    return snapshotLabel == other.snapshotLabel
      && isPlaceholder == other.isPlaceholder
  }
}

extension ClipboardWriteAction: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self,
      snapshotLabel != "ClipboardWriteAction.custom",
      other.snapshotLabel != "ClipboardWriteAction.custom"
    else {
      return false
    }
    return snapshotLabel == other.snapshotLabel
      && isPlaceholder == other.isPlaceholder
  }
}

extension ClipboardReadAction: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self,
      snapshotLabel != "ClipboardReadAction.custom",
      other.snapshotLabel != "ClipboardReadAction.custom"
    else {
      return false
    }
    return snapshotLabel == other.snapshotLabel
      && isPlaceholder == other.isPlaceholder
  }
}

extension EnvironmentValues {
  public var openLinkAction: OpenLinkAction {
    get { self[OpenLinkActionKey.self] }
    set { self[OpenLinkActionKey.self] = newValue }
  }

  public var resetFocus: ResetFocusAction {
    get { self[ResetFocusActionKey.self] }
    set { self[ResetFocusActionKey.self] = newValue }
  }

  public var clipboardWriteAction: ClipboardWriteAction {
    get { self[ClipboardWriteActionKey.self] }
    set { self[ClipboardWriteActionKey.self] = newValue }
  }

  package var clipboardReadAction: ClipboardReadAction {
    get { self[ClipboardReadActionKey.self] }
    set { self[ClipboardReadActionKey.self] = newValue }
  }
}
