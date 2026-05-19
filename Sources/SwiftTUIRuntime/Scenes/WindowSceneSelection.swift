public import SwiftTUICore
import SwiftTUIViews

@_spi(Runners) @MainActor public func collectWindowSceneDescriptors<S: Scene>(
  from scene: S
) -> [SceneDescriptor] {
  collectSceneDescriptors(from: scene)
}

@_spi(Runners) @MainActor public struct SelectedWindowScene {
  @_spi(Runners) public let descriptor: SceneDescriptor
  @_spi(Runners) public let rootIdentity: Identity

  private let runSceneClosure:
    @MainActor (
      String,
      SceneSessionResources,
      StateContainer<SceneSessionState>,
      FocusTracker
    ) async throws -> RunLoopResult<SceneSessionState>

  package init<Content: View>(
    descriptor: SceneDescriptor,
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
    stateContainer: StateContainer<SceneSessionState>,
    focusTracker: FocusTracker
  ) async throws -> RunLoopResult<SceneSessionState> {
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
