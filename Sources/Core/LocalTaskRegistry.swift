// SAFETY: All stored properties are either Sendable (descriptor) or explicitly @Sendable
// (operationClosure). The @unchecked is needed because the compiler cannot prove Sendability
// of the class type through its stored property analysis alone.
package final class TaskRegistration: @unchecked Sendable {
  package let descriptor: TaskDescriptor
  private let operationClosure: @Sendable () async -> Void

  package init(
    descriptor: TaskDescriptor,
    operation: @escaping @Sendable () async -> Void
  ) {
    self.descriptor = descriptor
    operationClosure = operation
  }

  package func run() async {
    await operationClosure()
  }
}

// SAFETY: Created and exclusively accessed on @MainActor during resolve/event phases.
// Contains non-Sendable TaskRegistration values. All mutable state protected by OSAllocatedUnfairLock.
package final class LocalTaskRegistry: @unchecked Sendable, Equatable {
  private struct Storage {
    var registrations: [Identity: TaskRegistration] = [:]
  }

  private let storage = OSAllocatedUnfairLock(uncheckedState: Storage())

  package init() {}

  package static func == (
    lhs: LocalTaskRegistry,
    rhs: LocalTaskRegistry
  ) -> Bool {
    lhs === rhs
  }

  package func register(
    identity: Identity,
    registration: TaskRegistration
  ) {
    storage.withLockUnchecked { storage in
      storage.registrations[identity] = registration
    }
  }

  package func registration(
    for identity: Identity
  ) -> TaskRegistration? {
    storage.withLockUnchecked { storage in
      storage.registrations[identity]
    }
  }

  package func reset() {
    storage.withLockUnchecked { storage in
      storage.registrations.removeAll(keepingCapacity: true)
    }
  }

  package func snapshot() -> [Identity: TaskRegistration] {
    storage.withLockUnchecked { storage in
      storage.registrations
    }
  }

  package func restore(
    _ snapshot: [Identity: TaskRegistration]
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    storage.withLockUnchecked { storage in
      for (identity, registration) in snapshot {
        storage.registrations[identity] = registration
      }
    }
  }
}
