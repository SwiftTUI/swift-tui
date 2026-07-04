package import SwiftTUICore

/// Live focused-values lookup for imperative callbacks, keyed by graph scope
/// (the ``LiveViewGraphRegistry`` pattern).
///
/// An ``ImperativeAuthoringContextSnapshot`` captures registration-time
/// focused values, but the callback fires later — after focus moved or the
/// focused subtree republished. The portal force-queue narrowing removed the
/// every-invalidation-frame root re-resolve that used to refresh such
/// registrations as a side effect, so a frozen snapshot would let
/// `@FocusedValue`/`@FocusedBinding` reads inside key commands and other
/// imperative handlers observe stale (or empty) values. The run loop
/// registers a provider for its graph scope; snapshot re-materialization
/// substitutes the live set when one is available.
@MainActor
package enum LiveFocusedValuesRegistry {
  private static var providersByScope: [StateGraphScopeID: @MainActor () -> FocusedValues?] = [:]

  /// Records the live provider for `scope`, sweeping entries whose provider
  /// has died (returns `nil`). Idempotent — a run loop re-registers under the
  /// same key.
  package static func register(
    scope: StateGraphScopeID,
    provider: @escaping @MainActor () -> FocusedValues?
  ) {
    providersByScope = providersByScope.filter { $0.value() != nil }
    providersByScope[scope] = provider
  }

  /// The live focused values for `scope`, or `nil` when no live provider is
  /// registered (snapshot values remain the best available).
  package static func currentFocusedValues(
    for scope: StateGraphScopeID
  ) -> FocusedValues? {
    providersByScope[scope]?()
  }
}
