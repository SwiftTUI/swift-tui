import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite("ForEach iteration traversal parity (F127)")
struct ForEachIterationParityTests {
  private struct Row {
    var id: String
    var label: String
  }

  @Test("declared-child enumeration is byte-identical to eager traversal")
  func enumerationMatchesEagerTraversal() {
    let rows = [
      Row(id: "duplicate", label: "first"),
      Row(id: "duplicate", label: "second"),
      Row(id: "unique", label: "third"),
    ]
    let content = ForEach(rows, id: \.id) { Text($0.label) }
    let context = structurallyDivergedContext("Enumeration")

    var eager: [ResolvedNode] = []
    var eagerIndex = 0
    content.appendDeclaredChildren(
      in: context,
      kindName: "ParityChild",
      nextIndex: &eagerIndex,
      into: &eager
    )

    var enumerated: [ResolvedNode] = []
    var enumerationIndex = 0
    content.enumerateDeclaredChildren(
      in: context,
      kindName: "ParityChild",
      nextIndex: &enumerationIndex
    ) { _, _, resolveOne in
      enumerated.append(resolveOne())
    }

    #expect(enumerationIndex == eagerIndex)
    #expect(enumerated.map(\.identity) == eager.map(\.identity))
    #expect(enumerated.map(\.structuralPath) == eager.map(\.structuralPath))
    #expect(enumerated.map(\.entityIdentity) == eager.map(\.entityIdentity))
    #expect(enumerated.map(\.entityStructuralPath) == eager.map(\.entityStructuralPath))
  }

  @Test("indexed-source realization is byte-identical to eager traversal")
  func indexedSourceMatchesEagerTraversal() {
    let rows = [
      Row(id: "duplicate", label: "first"),
      Row(id: "duplicate", label: "second"),
      Row(id: "unique", label: "third"),
    ]
    let content = ForEach(rows, id: \.id) { Text($0.label) }
    let context = structurallyDivergedContext("Indexed")
    let eager = content.resolveElements(in: context)
    let source = ForEachIndexedChildSource(
      data: rows,
      id: \.id,
      content: { Text($0.label) },
      childContext: context
    )
    let indexed = rows.indices.map { source.child(at: $0) }

    #expect(indexed.map(\.identity) == eager.map(\.identity))
    #expect(indexed.map(\.structuralPath) == eager.map(\.structuralPath))
    #expect(indexed.map(\.entityIdentity) == eager.map(\.entityIdentity))
    #expect(indexed.map(\.entityStructuralPath) == eager.map(\.entityStructuralPath))
  }

  @Test("indexed elementIdentity matches the realized occurrence-qualified identity")
  func indexedElementIdentityMatchesRealization() {
    let rows = [
      Row(id: "duplicate", label: "first"),
      Row(id: "duplicate", label: "second"),
    ]
    let source = ForEachIndexedChildSource(
      data: rows,
      id: \.id,
      content: { Text($0.label) },
      childContext: structurallyDivergedContext("ElementIdentity")
    )

    #expect(Set(rows.indices.map { source.elementIdentity(at: $0) }).count == 2)
    for index in rows.indices {
      #expect(source.elementIdentity(at: index) == source.child(at: index).identity)
    }
  }

  @Test("scoped payload identities follow element IDs across reorder")
  func scopedPayloadIdentitiesSurviveReorder() {
    let forward = resolvedScopedRows([
      Row(id: "a", label: "A"), Row(id: "b", label: "B"), Row(id: "c", label: "C"),
    ])
    let reversed = resolvedScopedRows([
      Row(id: "c", label: "C"), Row(id: "b", label: "B"), Row(id: "a", label: "A"),
    ])

    #expect(identityByLabel(forward) == identityByLabel(reversed))
    #expect(entityByLabel(forward) == entityByLabel(reversed))
  }

