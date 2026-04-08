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

/// The empty scene artifact produced by ``SceneBuilder``.
public struct EmptyScene: Scene {
  public typealias Body = Never

  public init() {}

  public var body: Never {
    fatalError("EmptyScene is a builder composition artifact.")
  }
}

/// The scene artifact produced by multiple sequential builder expressions.
public struct TupleScene<each Scenes: Scene>: Scene {
  public typealias Body = Never

  package let value: (repeat each Scenes)

  package init(
    _ value: (repeat each Scenes)
  ) {
    self.value = value
  }

  public var body: Never {
    fatalError("TupleScene is a builder composition artifact.")
  }
}

/// The scene artifact produced by conditional builder branches.
public struct ConditionalScene<TrueScene: Scene, FalseScene: Scene>: Scene {
  public typealias Body = Never

  public enum Storage {
    case trueScene(TrueScene)
    case falseScene(FalseScene)
  }

  package let storage: Storage
  package let collapsesImplicitEmptyFalseBranch: Bool

  package init(
    storage: Storage,
    collapsesImplicitEmptyFalseBranch: Bool
  ) {
    self.storage = storage
    self.collapsesImplicitEmptyFalseBranch = collapsesImplicitEmptyFalseBranch
  }

  public var body: Never {
    fatalError("ConditionalScene is a builder composition artifact.")
  }
}

/// The scene artifact produced by array-like builder expansion.
public struct VariadicScene<Content: Scene>: Scene {
  public typealias Body = Never

  package let content: [Content]

  package init(
    _ content: [Content]
  ) {
    self.content = content
  }

  public var body: Never {
    fatalError("VariadicScene is a builder composition artifact.")
  }
}

/// A type-erased terminal scene.
///
/// Use `AnyScene` when a call site must store heterogeneous scene values while
/// still participating in the normal authored `Scene` surface. Prefer typed
/// `@SceneBuilder` composition and generic scene storage when those are
/// practical.
public struct AnyScene: Scene {
  public typealias Body = Never

  private let box: any AnySceneBox

  @MainActor
  public init<S: Scene>(_ scene: S) {
    if let scene = scene as? AnyScene {
      self = scene
      return
    }

    box = SceneBox(base: scene)
  }

  public var body: Never {
    fatalError("AnyScene is a type-erased scene.")
  }

  package func traverseWindowScenes<Visitor: WindowSceneVisitor>(
    visitor: inout Visitor,
    state: inout SceneTraversalState
  ) -> SceneTraversalControl {
    box.traverseWindowScenes(
      visitor: &visitor,
      state: &state
    )
  }
}

@_spi(Runners) public struct WindowSceneConfiguration<Content: View> {
  @_spi(Runners) public var identifier: WindowIdentifier
  @_spi(Runners) public var title: String?
  @_spi(Runners) public var rootIdentity: Identity

  private let makeScopedRootViewClosure: @MainActor () -> ScopedBuilder<Content>

  package init(
    identifier: WindowIdentifier,
    title: String?,
    rootIdentity: Identity,
    makeRootView: @escaping @MainActor () -> ScopedBuilder<Content>
  ) {
    self.identifier = identifier
    self.title = title
    self.rootIdentity = rootIdentity
    makeScopedRootViewClosure = makeRootView
  }

  @_spi(Runners) @MainActor public func makeRootView() -> Content {
    makeScopedRootViewClosure().build()
  }

