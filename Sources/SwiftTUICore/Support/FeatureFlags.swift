#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#elseif canImport(WASILibc)
  import WASILibc
#endif

/// The known process-level performance/soundness feature gates.
package enum FeatureGate: CaseIterable, Sendable {
  case memoReuse
  case observableKeyPathInvalidation
  case preciseObservationFiring
  case readerAttribution
  case singlePassFocusConvergence
  case soundnessProbe

  package var environmentVariableName: String {
    switch self {
    case .memoReuse:
      "SWIFTTUI_MEMO_REUSE"
    case .observableKeyPathInvalidation:
      "SWIFTTUI_OBSERVABLE_KEYPATH_INVALIDATION"
    case .preciseObservationFiring:
      "SWIFTTUI_PRECISE_OBSERVATION_FIRING"
    case .readerAttribution:
      "SWIFTTUI_READER_ATTRIBUTION"
    case .singlePassFocusConvergence:
      "SWIFTTUI_SINGLE_PASS_FOCUS"
    case .soundnessProbe:
      "SWIFTTUI_SOUNDNESS_PROBE"
    }
  }

  package var defaultIsEnabled: Bool {
    switch self {
    case .memoReuse, .observableKeyPathInvalidation, .preciseObservationFiring,
      .readerAttribution:
      true
    case .singlePassFocusConvergence:
      // Off by default: the focus-sync convergence rewrite (render-until-fixpoint
      // loop → single-pass, one-frame-lag dependency invalidation) ships behind a
      // gate, proven at parity before the default flips. See
      // `SinglePassFocusConvergenceConfiguration`.
      false
    case .soundnessProbe:
      #if DEBUG
        true
      #else
        false
      #endif
    }
  }

  package func initialIsEnabled() -> Bool {
    FeatureFlags.isEnabled(named: environmentVariableName, default: defaultIsEnabled)
  }
}

/// Centralized access for the framework's `SWIFTTUI_*` feature gates.
///
/// Every perf gate and trace sink used to carry its own copy-pasted `getenv`
/// wrapper and default-on parser (plus the five-arm libc `#if` import). That
/// meant a parsing fix — or the WASILibc compile-out seam that has shipped
/// green-but-broken twice — had to be applied N times. ``FeatureGate`` now owns
/// the enrolled gate names and defaults; the per-gate configs keep their
/// test-settable `isEnabled` latches and delegate initial environment reads
/// here.
package enum FeatureFlags {
  /// Reads a process environment variable. First access wins (the value is
  /// latched by each gate's `static var`), matching the prior getenv semantics.
  package static func environmentValue(named name: String) -> String? {
    unsafe name.withCString { cName in
      guard let rawValue = unsafe getenv(cName) else {
        return nil
      }
      return unsafe String(cString: rawValue)
    }
  }

  /// Parses a boolean-ish feature flag: absent → `defaultValue`; `"0"` or empty
  /// → `false`; anything else → `true`.
  package static func isEnabled(
    named name: String,
    default defaultValue: Bool
  ) -> Bool {
    guard let rawValue = environmentValue(named: name) else {
      return defaultValue
    }
    return !rawValue.isEmpty && rawValue != "0"
  }
}
