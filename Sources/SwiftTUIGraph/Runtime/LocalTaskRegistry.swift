@MainActor
package final class TaskRegistration: Sendable {
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
  private var store = IdentityKeyedRegistryStorage<[TaskRegistration]>()

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
    var identityRegistrations = store[identity] ?? []
    if let index = identityRegistrations.firstIndex(where: {
      $0.descriptor.id == registration.descriptor.id
    }) {
      identityRegistrations[index] = registration
    } else {
      identityRegistrations.append(registration)
    }
    store.set(identityRegistrations, for: identity, owner: .current(identity: identity))
    ViewNodeContext.current?.recordTaskRegistration(
      identity: identity,
      registration: registration
    )
  }

  package func registration(
    for identity: Identity,
    descriptor: TaskDescriptor
  ) -> TaskRegistration? {
    store[identity]?.first { $0.descriptor == descriptor }
  }

  package func registration(
    for identity: Identity
  ) -> TaskRegistration? {
    store[identity]?.first
  }

  package func reset() {
    store.reset()
  }

  package func removeSubtrees(
    rootedAt roots: [Identity]
  ) {
    store.removeSubtrees(rootedAt: roots)
  }

  package func snapshot() -> [Identity: [TaskRegistration]] {
    store.values
  }

  package func restore(
    _ snapshot: [Identity: [TaskRegistration]],
    ownersByIdentity: [Identity: RuntimeRegistrationOwnerKey] = [:]
  ) {
    store.restore(snapshot, ownersByIdentity: ownersByIdentity)
  }
}
