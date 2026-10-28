import Testing

@testable import SwiftTUIGraph

@Suite("Framework stress: resolved traversal", .serialized)
struct FrameworkStressResolvedTraversalTests {
  @Test("stress resolved traversal 001 mixed trees collect in authored preorder")
  func resolvedTraversal001MixedTreesCollectInAuthoredPreorder() {
    let root = traversalNode(
      "Root",
      children: [
        traversalNode("A", children: [traversalNode("A1"), traversalNode("A2")]),
        traversalNode("B"),
        traversalNode("C", children: [traversalNode("C1")]),
      ])

    #expect(root.collectIdentities().map(\.path) == ["Root", "A", "A1", "A2", "B", "C", "C1"])
  }

  @Test("stress resolved traversal 002 collection appends after a caller prefix")
  func resolvedTraversal002CollectionAppendsAfterACallerPrefix() {
    let root = traversalNode("Root", children: [traversalNode("Child")])
    var identities = [testIdentity("Seed", "One"), testIdentity("Seed", "Two")]

    root.collectIdentities(into: &identities)

    #expect(identities.map(\.path) == ["Seed/One", "Seed/Two", "Root", "Child"])
  }

  @Test("stress resolved traversal 005 nested paths include every ancestor once")
  func resolvedTraversal005NestedPathsIncludeEveryAncestorOnce() {
    let target = testIdentity("Target")
    let root = traversalNode(
      "Root",
      children: [
        traversalNode(
          "Branch",
          children: [
            traversalNode("Inner", children: [traversalNode(target)])
          ])
      ])

    #expect(root.path(to: target)?.map(\.path) == ["Root", "Branch", "Inner", "Target"])
  }

  @Test("stress resolved traversal 006 duplicate paths select the first authored branch")
  func resolvedTraversal006DuplicatePathsSelectTheFirstAuthoredBranch() {
    let duplicate = testIdentity("Duplicate")
    let root = traversalNode(
      "Root",
      children: [
        traversalNode("First", children: [traversalNode(duplicate)]),
        traversalNode("Second", children: [traversalNode(duplicate)]),
      ])

    #expect(root.path(to: duplicate)?.map(\.path) == ["Root", "First", "Duplicate"])
  }

  @Test("stress resolved traversal 007 a missing lookup leaks no exited sibling path")
  func resolvedTraversal007MissingLookupLeaksNoExitedSiblingPath() {
    let target = testIdentity("Target")
    let root = traversalNode(
      "Root",
      children: [
        traversalNode(
          "DeadEnd",
          children: [
            traversalNode("DeepDeadEnd", children: [traversalNode("Leaf")])
          ]),
        traversalNode("Live", children: [traversalNode(target)]),
      ])

    #expect(root.path(to: target)?.map(\.path) == ["Root", "Live", "Target"])
    #expect(root.path(to: testIdentity("Absent")) == nil)
  }

  @Test("stress resolved traversal 011 deep chains remain stack safe")
  func resolvedTraversal011DeepChainsRemainStackSafe() throws {
    var root = traversalNode(Identity(components: ["Depth", "1024"]))
    for depth in stride(from: 1023, through: 0, by: -1) {
      root = traversalNode(Identity(components: ["Depth", String(depth)]), children: [root])
    }

    let identities = root.collectIdentities()
    let path = try #require(root.path(to: testIdentity("Depth", "1024")))

    #expect(identities.count == 1025)
    #expect(path.count == 1025)
    #expect(path.first == testIdentity("Depth", "0"))
    #expect(path.last == testIdentity("Depth", "1024"))
  }

  @Test("stress resolved traversal 012 wide trees retain the last authored child")
  func resolvedTraversal012WideTreesRetainTheLastAuthoredChild() {
    var children: [ResolvedNode] = []
    children.reserveCapacity(2048)
    for index in 0..<2048 {
      children.append(traversalNode(Identity(components: ["Child", String(index)])))
    }
    let root = traversalNode("Root", children: children)
    let target = testIdentity("Child", "2047")

    #expect(root.collectIdentities().last == target)
  }
}

private func traversalNode(
  _ component: String,
  children: [ResolvedNode] = [],
  lifecycle: LifecycleMetadata = .init()
) -> ResolvedNode {
  traversalNode(testIdentity(component), children: children, lifecycle: lifecycle)
}

private func traversalNode(
  _ identity: Identity,
  children: [ResolvedNode] = [],
  lifecycle: LifecycleMetadata = .init()
) -> ResolvedNode {
  ResolvedNode(
    identity: identity,
    kind: .view(identity.path),
    children: children,
    lifecycleMetadata: lifecycle
  )
}
