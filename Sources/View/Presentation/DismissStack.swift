package import Core

@MainActor
package struct DismissStack {
  package var entries: [DismissStackEntry<String>]

  package init(entries: [DismissStackEntry<String>] = []) {
    self.entries = entries
  }

  package func topmostEscapeDismissAction() -> (@MainActor @Sendable () -> Void)? {
    entries
      .filter(\.acceptsEscape)
      .max { lhs, rhs in
        portalOrderingPrecedes(lhs.ordering, rhs.ordering)
      }?
      .dismiss
  }
}
