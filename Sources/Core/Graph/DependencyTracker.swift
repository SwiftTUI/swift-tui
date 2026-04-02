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

  package func reset() -> DependencySet {
    defer {
      currentDependencies = .init()
    }
    return currentDependencies
  }
}
