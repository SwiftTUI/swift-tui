import SwiftTUIViews

@MainActor
package enum SceneTraversalControl {
  case `continue`
  case stop
}

@MainActor
package protocol WindowSceneVisitor {
  mutating func visit<Content: View>(
    _ scene: WindowGroup<Content>,
    isDefault: Bool
  ) -> SceneTraversalControl
}

@MainActor
package protocol AnySceneBox {
  func traverseWindowScenes<Visitor: WindowSceneVisitor>(
    visitor: inout Visitor,
    state: inout SceneTraversalState
  ) -> SceneTraversalControl
}

@MainActor
package protocol SceneTraversalNode: Scene {
  func traverseWindowScenes<Visitor: WindowSceneVisitor>(
    visitor: inout Visitor,
    state: inout SceneTraversalState
  ) -> SceneTraversalControl
}

@MainActor
package enum WindowSceneConfigurationVisitResult<Result> {
  case `continue`
  case finish(Result)
}

@MainActor
package protocol WindowSceneConfigurationVisitor {
  associatedtype Result

  mutating func visit<Content: View>(
    descriptor: SceneDescriptor,
    configuration: WindowSceneConfiguration<Content>
  ) -> WindowSceneConfigurationVisitResult<Result>
}

@MainActor
package struct SceneTraversalState {
  package var nextWindowSceneIsDefault = true

  package init() {}
}

@MainActor
package struct SceneBox<Base: Scene>: AnySceneBox {
  let base: Base

  package func traverseWindowScenes<Visitor: WindowSceneVisitor>(
    visitor: inout Visitor,
    state: inout SceneTraversalState
  ) -> SceneTraversalControl {
    SwiftTUIRuntime.traverseWindowScenes(
      base,
      visitor: &visitor,
      state: &state
    )
  }
}

@MainActor
package func traverseWindowScenes<S: Scene, Visitor: WindowSceneVisitor>(
  _ scene: S,
  visitor: inout Visitor
) -> SceneTraversalControl {
  var state = SceneTraversalState()
  return SwiftTUIRuntime.traverseWindowScenes(
    scene,
    visitor: &visitor,
    state: &state
  )
}

@MainActor
package func collectSceneDescriptors<S: Scene>(
  from scene: S
) -> [SceneDescriptor] {
  var visitor = SceneDescriptorCollector()
  _ = SwiftTUIRuntime.traverseWindowScenes(
    scene,
    visitor: &visitor
  )
  return visitor.descriptors
}

@MainActor
package func withFirstWindowSceneConfiguration<S: Scene, Visitor: WindowSceneConfigurationVisitor>(
  in scene: S,
  visitor: inout Visitor
) -> Visitor.Result? {
  withSelectedWindowSceneConfiguration(
    in: scene,
    matching: nil,
    visitor: &visitor
  )
}

@MainActor
package func withWindowSceneConfiguration<S: Scene, Visitor: WindowSceneConfigurationVisitor>(
  in scene: S,
  matching identifier: WindowIdentifier,
  visitor: inout Visitor
) -> Visitor.Result? {
  withSelectedWindowSceneConfiguration(
    in: scene,
    matching: identifier,
    visitor: &visitor
  )
}

@MainActor
private func withSelectedWindowSceneConfiguration<
  S: Scene, Visitor: WindowSceneConfigurationVisitor
>(
  in scene: S,
  matching identifier: WindowIdentifier?,
  visitor: inout Visitor
) -> Visitor.Result? {
  var selectingVisitor = SelectingWindowSceneConfigurationVisitor(
    matching: identifier,
    base: visitor
  )
  _ = SwiftTUIRuntime.traverseWindowScenes(
    scene,
    visitor: &selectingVisitor
  )
  visitor = selectingVisitor.base
  return selectingVisitor.result
}

