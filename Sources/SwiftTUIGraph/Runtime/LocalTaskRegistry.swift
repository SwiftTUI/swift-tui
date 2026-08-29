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

  /// The node axis of teardown — see
  /// ``RuntimeRegistry/removeUnjustifiedRegistrations(_:)``.
  package func removeUnjustifiedRegistrations(
    _ record: (ViewNodeID) -> NodeHandlers?
  ) {
    store.removeUnjustified { identity, owner in
      // An entry restored without an owner carries no node claim to check.
      guard let viewNodeID = owner.viewNodeID else {
        return true
      }
      return record(viewNodeID)?.task.registrations[identity] != nil
    }
  }

  package func snapshot() -> [Identity: [TaskRegistration]] {
    store.values
  }

  /// Merge-per-identity, deliberately not the family's replace-per-identity
  /// contract: one identity's task registrations can be contributed by
  /// MULTIPLE nodes. A `.task` attached to a builder conditional records on
  /// the ambient authoring node while the branch content's own `.task`
  /// records on the branch node — same host identity, different recording
  /// nodes. Publication restores per node (in `Set` iteration order, after a
  /// reset or a subtree removal), so wholesale replacement let the
  /// last-iterated node erase its sibling's registrations for the shared
  /// identity — and the erased task's committed `.taskStart` skipped at
  /// commit ("no task registration at commit"; gifeditor launch flip,
  /// 2026-08-03). Same-descriptor entries still replace, so a site's
  /// re-registration wins; cross-node contributions union.
  package func restore(
    _ snapshot: [Identity: [TaskRegistration]],
    ownersByIdentity: [Identity: RuntimeRegistrationOwnerKey] = [:]
  ) {
    guard !snapshot.isEmpty else {
      return
    }
    for (identity, restored) in snapshot {
      var merged = store[identity] ?? []
      for registration in restored {
        if let index = merged.firstIndex(where: {
          $0.descriptor.id == registration.descriptor.id
        }) {
          merged[index] = registration
        } else {
          merged.append(registration)
        }
      }
      store.set(
        merged,
        for: identity,
        owner: ownersByIdentity[identity] ?? .init(identity: identity)
      )
    }
  }
}
