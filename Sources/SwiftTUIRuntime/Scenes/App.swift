public import SwiftTUICore
public import SwiftTUIViews

/// Errors thrown while turning an ``App`` or ``Scene`` declaration into a
/// runtime configuration.
public enum AppLaunchError: Error, Equatable, Sendable, CustomStringConvertible {
  case noScenes

  public var description: String {
    switch self {
    case .noScenes:
      return "App.body did not produce any scenes."
    }
  }
}

/// A scene declaration for terminal applications.
@MainActor
public protocol Scene {
  associatedtype Body: Scene

  @MainActor
  var body: Body { get }
}

/// A typed identifier for a terminal window scene.
public struct WindowIdentifier: Hashable, Sendable, Codable, RawRepresentable,
  ExpressibleByStringLiteral, CustomStringConvertible
{
  public typealias RawValue = String
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = normalizedWindowIdentifier(rawValue)
  }

  public init<S: StringProtocol>(_ rawValue: S) {
    self.init(rawValue: String(rawValue))
  }

  public init(stringLiteral value: StringLiteralType) {
    self.init(value)
  }

  public var description: String {
    rawValue
  }
}

extension Never: Scene {
  /// Primitive scenes use `Never` as their body type.
  public typealias Body = Never

  public var body: Never {
    fatalError("Never.body is unreachable.")
  }
}

/// Declares a top-level terminal window scene.
public struct WindowGroup<Content: View>: Scene {
  /// `WindowGroup` is a primitive scene.
  public typealias Body = Never

  public let title: String?
  public let id: WindowIdentifier

  private let contentBuilder: ScopedBuilder<Content>
  private let exitKeyBindings: ExitKeyBindings

  /// Creates a window scene with an explicit identifier.
  public init(
    id: WindowIdentifier = "window",
    @ViewBuilder content: @escaping @MainActor () -> Content
  ) {
    self.title = nil
    self.id = id
    self.exitKeyBindings = .default
    contentBuilder = ScopedBuilder {
      content()
    }
  }

  /// Creates a window scene with a display title and optional explicit
  /// identifier.
  public init<S: StringProtocol>(
    _ title: S,
    id: WindowIdentifier? = nil,
    @ViewBuilder content: @escaping @MainActor () -> Content
  ) {
    let normalizedTitle = String(title)
    self.title = normalizedTitle
    self.id = id ?? WindowIdentifier(normalizedTitle)
    self.exitKeyBindings = .default
    contentBuilder = ScopedBuilder {
      content()
    }
  }

  private init(
    title: String?,
    id: WindowIdentifier,
    contentBuilder: ScopedBuilder<Content>,
    exitKeyBindings: ExitKeyBindings
  ) {
    self.title = title
    self.id = id
    self.contentBuilder = contentBuilder
    self.exitKeyBindings = exitKeyBindings
  }

  /// Returns a copy of this `WindowGroup` whose exit bindings are set
  /// to `bindings`. The call replaces any previously configured set in
  /// full — there is no accumulation — so chained calls behave as
  /// last-write-wins.
  ///
  /// Pass ``ExitKeyBindings/none`` (or `[]`) to disable framework-level
  /// exits entirely; the window will then only exit in response to OS
  /// signals, `stdin` EOF, or an explicit exit returned by a consumer
  /// `keyHandler` or `keyCommand`.
  public func exitOnKeys(_ keys: [KeyPress]) -> WindowGroup<Content> {
    WindowGroup(
      title: title,
      id: id,
      contentBuilder: contentBuilder,
      exitKeyBindings: ExitKeyBindings(keys)
    )
  }

  /// Convenience for a single-binding exit configuration. Equivalent
  /// to `exitOnKeys([KeyPress(key, modifiers: modifiers)])` and shares
  /// its replacement semantics.
  public func exitOnKey(
    _ key: KeyEvent,
    modifiers: EventModifiers = []
  ) -> WindowGroup<Content> {
    exitOnKeys([KeyPress(key, modifiers: modifiers)])
  }

  public var body: Never {
    fatalError("WindowGroup is a primitive scene.")
  }

  package func windowSceneConfiguration() -> WindowSceneConfiguration<Content> {
    WindowSceneConfiguration(
      identifier: id,
      title: title,
      rootIdentity: rootIdentity,
      exitKeyBindings: exitKeyBindings,
      makeRootView: { contentBuilder }
    )
  }

  package func sceneDescriptor(
    isDefault: Bool
  ) -> SceneDescriptor {
    SceneDescriptor(
      id: id,
      title: title,
      isDefault: isDefault
    )
  }

  private var rootIdentity: Identity {
    Identity(components: ["App", id.rawValue])
  }
}

/// A `WindowGroup` is an `ActionScope` — the scene identity is the root
/// of every focus chain rooted in that window. The scope becomes active
/// whenever the scene's rootIdentity appears on the current focus
/// region's `scopePath`.
extension WindowGroup: ActionScope {
  public typealias ID = WindowIdentifier
}

/// A terminal application declaration composed of scenes.
@MainActor
public protocol App {
  associatedtype Body: Scene

  nonisolated init()

  @SceneBuilder @MainActor
  var body: Body { get }
}

private func normalizedWindowIdentifier(_ value: String) -> String {
  let trimmed = value.trimmedUnicodeWhitespace()
  guard !trimmed.isEmpty else {
    return "window"
  }

  return String(
    trimmed.map { character in
      switch character {
      case "/", " ":
        "-"
      default:
        character
      }
    }
  )
}
