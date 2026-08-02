public import SwiftTUICore

// Semantic environment actions and their environment keys.
//
// These public action values are the runtime-injected verbs a view can pull
// out of the environment: open a link, reset focus, write/read the clipboard,
// or temporarily hand terminal ownership to an external operation.
// Each ships as an inert `.placeholder` until a run loop installs the live
// implementation (see `RunLoop+EnvironmentActions.swift` in SwiftTUIRuntime).
//
// Split out of `Environment.swift` so that file stays focused on the
// environment storage and `ResolveContext`. Each action's private
// `EnvironmentKey` and its `EnvironmentValues` accessor travel with it.

/// A semantic action that asks the active interactive session to terminate.
///
/// The request follows the same ``View/onTerminationRequest(perform:)``
/// policy as an exit key or signal. It returns `false` when no live run loop
/// owns the environment value.
public struct RequestTerminationAction: Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  package let snapshotLabel: String
  package let isPlaceholder: Bool
  private let handler: @MainActor @Sendable () -> Bool

  @MainActor
  public init(_ handler: @escaping @MainActor @Sendable () -> Bool) {
    snapshotLabel = "RequestTerminationAction.custom"
    isPlaceholder = false
    self.handler = handler
  }

  @discardableResult
  @MainActor
  public func callAsFunction() -> Bool { handler() }

  public var description: String { snapshotLabel }
  public var debugDescription: String { snapshotLabel }

  package init(
    snapshotLabel: String,
    isPlaceholder: Bool,
    handler: @escaping @MainActor @Sendable () -> Bool
  ) {
    self.snapshotLabel = snapshotLabel
    self.isPlaceholder = isPlaceholder
    self.handler = handler
  }

  package static let placeholder = Self(
    snapshotLabel: "RequestTerminationAction.default",
    isPlaceholder: true,
    handler: { false }
  )
}

private enum RequestTerminationActionKey: EnvironmentKey {
  static let defaultValue = RequestTerminationAction.placeholder
}

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

/// An error reported before or while handing the active terminal to an external operation.
public enum TerminalHandoffError: Error, Equatable, Sendable, CustomStringConvertible {
  /// No live terminal run loop is installed in the calling task.
  case unavailable
  /// The active terminal session is already running another handoff operation.
  case alreadyInProgress
  /// SwiftTUI did not reclaim terminal ownership after the operation completed.
  case failedToRestoreTerminal

  public var description: String {
    switch self {
    case .unavailable:
      "terminal handoff is unavailable outside an active terminal session"
    case .alreadyInProgress:
      "the active terminal session is already handed off"
    case .failedToRestoreTerminal:
      "SwiftTUI could not restore terminal ownership after the handoff"
    }
  }
}

/// Temporarily hands the active terminal to an asynchronous external operation.
///
/// The live terminal runtime suspends its input reader.
/// It restores cooked mode and the primary screen, and then waits for `operation`.
/// Then it starts its presentation mode again and schedules a full redraw.
/// Restoration also runs when `operation`
/// throws or cooperatively observes cancellation.
///
/// Read this value through ``EnvironmentValues/terminalHandoff`` when a view
/// performs the operation directly. Model-owned dependencies that cannot read
/// the environment during initialization can call
/// ``perform(_:)`` instead. The static entry point is task-local to the active
/// run loop, so concurrent terminal scenes cannot hand off each other's host.
public struct TerminalHandoffAction: Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  package let snapshotLabel: String
  package let isPlaceholder: Bool
  private let handler:
    @MainActor @Sendable (@escaping @MainActor @Sendable () async throws -> Void) async throws
      -> Void

  @TaskLocal package static var current: TerminalHandoffAction?

  /// Creates a custom terminal handoff action.
  ///
  /// A custom action owns the complete handoff contract. Prefer the
  /// runtime-injected environment value for terminal applications.
  @MainActor
  public init(
    _ handler:
      @escaping @MainActor @Sendable (
        @escaping @MainActor @Sendable () async throws -> Void
      ) async throws -> Void
  ) {
    snapshotLabel = "TerminalHandoffAction.custom"
    isPlaceholder = false
    self.handler = handler
  }

  /// Performs `operation` using this action's terminal session.
  @MainActor
  public func callAsFunction(
    _ operation: @escaping @MainActor @Sendable () async throws -> Void
  ) async throws {
    try await handler(operation)
  }

  /// Performs `operation` using the terminal session scoped to the current task.
  ///
  /// Child tasks inherit the active session. Detached tasks do not inherit it. They throw
  /// ``TerminalHandoffError/unavailable`` rather than consulting process-global
  /// state that can belong to another scene.
  @MainActor
  public static func perform(
    _ operation: @escaping @MainActor @Sendable () async throws -> Void
  ) async throws {
    guard let current else {
      throw TerminalHandoffError.unavailable
    }
    try await current(operation)
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
    handler:
      @escaping @MainActor @Sendable (
        @escaping @MainActor @Sendable () async throws -> Void
      ) async throws -> Void
  ) {
    self.snapshotLabel = snapshotLabel
    self.isPlaceholder = isPlaceholder
    self.handler = handler
  }

  package static let placeholder = Self(
    snapshotLabel: "TerminalHandoffAction.default",
    isPlaceholder: true,
    handler: { _ in throw TerminalHandoffError.unavailable }
  )
}

private enum TerminalHandoffActionKey: EnvironmentKey {
  static let defaultValue = TerminalHandoffAction.placeholder
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

extension RequestTerminationAction: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self,
      snapshotLabel != "RequestTerminationAction.custom",
      other.snapshotLabel != "RequestTerminationAction.custom"
    else { return false }
    return snapshotLabel == other.snapshotLabel && isPlaceholder == other.isPlaceholder
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

extension TerminalHandoffAction: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self,
      snapshotLabel != "TerminalHandoffAction.custom",
      other.snapshotLabel != "TerminalHandoffAction.custom"
    else {
      return false
    }
    return snapshotLabel == other.snapshotLabel
      && isPlaceholder == other.isPlaceholder
  }
}

extension EnvironmentValues {
  /// Requests that the active interactive session terminate.
  public var requestTermination: RequestTerminationAction {
    get { self[RequestTerminationActionKey.self] }
    set { self[RequestTerminationActionKey.self] = newValue }
  }

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

  /// The active runtime's asynchronous terminal-ownership handoff action.
  public var terminalHandoff: TerminalHandoffAction {
    get { self[TerminalHandoffActionKey.self] }
    set { self[TerminalHandoffActionKey.self] = newValue }
  }
}
