import Testing

@testable import SwiftTUIGraph

/// Depth-safety pins for the runtime-registration restore walks (the
/// bounded-depth-reuse program's Stage-2 slice 1): both walks must traverse
/// arbitrarily deep trees with O(1) native-stack growth, because the
/// reuse-hit restore runs while the resolve descent still occupies the
/// stack and the chunked resolve driver does not bound the walk. A
/// regression back to per-level recursion fails these depths on any
/// 512 KiB-stack thread and approaches the main-thread budget in debug.
@MainActor
struct RuntimeRegistrationRestoreWalkTests {
  private final class DispatchCounter {
    private(set) var count = 0
    func increment() { count += 1 }
  }

  private static let deepChainDepth = 8_192

  @Test("a deep resolved chain restores leaf registrations without stack growth")
  func deepResolvedChainRestoresLeafRegistrations() {
    let graph = ViewGraph()
    let leafIdentity = testIdentity("Leaf")
    let binding = KeyBinding(key: .character("s"), modifiers: .ctrl)
    let counter = DispatchCounter()

    graph.beginFrame()
    let leafNode = graph.beginEvaluation(identity: leafIdentity, invalidator: nil)
    leafNode.recordCommandRegistration(
      CommandRegistrySnapshot(
        keyCommandsByScope: [
          leafIdentity: [
            binding: RegisteredKeyCommand(
              binding: binding,
              description: "Save",
              isEnabled: true,
              action: { counter.increment() }
            )
          ]
        ]
      )
    )
    graph.finishEvaluation(
      leafNode,
      resolved: ResolvedNode(identity: leafIdentity, kind: .view("Leaf")),
      accessedStateSlots: 0
    )

    // Wrap the leaf under a chain far deeper than any authored tree — and
    // deeper than a per-level recursive walk survives on a 512 KiB stack.
    var resolved = ResolvedNode(identity: leafIdentity, kind: .view("Leaf"))
    for index in 0..<Self.deepChainDepth {
      resolved = ResolvedNode(
        identity: testIdentity("wrap\(index)"),
        kind: .view("Wrap"),
        children: [resolved]
      )
    }

    let commandRegistry = CommandRegistry()
    let registrations = RuntimeRegistrationSet(commandRegistry: commandRegistry)
    graph.restoreRuntimeRegistrations(
      for: resolved,
      into: registrations
    )

    #expect(commandRegistry.dispatch(key: binding, along: [leafIdentity]))
    #expect(counter.count == 1)
  }

  @Test("a deep live-node chain rebuilds leaf registrations without stack growth")
  func deepLiveNodeChainRebuildsLeafRegistrations() {
    let graph = ViewGraph()
    let binding = KeyBinding(key: .character("r"), modifiers: .ctrl)
    let counter = DispatchCounter()

    graph.beginFrame()
    let leafIdentity = testIdentity("chain0")
    let leafNode = graph.beginEvaluation(identity: leafIdentity, invalidator: nil)
    leafNode.recordCommandRegistration(
      CommandRegistrySnapshot(
        keyCommandsByScope: [
          leafIdentity: [
            binding: RegisteredKeyCommand(
              binding: binding,
              description: "Run",
              isEnabled: true,
              action: { counter.increment() }
            )
          ]
        ]
      )
    )
    graph.finishEvaluation(
      leafNode,
      resolved: ResolvedNode(identity: leafIdentity, kind: .view("Chain")),
      accessedStateSlots: 0
    )

    // Each level applies a SHALLOW resolved value (direct-child stub only):
    // the graph wires `ViewNode.children` from the direct children, so the
    // live chain links without ever applying a cumulative deep subtree —
    // deep-value applies exercise the apply path's own recursions, which are
    // not under test here.
    var rootNode = leafNode
    for index in 1..<Self.deepChainDepth {
      let identity = testIdentity("chain\(index)")
      let childStub = ResolvedNode(
        identity: testIdentity("chain\(index - 1)"),
        kind: .view("Chain")
      )
      let node = graph.beginEvaluation(identity: identity, invalidator: nil)
      graph.finishEvaluation(
        node,
        resolved: ResolvedNode(
          identity: identity,
          kind: .view("Chain"),
          children: [childStub]
        ),
        accessedStateSlots: 0
      )
      rootNode = node
    }

    let commandRegistry = CommandRegistry()
    let registrations = RuntimeRegistrationSet(commandRegistry: commandRegistry)
    rootNode.rebuildRuntimeRegistrations(into: registrations)

    #expect(commandRegistry.dispatch(key: binding, along: [leafIdentity]))
    #expect(counter.count == 1)
  }
}
