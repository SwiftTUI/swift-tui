import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI builder identity stress behavior", .serialized)
struct FrameworkStressBuilderIdentityTests {
  @Test("stress builder identity 001 empty buildArray emits no phantom node")
  func builder001EmptyBuildArrayEmitsNoPhantomNode() {
    let resolved = resolveBuilder(Builder001Probe())
    #expect(builderTextNodes(resolved).map(builderText) == ["tail"])
    #expect(!builderKinds(resolved).contains(.view("VariadicView")))
  }

  @Test("stress builder identity 002 single buildArray emits exactly one child")
  func builder002SingleBuildArrayEmitsExactlyOneChild() {
    let resolved = resolveBuilder(Builder002Probe())
    #expect(builderTextNodes(resolved).map(builderText) == ["array-0", "tail"])
  }

  @Test("stress builder identity 003 multi buildArray preserves source order")
  func builder003MultiBuildArrayPreservesSourceOrder() {
    let resolved = resolveBuilder(Builder003Probe())
    #expect(builderTextNodes(resolved).map(builderText) == ["array-0", "array-1", "array-2"])
  }

  @Test("stress builder identity 004 nested arrays flatten to unique structural positions")
  func builder004NestedArraysFlattenToUniqueStructuralPositions() {
    let resolved = resolveBuilder(Builder004Probe())
    let nodes = builderTextNodes(resolved)
    #expect(nodes.map(builderText) == ["0-0", "0-1", "1-0", "1-1"])
    #expect(Set(nodes.map(\.structuralPath)).count == 4)
  }

  @Test("stress builder identity 005 absent optional consumes its source position")
  func builder005AbsentOptionalConsumesItsSourcePosition() throws {
    let resolved = resolveBuilder(Builder005Probe(showOptional: false))
    let tail = try #require(builderTextNodes(resolved).first { builderText($0) == "tail" })
    #expect(tail.structuralPath.description.contains("1"))
  }

  @Test("stress builder identity 006 optional appearance preserves trailing identity")
  func builder006OptionalAppearancePreservesTrailingIdentity() throws {
    let absent = resolveBuilder(Builder005Probe(showOptional: false))
    let present = resolveBuilder(Builder005Probe(showOptional: true))
    let absentTail = try #require(builderTextNodes(absent).first { builderText($0) == "tail" })
    let presentTail = try #require(builderTextNodes(present).first { builderText($0) == "tail" })
    #expect(absentTail.identity == presentTail.identity)
    #expect(absentTail.structuralPath == presentTail.structuralPath)
  }

  @Test("stress builder identity 007 explicit empty false branch remains structural")
  func builder007ExplicitEmptyFalseBranchRemainsStructural() {
    let branch: ConditionalContent<Text, EmptyView> = ViewBuilder.buildEither(
      second: EmptyView()
    )
    #expect(!branch.collapsesImplicitEmptyFalseBranch)
  }

  @Test("stress builder identity 008 same type branches have distinct branch paths")
  func builder008SameTypeBranchesHaveDistinctBranchPaths() throws {
    let first = resolveBuilder(Builder008Probe(useFirst: true))
    let second = resolveBuilder(Builder008Probe(useFirst: false))
    let firstNode = try #require(builderTextNodes(first).first)
    let secondNode = try #require(builderTextNodes(second).first)
    #expect(firstNode.identity != secondNode.identity)
    #expect(firstNode.structuralPath != secondNode.structuralPath)
  }

  @Test("stress builder identity 009 nested absent optionals reserve independent positions")
  func builder009NestedAbsentOptionalsReserveIndependentPositions() throws {
    let absent = resolveBuilder(Builder009Probe(showOuter: false, showInner: false))
    let present = resolveBuilder(Builder009Probe(showOuter: true, showInner: true))
    let absentTail = try #require(builderTextNodes(absent).first { builderText($0) == "tail" })
    let presentTail = try #require(builderTextNodes(present).first { builderText($0) == "tail" })
    #expect(absentTail.identity == presentTail.identity)
  }

  @Test("stress builder identity 010 large tuple preserves every pack element")
  func builder010LargeTuplePreservesEveryPackElement() {
    let resolved = resolveBuilder(Builder010Probe())
    #expect(builderTextNodes(resolved).map(builderText) == (0..<12).map { "item-\($0)" })
  }

  @Test("stress builder identity 011 nested tuple and group omit no children")
  func builder011NestedTupleAndGroupOmitNoChildren() {
    let resolved = resolveBuilder(Builder011Probe())
    #expect(builderTextNodes(resolved).map(builderText) == ["A", "B", "C", "D", "E"])
  }

