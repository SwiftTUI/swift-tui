import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct PortalIdentityTriageTests {
  @Test("same exact IDs in different ForEach scopes present independent sheets")
  func independentScopedSheets() {
    let renderer = DefaultRenderer()
    let shared = testIdentity("SharedSheetSource")
    let artifacts = renderer.render(
      VStack {
        ForEach(0..<1) { _ in
          Text("Source A").id(shared)
            .sheet(isPresented: .constant(true)) { Text("Sheet A") }
        }
        ForEach(0..<1) { _ in
          Text("Source B").id(shared)
            .sheet(isPresented: .constant(true)) { Text("Sheet B") }
        }
      },
      context: .init(identity: testIdentity("ScopedSheets")),
      proposal: .init(width: 60, height: 18))
    let entries = renderer.debugRuntimeSubsystemSnapshot().presentationPortalState.overlayEntries
    #expect(entries.count == 2)
    #expect(Set(entries.map(\.id)).count == 2)
    #expect(artifacts.resolvedTree.descendant(withText: "Sheet A") != nil)
    #expect(artifacts.resolvedTree.descendant(withText: "Sheet B") != nil)
  }

  @Test("a top-level conditional portal sibling preserves the surviving stateful row")
  func conditionalSiblingPreservesState() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PortalConditionalSibling"), size: .init(width: 64, height: 20)
    ) { PortalConditionalRoot() }
    defer { harness.shutdown() }
    _ = try harness.clickText("Increment row")
    #expect(harness.frame.contains("Row count 1"))
    for _ in 0..<4 {
      _ = try harness.clickText("Toggle sibling")
      #expect(harness.frame.contains("Row count 1"))
    }
  }

  @Test("context-rooted portal payload identity survives one to two to one")
  func contextRootedPayloadIdentity() throws {
    let renderer = DefaultRenderer()
    let context = ResolveContext(identity: testIdentity("PayloadGroup"))
    let first = PortalAttachmentPayload { Text("Survivor") }
    let second = PortalAttachmentPayload { Text("Sibling") }
    var identities: [Identity] = []
    for payloads in [[first], [first, second], [first]] {
      let artifacts = renderer.render(
        PortalAttachmentGroupView(kindName: "Payloads", payloads: payloads),
        context: context, proposal: .init(width: 30, height: 6))
      identities.append(
        try #require(artifacts.resolvedTree.descendant(withText: "Survivor")?.identity))
    }
    #expect(Set(identities).count == 1)
  }
}

private struct PortalConditionalRoot: View {
  @State private var sibling = false
  var body: some View {
    Text("Source")
      .sheet(isPresented: .constant(true)) {
        PortalStatefulRow(sibling: $sibling)
        if sibling { Text("Conditional sibling") }
      }
  }
}

private struct PortalStatefulRow: View {
  @Binding var sibling: Bool
  @State private var count = 0
  var body: some View {
    VStack {
      Button("Toggle sibling") { sibling.toggle() }
      Text("Row count \(count)")
      Button("Increment row") { count += 1 }
    }
  }
}

extension ResolvedNode {
  fileprivate func descendant(withText text: String) -> ResolvedNode? {
    var pending = [self]
    while let node = pending.popLast() {
      if case .text(let value) = node.drawPayload, value == text { return node }
      pending.append(contentsOf: node.children)
    }
    return nil
  }
}
