import Testing

@testable import Core
@testable import TerminalUI
@testable import View

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

  @Test("Task modifiers, including task(id:), and DefaultRenderer render on the main actor")
  func taskModifiersAndRendererRenderOnMainActor() {
    struct TaskSurface: View {
      var body: some View {
        Text("Work")
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

    let configuration = try primaryWindowSceneConfiguration(
      from: SurfaceApp().body
    )
    let artifacts = DefaultRenderer().render(
      configuration.makeRootView(),
      context: .init(identity: configuration.rootIdentity)
    )

    #expect(configuration.identifier == WindowIdentifier("Actor-Surface"))
    #expect(artifacts.resolvedTree.identity == configuration.rootIdentity)
  }
}
