import SwiftTUICore

// Route wrappers: the one way a style body installs a synthetic pointer hit
// target around the view it composes for that target.
//
// `TabViewStyleItemConfiguration.route` was the first route wrapper. Every
// later family (picker options and triggers, slider tracks, stepper halves,
// menu portals) hands its style the same shape — a public `route { … }`
// method on the configuration — backed by this package machinery, so the
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
// on such a frame. That is a degraded state of an already-reported misuse,
// accepted over the alternative — a ledger that outlives the resolve and
// misreads a route that legitimately moved between structural slots.

/// The identity a route wrapper installs, with the diagnostic names the
/// misuse channel reports.
package struct StyleRouteTarget: Sendable, Equatable {
  /// The live pointer identity the wrapper installs.
  package var identity: Identity
  /// The style family that owns the route (`"TabViewStyle"`).
  package var family: String
  /// The route's name within the family (`"item"`, `"overflow trigger"`).
  package var role: String

  package init(
    identity: Identity,
    family: String,
    role: String
  ) {
    self.identity = identity
    self.family = family
    self.role = role
  }
}

/// The routes one style-body resolve has installed so far.
@MainActor
package final class StyleRouteInstallationLedger {
  /// The resolving style's `snapshotLabel`, for the misuse message.
  package let styleLabel: String
  private var installed: Set<Identity> = []

  package init(styleLabel: String) {
    self.styleLabel = styleLabel
  }

  /// Records `identity` and returns whether this is its first installation
  /// in the current body resolve.
  package func claim(_ identity: Identity) -> Bool {
    installed.insert(identity).inserted
  }
}

package enum StyleRouteInstallationLedgerStorage {
  @TaskLocal package static var current: StyleRouteInstallationLedger?
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
      content: content
    )
    .resolveElements(in: context)
  }
}
