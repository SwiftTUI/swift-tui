@MainActor
package final class DependencyTracker {
  package private(set) var currentDependencies = DependencySet()

  package init() {}

  package func recordStateRead(_ key: StateSlotKey, version: StateValueIdentity? = nil) {
    currentDependencies.mergeStateRead(key, certificate: .init(version: version))
  }

  package func recordEnvironmentRead(_ key: ObjectIdentifier) {
    currentDependencies.environmentReads.insert(key)
  }

  package func recordObservableRead(_ id: ObjectIdentifier) {
    currentDependencies.observableReads.insert(id)
    if let certificate = MemoObservationCertificateScope.current {
      recordObservationCertificate(certificate)
    } else {
      currentDependencies.hasUncertifiedObservableReads = true
    }
  }

  package func recordObservationCertificate(_ certificate: MemoObservationCertificate) {
    if !currentDependencies.observationCertificates.contains(certificate) {
      currentDependencies.observationCertificates.append(certificate)
    }
  }

  package func recordEnvironmentWrite(_ key: ObjectIdentifier) {
    currentDependencies.environmentWrites.insert(key)
  }

  package func recordFocusComparisonTargets(_ targets: Set<Identity>) {
    currentDependencies.focusComparisonTargets.formUnion(targets)
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
