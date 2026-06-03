import SwiftTUICore

@MainActor
final class TaskRunner {
  private struct ActiveTask {
    var identity: Identity
    var descriptor: TaskDescriptor
    var generation: Int
    var task: Task<Void, Never>
  }

  private var activeTasks: [ViewNodeID: ActiveTask] = [:]
  private var nextGeneration = 0

  func start(
    viewNodeID: ViewNodeID,
    identity: Identity,
    registration: TaskRegistration
  ) {
    cancel(viewNodeID: viewNodeID)

    nextGeneration += 1
    let generation = nextGeneration
    let descriptor = registration.descriptor
    let task = Task(priority: taskPriority(for: descriptor.priority)) { [weak self] in
      await registration.run()
      self?.finish(viewNodeID: viewNodeID, generation: generation)
    }

    activeTasks[viewNodeID] = ActiveTask(
      identity: identity,
      descriptor: descriptor,
      generation: generation,
      task: task
    )
  }

  func cancel(
    viewNodeID: ViewNodeID,
    matching descriptor: TaskDescriptor? = nil
  ) {
    guard let activeTask = activeTasks[viewNodeID] else {
      return
    }
    guard descriptor == nil || descriptor == activeTask.descriptor else {
      return
    }
    activeTasks.removeValue(forKey: viewNodeID)

    activeTask.task.cancel()
  }

  func cancelAll() {
    let tasks = activeTasks.values.map(\.task)
    activeTasks.removeAll(keepingCapacity: true)
    for task in tasks {
      task.cancel()
    }
  }

  package var activeTaskDescriptors: [Identity: TaskDescriptor] {
    Dictionary(
      activeTasks.values.map { ($0.identity, $0.descriptor) },
      uniquingKeysWith: { _, latest in latest }
    )
  }

  private func finish(
    viewNodeID: ViewNodeID,
    generation: Int
  ) {
    guard activeTasks[viewNodeID]?.generation == generation else {
      return
    }
    activeTasks.removeValue(forKey: viewNodeID)
  }

  private func taskPriority(
    for priority: SwiftTUICore.TaskPriority
  ) -> _Concurrency.TaskPriority {
    switch priority {
    case .userInitiated:
      return .userInitiated
    case .high:
      return .high
    case .medium:
      return .medium
    case .low:
      return .low
    case .background:
      return .background
    }
  }
}
