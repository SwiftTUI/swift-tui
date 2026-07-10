/// Memoization soundness diagnostics. Answers the design's kill-gate question —
/// *how many recomputed nodes per interaction frame would have been memoizable,
/// and is skipping them sound* — without changing any behavior.
///
/// The observer is active on every frame in DEBUG/test builds and sampled
/// 1-in-256 in release by default (F90, mirroring the F34 soundness-probe
/// promotion); `SWIFTTUI_MEMO_TRACE=0` opts out. Trace lines are emitted only
/// when the env flag or `SWIFTTUI_MEMO_TRACE_FILE` is present, so the default
/// oracle does not spam stderr. On a sampled frame the resolver additionally
/// stashes every recomputed view value (not just `Equatable` ones), so the
/// frame after a sampled frame pays the production gate's guard chain for
/// those nodes — the same bounded, vanishes-in-profiles trade F34 made.
///
/// Per resolve pass, for every node an ancestor re-ran and reached (i.e. a node
/// recomputed *not* because it was itself invalidated):
///
/// - `computed` — recomputed nodes considered.
/// - `addressableMemoSkip` — view value structurally equal to the committed
///   value, passed the non-dirty reuse guards, **and the freshly recomputed
///   output proved byte-identical to the prior committed output** (the shadow
///   oracle). These are the sound memoization wins.
/// - `unsoundSkip` — the same, but the recomputed output **differed**: a node
///   whose view value looked equal yet whose body produced a different result
///   (the closure-captured-out-of-band-state hazard). Split three ways: nodes
///   with recorded dynamic reads (a changed read legitimately changes output),
///   no-reads nodes whose divergence is per-resolve entity bookkeeping only
///   (over-strict oracle fields, tracked in the histogram), and no-reads nodes
///   with a **content** divergence — a comparator false-equal. The content
///   class must stay 0; it raises the memo-soundness alarm
///   (``SoundnessProbeConfiguration/recordMemoUnsoundSkip(_:)``), which the
///   run loop routes to the host as a `RuntimeIssue`.
/// - `blocked*` — nodes the comparator could not reason about (closure / AnyView
///   / opaque existential fields). The interactive-leaf ceiling.
///
/// `ViewGraph.beginFrame` dumps and resets the histogram, so the stream shows one
/// `[MEMO-TRACE]` line per frame. Mirrors ``ReuseDenialTrace``.
/// Process-global by design (F119): this subsystem's state is `@MainActor`
/// statics keyed by per-`ViewGraph` frame IDs, so two live graphs in one
/// process would interleave counters and misattribute trace lines. Note-only
/// until multi-scene hosting is real; the fix shape is scoping to the
/// `ViewGraph` instance (or task-locals, the animation-sink storages' shape).
@MainActor
package enum MemoSkipTrace {
  package static let environmentVariableName = "SWIFTTUI_MEMO_TRACE"
  package static let fileEnvironmentVariableName = "SWIFTTUI_MEMO_TRACE_FILE"
  package static let sampleEnvironmentVariableName = "SWIFTTUI_MEMO_TRACE_SAMPLE"

  package static var isEnabled: Bool = environmentDefault()
  package static var sampleEveryNFrames: Int = sampleDefault()
  package static var isSampledFrame: Bool = false
  package static var outputFilePath: String? = environmentValue(
    named: fileEnvironmentVariableName
  )
  package static var emitsTraceLines: Bool = traceEmissionDefault()

  package private(set) static var computed = 0
  package private(set) static var addressableMemoSkip = 0
  package private(set) static var unsoundSkip = 0
  /// Unsound candidates split by why: with recorded reads (the dependency-value
  /// snapshot will reclassify these as correct re-runs) vs none (a comparator
  /// false-equal — a real bug to fix, not closed by the dependency gate).
  package private(set) static var unsoundWithReads = 0
  package private(set) static var unsoundNoReads = 0
  /// The alarmed subclass of `unsoundNoReads`: the divergence touches a
  /// *content* field (``ResolvedNode/memoUnsoundContentDivergence(from:)``),
  /// not just per-resolve entity bookkeeping. Must stay 0.
  package private(set) static var unsoundContentNoReads = 0
  package private(set) static var blockedClosure = 0
  package private(set) static var blockedAnyView = 0
  package private(set) static var blockedExistential = 0
  /// Adoption-trap counter: a view the author conformed to `Equatable` (opted
  /// into memoization) that is value-equal and passes the non-dirty reuse guards
  /// but is DENIED by the production gate because it reads `@State`/`@Observable`
  /// or focus/press state — so the `.equatable()` is silently a no-op. The #1
  /// adoption trap; surfacing it tells an author their opt-in is inert.
  package private(set) static var inertEquatableBoundary = 0
  /// Which `ResolvedNode` field first differed on an unsound mismatch — tells us
  /// whether the `no_reads` class is real content (comparator false-equal) or
  /// per-resolve identity bookkeeping (over-strict oracle).
  package private(set) static var unsoundFieldCounts: [String: Int] = [:]

  package static var shouldObserve: Bool {
    isEnabled && isSampledFrame
  }

  package static func beginFrame(frameID: UInt64) {
    guard isEnabled else {
      isSampledFrame = false
      return
    }
    isSampledFrame = frameID % UInt64(max(1, sampleEveryNFrames)) == 0
  }

  package static func recordComputed() {
    guard shouldObserve else { return }
    computed += 1
  }

  package static func recordAddressableSkip() {
    guard shouldObserve else { return }
    addressableMemoSkip += 1
  }

  /// Records an unsound candidate (view value looked equal but the recomputed
  /// output differed). `hadReads` distinguishes the dependency-closable class
  /// from a comparator false-equal; `contentDivergenceField` is the first
  /// diverging *content* field (nil when the divergence is per-resolve entity
  /// bookkeeping only); `firstDifferingField` feeds the histogram. A content
  /// divergence with no reads raises the memo-soundness alarm on
  /// ``SoundnessProbeConfiguration`` — the class that would have served stale
  /// UI had the production gate skipped it.
  package static func recordUnsoundSkip(
    hadReads: Bool,
    contentDivergenceField: String? = nil,
    firstDifferingField: String? = nil
  ) {
    guard shouldObserve else { return }
    unsoundSkip += 1
    if hadReads {
      unsoundWithReads += 1
    } else {
      unsoundNoReads += 1
    }
    if let field = firstDifferingField {
      unsoundFieldCounts[field, default: 0] += 1
    }
    guard !hadReads, let contentField = contentDivergenceField else { return }
    unsoundContentNoReads += 1
    SoundnessProbeConfiguration.recordMemoUnsoundSkip(
      "memo shadow oracle: content field '\(contentField)' diverged on a no-reads would-skip node"
    )
  }

  package static func recordBlocked(_ reason: MemoBlockReason) {
    guard shouldObserve else { return }
    switch reason {
    case .closure: blockedClosure += 1
    case .anyView: blockedAnyView += 1
    case .existential: blockedExistential += 1
    }
  }

  package static func recordInertEquatableBoundary() {
    guard shouldObserve else { return }
    inertEquatableBoundary += 1
  }

  package static func reset() {
    computed = 0
    addressableMemoSkip = 0
    unsoundSkip = 0
    unsoundWithReads = 0
    unsoundNoReads = 0
    unsoundContentNoReads = 0
    blockedClosure = 0
    blockedAnyView = 0
    blockedExistential = 0
    inertEquatableBoundary = 0
    unsoundFieldCounts.removeAll(keepingCapacity: true)
  }

  package static func dumpAndReset(frameID: UInt64) {
    guard shouldObserve, computed > 0 else {
      reset()
      return
    }
    if emitsTraceLines {
      let blockedTotal = blockedClosure + blockedAnyView + blockedExistential
      var line = "[MEMO-TRACE] frame=\(frameID)"
      line += " computed=\(computed)"
      line += " addressable_memo_skip=\(addressableMemoSkip)"
      line += " unsound_skip=\(unsoundSkip)"
      line += " (with_reads=\(unsoundWithReads) no_reads=\(unsoundNoReads)"
      line += " content_no_reads=\(unsoundContentNoReads))"
      line += " blocked=\(blockedTotal)"
      line += " (closure=\(blockedClosure) anyview=\(blockedAnyView)"
      line += " existential=\(blockedExistential))"
      line += " inert_equatable=\(inertEquatableBoundary)"
      if !unsoundFieldCounts.isEmpty {
        line += " | unsound-fields:"
        for (field, count) in unsoundFieldCounts.sorted(by: { $0.value > $1.value }) {
          line += " \(field)=\(count)"
        }
      }
      line += "\n"
      emit(line)
    }
    reset()
  }

  private static func emit(_ message: String) {
    DiagnosticTraceSink.emit(message, toFileAt: outputFilePath)
  }

  private static func environmentDefault() -> Bool {
    guard let rawValue = environmentValue(named: environmentVariableName) else {
      // Default ON in every configuration (F90, mirroring the F34 probe
      // promotion): the memo-soundness alarm this observer feeds must run in
      // the builds users actually run, not only under DEBUG.
      // `SWIFTTUI_MEMO_TRACE=0` opts out.
      return true
    }
    return !rawValue.isEmpty && rawValue != "0"
  }

  private static func sampleDefault() -> Int {
    guard let rawValue = environmentValue(named: sampleEnvironmentVariableName),
      let parsed = Int(rawValue), parsed > 0
    else {
      #if DEBUG
        return 1
      #else
        // 1-in-256 now that the observer defaults ON in release (F90,
        // matching the F34 soundness-probe rationale): rare enough that
        // observed frames vanish in steady-state profiles, frequent enough
        // that a persistent comparator false-equal surfaces within seconds
        // at interactive frame rates.
        return 256
      #endif
    }
    return parsed
  }

  private static func traceEmissionDefault() -> Bool {
    if let rawValue = environmentValue(named: environmentVariableName) {
      return !rawValue.isEmpty && rawValue != "0"
    }
    return environmentValue(named: fileEnvironmentVariableName) != nil
  }

  private static func environmentValue(named name: String) -> String? {
    FeatureFlags.environmentValue(named: name)
  }
}
