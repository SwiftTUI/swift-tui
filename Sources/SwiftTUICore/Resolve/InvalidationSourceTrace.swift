/// Diagnostic-only trace of **how each frame's invalidation set was assembled**,
/// gated by `SWIFTTUI_INVAL_TRACE` (default off). Inert/zero-cost when disabled.
///
/// Companion to ``ReuseDenialTrace``: the reuse trace says *which* invalidated
/// identity a recomputed node conflicted with; this trace says *where that
/// identity came from* — the raw scheduler-coalesced set, the
/// portal-translation rewrite (``ViewGraph/translatePresentationPortalInvalidations``),
/// or a force-root decision. Used to pin which path injects an ancestor of a
/// large reused subtree (e.g. the content root) on a presentation open/close.
///
/// One `[INVAL-TRACE]` line per resolved frame, written through
/// ``DiagnosticTraceSink`` (the `SWIFTTUI_INVAL_TRACE_FILE` append-file sink when
/// set, otherwise stderr).
@MainActor
package enum InvalidationSourceTrace {
  package static let environmentVariableName = "SWIFTTUI_INVAL_TRACE"
  package static let fileEnvironmentVariableName = "SWIFTTUI_INVAL_TRACE_FILE"

  package static var isEnabled: Bool = environmentDefault()

  /// File sink path; `nil` ⇒ stderr. Resolved once on first use; settable for
  /// tests. See ``ReuseDenialTrace/outputFilePath``.
  package static var outputFilePath: String? = DiagnosticTraceSink.environmentValue(
    named: fileEnvironmentVariableName
  )

  private static var sequence: UInt64 = 0

  /// Emits one line decomposing a frame's invalidation-set assembly: the `raw`
  /// scheduler set, the post-portal-translation `xlated` set (only when it
  /// differs), the final selective-evaluation decision, and the force-root
  /// reasons when selective evaluation is disabled.
  package static func recordFrame(
    raw: Set<Identity>,
    translated: Set<Identity>,
    usesSelectiveEvaluation: Bool,
    disabledReasons: [String]
  ) {
    guard isEnabled else { return }
    var line = "[INVAL-TRACE] seq=\(sequence)"
    sequence &+= 1
    line += " raw={\(joined(raw))}"
    if translated != raw {
      line += " xlated={\(joined(translated))}"
    }
    line += " selective=\(usesSelectiveEvaluation)"
    if !disabledReasons.isEmpty {
      line += " force-root-reasons=[\(disabledReasons.sorted().joined(separator: ","))]"
    }
    line += "\n"
    DiagnosticTraceSink.emit(line, toFileAt: outputFilePath)
  }

  /// Caller attribution: synchronously emits a labeled source line
  /// (`[INVAL-SRC] <source>={…}`) for an invalidation request, so the subsystem
  /// that injected a given identity can be identified by correlating with the
  /// `[INVAL-TRACE]` frame line that follows. Inert unless the trace is on.
  package static func note(_ source: StaticString, _ identities: Set<Identity>) {
    guard isEnabled, !identities.isEmpty else { return }
    let line = "[INVAL-SRC] \(source)={\(joined(identities))}\n"
    DiagnosticTraceSink.emit(line, toFileAt: outputFilePath)
  }

  /// Resets the sequence counter (test seam).
  package static func reset() {
    sequence = 0
  }

  private static func joined(_ identities: Set<Identity>) -> String {
    identities.map(\.path).sorted().joined(separator: ",")
  }

  private static func environmentDefault() -> Bool {
    guard let rawValue = DiagnosticTraceSink.environmentValue(named: environmentVariableName)
    else {
      return false
    }
    return !rawValue.isEmpty && rawValue != "0"
  }
}
