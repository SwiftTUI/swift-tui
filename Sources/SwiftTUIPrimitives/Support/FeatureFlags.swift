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
  case collectionProbes
  case collectionResolveReuse
  case lazyStackIdealEstimate
  case scrollRegionEmission
  case scrollBlit
  case measureSizeStabilityCutoff
  case persistentCustomLayoutCache

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
    case .collectionProbes:
      "SWIFTTUI_COLLECTION_PROBES"
    case .collectionResolveReuse:
      "SWIFTTUI_COLLECTION_RESOLVE_REUSE"
    case .lazyStackIdealEstimate:
      "SWIFTTUI_LAZY_IDEAL_ESTIMATE"
    case .scrollRegionEmission:
      "SWIFTTUI_SCROLL_REGION"
    case .scrollBlit:
      "SWIFTTUI_SCROLL_BLIT"
    case .measureSizeStabilityCutoff:
      "SWIFTTUI_MEASURE_CUTOFF"
    case .persistentCustomLayoutCache:
      "SWIFTTUI_PERSISTENT_LAYOUT_CACHE"
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
      // flip was measured on the drop-heavy browser regime and DECLINED
      // (2026-07-21, docs/plans/2026-07-20-001 Stage 5): the guard closes the
      // disposal class at zero cost in the shipped `async-no-cancel` regime,
      // but under plain `.async` it delivers 0.674 distinct-generation
      // coverage vs the 0.72 fix band — `async-no-cancel` stays the cadence
      // mechanism; the guard stays opt-in insurance.
      false
    case .collectionProbes:
      // Configuration-split default (WP-4 of the scroll-latency program).
      // The collection probes are magnitude counters — realized rows, list
      // layout derivations — that the existing DEBUG-only test consumers read
      // unconditionally, so DEBUG must stay armed or those suites lose their
      // instrument. Release defaults OFF because the realization counter fires
      // once per realized row: free when disarmed (a static Bool read),
      // not free enough to impose on every shipped app.
      //
      // Release must nonetheless be *armable*: debug scroll timings contradict
      // release for per-cell work (the D71 lesson), so a release run has to be
      // able to correlate its milliseconds with rows realized, or every A/B in
      // this program argues by faith.
      #if DEBUG
        true
      #else
        false
      #endif
    case .collectionResolveReuse:
      // Kill switch, not an opt-in (scroll-latency R4-A): the hosted-collection
      // resolve reuses — the integer-range id-space witness that verifies
      // retained identity artifacts in O(1), and the retained row-selection
      // snapshot — are content-verified against exactly the inputs that
      // determine them (ids witness + identity root + entity scope; artifacts
      // lifetime + selection-compat key), so a stale entry can only miss,
      // never corrupt. `SWIFTTUI_COLLECTION_RESOLVE_REUSE=0` restores the
      // element-wise O(N)-per-resolve paths wholesale (and is the A/B lever).
      true
    case .lazyStackIdealEstimate:
      // Kill switch, not an opt-in (scroll-latency R4-C): an enclosing stack's
      // ideal round proposes an unspecified main dimension, which a scroll
      // layout maps to "no measure viewport" — so before this gate the ideal
      // round of an indexed lazy stack realized and measured EVERY element,
      // every frame, defeating scroll windowing behind any chrome stack (the
      // 2026-08-01 app-tier finding 1: 300/300 realized where the windowed
      // round realizes <=60). The estimate serves the ideal from the retained
      // allocation snapshot (exact-as-of-last-frame lengths) or, cold and
      // above a count threshold, from an element-0 probe (stride x count) —
      // the same estimate currency windowed measurement already synthesizes
      // out-of-window entries from. `SWIFTTUI_LAZY_IDEAL_ESTIMATE=0` restores
      // the exhaustive ideal round wholesale (and is the A/B lever).
      true
    case .scrollRegionEmission:
      // Kill switch, not an opt-in: scroll-region emission (R2.3) is
      // verification-backed — every emitted translation is proven
      // cell-for-cell against the written baseline before any bytes go out —
      // and DECSTBM/SU/SD are VT100-core, so the capability defaults on for
      // real terminals. `SWIFTTUI_SCROLL_REGION=0` disables the emission
      // wholesale if a terminal misbehaves.
      true
    case .scrollBlit:
      // Kill switch, not an opt-in (scroll-latency R3.2b): the translation
      // blit is prove-before-serve — every served row is draw-walk verified,
      // flank-verified, and constructed as a row-buffer identity the planner
      // re-proves — and the F13 oracle sits on top unchanged. Certified by
      // the R3.2 A/B (notch raster_ms 1.50 -> 0.45, pipeline p50 -1.1 ms,
      // zero oracle repairs across every armed lane and a 1000-frame
      // full-verify release probe). `SWIFTTUI_SCROLL_BLIT=0` disables the
      // blit (and with it the planner's identity fast path) wholesale.
      true
    case .measureSizeStabilityCutoff:
      // Opt-in stage gate (size-stability cutoff, plan 2026-08-11-002).
      // Stage 1 is dark — behind the gate the pre-pass computes eligibility
      // and certificates and records counters only; nothing is served.
      // Promotion to a default-on kill switch requires the plan's Stage 4
      // benchmark acceptance.
      false
    case .persistentCustomLayoutCache:
      // Kill switch, not an opt-in (plan 2026-08-11-004 Stage 2): the
      // `Layout.Cache` doc contract already demands value-semantic,
      // pass-independent state, serves are equivalence- and
      // invalidation-checked against the node the cache was built for, and
      // the DEBUG divergence check compares every served pass against a
      // fresh `makeCache` recompute. `SWIFTTUI_PERSISTENT_LAYOUT_CACHE=0`
      // restores per-pass `makeCache` wholesale (the plan's triage escape
      // hatch).
      true
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
