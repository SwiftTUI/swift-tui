import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite("Builder-slot structural identity migration", .serialized)
struct BuilderSlotStructuralIdentityTests {
  @Test("multi-element conditional consumes one parent slot")
  func multiElementConditionalConsumesOneParentSlot() throws {
    let collapsed = resolveBuilderSlotProbe(
      BuilderSlotConditionalProbe(expanded: false)
    )
    let expanded = resolveBuilderSlotProbe(
      BuilderSlotConditionalProbe(expanded: true)
    )

    let collapsedTail = try builderSlotTextNode("tail", in: collapsed)
    let expandedTail = try builderSlotTextNode("tail", in: expanded)
    #expect(collapsedTail.identity == expandedTail.identity)
    #expect(collapsedTail.structuralPath == expandedTail.structuralPath)
  }

  @Test("unequal conditional branches consume one parent slot")
  func unequalConditionalBranchesConsumeOneParentSlot() throws {
    let narrow = resolveBuilderSlotProbe(
      BuilderSlotUnequalBranchProbe(usesWideBranch: false)
    )
    let wide = resolveBuilderSlotProbe(
      BuilderSlotUnequalBranchProbe(usesWideBranch: true)
    )

    let narrowTail = try builderSlotTextNode("tail", in: narrow)
    let wideTail = try builderSlotTextNode("tail", in: wide)
    #expect(narrowTail.identity == wideTail.identity)
    #expect(narrowTail.structuralPath == wideTail.structuralPath)
  }

  @Test("buildArray cardinality consumes one parent slot")
  func buildArrayCardinalityConsumesOneParentSlot() throws {
    let empty = resolveBuilderSlotProbe(BuilderSlotArrayProbe(count: 0))
    let many = resolveBuilderSlotProbe(BuilderSlotArrayProbe(count: 3))

    let emptyTail = try builderSlotTextNode("tail", in: empty)
    let manyTail = try builderSlotTextNode("tail", in: many)
    #expect(emptyTail.identity == manyTail.identity)
    #expect(emptyTail.structuralPath == manyTail.structuralPath)
  }

  @Test("expanded children keep distinct local structural paths")
  func expandedChildrenKeepDistinctLocalStructuralPaths() throws {
    let resolved = resolveBuilderSlotProbe(
      BuilderSlotConditionalProbe(expanded: true)
    )
    let first = try builderSlotTextNode("prefix-0", in: resolved)
    let second = try builderSlotTextNode("prefix-1", in: resolved)

    #expect(first.identity != second.identity)
    #expect(first.structuralPath != second.structuralPath)
    #expect(first.identity.parent == second.identity.parent)
  }

  @Test("declared-child enumeration matches eager slot indexing")
  func declaredChildEnumerationMatchesEagerSlotIndexing() {
    let content = builderSlotMetadataContent(expanded: true)
    let context = ResolveContext(identity: testIdentity("BuilderSlotMetadata"))
    let eager = resolveViewElements(content, in: context)
    var nextIndex = 0
    var enumerated: [ResolvedNode] = []

    enumerateDeclaredChildViews(
      content,
      in: context,
      kindName: "Group",
      nextIndex: &nextIndex
    ) { _, _, resolveOne in
      enumerated.append(resolveOne())
    }

    #expect(enumerated.map(\.identity) == eager.map(\.identity))
    #expect(enumerated.map(\.structuralPath) == eager.map(\.structuralPath))
  }
}

@MainActor
private func resolveBuilderSlotProbe<V: View>(_ view: V) -> ResolvedNode {
  Resolver().resolve(
    view,
    in: .init(identity: testIdentity("BuilderSlotStructural"))
  )
}

private func builderSlotTextNode(
  _ text: String,
  in node: ResolvedNode
) throws -> ResolvedNode {
  try #require(
    builderSlotTextNodes(node).first { candidate in
      if case .text(text) = candidate.drawPayload {
        return true
      }
      return false
    })
}

private func builderSlotTextNodes(_ node: ResolvedNode) -> [ResolvedNode] {
  var nodes: [ResolvedNode] = []
  if case .text = node.drawPayload {
    nodes.append(node)
  }
  for child in node.children {
    nodes.append(contentsOf: builderSlotTextNodes(child))
  }
  return nodes
}

@MainActor
private struct BuilderSlotConditionalProbe: View {
  let expanded: Bool

  var body: some View {
    VStack {
      if expanded {
        Text("prefix-0")
        Text("prefix-1")
      }
      Text("tail")
    }
  }
}

@MainActor
private struct BuilderSlotUnequalBranchProbe: View {
  let usesWideBranch: Bool

  var body: some View {
    VStack {
      if usesWideBranch {
        Text("wide-0")
        Text("wide-1")
        Text("wide-2")
      } else {
        Text("narrow")
      }
      Text("tail")
    }
  }
}

@MainActor
private struct BuilderSlotArrayProbe: View {
  let count: Int

  var body: some View {
    VStack {
      for index in 0..<count {
        Text("array-\(index)")
      }
      Text("tail")
    }
  }
}

@MainActor @ViewBuilder
private func builderSlotMetadataContent(expanded: Bool) -> some View {
  if expanded {
    Text("prefix-0")
    Text("prefix-1")
  }
  Text("tail")
}
