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
  private var registrations: [Identity: TaskRegistration] = [:]
  private var ownersByIdentity: [Identity: RuntimeRegistrationOwnerKey] = [:]

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
    ownersByIdentity[identity] = .current(identity: identity)
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
    ownersByIdentity.removeAll(keepingCapacity: true)
  }

  package func removeSubtrees(
    rootedAt roots: [Identity]
  ) {
    guard !roots.isEmpty else {
      return
    }

    for identity in registrations.keys.filter({
      (ownersByIdentity[$0] ?? .init(identity: $0)).matchesAnySubtreeRoot(roots)
    }) {
      registrations.removeValue(forKey: identity)
      ownersByIdentity.removeValue(forKey: identity)
    }
  }

  package func snapshot() -> [Identity: TaskRegistration] {
    registrations
  }

  package func restore(
    _ snapshot: [Identity: TaskRegistration],
    ownersByIdentity: [Identity: RuntimeRegistrationOwnerKey] = [:]
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    for (identity, registration) in snapshot {
      registrations[identity] = registration
      self.ownersByIdentity[identity] = ownersByIdentity[identity] ?? .init(identity: identity)
    }
  }
}