  @Test("portal payload identities follow element IDs across reorder")
  func portalPayloadIdentitiesSurviveReorder() {
    let forward = resolvedPortalRows([
      Row(id: "a", label: "A"), Row(id: "b", label: "B"), Row(id: "c", label: "C"),
    ])
    let reversed = resolvedPortalRows([
      Row(id: "c", label: "C"), Row(id: "b", label: "B"), Row(id: "a", label: "A"),
    ])

    #expect(identityByLabel(forward) == identityByLabel(reversed))
    #expect(entityByLabel(forward) == entityByLabel(reversed))
  }

  @Test("portal attachment sequence preserves authored IDs across payload reorder")
  func portalAttachmentSequencePreservesAuthoredIDs() {
    let forward = resolvedPortalSequenceRows([
      Row(id: "a", label: "A"), Row(id: "b", label: "B"), Row(id: "c", label: "C"),
    ])
    let reversed = resolvedPortalSequenceRows([
      Row(id: "c", label: "C"), Row(id: "b", label: "B"), Row(id: "a", label: "A"),
    ])

    #expect(identityByLabel(forward) == identityByLabel(reversed))
    #expect(entityByLabel(forward) == entityByLabel(reversed))
  }

  @Test("all declared consumers preserve empty and group splicing byte-for-byte")
  func declaredConsumersPreserveIterationConsumption() {
    let rows = [
      Row(id: "duplicate", label: "A"),
      Row(id: "skip", label: "skip"),
      Row(id: "duplicate", label: "B"),
    ]
    let content = ForEach(rows, id: \.id) { row in
      if row.label == "skip" {
        EmptyView()
      } else {
        Text("\(row.label)-1")
        Text("\(row.label)-2")
      }
    }
    let placementRoot = ResolveContext(
      identity: testIdentity("ForEachParity", "DeclaredConsumption")
    )
    let eager = content.resolveElements(
      in: placementRoot.indexedChild(
        kind: .init(rawValue: "Group"),
        index: 0
      )
    )
    let scoped = scopedDeclaredBuilderChildren(from: content)
      .enumerated()
      .flatMap { index, payload in
        payload.resolveElements(
          in: placementRoot.indexedChild(
            kind: .init(rawValue: "ScopedPayload"),
            index: index
          ),
          placementRoot: placementRoot
        )
      }
    let portal = portalDeclaredBuilderChildren(from: content)
      .enumerated()
      .flatMap { index, payload in
        payload.resolveElements(
          in: placementRoot.indexedChild(
            kind: .init(rawValue: "PortalPayload"),
            index: index
          ),
          placementRoot: placementRoot
        )
      }

    #expect(eager.compactMap(nodeText) == ["A-1", "A-2", "B-1", "B-2"])
    #expect(scoped.map(\.identity) == eager.map(\.identity))
    #expect(scoped.map(\.structuralPath) == eager.map(\.structuralPath))
    #expect(scoped.map(\.entityIdentity) == eager.map(\.entityIdentity))
    #expect(scoped.map(\.entityStructuralPath) == eager.map(\.entityStructuralPath))
    #expect(portal.map(\.identity) == eager.map(\.identity))
    #expect(portal.map(\.structuralPath) == eager.map(\.structuralPath))
    #expect(portal.map(\.entityIdentity) == eager.map(\.entityIdentity))
    #expect(portal.map(\.entityStructuralPath) == eager.map(\.entityStructuralPath))
  }

  @Test("scoped payloads keep sibling ForEach entity scopes disjoint")
  func scopedPayloadSiblingScopesStayDisjoint() {
    let payloads = scopedDeclaredBuilderChildren(from: siblingForEachContent())
    let placementRoot = ResolveContext(
      identity: testIdentity("ForEachParity", "ScopedSiblings")
    )
    let resolved = payloads.enumerated().map { index, payload in
      payload.resolve(
        in: placementRoot.indexedChild(
          kind: .init(rawValue: "Payload"),
          index: index
        ),
        placementRoot: placementRoot
      )
    }

    #expect(resolved.count == 2)
    #expect(Set(resolved.map(\.identity)).count == 2)
    #expect(Set(resolved.compactMap(\.entityIdentity)).count == 2)
  }

