import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct ActorIsolationSurfaceTests {
  @Test("View and Resolver stay main-actor isolated")
  func resolverResolvesViewOnMainActor() {
    struct SurfaceView: View {
      var body: some View {
        Text("Actor isolated")
      }
    }

    let identity = testIdentity("ActorIsolation", "Resolver")
    let resolved = Resolver().resolve(
      SurfaceView(),
      in: .init(identity: identity)
    )

    #expect(resolved.identity == identity)
  }

  @Test("Binding inherits the authored actor context and Button actions stay main-actor authored")
  func bindingAndButtonAuthoringCompileOnMainActor() {
    @MainActor
    final class Box {
      var count = 0
    }

    func inheritedBinding(for box: Box) -> Binding<Int> {
      Binding(
        get: { box.count },
        set: { box.count = $0 }
      )
    }

    struct BindingSurface: View {
      let box: Box

      var body: some View {
        let count = inheritedBinding(for: box)

        VStack(alignment: .leading, spacing: 1) {
          Text("Count \(count.wrappedValue)")
          Button("Increment") {
            count.wrappedValue += 1
          }
        }
      }
    }

    let box = Box()
    let resolved = Resolver().resolve(
      BindingSurface(box: box),
      in: .init(identity: testIdentity("ActorIsolation", "Binding"))
    )

    #expect(resolved.identity == testIdentity("ActorIsolation", "Binding"))
    #expect(box.count == 0)
  }

  @Test("Task and onChange modifiers, plus DefaultRenderer, render on the main actor")
  func taskAndOnChangeModifiersAndRendererRenderOnMainActor() {
    struct TaskSurface: View {
      var body: some View {
        Text("Work")
          .onChange(of: 1, initial: true) {}
          .onChange(of: 1, initial: true) { oldValue, newValue in
            _ = oldValue
            _ = newValue
          }
          .task {}
          .task(id: 1) {}
      }
    }

    let identity = testIdentity("ActorIsolation", "Task")
    let artifacts = DefaultRenderer().render(
      TaskSurface(),
      context: .init(identity: identity)
    )

    #expect(artifacts.resolvedTree.identity == identity)
    #expect(!artifacts.commitPlan.lifecycle.isEmpty)
  }

  @Test("App and Scene authoring compile on the main actor")
  func appAndSceneAuthoringCompileOnMainActor() throws {
    struct SurfaceApp: App {
      var body: some Scene {
        WindowGroup("Actor Surface") {
          Text("Main actor app")
        }
      }
    }

    var visitor = ActorIsolationSceneVisitor()
    let selection = try #require(
      withFirstWindowSceneConfiguration(
        in: SurfaceApp().body,
        visitor: &visitor
      )
    )

    #expect(selection.identifier == WindowIdentifier("Actor-Surface"))
    #expect(selection.artifacts.resolvedTree.identity == selection.rootIdentity)
  }

  @Test("RunLoop typed builders still accept AnyView via Content == AnyView")
  func runLoopTypedBuilderStillAcceptsAnyView() {
    final class SurfaceTerminalHost: PresentationSurface {
      let surfaceSize: CellSize = .init(width: 40, height: 12)
      let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
      let appearance: TerminalAppearance = .fallback

      func enableRawMode() throws {}
      func disableRawMode() throws {}
      func write(_: String) throws {}
      func clearScreen() throws {}
      func moveCursor(to _: CellPoint) throws {}
    }

    final class SurfaceInputReader: InputReading {
      func events() -> AsyncStream<KeyPress> {
        AsyncStream { continuation in
          continuation.finish()
        }
      }
    }

    func makeRunLoop<Content: View>(
      viewBuilder: @escaping (_ state: Int, _ focusedIdentity: Identity?) -> Content
    ) -> RunLoop<Int, Content> {
      let identity = testIdentity("ActorIsolation", "RunLoop")
      return RunLoop(
        rootIdentity: identity,
        presentationSurface: SurfaceTerminalHost(),
        inputReader: SurfaceInputReader(),
        stateContainer: StateContainer(initialState: 0),
        focusTracker: FocusTracker(invalidationIdentities: [identity]),
        viewBuilder: viewBuilder
      )
    }

    let runLoop = makeRunLoop { state, _ in
      AnyView(Text("State \(state)"))
    }

    #expect(runLoop.rootIdentity == testIdentity("ActorIsolation", "RunLoop"))
  }
}

@MainActor
private struct ActorIsolationSceneSelection {
  let identifier: WindowIdentifier
  let rootIdentity: Identity
  let artifacts: RenderSnapshot
}

@MainActor
private struct ActorIsolationSceneVisitor: WindowSceneConfigurationVisitor {
  mutating func visit<Content: View>(
    descriptor _: SceneDescriptor,
    configuration: WindowSceneConfiguration<Content>
  ) -> WindowSceneConfigurationVisitResult<ActorIsolationSceneSelection> {
    .finish(
      ActorIsolationSceneSelection(
        identifier: configuration.identifier,
        rootIdentity: configuration.rootIdentity,
        artifacts: DefaultRenderer().render(
          configuration.makeScopedRootView(),
          context: .init(identity: configuration.rootIdentity)
        )
      )
    )
  }
}
