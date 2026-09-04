import SwiftTUICore

// The two rules every erased style box obeys.
//
// Four style families — button, picker, text-field, tab-view — each store a
// concrete style behind a per-family existential box. What the boxes forward
// genuinely differs (prominence, selection deltas, pointer routing, strip
// presentation), but they agreed on these two rules by copy-and-paste, with the
// rationale for `resolveStyleBody` living as a comment in `ButtonStyles` that
// the other three pointed at by name. A fifth family had to rediscover both.

/// A style whose instances carry no configuration.
///
/// Conformers are SwiftTUI's own builtin styles: `init()` and nothing stored,
/// so any two instances of the same type are interchangeable and the reuse gate
/// can answer from type identity alone.
///
/// This is not a shortcut — it is load-bearing. A stateless style struct
/// conforms to neither `Equatable` nor `TypedReuseEqualityProviding`, and is
/// not a class, so ``typedValuesAreEqualForReuse`` finds no typed proof and
/// returns its deliberately conservative `false`. Without this marker every
/// builtin style would compare unequal on every frame and deny reuse of the
/// control it styles.
///
/// Deliberately not `public`: it asserts statelessness, and that can only be
/// checked inside this module. A third-party style with stored properties that
/// claimed transparency would reuse silently across its own value changes.
protocol ReuseTransparentStyle {}

/// Decides whether two values of the *same* concrete style type are
/// interchangeable for reuse.
///
/// Callers establish the same-type precondition first (an erased box compares
/// `as? Self` before delegating here), so this answers only the value question.
func styleValuesAreEqualForReuse<S: Sendable>(
  _ lhs: S,
  _ rhs: S
) -> Bool {
  if lhs is any ReuseTransparentStyle {
    return true
  }
  return typedValuesAreEqualForReuse(lhs, rhs)
}

/// Resolves a style body through its own view node, keeping the enclosing
/// control's authoring scope rebased onto that node.
///
/// Both halves are load-bearing, and both were found by regression:
///
/// - **Its own node.** A value-only style child forces the graph to mint a
///   hollow, never-evaluated placeholder whose chrome interiors outlive their
///   anchors when a host generation departs — the F04 teardown-coherence
///   residual.
/// - **The enclosing scope, rebased.** A *fresh* authoring scope re-roots
///   registration owners onto the re-mintable style-body island, where
///   input-driven `@State` writes degrade to detached seed boxes: no dirt, no
///   invalidation, stale retained reuse. This is the seam the `8ace32a5`
///   regression wedged on, where tab-hosted scroll panes silently lost
///   input-driven `@State` writes.
///
/// The resolve also opens the style's route ledger (`StyleRoute.swift`), so a
/// route wrapper the body installs twice is reported once under
/// `styleLabel` and the first installation wins.
@MainActor
func resolveStyleBody<Body: View>(
  _ body: Body,
  styleLabel: String,
  in context: ResolveContext
) -> ResolvedNode {
  withStyleRouteInstallationLedger(styleLabel: styleLabel) {
    resolveView(
      body,
      in: context,
      authoringContextOverride: currentAuthoringContext()
    )
  }
}
