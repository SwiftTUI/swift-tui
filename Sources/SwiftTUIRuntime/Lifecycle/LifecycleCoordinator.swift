import SwiftTUICore

@MainActor
package final class LifecycleCoordinator {
  private let taskRunner: TaskRunner
  private(set) var previousLifecycleHandlers = LifecycleHandlerSnapshot()

  init(taskRunner: TaskRunner = .init()) {
    self.taskRunner = taskRunner
  }

  func applyCommittedFrame(
    plan: CommitPlan,
    currentLifecycleRegistry: LocalLifecycleRegistry,
    currentTaskRegistry: LocalTaskRegistry
  ) {
    for entry in plan.lifecycle {
      apply(
        entry,
        currentLifecycleRegistry: currentLifecycleRegistry,
        currentTaskRegistry: currentTaskRegistry
      )
    }

    previousLifecycleHandlers = currentLifecycleRegistry.snapshot()
  }

  func shutdown() {
    taskRunner.cancelAll()
    previousLifecycleHandlers = .init()
  }

  package var activeTaskDescriptors: [Identity: TaskDescriptor] {
    taskRunner.activeTaskDescriptors
  }

  private func apply(
    _ entry: LifecycleCommitEntry,
    currentLifecycleRegistry: LocalLifecycleRegistry,
    currentTaskRegistry: LocalTaskRegistry
  ) {
    switch entry.operation {
    case .appear(let handlerIDs):
      for handlerID in handlerIDs {
        currentLifecycleRegistry.appearHandler(for: handlerID)?()
      }
    case .disappear(let handlerIDs):
      for handlerID in handlerIDs {
        previousLifecycleHandlers.disappearHandlers[handlerID]?()
      }
    case .change(let handlerIDs):
      for handlerID in handlerIDs {
        currentLifecycleRegistry.changeHandler(for: handlerID)?()
      }
    case .taskStart(let descriptor):
      guard let registration = currentTaskRegistry.registration(for: entry.identity),
        registration.descriptor == descriptor
      else {
        return
      }
      taskRunner.start(identity: entry.identity, registration: registration)
    case .taskCancel(let descriptor):
      taskRunner.cancel(identity: entry.identity, matching: descriptor)
    }
  }
}
