import Synchronization

/// Marks package-owned keys whose values may have unattributed consumers.
/// External keys cannot adopt this package-only marker and remain reader-scoped.
package protocol FrameworkEnvironmentKey {}

/// A per-key proof that every production consumer is attributed during resolve.
/// Certification also enables writer tracking and must be backed by the memo
/// shadow oracle and dedicated unread/reader boundary tests. A read-site audit
/// alone is insufficient: FocusedValues exposed a preference-collection escape
/// that such an audit missed. Keys with untracked text/layout reads stay
/// uncertified. Inherit this marker only for an explicitly qualified key.
package protocol ReaderAttributedFrameworkEnvironmentKey: FrameworkEnvironmentKey {}

/// External keys use attributed public reads. Framework keys default to denial
/// because internal resolve/draw paths can consume their values untracked.
/// The explicit certification marker is the only framework exception.
///
/// This cache is lock guarded because the environment setter is nonisolated.
/// Classification stays beside the metatype; only its ObjectIdentifier crosses
/// into the dependency-recording closure. No reflected name is a proof of key
/// ownership or read attribution.
package enum EnvironmentKeyReuseClassification {
  private static let classificationsByKey = Mutex<[ObjectIdentifier: Bool]>([:])

  package static func isReaderAttributedOnly(_ keyType: Any.Type) -> Bool {
    let key = ObjectIdentifier(keyType)
    return classificationsByKey.withLock { classifications in
      if let cached = classifications[key] { return cached }
      let classification =
        !(keyType is any FrameworkEnvironmentKey.Type)
        || keyType is any ReaderAttributedFrameworkEnvironmentKey.Type
      classifications[key] = classification
      return classification
    }
  }

  package static func resetForTesting() {
    classificationsByKey.withLock { $0.removeAll(keepingCapacity: false) }
  }
}
