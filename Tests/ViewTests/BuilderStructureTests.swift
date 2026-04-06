import Testing

@testable import Core
@testable import View

@MainActor
@Suite
struct BuilderStructureTests {
  @Test("typed traversal preserves nested builder child order")
  func typedTraversalPreservesNestedBuilderChildOrder() {
    let resolved = Resolver().resolve(
      HStack {
        nestedBuilderProbe()
      },
      in: .init(identity: testIdentity("BuilderStructure", "TypedTraversal"))
    )

    #expect(resolved.kind == .view("HStack"))
    #expect(resolved.children.map(resolvedNodeLabelText(from:)) == ["A", "B", "C", "D"])
  }

  @Test("erased declared builder children preserve nested builder output order")
  func erasedDeclaredBuilderChildrenPreserveNestedBuilderOutputOrder() {
    let resolved = Resolver().resolve(
      combinedView(
        from: erasedDeclaredBuilderChildren(from: nestedBuilderProbe()),
        kindName: "ErasedProbe"
      ),
      in: .init(identity: testIdentity("BuilderStructure", "ErasedTraversal"))
    )

    #expect(resolved.kind == .view("ErasedProbe"))
    #expect(resolvedNodeLabelText(from: resolved) == "A B C D")
  }

  @Test("deferred declared builder children preserve nested builder output order")
  func deferredDeclaredBuilderChildrenPreserveNestedBuilderOutputOrder() {
    let resolved = Resolver().resolve(
      DeferredPayloadGroupView(
        kindName: "DeferredProbe",
        payloads: deferredDeclaredBuilderChildren(from: nestedBuilderProbe())
      ),
      in: .init(identity: testIdentity("BuilderStructure", "DeferredTraversal"))
    )

    #expect(resolved.kind == .view("DeferredProbe"))
    #expect(resolvedNodeLabelText(from: resolved) == "A B C D")
  }

  @Test("limited-availability builder branches still resolve through the compatibility seam")
  func limitedAvailabilityBuilderBranchesStillResolve() {
    let children = erasedDeclaredBuilderChildren(
      from: limitedAvailabilityBuilderProbe()
    )
    let resolved = Resolver().resolve(
      combinedView(
        from: children,
        kindName: "AvailabilityProbe"
      ),
      in: .init(identity: testIdentity("BuilderStructure", "Availability"))
    )

    #expect(children.count == 1)
    #expect(resolvedNodeLabelText(from: resolved) == "Current")
  }

  @Test("deferred builder children preserve limited-availability output")
  func deferredBuilderChildrenPreserveLimitedAvailabilityOutput() {
    let children = deferredDeclaredBuilderChildren(
      from: limitedAvailabilityBuilderProbe()
    )
    let resolved = Resolver().resolve(
      DeferredPayloadGroupView(
        kindName: "DeferredAvailabilityProbe",
        payloads: children
      ),
      in: .init(identity: testIdentity("BuilderStructure", "DeferredAvailability"))
    )

    #expect(children.count == 1)
    #expect(resolvedNodeLabelText(from: resolved) == "Current")
  }
}

@MainActor
@ViewBuilder
private func nestedBuilderProbe() -> some View {
  Text("A")

  if true {
    Text("B")
  }

  ForEach(["C", "D"], id: \.self) { value in
    Text(value)
  }

  if false {
    Text("Skipped")
  }
}

@MainActor
@ViewBuilder
private func limitedAvailabilityBuilderProbe() -> some View {
  if #available(macOS 999, iOS 999, *) {
    Text("Future")
  } else {
    Text("Current")
  }
}
