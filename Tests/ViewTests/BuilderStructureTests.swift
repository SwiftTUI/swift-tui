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

    // The probe gates on `if #available(macOS 999, iOS 999, *)`. Apple
    // platforms see macOS/iOS in the version list, fail the version check,
    // and take the else branch ("Current"). Linux is matched by the `*`
    // wildcard (which means "any platform not explicitly listed"), so the
    // gate succeeds and the if branch ("Future") runs. This is a property
    // of the language probe, not a behavioral difference in the resolver.
    #if canImport(Darwin)
      let expectedLimitedAvailabilityText = "Current"
    #else
      let expectedLimitedAvailabilityText = "Future"
    #endif

    #expect(children.count == 1)
    #expect(resolvedNodeLabelText(from: resolved) == expectedLimitedAvailabilityText)
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
