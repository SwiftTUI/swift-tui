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
  case soundnessProbe
  case overlayIncrementalDamage
  case rasterVerifyIncremental
  case rasterTrustSoundDamage
  case presentedProgressGuard

  package var environmentVariableName: String {
    switch self {
    case .soundnessProbe:
      "SWIFTTUI_SOUNDNESS_PROBE"
    case .overlayIncrementalDamage:
      "SWIFTTUI_OVERLAY_INCREMENTAL_DAMAGE"
    case .rasterVerifyIncremental:
      "SWIFTTUI_RASTER_VERIFY_INCREMENTAL"
    case .rasterTrustSoundDamage:
      "SWIFTTUI_RASTER_TRUST_SOUND_DAMAGE"
    case .presentedProgressGuard:
      "SWIFTTUI_PRESENTED_PROGRESS_GUARD"
    }
  }

  package var defaultIsEnabled: Bool {
    switch self {
    case .soundnessProbe:
      // On in every configuration (F34). Release runs the oracles on a
      // 1-in-N sampled frame (see `SoundnessProbeConfiguration`), so the
      // steady-state cost is one Bool store per frame plus rare oracle
      // frames; in exchange the reconciliation-seam bug class stays
      // observable in the builds users actually run. `SWIFTTUI_SOUNDNESS_PROBE=0`
      // opts out.
      true
    case .overlayIncrementalDamage, .rasterVerifyIncremental, .rasterTrustSoundDamage,
      .presentedProgressGuard:
      // Opt-in behavior/verification toggles: absent ⇒ off, leaving the default
      // build (and, for the raster pair, the `#if DEBUG` policy fallback at their
      // resolution sites) in effect. The presented-progress guard's default
      // flip is gated on its pre-committed rusage A/B bound
      // (docs/plans/2026-07-20-001, Stage 5 — land-only-on-wins).
      false
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
