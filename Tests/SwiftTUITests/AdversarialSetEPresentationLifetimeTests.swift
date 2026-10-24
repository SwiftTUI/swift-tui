import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Campaign F3 presentation source lifetimes", .serialized)
struct AdversarialSetEPresentationLifetimeTests {
  @Test(arguments: Array(31...40))
  func presentationLifetime(id: Int) throws {
    let probe = SetEPresentationProbe()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setE", String(id)), size: .init(width: 60, height: 20)
    ) { SetEPresentationLifetimeRoot(kind: id, probe: probe) }
    defer { h.shutdown() }
    let baseline = setECensus(h)
    let restorationDepth = h.focusModalRestorationStackCount
    var mounted: [String: Int]?
    #expect(probe.dismissed == 0)
    for cycle in 1...3 {
      _ = try h.clickText("Open")
      try #require(h.frame.contains("Subject"))
      #expect(probe.appeared == cycle)
      let current = setECensus(h)
      if let mounted { #expect(current == mounted) } else { mounted = current }
      _ = try h.focusText("Subject")
      _ = try h.pressKey(.init(.character("z")))
      #expect(probe.keys == cycle)
      _ = try h.pressKey(.init(.escape))
      #expect(!h.frame.contains("Subject"))
      #expect(probe.dismissed == cycle)
      #expect(probe.disappeared == cycle)
      #expect(h.focusModalRestorationStackCount == restorationDepth)
      #expect(setECensus(h) == baseline)
      _ = try h.focusText("Open")
      _ = try h.pressKey(.init(.character("z")))
      #expect(probe.keys == cycle)
      #expect(setECensus(h) == baseline)
    }
  }
}

@MainActor
private final class SetEPresentationProbe {
  var appeared = 0
  var disappeared = 0
  var dismissed = 0
  var keys = 0
}

private struct SetEPresentationItem: Identifiable, Sendable { let id: Int }

private struct SetEPresentationLifetimeRoot: View {
  let kind: Int
  let probe: SetEPresentationProbe
  @State private var shown = false
  @State private var item: SetEPresentationItem?
  private var opener: some View {
    Button("Open") {
      shown = true
      item = .init(id: 1)
    }
  }
  private var content: some View {
    Button("Subject") {}
      .onKeyPress(.character("z")) { _ in
        probe.keys += 1
        return .handled
      }
      .onAppear { probe.appeared += 1 }
      .onDisappear { probe.disappeared += 1 }
  }
  @ViewBuilder var body: some View {
    switch kind {
    case 31:
      opener.sheet(isPresented: $shown, onDismiss: { probe.dismissed += 1 }) { content }
    case 32:
      opener.sheet(item: $item, onDismiss: { probe.dismissed += 1 }) { _ in content }
    case 33:
      opener.fullScreenCover(isPresented: $shown, onDismiss: { probe.dismissed += 1 }) { content }
    case 34:
      opener.fullScreenCover(item: $item, onDismiss: { probe.dismissed += 1 }) { _ in content }
    case 35:
      opener.popover(isPresented: $shown, onDismiss: { probe.dismissed += 1 }) { content }
    case 36:
      opener.popover(item: $item, onDismiss: { probe.dismissed += 1 }) { _ in content }
    case 37:
      opener.alert("Notice", isPresented: $shown, onDismiss: { probe.dismissed += 1 }) {
        content
      } message: {
        Text("Message")
      }
    case 38:
      opener.alert("Notice", item: $item, onDismiss: { probe.dismissed += 1 }) { _ in
        content
      } message: { _ in
        Text("Message")
      }
    case 39:
      opener.confirmationDialog("Confirm", isPresented: $shown, onDismiss: { probe.dismissed += 1 })
      {
        content
      } message: {
        Text("Message")
      }
    default:
      opener.confirmationDialog("Confirm", item: $item, onDismiss: { probe.dismissed += 1 }) { _ in
        content
      } message: { _ in
        Text("Message")
      }
    }
  }
}
