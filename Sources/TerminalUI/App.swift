import Core
import View

/// Errors thrown while turning an ``App`` or ``Scene`` declaration into a
/// runtime configuration.
public enum AppLaunchError: Error, Equatable, Sendable, CustomStringConvertible {
  case noScenes
  case multipleScenesUnsupported(count: Int)

  public var description: String {
    switch self {
    case .noScenes:
      return "App.body did not produce any scenes."
    case .multipleScenesUnsupported(let count):
      return "Expected exactly one scene, but App.body produced \(count)."
    }
  }
}

/// A scene declaration for terminal applications.
public protocol Scene {
  associatedtype Body: Scene

  var body: Body { get }
}

extension Never: Scene {
  /// Primitive scenes use `Never` as their body type.
  public typealias Body = Never

  public var body: Never {
    fatalError("Never.body is unreachable.")
  }
}

package protocol SceneConfigurationProviding {
  func parallelWindowSceneConfigurations() -> [WindowSceneConfiguration]
}

package struct WindowSceneConfiguration {
  package var identifier: String
  package var title: String?
  package var rootIdentity: Identity
  package var makeRootView: () -> AnyView
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
  private let configurationsClosure: () -> [WindowSceneConfiguration]

  package init<S: Scene>(_ scene: S) {
    configurationsClosure = {
      collectWindowSceneConfigurations(from: scene)
    }
  }

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
  package func parallelWindowSceneConfigurations() -> [WindowSceneConfiguration] {
    scenes.flatMap { $0.sceneConfigurations() }
  }
}

@resultBuilder
/// Builds typed scene trees from ``Scene`` expressions.
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
  public let id: String

  private let contentBuilder: () -> AnyView

  /// Creates a window scene with an explicit identifier.
  public init<Content: View>(
    id: String = "window",
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = nil
    self.id = normalizedWindowIdentifier(id)
    contentBuilder = { AnyView(content()) }
  }

  /// Creates a window scene with a display title and optional explicit
  /// identifier.
  public init<S: StringProtocol, Content: View>(
    _ title: S,
    id: String? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    let normalizedTitle = String(title)
    self.title = normalizedTitle
    self.id = normalizedWindowIdentifier(id ?? normalizedTitle)
    contentBuilder = { AnyView(content()) }
  }

  public var body: Never {
    fatalError("WindowGroup is a primitive scene.")
  }
}

extension WindowGroup: SceneConfigurationProviding {
  package func parallelWindowSceneConfigurations() -> [WindowSceneConfiguration] {
    [
      WindowSceneConfiguration(
        identifier: id,
        title: title,
        rootIdentity: Identity(components: ["App", id]),
        makeRootView: contentBuilder
      )
    ]
  }
}

/// A terminal application declaration composed of scenes.
public protocol App {
  associatedtype Body: Scene

  init()

  @SceneBuilder var body: Body { get }
}

package func collectWindowSceneConfigurations<S: Scene>(
  from scene: S
) -> [WindowSceneConfiguration] {
  if let provider = scene as? any SceneConfigurationProviding {
    return provider.parallelWindowSceneConfigurations()
  }

  return collectWindowSceneConfigurations(from: scene.body)
}

package func primaryWindowSceneConfiguration<S: Scene>(
  from scene: S
) throws -> WindowSceneConfiguration {
  let configurations = collectWindowSceneConfigurations(from: scene)
  guard !configurations.isEmpty else {
    throw AppLaunchError.noScenes
  }
  guard configurations.count == 1 else {
    throw AppLaunchError.multipleScenesUnsupported(count: configurations.count)
  }
  return configurations[0]
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
