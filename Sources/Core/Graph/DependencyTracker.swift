@MainActor
package final class DependencyTracker {
  package struct Checkpoint {
    fileprivate var currentDependencies: DependencySet
  }

  package private(set) var currentDependencies = DependencySet()

  package init() {}

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(currentDependencies: currentDependencies)
  }

  package func restore(_ checkpoint: Checkpoint) {
    currentDependencies = checkpoint.currentDependencies
  }

  package func recordStateRead(_ key: StateSlotKey) {
    currentDependencies.stateSlotReads.insert(key)
  }

  package func recordEnvironmentRead(_ key: ObjectIdentifier) {
    currentDependencies.environmentReads.insert(key)
  }

  package func recordObservableRead(_ id: ObjectIdentifier) {
    currentDependencies.observableReads.insert(id)
  }

  package func reset() -> DependencySet {
    defer {
      currentDependencies = .init()
    }
    return currentDependencies
  }
}
