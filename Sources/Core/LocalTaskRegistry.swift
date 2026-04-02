@MainActor
package final class TaskRegistration: @unchecked Sendable {
  package let descriptor: TaskDescriptor
  private let operationClosure: @MainActor @Sendable () async -> Void

  package init(
    descriptor: TaskDescriptor,
    operation: @escaping @MainActor @Sendable () async -> Void
  ) {
    self.descriptor = descriptor
    operationClosure = operation
  }

  package func run() async {
    await operationClosure()
  }
}

@MainActor
package final class LocalTaskRegistry: Equatable {
  private var registrations: [Identity: TaskRegistration] = [:]

  package init() {}

  nonisolated package static func == (
    lhs: LocalTaskRegistry,
    rhs: LocalTaskRegistry
  ) -> Bool {
    lhs === rhs
  }

  package func register(
    identity: Identity,
    registration: TaskRegistration
  ) {
    registrations[identity] = registration
    ViewNodeContext.current?.recordTaskRegistration(
      identity: identity,
      registration: registration
    )
  }

  package func registration(
    for identity: Identity
  ) -> TaskRegistration? {
    registrations[identity]
  }

  package func reset() {
    registrations.removeAll(keepingCapacity: true)
  }

  package func snapshot() -> [Identity: TaskRegistration] {
    registrations
  }

  package func restore(
    _ snapshot: [Identity: TaskRegistration]
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    for (identity, registration) in snapshot {
      registrations[identity] = registration
    }
  }
}
