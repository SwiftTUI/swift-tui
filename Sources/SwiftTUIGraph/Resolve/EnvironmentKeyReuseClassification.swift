import Synchronization

/// Classifies environment keys for the reader-scoped reuse toleration.
///
/// A snapshot mismatch confined to *reader-attributed-only* keys can be
/// tolerated by a reuse door when the candidate subtree recorded no read of
/// any changed key: outside this framework's own modules, environment values
/// are reachable only through attributed surfaces (`@Environment` and
/// composed wrappers → `DependencyTracker.recordEnvironmentRead`), so an
/// empty reader set genuinely proves the subtree's output cannot depend on
/// the change. Keys DECLARED inside this framework are excluded by default:
/// framework resolve/draw code also consumes them without attribution (the
/// `EnvironmentValues[untracked:]` text-attribute reads, style extraction,
/// layout-axis reads), so no reader-set argument holds for them — except the
/// individually certified keys in ``certifiedFrameworkKeyNames``, whose every
/// consumer reads through the tracked subscript during node evaluation.
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

  /// Framework-declared keys individually certified as reader-attributed.
  ///
  /// Certification is a per-key soundness claim: every production consumer of
  /// the key's value reads it through the tracked typed subscript while a
  /// node is being evaluated, so the value reaches committed output only from
  /// attributed reads. The claim is *verified by measurement* — the memo
  /// shadow oracle across the full test corpus — never by enumerating read
  /// sites alone: the `FocusedValuesKey` attempt showed a value can leave the
  /// environment through a consumer (the preference collection path) that no
  /// read-site audit surfaces. Keys with `[untracked:]` reads (the
  /// text-attribute set) are structurally ineligible.
  ///
  /// Certifying a key also puts its authored writes into the writer index
  /// (the setter consults this classification), which the interior-writer
  /// denial requires.
  private static let certifiedFrameworkKeyNames: Set<String> = [
    // Read only by `Button`'s resolve (tracked); the style body it selects
    // is resolved output, and the draw phase never consults the key.
    "ButtonStyleKey",
    // Passive composition styles are read only by their primitive's resolve;
    // captured slots and style bodies carry the resulting composition forward.
    "LabelStyleKey",
    "LabeledContentStyleKey",
    "GroupBoxStyleKey",
    // Read only by `ScrollView`/`List`/`Table` resolve (tracked); the draw
    // phase consumes the resolved `drawMetadata.scrollIndicatorAxes` stamp,
    // never the environment.
    "ScrollIndicatorVisibilityKey",
    "HorizontalScrollIndicatorVisibilityKey",
    // Read only by `List`'s resolve (tracked) since the A1 List/Table split;
    // the resolved `ListStylePresentation` travels in `ListPayload.style`,
    // and the layout/draw phases consume the payload, never the environment.
    "ListStyleKey",
    // Same shape as `ListStyleKey`: one tracked read in `Table`'s resolve,
    // the resolved `TableStylePresentation` travels in `TablePayload.style`.
    "TableStyleKey",
    // Same shape again: one tracked read in `Spinner`'s body, and the
    // resolved `SpinnerStylePresentation` reaches output only as the glyph
    // text and task key the body produces. Unlike the three keys above,
    // this one carries no measurable census population — nothing in the
    // corpus changes a spinner style across a reuse boundary — so its
    // certification rests on read-shape identity with them plus a dedicated
    // boundary test, not on a denial-count reduction.
    "SpinnerStyleKey",
    // One tracked read in the toolbar host's resolve; the resolved layout
    // and placement reach output as the composed strip node, and the late
    // preference reconciliation replays through that same host rather than
    // re-reading the environment.
    "ToolbarStyleKey",
    // Read once at the sheet declaration's resolve, where the resolved
    // chrome is folded into the descriptor the portal coordinator
    // consumes; nothing re-reads the key downstream.
    "SheetStyleKey",
    // One tracked read in each primitive's resolve; style output travels
    // through a captured body node, with no downstream environment reread.
    // Dedicated unread/reader boundary tests and the full memo oracle pin
    // both toleration and invalidation for these four families.
    "ToggleStyleKey",
    "DisclosureGroupStyleKey",
    "TextEditorStyleKey",
    "ProgressViewStyleKey",
    // The value-control primitives read these once while constructing the
    // captured style body; route placement carries resolved semantics forward.
    "SliderStyleKey",
    "StepperStyleKey",
  ]

  package static func isReaderAttributedOnly(_ keyType: Any.Type) -> Bool {
    let key = ObjectIdentifier(keyType)
    return classificationsByKey.withLock { classifications in
      if let cached = classifications[key] {
        return cached
      }
      let reflectedName = String(reflecting: keyType)
      let isFrameworkDeclared = frameworkModulePrefixes.contains { prefix in
        reflectedName.hasPrefix(prefix)
      }
      let classification =
        !isFrameworkDeclared
        || certifiedFrameworkKeyNames.contains(lastNameComponent(of: reflectedName))
      classifications[key] = classification
      return classification
    }
  }

  /// The final dot-separated component of a reflected type name. Private key
  /// enums reflect with an opaque discriminator between the module and the
  /// type name (`Module.(unknown context at $…).Key`), so certification
  /// matches the trailing component rather than a full path. The framework
  /// prefix check has already accepted the name when this runs, so the space
  /// being matched is the framework's own — a user key that happens to share
  /// a certified trailing name never reaches this comparison.
  private static func lastNameComponent(of reflectedName: String) -> String {
    guard let lastDot = reflectedName.lastIndex(of: ".") else {
      return reflectedName
    }
    return String(reflectedName[reflectedName.index(after: lastDot)...])
  }

  /// Test seam: drops the cached classifications.
  package static func resetForTesting() {
    classificationsByKey.withLock { classifications in
      classifications.removeAll(keepingCapacity: false)
    }
  }
}
