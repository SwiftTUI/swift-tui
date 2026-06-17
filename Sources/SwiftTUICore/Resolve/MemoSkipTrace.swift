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

/// Stage-0 memoization diagnostics, gated by `SWIFTTUI_MEMO_TRACE` (default off,
/// zero-cost when disabled). Answers the design's kill-gate question — *how many
/// recomputed nodes per interaction frame would have been memoizable, and is
/// skipping them sound* — without changing any behavior.
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

  package static var isEnabled: Bool = environmentDefault()
  package static var outputFilePath: String? = environmentValue(
    named: fileEnvironmentVariableName
  )

  package private(set) static var computed = 0
  package private(set) static var addressableMemoSkip = 0
  package private(set) static var unsoundSkip = 0
  package private(set) static var blockedClosure = 0
  package private(set) static var blockedAnyView = 0
  package private(set) static var blockedExistential = 0

  package static func recordComputed() {
    guard isEnabled else { return }
    computed += 1
  }

  package static func recordAddressableSkip() {
    guard isEnabled else { return }
    addressableMemoSkip += 1
  }

  package static func recordUnsoundSkip() {
    guard isEnabled else { return }
    unsoundSkip += 1
  }

  package static func recordBlocked(_ reason: MemoBlockReason) {
    guard isEnabled else { return }
    switch reason {
    case .closure: blockedClosure += 1
    case .anyView: blockedAnyView += 1
    case .existential: blockedExistential += 1
    }
  }

  package static func reset() {
    computed = 0
    addressableMemoSkip = 0
    unsoundSkip = 0
    blockedClosure = 0
    blockedAnyView = 0
    blockedExistential = 0
  }

  package static func dumpAndReset(frameID: UInt64) {
    guard isEnabled, computed > 0 else {
      reset()
      return
    }
    let blockedTotal = blockedClosure + blockedAnyView + blockedExistential
    var line = "[MEMO-TRACE] frame=\(frameID)"
    line += " computed=\(computed)"
    line += " addressable_memo_skip=\(addressableMemoSkip)"
    line += " unsound_skip=\(unsoundSkip)"
    line += " blocked=\(blockedTotal)"
    line += " (closure=\(blockedClosure) anyview=\(blockedAnyView)"
    line += " existential=\(blockedExistential))\n"
    emit(line)
    reset()
  }

  private static func emit(_ message: String) {
    DiagnosticTraceSink.emit(message, toFileAt: outputFilePath)
  }

  private static func environmentDefault() -> Bool {
    guard let rawValue = environmentValue(named: environmentVariableName) else {
      return false
    }
    return !rawValue.isEmpty && rawValue != "0"
  }

  private static func environmentValue(named name: String) -> String? {
    unsafe name.withCString { cName in
      guard let rawValue = unsafe getenv(cName) else {
        return nil
      }
      return unsafe String(cString: rawValue)
    }
  }
}