  @Test("portal payloads keep sibling ForEach entity scopes disjoint")
  func portalPayloadSiblingScopesStayDisjoint() {
    let payloads = portalDeclaredBuilderChildren(from: siblingForEachContent())
    let placementRoot = ResolveContext(
      identity: testIdentity("ForEachParity", "PortalSiblings")
    )
    let resolved = payloads.enumerated().map { index, payload in
      payload.resolve(
        in: placementRoot.indexedChild(
          kind: .init(rawValue: "Payload"),
          index: index
        ),
        placementRoot: placementRoot
      )
    }

    #expect(resolved.count == 2)
    #expect(Set(resolved.map(\.identity)).count == 2)
    #expect(Set(resolved.compactMap(\.entityIdentity)).count == 2)
  }

  private func resolvedScopedRows(_ rows: [Row]) -> [ResolvedNode] {
    let payloads = scopedDeclaredBuilderChildren(
      from: ForEach(rows, id: \.id) { Text($0.label) }
    )
    let placementRoot = ResolveContext(
      identity: testIdentity("ForEachParity", "ScopedReorder")
    )
    return payloads.enumerated().map { index, payload in
      payload.resolve(
        in: placementRoot.indexedChild(
          kind: .init(rawValue: "Payload"),
          index: index
        ),
        placementRoot: placementRoot
      )
    }
  }

  private func resolvedPortalRows(_ rows: [Row]) -> [ResolvedNode] {
    let payloads = portalDeclaredBuilderChildren(
      from: ForEach(rows, id: \.id) { Text($0.label) }
    )
    let placementRoot = ResolveContext(
      identity: testIdentity("ForEachParity", "PortalReorder")
    )
    return payloads.enumerated().map { index, payload in
      payload.resolve(
        in: placementRoot.indexedChild(
          kind: .init(rawValue: "Payload"),
          index: index
        ),
        placementRoot: placementRoot
      )
    }
  }

  private func resolvedPortalSequenceRows(_ rows: [Row]) -> [ResolvedNode] {
    let payloads = portalDeclaredBuilderChildren(
      from: ForEach(rows, id: \.id) { Text($0.label) }
    ).map { PortalAttachmentPayload($0) }
    let sequence = PortalAttachmentSequenceView(payloads: payloads)
    var resolved: [ResolvedNode] = []
    var nextIndex = 0
    sequence.appendDeclaredChildren(
      in: ResolveContext(
        identity: testIdentity("ForEachParity", "PortalSequence")
      ),
      kindName: "VStack",
      nextIndex: &nextIndex,
      into: &resolved
    )
    return resolved
  }

  private func identityByLabel(_ nodes: [ResolvedNode]) -> [String: Identity] {
    Dictionary(
      uniqueKeysWithValues: nodes.compactMap { node in
        nodeText(node).map { ($0, node.identity) }
      })
  }

  private func entityByLabel(_ nodes: [ResolvedNode]) -> [String: EntityIdentity] {
    Dictionary(
      uniqueKeysWithValues: nodes.compactMap { node in
        guard let label = nodeText(node), let entityIdentity = node.entityIdentity else {
          return nil
        }
        return (label, entityIdentity)
      })
  }

  private func structurallyDivergedContext(_ suffix: String) -> ResolveContext {
    ResolveContext(
      identity: testIdentity("ForEachParity", "Structural", suffix)
    ).replacingIdentity(
      with: testIdentity("ForEachParity", "Logical", suffix)
    )
  }

  private func nodeText(_ node: ResolvedNode) -> String? {
    if case .text(let value) = node.drawPayload {
      return value
    }
    return node.children.lazy.compactMap(nodeText).first
  }

  @ViewBuilder
  private func siblingForEachContent() -> some View {
    ForEach([Row(id: "same", label: "left")], id: \.id) { Text($0.label) }
    ForEach([Row(id: "same", label: "right")], id: \.id) { Text($0.label) }
  }
}