  @Test("stress builder identity 012 group consumes one outer position")
  func builder012GroupConsumesOneOuterPosition() throws {
    let one = resolveBuilder(Builder012Probe(expanded: false))
    let many = resolveBuilder(Builder012Probe(expanded: true))
    let oneTail = try #require(builderTextNodes(one).first { builderText($0) == "tail" })
    let manyTail = try #require(builderTextNodes(many).first { builderText($0) == "tail" })
    #expect(oneTail.identity == manyTail.identity)
    #expect(oneTail.structuralPath == manyTail.structuralPath)
  }

  @Test("stress builder identity 013 nested group indices restart locally")
  func builder013NestedGroupIndicesRestartLocally() throws {
    let resolved = resolveBuilder(Builder013Probe())
    let left = try #require(builderTextNodes(resolved).first { builderText($0) == "left-0" })
    let right = try #require(builderTextNodes(resolved).first { builderText($0) == "right-0" })
    #expect(left.structuralPath != right.structuralPath)
    #expect(left.structuralPath.description.hasSuffix("[0]"))
    #expect(right.structuralPath.description.hasSuffix("[0]"))
  }

  @Test("stress builder identity 014 scoped traversal flattens groups in authored order")
  func builder014ScopedTraversalFlattensGroupsInAuthoredOrder() {
    let payloads = scopedDeclaredBuilderChildren(from: builder014Content())
    let texts = payloads.enumerated().compactMap { index, payload in
      builderTextNodes(
        payload.resolve(in: .init(identity: testIdentity("Builder014", "\(index)")))
      ).first.flatMap(builderText)
    }
    #expect(texts == ["A", "B", "C", "D"])
  }

  @Test("stress builder identity 015 portal traversal matches declared order")
  func builder015PortalTraversalMatchesDeclaredOrder() {
    let payloads = portalDeclaredBuilderChildren(from: builder014Content())
    let texts = payloads.enumerated().compactMap { index, payload in
      builderTextNodes(
        payload.resolve(in: .init(identity: testIdentity("Builder015", "\(index)")))
      ).first.flatMap(builderText)
    }
    #expect(texts == ["A", "B", "C", "D"])
  }

  @Test("stress builder identity 016 foreach reorder preserves element identity")
  func builder016ForEachReorderPreservesElementIdentity() throws {
    let forward = resolveBuilder(Builder016Probe(values: ["A", "B", "C"]))
    let reversed = resolveBuilder(Builder016Probe(values: ["C", "B", "A"]))
    for value in ["A", "B", "C"] {
      let lhs = try #require(builderTextNodes(forward).first { builderText($0) == value })
      let rhs = try #require(builderTextNodes(reversed).first { builderText($0) == value })
      #expect(lhs.identity == rhs.identity)
      #expect(lhs.entityIdentity == rhs.entityIdentity)
    }
  }

  @Test("stress builder identity 017 duplicate foreach ids are occurrence qualified")
  func builder017DuplicateForEachIDsAreOccurrenceQualified() {
    let resolved = resolveBuilder(Builder017Probe())
    let nodes = builderTextNodes(resolved)
    #expect(nodes.count == 3)
    #expect(Set(nodes.map(\.identity)).count == 3)
    #expect(nodes.compactMap(\.entityIdentity).map(\.occurrence) == [0, 1, 2])
  }

  @Test("stress builder identity 018 sibling foreach instances have disjoint scopes")
  func builder018SiblingForEachInstancesHaveDisjointScopes() throws {
    let resolved = resolveBuilder(Builder018Probe())
    let left = try #require(builderTextNodes(resolved).first { builderText($0) == "left-X" })
    let right = try #require(builderTextNodes(resolved).first { builderText($0) == "right-X" })
    #expect(left.entityIdentity != right.entityIdentity)
    #expect(left.entityStructuralPath != right.entityStructuralPath)
  }

  @Test("stress builder identity 019 nested foreach scopes distinguish equal inner ids")
  func builder019NestedForEachScopesDistinguishEqualInnerIDs() {
    let resolved = resolveBuilder(Builder019Probe())
    let nodes = builderTextNodes(resolved)
    #expect(nodes.map(builderText) == ["A-X", "B-X"])
    #expect(Set(nodes.compactMap(\.entityIdentity)).count == 2)
  }

