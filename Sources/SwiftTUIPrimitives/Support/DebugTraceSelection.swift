/// The `SWIFTTUI_TRACE` selector: one variable that arms diagnostic-trace
/// *emission* across the framework, replacing the per-trace
/// `X` / `X_FILE` / `X_SAMPLE` variable triplets (which keep working as
/// overrides).
///
/// ```
/// SWIFTTUI_TRACE = trace *( "," trace )
/// trace          = name [ "@" sampleN ]
/// name           = "frames" | "memo" | "reuse" | "inval"
///                | "soundness" | "publication"
/// ```
///
/// Example: `SWIFTTUI_TRACE=memo@256,reuse,frames`.
///
/// `@N` sets the owning oracle's 1-in-*N* frame sampling where one exists
/// (`memo`, `soundness`). Malformed input fails closed to an empty selection
/// — mirroring `SWIFTTUI_PROFILE` — rather than partially arming. Unknown
/// names are ignored so a newer environment keeps working against an older
/// binary. Destinations come from ``DebugLogRouter`` (`SWIFTTUI_DEBUG_DIR`
/// or per-trace `*_FILE` overrides), stderr otherwise.
package struct DebugTraceSelection: Sendable, Equatable {
  package struct Entry: Sendable, Equatable {
    package var name: String
    package var sampleEveryNFrames: Int?

    package init(name: String, sampleEveryNFrames: Int? = nil) {
      self.name = name
      self.sampleEveryNFrames = sampleEveryNFrames
    }
  }

  package static let environmentVariableName = "SWIFTTUI_TRACE"

  package static let knownTraceNames: Set<String> = [
    "frames", "memo", "reuse", "inval", "soundness", "publication", "cutoff",
  ]

  /// The process-level selection, parsed from `SWIFTTUI_TRACE` once.
  package static let current = DebugTraceSelection.parse(
    FeatureFlags.environmentValue(named: environmentVariableName)
  )

  package var entries: [Entry]

  package init(entries: [Entry] = []) {
    self.entries = entries
  }

  package static func parse(_ raw: String?) -> DebugTraceSelection {
    guard let raw else {
      return DebugTraceSelection()
    }
    let normalized = raw.trimmingWhitespace()
    guard !normalized.isEmpty else {
      return DebugTraceSelection()
    }
    var entries: [Entry] = []
    for rawEntry in normalized.split(separator: ",", omittingEmptySubsequences: false) {
      let entry = rawEntry.trimmingWhitespace()
      guard !entry.isEmpty else {
        return DebugTraceSelection()
      }
      let parts = entry.split(separator: "@", omittingEmptySubsequences: false)
      let name = String(parts[0]).lowercased()
      guard !name.isEmpty else {
        return DebugTraceSelection()
      }
      var sample: Int? = nil
      if parts.count == 2 {
        guard let parsed = Int(parts[1]), parsed > 0 else {
          return DebugTraceSelection()
        }
        sample = parsed
      } else if parts.count > 2 {
        return DebugTraceSelection()
      }
      guard knownTraceNames.contains(name) else {
        // Unknown names are skipped, not fatal: forward compatibility with
        // selections written for a newer framework.
        continue
      }
      entries.append(Entry(name: name, sampleEveryNFrames: sample))
    }
    return DebugTraceSelection(entries: entries)
  }

  package func entry(named name: String) -> Entry? {
    entries.first { entry in entry.name == name }
  }

  package func isArmed(_ name: String) -> Bool {
    entry(named: name) != nil
  }
}

extension StringProtocol {
  fileprivate func trimmingWhitespace() -> String {
    var value = Substring(self)
    while value.first == " " || value.first == "\t" {
      value.removeFirst()
    }
    while value.last == " " || value.last == "\t" {
      value.removeLast()
    }
    return String(value)
  }
}
