import Core
public import View

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

@MainActor
protocol SceneConfigurationProviding {
  func windowSceneConfigurations() -> [WindowSceneConfiguration]
}

@_spi(Runners) public struct WindowSceneConfiguration {
  @_spi(Runners) public var identifier: WindowIdentifier
  @_spi(Runners) public var title: String?
  @_spi(Runners) public var rootIdentity: Identity
  // AnyView policy: retain an erased root-view builder here for deferred
  // authored-content capture between scene declarations and the runtime.
  @_spi(Runners) public var makeRootView: @MainActor () -> AnyView

  @_spi(Runners) public init(
    identifier: WindowIdentifier,
    title: String?,
    rootIdentity: Identity,
    makeRootView: @escaping @MainActor () -> AnyView
  ) {
    self.identifier = identifier
    self.title = title
    self.rootIdentity = rootIdentity
    self.makeRootView = makeRootView
  }
}

package struct WindowHostLayout: Layout {
  package func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    let fallbackSize = subviews.reduce(into: LayoutSize.zero) { partial, subview in
      let measured = subview.sizeThatFits(proposal)
      partial.width = max(partial.width, measured.width)
      partial.height = max(partial.height, measured.height)
    }

    return LayoutSize(
      width: resolvedDimension(proposal.width, fallback: fallbackSize.width),
      height: resolvedDimension(proposal.height, fallback: fallbackSize.height)
    )
  }

  package func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    let fillProposal = ProposedViewSize(
      width: bounds.size.width,
      height: bounds.size.height
    )

    for subview in subviews {
      subview.place(
        at: bounds.origin,
        anchor: .topLeading,
        proposal: fillProposal
      )
    }
  }

  private func resolvedDimension(
    _ dimension: ProposedDimension,
    fallback: Int
  ) -> Int {
    switch dimension {
    case .finite(let value):
      return max(0, value)
    case .unspecified, .infinity:
      return max(0, fallback)
    }
  }
}

package struct WindowHostView: View {
  package let content: AnyView

  package init(content: AnyView) {
    self.content = content
  }

  package var body: some View {
    WindowHostLayout {
      content
    }
    .clipped()
  }
}

package struct AnyScene {
  private let configurationsClosure: @MainActor () -> [WindowSceneConfiguration]

  @MainActor
  package init<S: Scene>(_ scene: S) {
    configurationsClosure = {
      collectWindowSceneConfigurations(from: scene)
    }
  }

  @MainActor
  package func sceneConfigurations() -> [WindowSceneConfiguration] {
    configurationsClosure()
  }
}

/// A primitive container that groups multiple scene declarations.
public struct SceneGroup: Scene {
  /// `SceneGroup` is a primitive scene container.
  public typealias Body = Never

  package var scenes: [AnyScene]

  package init(scenes: [AnyScene]) {
    self.scenes = scenes
  }

  public var body: Never {
    fatalError("SceneGroup is a primitive scene container.")
  }
}

extension SceneGroup: SceneConfigurationProviding {
  package func windowSceneConfigurations() -> [WindowSceneConfiguration] {
    scenes.flatMap { $0.sceneConfigurations() }
  }
}

@resultBuilder
/// Builds typed scene trees from ``Scene`` expressions.
@MainActor
public enum SceneBuilder {
  public static func buildExpression<S: Scene>(_ expression: S) -> SceneGroup {
    SceneGroup(scenes: [AnyScene(expression)])
  }

  public static func buildExpression(_ expression: ()) -> SceneGroup {
    SceneGroup(scenes: [])
  }

  public static func buildBlock(_ components: SceneGroup...) -> SceneGroup {
    SceneGroup(scenes: components.flatMap(\.scenes))
  }

  public static func buildOptional(_ component: SceneGroup?) -> SceneGroup {
    component ?? SceneGroup(scenes: [])
  }

  public static func buildEither(first component: SceneGroup) -> SceneGroup {
    component
  }

  public static func buildEither(second component: SceneGroup) -> SceneGroup {
    component
  }

  public static func buildArray(_ components: [SceneGroup]) -> SceneGroup {
    SceneGroup(scenes: components.flatMap(\.scenes))
  }

  public static func buildLimitedAvailability(_ component: SceneGroup) -> SceneGroup {
    component
  }
}

/// Declares a top-level terminal window scene.
public struct WindowGroup: Scene {
  /// `WindowGroup` is a primitive scene.
  public typealias Body = Never

  public let title: String?
  public let id: WindowIdentifier

  // AnyView policy: retain this stored erased builder for deferred
  // authored-content capture, and restore the original dynamic-property scope
  // when the scene root is built later.
  private let contentBuilder: @MainActor () -> AnyView

  /// Creates a window scene with an explicit identifier.
  public init<Content: View>(
    id: WindowIdentifier = "window",
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = nil
    self.id = id
    let authoringScope = currentAuthoringContext()
    contentBuilder = {
      scopedAnyView(authoringContext: authoringScope) {
        content()
      }
    }
  }

  /// Creates a window scene with a display title and optional explicit
  /// identifier.
  public init<S: StringProtocol, Content: View>(
    _ title: S,
    id: WindowIdentifier? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    let normalizedTitle = String(title)
    self.title = normalizedTitle
    self.id = id ?? WindowIdentifier(normalizedTitle)
    let authoringScope = currentAuthoringContext()
    contentBuilder = {
      scopedAnyView(authoringContext: authoringScope) {
        content()
      }
    }
  }

  public var body: Never {
    fatalError("WindowGroup is a primitive scene.")
  }
}

extension WindowGroup: SceneConfigurationProviding {
  package func windowSceneConfigurations() -> [WindowSceneConfiguration] {
    [
      WindowSceneConfiguration(
        identifier: id,
        title: title,
        rootIdentity: Identity(components: ["App", id.rawValue]),
        makeRootView: contentBuilder
      )
    ]
  }
}

/// A terminal application declaration composed of scenes.
@preconcurrency @MainActor
public protocol App {
  associatedtype Body: Scene

  @MainActor @preconcurrency
  init()

  @SceneBuilder @MainActor @preconcurrency
  var body: Body { get }
}

@_spi(Runners) @MainActor public func collectWindowSceneConfigurations<S: Scene>(
  from scene: S
) -> [WindowSceneConfiguration] {
  if let provider = scene as? any SceneConfigurationProviding {
    return provider.windowSceneConfigurations()
  }

  return collectWindowSceneConfigurations(from: scene.body)
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
