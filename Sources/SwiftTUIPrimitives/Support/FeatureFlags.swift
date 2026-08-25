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
#elseif canImport(ucrt)
  import CRT
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
  case focusMoveInvalidationNarrowing
  case stateCaptureBinding
  case animationVelocity

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
    case .focusMoveInvalidationNarrowing:
      "SWIFTTUI_FOCUS_MOVE_NARROWING"
    case .stateCaptureBinding:
      "SWIFTTUI_STATE_CAPTURE_BINDING"
    case .animationVelocity:
      "SWIFTTUI_ANIMATION_VELOCITY"
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
      // Kill switch, not an opt-in (plan 2026-08-11-002 Stage 4): the
      // pre-pass certifies size-stable dirty subtrees with the multi-sample
      // certificate (retained + cached baselines including the parent's
      // ideal-round proposal) and serves every certified root through the
      // derived measure session; the layout shadow oracle polices every
      // serve. Promoted 2026-08-11 on the plan-005 committed-benchmark A/B:
      // lazy-vstack-scroll pipeline p50 22.5 -> 10.4 ms ([real], zero-band
      // deterministic counter drops), measure-request counters down [real]
      // on every suite member, and the narrow-invalidation guard flat —
      // plus the plan-006 enablement evidence (180/180 chrome frames
      // certified+served, oracle-clean under every-frame DEBUG sampling).
      // `SWIFTTUI_MEASURE_CUTOFF=0` restores the conservative full
      // ancestor-spine re-measure wholesale (and is the A/B lever).
      true
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
    case .focusMoveInvalidationNarrowing:
      // Kill switch, not an opt-in (flip plan 2026-08-12-004 Stage 3): the
      // run loop translates focus-tracker move notifications into frame-time
      // endpoint invalidations, re-validated against the live reader
      // registries per resolve pass, instead of enqueuing event-time raw
      // identities. An endpoint that departed with its presentation (the
      // palette close-button leaf) then contributes nothing — previously its
      // unmappable identity remapped onto the outermost portal host and
      // conflict-denied the whole background (palette close conflicts
      // 177 → 0 at 176 rows; close class gone at 704 — report
      // 2026-08-12-003's A/B). The one named flip blocker — the coalesced
      // focus-flip + internal-scroll selective seam, masked flag-off by the
      // dispatch backstop's set-equality accident — is fixed (flip plan
      // Stages 1–2: collapse-boundary frontier lifting; generation-compare
      // backstop), pinned by `KeyboardScrollCoalescedFramePinTests`.
      // `SWIFTTUI_FOCUS_MOVE_NARROWING=0` restores the event-time raw
      // enqueue wholesale (and is the A/B lever).
      true
    case .stateCaptureBinding:
      // Default-on (plan 2026-08-20-001 Stage 4): bind `@State` ownership
      // into the view copy body evaluation captures, so imperative closures
      // resolve state through their carried owner instead of the ambient
      // dispatch context. `SWIFTTUI_STATE_CAPTURE_BINDING=0` disables the
      // bind pass as a diagnostic A/B lever; with the ambient ladder deleted
      // (Stage 5) that arm serves imperative reads from the loud authored
      // seed, so it attributes capture regressions — it does not restore the
      // pre-capture dispatch behavior.
      true
    case .animationVelocity:
      // Kill switch, not an opt-in (plan 2026-08-25-002 T4): the animation
      // velocity channel seeds a built-in spring with the outgoing curve's
      // velocity on retarget and with the sampled velocity of preceding
      // `tracksVelocity` writes, so a retargeted or released spring no
      // longer restarts at rest. `SWIFTTUI_ANIMATION_VELOCITY=0` restores
      // the at-rest restart wholesale for one release.
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
      #if os(Windows)
        // getenv is CRT-deprecated on Windows (C4996); _dupenv_s is the
        // conformant spelling. Success with a nil buffer means the variable
        // is unset; the CRT mallocs the buffer and this side frees it.
        var buffer: UnsafeMutablePointer<CChar>? = nil
        var length: size_t = 0
        guard unsafe _dupenv_s(&buffer, &length, cName) == 0,
          let rawValue = unsafe buffer
        else {
          return nil
        }
        defer { unsafe free(rawValue) }
        return unsafe String(cString: rawValue)
      #else
        guard let rawValue = unsafe getenv(cName) else {
          return nil
        }
        return unsafe String(cString: rawValue)
      #endif
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