@MainActor
package func traverseWindowScenes<S: Scene, Visitor: WindowSceneVisitor>(
  _ scene: S,
  visitor: inout Visitor,
  state: inout SceneTraversalState
) -> SceneTraversalControl {
  let erased: Any = scene
  if let traversable = erased as? any SceneTraversalNode {
    return traversable.traverseWindowScenes(
      visitor: &visitor,
      state: &state
    )
  }

  return SwiftTUIRuntime.traverseWindowScenes(
    scene.body,
    visitor: &visitor,
    state: &state
  )
}

extension EmptyScene: SceneTraversalNode {
  package func traverseWindowScenes<Visitor: WindowSceneVisitor>(
    visitor _: inout Visitor,
    state _: inout SceneTraversalState
  ) -> SceneTraversalControl {
    .continue
  }
}

extension TupleScene: SceneTraversalNode {
  package func traverseWindowScenes<Visitor: WindowSceneVisitor>(
    visitor: inout Visitor,
    state: inout SceneTraversalState
  ) -> SceneTraversalControl {
    for child in repeat each value {
      if SwiftTUIRuntime.traverseWindowScenes(
        child,
        visitor: &visitor,
        state: &state
      ) == .stop {
        return .stop
      }
    }

    return .continue
  }
}

extension ConditionalScene: SceneTraversalNode {
  package func traverseWindowScenes<Visitor: WindowSceneVisitor>(
    visitor: inout Visitor,
    state: inout SceneTraversalState
  ) -> SceneTraversalControl {
    switch storage {
    case .trueScene(let trueScene):
      return SwiftTUIRuntime.traverseWindowScenes(
        trueScene,
        visitor: &visitor,
        state: &state
      )
    case .falseScene(let falseScene):
      if collapsesImplicitEmptyFalseBranch, falseScene is EmptyScene {
        return .continue
      }
      return SwiftTUIRuntime.traverseWindowScenes(
        falseScene,
        visitor: &visitor,
        state: &state
      )
    }
  }
}

extension VariadicScene: SceneTraversalNode {
  package func traverseWindowScenes<Visitor: WindowSceneVisitor>(
    visitor: inout Visitor,
    state: inout SceneTraversalState
  ) -> SceneTraversalControl {
    for child in content {
      if SwiftTUIRuntime.traverseWindowScenes(
        child,
        visitor: &visitor,
        state: &state
      ) == .stop {
        return .stop
      }
    }

    return .continue
  }
}

extension WindowGroup: SceneTraversalNode {
  package func traverseWindowScenes<Visitor: WindowSceneVisitor>(
    visitor: inout Visitor,
    state: inout SceneTraversalState
  ) -> SceneTraversalControl {
    let isDefault = state.nextWindowSceneIsDefault
    state.nextWindowSceneIsDefault = false
    return visitor.visit(
      self,
      isDefault: isDefault
    )
  }
}

extension AnyScene: SceneTraversalNode {}

@MainActor
private struct SceneDescriptorCollector: WindowSceneVisitor {
  var descriptors: [SceneDescriptor] = []

  mutating func visit<Content: View>(
    _ scene: WindowGroup<Content>,
    isDefault: Bool
  ) -> SceneTraversalControl {
    descriptors.append(
      scene.sceneDescriptor(isDefault: isDefault)
    )
    return .continue
  }
}

@MainActor
private struct SelectingWindowSceneConfigurationVisitor<Base: WindowSceneConfigurationVisitor>:
  WindowSceneVisitor
{
  let matching: WindowIdentifier?
  var base: Base
  var result: Base.Result?

  mutating func visit<Content: View>(
    _ scene: WindowGroup<Content>,
    isDefault: Bool
  ) -> SceneTraversalControl {
    if let matching, scene.id != matching {
      return .continue
    }

    switch base.visit(
      descriptor: scene.sceneDescriptor(isDefault: isDefault),
      configuration: scene.windowSceneConfiguration()
    ) {
    case .continue:
      return .stop
    case .finish(let result):
      self.result = result
      return .stop
    }
  }
}
