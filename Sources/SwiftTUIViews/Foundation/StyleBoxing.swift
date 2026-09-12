import SwiftTUICore

/// Common storage and reuse proof for every erased style family. Family
/// conformances forward only the requirements specific to their protocol.
protocol AnyStyleBox: Sendable {
  func isEqualForReuse(to other: any AnyStyleBox) -> Bool
}

struct ConcreteStyleBox<S: Sendable>: AnyStyleBox {
  let style: S

  func isEqualForReuse(to other: any AnyStyleBox) -> Bool {
    guard let other = other as? Self else { return false }
    return styleValuesAreEqualForReuse(style, other.style)
  }

  @MainActor
  func resolveBody<Configuration: Sendable, Body: View>(
    configuration: Configuration,
    styleLabel: String,
    in context: ResolveContext,
    makeBody: @escaping @MainActor @Sendable (S, Configuration) -> Body
  ) -> ResolveWork<ResolvedNode> {
    if hasDynamicPropertyUpdateSurface(style) {
      return resolveStyleBody(
        DynamicStyleBody(style: style, configuration: configuration, makeBody: makeBody),
        styleLabel: styleLabel, in: context)
    }
    return resolveStyleBody(
      makeBody(bindingForwardedDynamicPropertyCaptures(style), configuration),
      styleLabel: styleLabel, in: context)
  }
}

/// A style carrying wrappers participates in the same preparation and reuse
/// contract as a composed modifier. Update its concrete working copy before
/// evaluating the body, under the style body's rebased authoring scope.
private struct DynamicStyleBody<S: Sendable, Configuration: Sendable, Body: View>: View,
  AdditionalDynamicPropertyUpdating
{
  var style: S
  let configuration: Configuration
  let makeBody: @MainActor @Sendable (S, Configuration) -> Body

  var body: Body {
    makeBody(bindingForwardedDynamicPropertyCaptures(style), configuration)
  }

  func ownsDynamicPropertyTraversal(ofStoredFieldAt index: Int) -> Bool { index == 0 }

  mutating func updateAdditionalDynamicProperties(
    in context: AdditionalDynamicPropertyUpdateContext
  ) -> DynamicPropertyUpdateResult {
    runForwardedDynamicPropertyUpdates(on: &style, in: context)
  }

  func hasAdditionalDynamicPropertyUpdateSurface() -> Bool {
    hasDynamicPropertyUpdateSurface(style)
  }
}

// The two rules every erased style box obeys.
//
// Every style family stores a concrete style behind a per-family existential
// box. What the boxes forward genuinely differs (prominence, selection deltas,
// pointer routing, strip presentation, presentation values), but the reuse
// rule and the body-resolve rule are the same for all of them, so they live
// here rather than being rediscovered per family.

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
) -> ResolveWork<ResolvedNode> {
  withStyleRouteInstallationLedger(styleLabel: styleLabel) {
    resolveViewWork(
      body,
      in: context,
      authoringContextOverride: currentAuthoringContext()
    )
  }
}
