import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Campaign F3 item activation identity", .serialized)
struct AdversarialSetEItemLifetimeTests {
  @Test(arguments: Array(41...50))
  func itemLifetime(id: Int) throws {
    let probe = SetEItemProbe()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setE", String(id)), size: .init(width: 60, height: 20)
    ) { SetEItemLifetimeRoot(kind: id, probe: probe) }
    defer { h.shutdown() }
    let baseline = setECensus(h)
    let depth = h.focusModalRestorationStackCount
    _ = try h.clickText("Open")
    try #require(h.frame.contains("Payload 0"))
    try #require(h.frame.contains("Value 0"))
    let mounted = setECensus(h)
    for replacement in 1...3 {
      _ = try h.clickText("Bump")
      #expect(h.frame.contains("Value \(id < 46 ? replacement : 1)"))
      _ = try h.clickText("Replace")
      #expect(h.frame.contains("Payload \(replacement)"))
      #expect(h.frame.contains("Value \(id < 46 ? replacement : 0)"))
      #expect(probe.appeared == (id < 46 ? 1 : replacement + 1))
      #expect(probe.disappeared == (id < 46 ? 0 : replacement))
      #expect(probe.dismissed == (id < 46 ? 0 : replacement))
      #expect(setECensus(h) == mounted)
    }
    _ = try h.pressKey(.init(.escape))
    #expect(probe.dismissed == (id < 46 ? 1 : 4))
    #expect(probe.disappeared == probe.appeared)
    #expect(setECensus(h) == baseline)
    #expect(h.focusModalRestorationStackCount == depth)
  }
}

@MainActor
private final class SetEItemProbe {
  var appeared = 0
  var disappeared = 0
  var dismissed = 0
}

private struct SetERefreshItem: Identifiable, Sendable {
  let id: Int
  let payload: Int
}

private struct SetERefreshContent: View {
  let item: SetERefreshItem
  let replace: @MainActor () -> Void
  let probe: SetEItemProbe
  @State private var value = 0
  var body: some View {
    VStack {
      Text("Payload \(item.payload)")
      Text("Value \(value)")
      Button("Bump") { value += 1 }
      Button("Replace", action: replace)
    }.onAppear { probe.appeared += 1 }.onDisappear { probe.disappeared += 1 }
  }
}

private struct SetEItemLifetimeRoot: View {
  let kind: Int
  let probe: SetEItemProbe
  @State private var item: SetERefreshItem?
  private var opener: some View { Button("Open") { item = .init(id: 0, payload: 0) } }
  private func content(_ value: SetERefreshItem) -> some View {
    SetERefreshContent(
      item: value,
      replace: {
        item = .init(id: value.id + (kind < 46 ? 0 : 1), payload: value.payload + 1)
      }, probe: probe)
  }
  @ViewBuilder var body: some View {
    switch (kind - 41) % 5 {
    case 0:
      opener.sheet(item: $item, onDismiss: { probe.dismissed += 1 }) { content($0) }
    case 1:
      opener.fullScreenCover(item: $item, onDismiss: { probe.dismissed += 1 }) { content($0) }
    case 2:
      opener.popover(item: $item, onDismiss: { probe.dismissed += 1 }) { content($0) }
    case 3:
      opener.alert("Notice", item: $item, onDismiss: { probe.dismissed += 1 }) {
        content($0)
      } message: { _ in
        Text("Message")
      }
    default:
      opener.confirmationDialog("Confirm", item: $item, onDismiss: { probe.dismissed += 1 }) {
        content($0)
      } message: { _ in
        Text("Message")
      }
    }
  }
}
