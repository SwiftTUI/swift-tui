import Core

@MainActor
final class TaskRunner {
  private struct ActiveTask {
    var descriptor: TaskDescriptor
    var generation: Int
    var task: Task<Void, Never>
  }

  private var activeTasks: [Identity: ActiveTask] = [:]
  private var nextGeneration = 0

  func start(
    identity: Identity,
    registration: TaskRegistration
  ) {
    cancel(identity: identity)

    nextGeneration += 1
    let generation = nextGeneration
    let descriptor = registration.descriptor
    let task = Task(priority: taskPriority(for: descriptor.priority)) { [weak self] in
      await registration.run()
      self?.finish(identity: identity, generation: generation)
    }

    activeTasks[identity] = ActiveTask(
      descriptor: descriptor,
      generation: generation,
      task: task
    )
  }

  func cancel(
    identity: Identity,
    matching descriptor: TaskDescriptor? = nil
  ) {
    guard let activeTask = activeTasks[identity] else {
      return
    }
    guard descriptor == nil || descriptor == activeTask.descriptor else {
      return
    }
    activeTasks.removeValue(forKey: identity)

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
    activeTasks.mapValues(\.descriptor)
  }

  private func finish(
    identity: Identity,
    generation: Int
  ) {
    guard activeTasks[identity]?.generation == generation else {
      return
    }
    activeTasks.removeValue(forKey: identity)
  }

  private func taskPriority(
    for priority: Core.TaskPriority
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
