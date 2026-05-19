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

  public static func buildBlock<Content: Scene>(
    _ scene: Content
  ) -> Content {
    scene
  }

  public static func buildBlock<each Content: Scene>(
    _ scenes: repeat each Content
  ) -> TupleScene<repeat each Content> {
    TupleScene((repeat each scenes))
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
