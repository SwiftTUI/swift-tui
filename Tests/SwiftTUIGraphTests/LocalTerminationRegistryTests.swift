import Testing

@testable import SwiftTUIGraph

/// First unit coverage for `LocalTerminationRegistry` (F109) — previously the
/// only registry with none. Termination handlers decide whether a session may
/// end, so the dispatch ordering (preferred path leafmost-first, then
/// remaining identities deepest-first; stacked handlers newest-first; first
/// `.cancel` wins) and the lifecycle paths are pinned directly.
@MainActor
@Suite("LocalTerminationRegistry")
struct LocalTerminationRegistryTests {
  @Test("dispatch allows termination when no handler cancels")
  func dispatchAllowsByDefault() {
    let registry = LocalTerminationRegistry()
    registry.register(identity: testIdentity("Root")) { _ in .allow }
    #expect(registry.dispatch(.inputEnded, preferredPath: []) == .allow)
  }

  @Test("the first cancelling handler short-circuits dispatch")
  func firstCancelWinsAndShortCircuits() {
    let registry = LocalTerminationRegistry()
    var consultedAfterCancel = false
    // Deeper identity is consulted first (deepest-first fallback ordering);
    // its .cancel must stop the walk before the shallow handler runs.
    registry.register(identity: testIdentity("Root", "Sheet")) { _ in .cancel }
    registry.register(identity: testIdentity("Root")) { _ in
      consultedAfterCancel = true
      return .allow
    }

    #expect(registry.dispatch(.signal("TERM"), preferredPath: []) == .cancel)
    #expect(consultedAfterCancel == false)
  }

  @Test("the preferred path is consulted leafmost-first, before other identities")
  func preferredPathIsConsultedLeafmostFirst() {
    let registry = LocalTerminationRegistry()
    var order: [String] = []
    let root = testIdentity("Root")
    let leaf = testIdentity("Root", "Tab", "Editor")
    let bystander = testIdentity("Root", "Other", "Deep", "Deeper")
    registry.register(identity: root) { _ in
      order.append("root")
      return .allow
    }
    registry.register(identity: leaf) { _ in
      order.append("leaf")
      return .allow
    }
    registry.register(identity: bystander) { _ in
      order.append("bystander")
      return .allow
    }

    _ = registry.dispatch(.inputEnded, preferredPath: [root, leaf])

    // preferredPath is walked reversed (leafmost-first), then the remaining
    // identities deepest-first — the bystander is deeper than root but comes
    // after the whole preferred path.
    #expect(order == ["leaf", "root", "bystander"])
  }

  @Test("stacked handlers on one identity run newest-first")
  func stackedHandlersRunNewestFirst() {
    let registry = LocalTerminationRegistry()
    var order: [String] = []
    let identity = testIdentity("Root")
    registry.register(identity: identity) { _ in
      order.append("first-registered")
      return .allow
    }
    registry.register(identity: identity) { _ in
      order.append("second-registered")
      return .allow
    }

    _ = registry.dispatch(.inputEnded, preferredPath: [])

    #expect(order == ["second-registered", "first-registered"])
  }

  @Test("removeSubtrees drops descendants' handlers and keeps the sibling's")
  func removeSubtreesSplitsSubtreeFromSibling() {
    let registry = LocalTerminationRegistry()
    var consulted: [String] = []
    let parent = testIdentity("Root", "Parent")
    registry.register(identity: testIdentity("Root", "Parent", "Child")) { _ in
      consulted.append("child")
      return .allow
    }
    registry.register(identity: testIdentity("Root", "Sibling")) { _ in
      consulted.append("sibling")
      return .allow
    }

    registry.removeSubtrees(rootedAt: [parent])
    _ = registry.dispatch(.inputEnded, preferredPath: [])

    #expect(consulted == ["sibling"])
  }

  @Test("reset drops every handler")
  func resetDropsEverything() {
    let registry = LocalTerminationRegistry()
    var consulted = false
    registry.register(identity: testIdentity("Root")) { _ in
      consulted = true
      return .cancel
    }

    registry.reset()

    #expect(registry.dispatch(.inputEnded, preferredPath: []) == .allow)
    #expect(consulted == false)
  }

  @Test("restore replaces an identity's handler stack; empty restore is a no-op")
  func restoreReplacesPerIdentityAndEmptyRestoreIsNoOp() {
    let registry = LocalTerminationRegistry()
    let identity = testIdentity("Root")
    var consulted: [String] = []
    registry.register(identity: identity) { _ in
      consulted.append("original")
      return .allow
    }

    // Restore replaces the identity's stack (snapshot semantics), it does not
    // append to it.
    let replacement: LocalTerminationRegistry.Handler = { _ in
      consulted.append("restored")
      return .allow
    }
    registry.restore([identity: [replacement]])
    _ = registry.dispatch(.inputEnded, preferredPath: [])
    #expect(consulted == ["restored"])

    // The family-standard empty-snapshot guard: no change.
    consulted = []
    registry.restore([:])
    _ = registry.dispatch(.inputEnded, preferredPath: [])
    #expect(consulted == ["restored"])
  }
}