  @Test("stress builder identity 020 empty foreach row preserves occurrence numbering")
  func builder020EmptyForEachRowPreservesOccurrenceNumbering() throws {
    let resolved = resolveBuilder(Builder020Probe())
    let survivor = try #require(builderTextNodes(resolved).first)
    #expect(builderText(survivor) == "visible")
    withKnownIssue("An omitted duplicate-ID row collapses the survivor to occurrence zero") {
      #expect(survivor.entityIdentity?.occurrence == 1)
    }
  }

  @Test("stress builder identity 021 group row attaches entity to every child")
  func builder021GroupRowAttachesEntityToEveryChild() {
    let resolved = resolveBuilder(Builder021Probe())
    let nodes = builderTextNodes(resolved)
    #expect(nodes.count == 2)
    withKnownIssue("Spliced Group row children lose their ForEach entity metadata") {
      #expect(
        nodes.allSatisfy { $0.entityIdentity != nil }
          && Set(nodes.compactMap(\.entityIdentity)).count == 1
      )
    }
  }

  @Test("stress builder identity 022 tuple row shares entity but keeps distinct paths")
  func builder022TupleRowSharesEntityButKeepsDistinctPaths() {
    let resolved = resolveBuilder(Builder022Probe())
    let nodes = builderTextNodes(resolved)
    #expect(nodes.count == 2)
    withKnownIssue("Tuple row children lose their shared ForEach entity metadata") {
      #expect(Set(nodes.compactMap(\.entityIdentity)).count == 1)
    }
    #expect(Set(nodes.map(\.structuralPath)).count == 2)
  }

  @Test("stress builder identity 023 array slice uses element ids not source indices")
  func builder023ArraySliceUsesElementIDsNotSourceIndices() throws {
    let values = ["skip", "A", "B", "C"]
    let slice = values[1...]
    let resolved = resolveBuilder(Builder023Probe(values: slice))
    let nodes = builderTextNodes(resolved)
    #expect(nodes.map(builderText) == ["A", "B", "C"])
    for node in nodes {
      #expect(node.identity.description.contains(builderText(node) ?? "missing"))
    }
  }

  @Test("stress builder identity 024 limited availability keeps one erased payload boundary")
  func builder024LimitedAvailabilityKeepsOneErasedPayloadBoundary() throws {
    let erased = ViewBuilder.buildLimitedAvailability(Text("limited"))
    let resolved = Resolver().resolve(erased, in: .init(identity: testIdentity("Builder024")))
    let payload = try #require(resolved.children.first)
    #expect(resolved.kind == .view("AnyView"))
    #expect(payload.kind == .view("AnyViewPayload"))
    #expect(payload.children.count == 1)
    #expect(payload.children[0].typeDiscriminator != nil)
  }

  @Test("stress builder identity 025 concat applies id at its authored chain stage")
  func builder025ConcatAppliesIDAtAuthoredChainStage() {
    let modifier = Builder025IdentityModifier().concat(Builder025OffsetModifier())
    let resolved = Resolver().resolve(
      Text("target").modifier(modifier),
      in: .init(identity: testIdentity("Builder025"))
    )
    #expect(resolved.identity == testIdentity("Builder025"))
    #expect(resolved.kind == .view("Offset"))
    let padding = builderNodes(resolved).first { $0.kind == .view("Padding") }
    #expect(padding?.identity.isDescendant(of: resolved.identity) == true)
    #expect(padding?.identity.description.contains("ID[\"inner\"]") == true)
  }
}

@MainActor
private func resolveBuilder<V: View>(_ view: V) -> ResolvedNode {
  Resolver().resolve(view, in: .init(identity: testIdentity("BuilderStressRoot")))
}

private func builderText(_ node: ResolvedNode) -> String? {
  if case .text(let value) = node.drawPayload { return value }
  return nil
}

private func builderTextNodes(_ node: ResolvedNode) -> [ResolvedNode] {
  var output: [ResolvedNode] = []
  if builderText(node) != nil { output.append(node) }
  for child in node.children { output.append(contentsOf: builderTextNodes(child)) }
  return output
}

private func builderKinds(_ node: ResolvedNode) -> [NodeKind] {
  [node.kind] + node.children.flatMap(builderKinds)
}

private func builderNodes(_ node: ResolvedNode) -> [ResolvedNode] {
  [node] + node.children.flatMap(builderNodes)
}

