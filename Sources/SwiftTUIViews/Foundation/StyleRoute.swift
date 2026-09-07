import SwiftTUICore

// Route wrappers: the one way a style body installs a synthetic pointer hit
// target around the view it composes for that target.
//
// `TabViewStyleItemConfiguration.route` was the first route wrapper. Every
// later family hands its style the same shape — a public wrapper method on
// the configuration (`route`, `track`, `decrement`, `increment`, `trigger`,
// the palette command's `route`) — backed by this package machinery, so the
// rules shared by every route live in one place:
//
// - A route wrapper never traps. Misuse degrades and reports.
// - Omitting an optional route removes only the pointer target. Keyboard
//   interaction is owned by the primitive, which registers its handlers
//   independently of anything the style body composes.
// - Installing the same route more than once in one style-body resolve
//   emits `style.duplicateRoute` and the first installation wins: later
//   installations render their content without a pointer target.
// - A fixture-constructed configuration carries no control identity, so its
//   route wrappers are inert: they render their content and install nothing.
//   That branch is the configuration's (`if let controlIdentity`), which is
//   why this view takes a non-optional identity.
//
// The duplicate ledger is scoped to one style-body resolve
// (`resolveStyleBody`). A selective re-run of an evaluator inside the body
// runs without it and installs whatever it resolves, so a duplicate the
// first full resolve already reported can reappear as a second live target
// on such a frame. The same applies to a subtree the stack-lean resolve
// profile cuts at its depth cap and drains from the outermost resolve, which
// is outside every ledger scope. Both are degraded states of an
// already-reported or unreported misuse, accepted over the alternative — a
// ledger that outlives the resolve and misreads a route that legitimately
// moved between structural slots.
//
// A container that resolves several candidates and places one
// (`ViewThatFits`) is the one place a route legitimately appears more than
// once in a resolve. Each candidate claims on its own alternative of the
// ledger (`withStyleRouteAlternatives`), so sibling candidates do not report
// against each other while a candidate re-installing an outer route still
// does.

/// The identity a route wrapper installs, with the diagnostic names the
/// misuse channel reports.
package struct StyleRouteTarget: Sendable, Equatable {
  /// The live pointer identity the wrapper installs.
  package var identity: Identity
  /// The style family that owns the route (`"TabViewStyle"`).
  package var family: String
  /// The route's name within the family (`"item"`, `"overflow trigger"`).
  package var role: String
  /// Keeps a drag on this route even after the pointer leaves its bounds.
  package var captureOnPress: Bool

  package init(
    identity: Identity,
    family: String,
    role: String,
    captureOnPress: Bool = false
  ) {
    self.identity = identity
    self.family = family
    self.role = role
    self.captureOnPress = captureOnPress
  }
}

/// The routes one style-body resolve has installed so far.
@MainActor
package final class StyleRouteInstallationLedger {
  /// The resolving style's `snapshotLabel`, for the misuse message.
  package let styleLabel: String
  private var installed: Set<Identity>
  private var alternatives: [StyleRouteInstallationLedger] = []

  package convenience init(styleLabel: String) {
    self.init(styleLabel: styleLabel, installed: [])
  }

  private init(styleLabel: String, installed: Set<Identity>) {
    self.styleLabel = styleLabel
    self.installed = installed
  }

  /// Records `identity` and returns whether this is its first installation
  /// in the current body resolve.
  package func claim(_ identity: Identity) -> Bool {
    installed.insert(identity).inserted
  }

  /// A ledger for one candidate of an alternatives container. It starts from
  /// the routes installed so far, so a candidate that re-installs an outer
  /// route still reports, while sibling candidates that each install the
  /// same route do not report against each other.
  package func makeAlternative() -> StyleRouteInstallationLedger {
    let alternative = StyleRouteInstallationLedger(styleLabel: styleLabel, installed: installed)
    alternatives.append(alternative)
    return alternative
  }

  /// Folds every candidate's claims back once all candidates have resolved,
  /// so a later installation outside the container still reports.
  package func absorbAlternatives() {
    for alternative in alternatives {
      installed.formUnion(alternative.installed)
    }
    alternatives.removeAll()
  }
}

package enum StyleRouteInstallationLedgerStorage {
  @TaskLocal package static var current: StyleRouteInstallationLedger?

  /// Set while an alternatives container resolves its candidates: each
  /// declared child then claims on its own alternative of `current`.
  /// Resolution is synchronous on the main actor, so a plain flag scopes
  /// exactly like the task-local ledger without a lookup per declared child.
  @MainActor package static var forksPerDeclaredChild = false
}

/// Resolves the candidates of an alternatives container so that each declared
/// child claims routes on its own alternative of the current ledger.
@MainActor
package func withStyleRouteAlternatives<Result>(_ body: () -> Result) -> Result {
  guard let ledger = StyleRouteInstallationLedgerStorage.current else {
    return body()
  }
  let previous = StyleRouteInstallationLedgerStorage.forksPerDeclaredChild
  StyleRouteInstallationLedgerStorage.forksPerDeclaredChild = true
  defer {
    StyleRouteInstallationLedgerStorage.forksPerDeclaredChild = previous
    ledger.absorbAlternatives()
  }
  return body()
}

/// Resolves one declared child. Inside `withStyleRouteAlternatives` the child
/// gets its own alternative ledger; containers nested in it resolve normally.
@MainActor
package func resolvingStyleRouteAlternative<Result>(_ body: () -> Result) -> Result {
  guard StyleRouteInstallationLedgerStorage.forksPerDeclaredChild,
    let ledger = StyleRouteInstallationLedgerStorage.current
  else {
    return body()
  }
  StyleRouteInstallationLedgerStorage.forksPerDeclaredChild = false
  defer { StyleRouteInstallationLedgerStorage.forksPerDeclaredChild = true }
  return StyleRouteInstallationLedgerStorage.$current.withValue(ledger.makeAlternative()) {
    body()
  }
}

/// Runs `body` with a fresh route ledger for one style-body resolve.
@MainActor
package func withStyleRouteInstallationLedger<Result>(
  styleLabel: String,
  _ body: () -> Result
) -> Result {
  StyleRouteInstallationLedgerStorage.$current.withValue(
    StyleRouteInstallationLedger(styleLabel: styleLabel)
  ) {
    body()
  }
}

/// The view a route wrapper returns for a live target.
///
/// A first installation resolves exactly as `PointerRouteView` does. A
/// repeated installation within the same style-body resolve reports through
/// the shared misuse channel and resolves its content without a route.
package struct StyleRouteView<Content: View>: PrimitiveView, ResolvableView {
  package var target: StyleRouteTarget
  package var content: Content

  package init(
    target: StyleRouteTarget,
    content: Content
  ) {
    self.target = target
    self.content = content
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    if let ledger = StyleRouteInstallationLedgerStorage.current,
      !ledger.claim(target.identity)
    {
      // Style bodies resolve in composed context, so the issue rides the
      // imperative queue and surfaces at this frame's head merge — the
      // same channel `Spinner` uses for an invalid presentation.
      ImperativeRuntimeIssueQueue.record(
        StyleMisuse.duplicateRouteIssue(
          family: target.family,
          role: target.role,
          styleLabel: ledger.styleLabel,
          identity: target.identity
        )
      )
      return [
        content.resolve(in: context.child(component: .named("content")))
      ]
    }
    return PointerRouteView(
      identity: target.identity,
      content: content,
      captureOnPress: target.captureOnPress
    )
    .resolveElements(in: context)
  }
}
