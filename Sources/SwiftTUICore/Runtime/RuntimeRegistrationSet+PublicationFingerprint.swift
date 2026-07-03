extension RuntimeRegistrationSet {
  /// Order-insensitive projection of every registry's keyed contents: one
  /// `registry|key` bucket per registration, with a count where handlers
  /// stack. Handlers are closures and cannot be compared for equality; keys
  /// and per-key counts are exactly the surface the scoped-restore bug class
  /// corrupts (missing, stale, or duplicated registrations after a partial
  /// republication). Used by the sampled publication oracle to compare a
  /// scoped restore against a scratch full rebuild — see
  /// ``ViewGraphFrameDraft/commitRuntimeRegistrations(from:)``.
  package func publicationOracleFingerprint() -> [String: Int] {
    var builder = RuntimeRegistrationFingerprintBuilder()
    for registry in allRegistries {
      registry.fingerprint(into: &builder)
    }
    return builder.fingerprint
  }
}
