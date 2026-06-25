import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Multiple task modifiers per view node")
struct MultipleTaskModifiersTests {
  private func render(_ view: some View) -> (
    artifacts: FrameArtifacts,
    lifecycleRegistry: LocalLifecycleRegistry,
    taskRegistry: LocalTaskRegistry
  ) {
    let lifecycleRegistry = LocalLifecycleRegistry()
    let taskRegistry = LocalTaskRegistry()
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(
        identity: testIdentity("Root"),
        localLifecycleRegistry: lifecycleRegistry,
        localTaskRegistry: taskRegistry,
        applyEnvironmentValues: true
      )
    )
    return (artifacts, lifecycleRegistry, taskRegistry)
  }

  private func startedDescriptors(_ artifacts: FrameArtifacts) -> [TaskDescriptor] {
    artifacts.commitPlan.lifecycle.compactMap { entry in
      if case .taskStart(let descriptor) = entry.operation {
        return descriptor
      }
      return nil
    }
  }

  @Test("two .task(id:) modifiers on one node each register with a distinct descriptor")
  func twoTasksOnOneNodeRegisterDistinctly() {
    let (artifacts, _, taskRegistry) = render(
      Text("Two tasks")
        .task(id: 1) {}
        .task(id: "a") {}
    )

    let started = startedDescriptors(artifacts)
    #expect(started.count == 2)
    #expect(Set(started.map(\.id)).count == 2)
    for descriptor in started {
      #expect(
        taskRegistry.registration(for: testIdentity("Root"), descriptor: descriptor) != nil)
    }
  }

  @Test("both tasks on one node start in the runner")
  func bothTasksStartInRunner() {
    let (artifacts, lifecycleRegistry, taskRegistry) = render(
      Text("Two tasks")
        .task(id: 1) {}
        .task(id: "a") {}
    )

    let coordinator = LifecycleCoordinator()
    coordinator.applyCommittedFrame(
      plan: artifacts.commitPlan,
      currentLifecycleRegistry: lifecycleRegistry,
      currentTaskRegistry: taskRegistry
    )

    #expect(coordinator.activeTaskCount == 2)
  }

  @Test("a non-id .task and a .task(id:) coexist on one node")
  func nonIDAndIDTaskCoexist() {
    let (artifacts, _, _) = render(
      Text("Mixed tasks")
        .task {}
        .task(id: 7) {}
    )

    #expect(startedDescriptors(artifacts).count == 2)
  }

  @Test("a single .task keeps its historical descriptor id")
  func singleTaskKeepsHistoricalDescriptorID() {
    let (artifacts, _, _) = render(
      Text("One task").task(priority: .userInitiated) {}
    )

    #expect(
      startedDescriptors(artifacts)
        == [TaskDescriptor(id: "Root#task", priority: .userInitiated)])
  }
}
