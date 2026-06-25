@MainActor
package final class DependencyTracker {
  package private(set) var currentDependencies = DependencySet()

  package init() {}

  package func recordStateRead(_ key: StateSlotKey) {
    currentDependencies.stateSlotReads.insert(key)
  }

  package func recordEnvironmentRead(_ key: ObjectIdentifier) {
    currentDependencies.environmentReads.insert(key)
  }

  package func recordObservableRead(_ id: ObjectIdentifier) {
    currentDependencies.observableReads.insert(id)
  }

  package func recordObservableKeyPathRead(_ key: ObservableKeyPathKey) {
    currentDependencies.observableKeyPathReads.insert(key)
  }

  package func reset() -> DependencySet {
    defer {
      currentDependencies = .init()
    }
    return currentDependencies
  }
}

extension DependencyTracker {
  package struct Checkpoint {
    package var currentDependencies: DependencySet
  }

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(currentDependencies: currentDependencies)
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    currentDependencies = checkpoint.currentDependencies
  }
}
