/// A replacement witness for an immutable state value. A missing token is an
/// uncovered read, including conflicting versions read in one evaluation.
package struct StateReadCertificate: Equatable {
  package var version: StateValueIdentity?

  package init(version: StateValueIdentity?) { self.version = version }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.version === rhs.version
  }
}

/// The observation owner supplies synchronized callback and registration
/// currency. Checkpoint copies share the witness: firing cannot be rolled back.
@MainActor
package final class MemoObservationCertificate: Equatable {
  private let check: @MainActor () -> Bool

  package init(isCurrent: @escaping @MainActor () -> Bool) { check = isCurrent }
  package var isCurrent: Bool { check() }

  #if DEBUG
    // A retired registration is not evidence of a model mutation. The
    // framework's bridge supplies a separate diagnostic-only witness.
    package var observedChangeWhileRegistered: (@MainActor () -> Bool)?
  #endif

  nonisolated package static func == (
    lhs: MemoObservationCertificate, rhs: MemoObservationCertificate
  )
    -> Bool
  { lhs === rhs }
}

package enum MemoObservationCertificateScope {
  @TaskLocal package static var current: MemoObservationCertificate?
}