  @MainActor
  package func makeScopedRootView() -> ScopedBuilder<Content> {
    makeScopedRootViewClosure()
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

package struct WindowHostView<Content: View>: View {
  package let content: Content

  package init(content: Content) {
    self.content = content
  }

  package var body: some View {
    WindowHostLayout {
      content
    }
    .clipped()
  }
}

@resultBuilder
/// Builds typed scene trees from ``Scene`` expressions.
@MainActor
public enum SceneBuilder {
  public static func buildBlock() -> EmptyScene {
    EmptyScene()
  }

  public static func buildExpression<S: Scene>(_ expression: S) -> S {
    expression
  }

  public static func buildExpression(_ expression: ()) -> EmptyScene {
    EmptyScene()
  }

  public static func buildPartialBlock<Content: Scene>(
    first content: Content
  ) -> Content {
    content
  }

  public static func buildPartialBlock<Accumulated: Scene, Next: Scene>(
    accumulated: Accumulated,
    next: Next
  ) -> TupleScene<Accumulated, Next> {
    TupleScene((accumulated, next))
  }

  public static func buildOptional<Content: Scene>(
    _ component: Content?
  ) -> ConditionalScene<Content, EmptyScene> {
    if let component {
      return ConditionalScene(
        storage: .trueScene(component),
        collapsesImplicitEmptyFalseBranch: true
      )
    }

    return ConditionalScene(
      storage: .falseScene(EmptyScene()),
      collapsesImplicitEmptyFalseBranch: true
    )
  }

  public static func buildEither<TrueScene: Scene, FalseScene: Scene>(
    first component: TrueScene
  ) -> ConditionalScene<TrueScene, FalseScene> {
    ConditionalScene(
      storage: .trueScene(component),
      collapsesImplicitEmptyFalseBranch: false
    )
  }

  public static func buildEither<TrueScene: Scene, FalseScene: Scene>(
    second component: FalseScene
  ) -> ConditionalScene<TrueScene, FalseScene> {
    ConditionalScene(
      storage: .falseScene(component),
      collapsesImplicitEmptyFalseBranch: false
    )
  }

  public static func buildArray<Content: Scene>(
    _ components: [Content]
  ) -> VariadicScene<Content> {
    VariadicScene(components)
  }

  public static func buildLimitedAvailability<Content: Scene>(
    _ component: Content
  ) -> AnyScene {
    AnyScene(component)
  }
}

/// Declares a top-level terminal window scene.
public struct WindowGroup<Content: View>: Scene {
  /// `WindowGroup` is a primitive scene.
  public typealias Body = Never

  public let title: String?
  public let id: WindowIdentifier

  private let contentBuilder: ScopedBuilder<Content>

  /// Creates a window scene with an explicit identifier.
  public init(
    id: WindowIdentifier = "window",
    @ViewBuilder content: @escaping @MainActor () -> Content
  ) {
    self.title = nil
    self.id = id
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
    contentBuilder = ScopedBuilder {
      content()
    }
  }

  public var body: Never {
    fatalError("WindowGroup is a primitive scene.")
  }

  package func windowSceneConfiguration() -> WindowSceneConfiguration<Content> {
    WindowSceneConfiguration(
      identifier: id,
      title: title,
      rootIdentity: rootIdentity,
      makeRootView: { contentBuilder }
    )
  }

  package func sceneDescriptor(
    isDefault: Bool
  ) -> TerminalUISceneDescriptor {
    TerminalUISceneDescriptor(
      id: id,
      title: title,
      isDefault: isDefault
    )
  }

  private var rootIdentity: Identity {
    Identity(components: ["App", id.rawValue])
  }
}

/// A terminal application declaration composed of scenes.
@MainActor
public protocol App {
  associatedtype Body: Scene

  @MainActor
  init()

  @SceneBuilder @MainActor
  var body: Body { get }
}

@_spi(Runners) @MainActor public func collectWindowSceneDescriptors<S: Scene>(
  from scene: S
) -> [TerminalUISceneDescriptor] {
  collectSceneDescriptors(from: scene)
}

@_spi(Runners) @MainActor public struct SelectedWindowScene {
  @_spi(Runners) public let descriptor: TerminalUISceneDescriptor
  @_spi(Runners) public let rootIdentity: Identity

  private let runSceneClosure:
    @MainActor (
      String,
      SceneSessionResources,
      StateContainer<TerminalUISceneSessionState>,
      FocusTracker
    ) async throws -> RunLoopResult<TerminalUISceneSessionState>

  package init<Content: View>(
    descriptor: TerminalUISceneDescriptor,
    configuration: WindowSceneConfiguration<Content>
  ) {
    self.descriptor = descriptor
    rootIdentity = configuration.rootIdentity
    runSceneClosure = { sessionName, resources, stateContainer, focusTracker in
      try await SceneSession.run(
        configuration: configuration,
        sessionName: sessionName,
        stateContainer: stateContainer,
        focusTracker: focusTracker,
        resources: resources
      )
    }
  }

  @_spi(Runners) public var identifier: WindowIdentifier {
    descriptor.id
  }

  @_spi(Runners) public var title: String? {
    descriptor.title
  }

  @_spi(Runners) public var isDefault: Bool {
    descriptor.isDefault
  }

  @_spi(Runners) @MainActor public func run(
    sessionName: String,
    resources: SceneSessionResources,
    stateContainer: StateContainer<TerminalUISceneSessionState>,
    focusTracker: FocusTracker
  ) async throws -> RunLoopResult<TerminalUISceneSessionState> {
    try await runSceneClosure(
      sessionName,
      resources,
      stateContainer,
      focusTracker
    )
  }
}

@_spi(Runners) @MainActor public func collectWindowSceneSelections<S: Scene>(
  from scene: S
) -> [SelectedWindowScene] {
  var visitor = SelectedWindowSceneCollector()
  _ = traverseWindowScenes(
    scene,
    visitor: &visitor
  )
  return visitor.selections
}

@MainActor
private struct SelectedWindowSceneCollector: WindowSceneVisitor {
  var selections: [SelectedWindowScene] = []

  mutating func visit<Content: View>(
    _ scene: WindowGroup<Content>,
    isDefault: Bool
  ) -> SceneTraversalControl {
    selections.append(
      SelectedWindowScene(
        descriptor: scene.sceneDescriptor(isDefault: isDefault),
        configuration: scene.windowSceneConfiguration()
      )
    )
    return .continue
  }
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
