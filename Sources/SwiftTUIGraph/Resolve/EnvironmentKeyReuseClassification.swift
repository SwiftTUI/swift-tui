import Synchronization

/// Classifies environment keys for the reader-scoped reuse toleration.
///
/// A snapshot mismatch confined to *reader-attributed-only* keys can be
/// tolerated by a reuse door when the candidate subtree recorded no read of
/// any changed key: outside this framework's own modules, environment values
/// are reachable only through attributed surfaces (`@Environment` and
/// composed wrappers → `DependencyTracker.recordEnvironmentRead`), so an
/// empty reader set genuinely proves the subtree's output cannot depend on
/// the change. Keys DECLARED inside this framework are excluded wholesale:
/// framework resolve/draw code also consumes them without attribution (the
/// `EnvironmentValues[untracked:]` text-attribute reads, style extraction,
/// layout-axis reads), so no reader-set argument holds for them.
///
/// The classification is name-based (the declaring module prefix of the
/// reflected key type), computed once per key type and cached — the same
/// cold-per-type discipline as `MemoComparisonPlanCache`.
///
/// **Lock-guarded rather than `@MainActor`-guarded**, unlike its sibling
/// caches. The one production caller is `EnvironmentValues`' typed subscript
/// *setter*, which is nonisolated and holds the key metatype; an actor-isolated
/// cache would force that metatype across an isolation boundary
/// (`sending 'key' risks causing data races`), and metatypes are not `Sendable`.
/// Classifying outside the hop keeps only the `ObjectIdentifier` — which is
/// `Sendable` — crossing into the recording closure, exactly as the matching
/// read path does. The lock is taken once per environment write; the cache is
/// write-once per key type and read-only thereafter.
package enum EnvironmentKeyReuseClassification {
  private static let classificationsByKey = Mutex<[ObjectIdentifier: Bool]>([:])

  /// Module prefixes whose environment keys may be consumed without read
  /// attribution. `SwiftTUICharts` and other external view libraries are
  /// deliberately NOT listed: they compose on the public authoring surface,
  /// where every environment read is attributed.
  private static let frameworkModulePrefixes = [
    "SwiftTUIPrimitives.",
    "SwiftTUIGraph.",
    "SwiftTUICore.",
    "SwiftTUIViews.",
    "SwiftTUIRuntime.",
    "SwiftTUIAnimatedImage.",
    "SwiftTUIWASI.",
    "SwiftTUI.",
  ]

  package static func isReaderAttributedOnly(_ keyType: Any.Type) -> Bool {
    let key = ObjectIdentifier(keyType)
    return classificationsByKey.withLock { classifications in
      if let cached = classifications[key] {
        return cached
      }
      let reflectedName = String(reflecting: keyType)
      let classification = !frameworkModulePrefixes.contains { prefix in
        reflectedName.hasPrefix(prefix)
      }
      classifications[key] = classification
      return classification
    }
  }

  /// Test seam: drops the cached classifications.
  package static func resetForTesting() {
    classificationsByKey.withLock { classifications in
      classifications.removeAll(keepingCapacity: false)
    }
  }
}
