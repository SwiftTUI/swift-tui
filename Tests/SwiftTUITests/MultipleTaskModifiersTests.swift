import Observation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Multiple task modifiers per view node")
struct MultipleTaskModifiersTests {
  @Test(
    "both public task modifiers run, replace independently, and cancel on removal",
    .timeLimit(.minutes(1)))
  func liveReplacementAndRemoval() async throws {
    let model = MultiTaskModel()
    let identity = testIdentity("LiveMultipleTasks")
    let loop = RunLoop(
      rootIdentity: identity,
      presentationSurface: RecordingPresentationSurface(surfaceSize: .init(width: 30, height: 8)),
      terminalInputReader: MultiTaskInput(), signalReader: ImmediateFinishSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [identity]),
      focusTracker: FocusTracker(invalidationIdentities: [identity]),
      environmentValues: .init(), proposal: .init(width: 30, height: 8),
      viewBuilder: { _, _ in MultiTaskRoot(model: model) })
    defer { loop.lifecycleCoordinator.shutdown() }
    var frames = 0
    func render() throws {
      loop.scheduler.requestInvalidation(of: [identity])
      try loop.renderPendingFrames(renderedFrames: &frames)
    }
    try render()
    #expect(loop.lifecycleCoordinator.activeTaskCount == 2)
    #expect(loop.lifecycleCoordinator.taskStartSkipCount == 0)
    #expect(loop.lifecycleCoordinator.taskStartSupersededCount == 0)
    try await waitForEvents(model, count: 2)
    #expect(Set(model.events) == ["start:first:0", "start:second"])
    #expect(loop.lifecycleCoordinator.activeTaskCount == 2)

    model.generation = 1
    try render()
    try await waitForEvents(model, count: 4)
    #expect(Set(model.events.suffix(2)) == ["cancel:first:0", "start:first:1"])
    #expect(loop.lifecycleCoordinator.activeTaskCount == 2)

    model.visible = false
    try render()
    try await waitForEvents(model, count: 6)
    #expect(Set(model.events.suffix(2)) == ["cancel:first:1", "cancel:second"])
    #expect(loop.lifecycleCoordinator.activeTaskCount == 0)
  }

  private func waitForEvents(_ model: MultiTaskModel, count: Int) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while model.events.count < count && ContinuousClock.now < deadline {
      await Task.yield()
    }
    try #require(model.events.count == count, "Observed task events: \(model.events)")
  }

  private func render(_ view: some View) -> (
    artifacts: RenderSnapshot,
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

  private func startedDescriptors(_ artifacts: RenderSnapshot) -> [TaskDescriptor] {
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

@MainActor
@Observable
private final class MultiTaskModel {
  var generation = 0
  var visible = true
  var events: [String] = []
}

private struct MultiTaskRoot: View {
  let model: MultiTaskModel

  var body: some View {
    if model.visible {
      let generation = model.generation
      Text("Two tasks")
        .task(id: generation) {
          model.events.append("start:first:\(generation)")
          await suspendUntilCancelled()
          model.events.append("cancel:first:\(generation)")
        }
        .task(id: "second") {
          model.events.append("start:second")
          await suspendUntilCancelled()
          model.events.append("cancel:second")
        }
    } else {
      Text("Removed")
    }
  }
}

private final class MultiTaskInput: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> { AsyncStream { $0.finish() } }
}