@MainActor private struct Builder001Probe: View {
  var body: some View {
    VStack {
      for _ in 0..<0 { Text("never") }
      Text("tail")
    }
  }
}
@MainActor private struct Builder002Probe: View {
  var body: some View {
    VStack {
      for index in 0..<1 { Text("array-\(index)") }
      Text("tail")
    }
  }
}
@MainActor private struct Builder003Probe: View {
  var body: some View { VStack { for index in 0..<3 { Text("array-\(index)") } } }
}
@MainActor private struct Builder004Probe: View {
  var body: some View {
    VStack { for row in 0..<2 { Group { for column in 0..<2 { Text("\(row)-\(column)") } } } }
  }
}
@MainActor private struct Builder005Probe: View {
  let showOptional: Bool
  var body: some View {
    VStack {
      if showOptional { Text("optional") }
      Text("tail")
    }
  }
}
@MainActor private struct Builder007Probe: View {
  let showContent: Bool
  var body: some View { VStack { if showContent { Text("content") } else { EmptyView() } } }
}
@MainActor private struct Builder008Probe: View {
  let useFirst: Bool
  var body: some View { VStack { if useFirst { Text("same") } else { Text("same") } } }
}
@MainActor private struct Builder009Probe: View {
  let showOuter: Bool
  let showInner: Bool
  var body: some View {
    VStack {
      if showOuter { Group { if showInner { Text("inner") } } }
      Text("tail")
    }
  }
}
@MainActor private struct Builder010Probe: View {
  var body: some View {
    VStack {
      Text("item-0")
      Text("item-1")
      Text("item-2")
      Text("item-3")
      Text("item-4")
      Text("item-5")
      Text("item-6")
      Text("item-7")
      Text("item-8")
      Text("item-9")
      Text("item-10")
      Text("item-11")
    }
  }
}
@MainActor private struct Builder011Probe: View {
  var body: some View {
    VStack {
      Text("A")
      Group {
        Text("B")
        Group {
          Text("C")
          Text("D")
        }
      }
      Text("E")
    }
  }
}
@MainActor private struct Builder012Probe: View {
  let expanded: Bool
  var body: some View {
    VStack {
      Group {
        Text("first")
        if expanded {
          Text("second")
          Text("third")
        }
      }
      Text("tail")
    }
  }
}
@MainActor private struct Builder013Probe: View {
  var body: some View {
    VStack {
      Group { Text("left-0") }
      Group { Text("right-0") }
    }
  }
}
@MainActor @ViewBuilder private func builder014Content() -> some View {
  Text("A")
  Group {
    Text("B")
    Text("C")
  }
  Text("D")
}
@MainActor private struct Builder016Probe: View {
  let values: [String]
  var body: some View { VStack { ForEach(values, id: \.self) { Text($0) } } }
}
private struct Builder017Value {
  let id: String
  let label: String
}
@MainActor private struct Builder017Probe: View {
  var body: some View {
    VStack {
      ForEach(
        [
          Builder017Value(id: "X", label: "A"), Builder017Value(id: "X", label: "B"),
          Builder017Value(id: "X", label: "C"),
        ], id: \.id
      ) { Text($0.label) }
    }
  }
}
@MainActor private struct Builder018Probe: View {
  var body: some View {
    VStack {
      ForEach(["X"], id: \.self) { Text("left-\($0)") }
      ForEach(["X"], id: \.self) { Text("right-\($0)") }
    }
  }
}
@MainActor private struct Builder019Probe: View {
  var body: some View {
    VStack {
      ForEach(["A", "B"], id: \.self) { outer in
        ForEach(["X"], id: \.self) { inner in Text("\(outer)-\(inner)") }
      }
    }
  }
}
private struct Builder020Value {
  let id: String
  let visible: Bool
}
@MainActor private struct Builder020Probe: View {
  var body: some View {
    VStack {
      ForEach(
        [Builder020Value(id: "X", visible: false), Builder020Value(id: "X", visible: true)],
        id: \.id
      ) { value in if value.visible { Text("visible") } }
    }
  }
}
@MainActor private struct Builder021Probe: View {
  var body: some View {
    VStack {
      ForEach(["row"], id: \.self) { _ in
        Group {
          Text("A")
          Text("B")
        }
      }
    }
  }
}
@MainActor private struct Builder022Probe: View {
  var body: some View {
    VStack {
      ForEach(["row"], id: \.self) { _ in
        Text("A")
        Text("B")
      }
    }
  }
}
@MainActor private struct Builder023Probe: View {
  let values: ArraySlice<String>
  var body: some View { VStack { ForEach(values, id: \.self) { Text($0) } } }
}
@MainActor private struct Builder025IdentityModifier: ViewModifier {
  func body(content: Content) -> some View { content.padding(1).id("inner") }
}
@MainActor private struct Builder025OffsetModifier: ViewModifier {
  func body(content: Content) -> some View { content.offset(x: 2, y: 1) }
}
