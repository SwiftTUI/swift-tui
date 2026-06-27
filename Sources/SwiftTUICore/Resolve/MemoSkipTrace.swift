/// Memoization soundness diagnostics. Answers the design's kill-gate question —
/// *how many recomputed nodes per interaction frame would have been memoizable,
/// and is skipping them sound* — without changing any behavior.
///
/// The observer is active on every frame in DEBUG/test builds and opt-in sampled
/// in release via `SWIFTTUI_MEMO_TRACE=1`. Trace lines are emitted only when the
/// env flag or `SWIFTTUI_MEMO_TRACE_FILE` is present, so the default test-mode
/// oracle does not spam stderr.
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
///   (the closure-captured-out-of-band-state hazard). Must stay ~0; any nonzero
///   value is a loud soundness alarm.
/// - `blocked*` — nodes the comparator could not reason about (closure / AnyView
///   / opaque existential fields). The interactive-leaf ceiling.
///
/// `ViewGraph.beginFrame` dumps and resets the histogram, so the stream shows one
/// `[MEMO-TRACE]` line per frame. Mirrors ``ReuseDenialTrace``.
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

  package static func recordUnsoundField(_ field: String) {
    guard shouldObserve else { return }
    unsoundFieldCounts[field, default: 0] += 1
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
  /// from a comparator false-equal.
  package static func recordUnsoundSkip(hadReads: Bool) {
    guard shouldObserve else { return }
    unsoundSkip += 1
    if hadReads {
      unsoundWithReads += 1
    } else {
      unsoundNoReads += 1
    }
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
      line += " (with_reads=\(unsoundWithReads) no_reads=\(unsoundNoReads))"
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
      #if DEBUG
        return true
      #else
        return false
      #endif
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
        return 64
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
