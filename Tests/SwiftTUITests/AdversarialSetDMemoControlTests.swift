import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Campaign F2 memo reuse retains control registrations", .serialized)
struct AdversarialSetDMemoControlTests {
  @Test(arguments: Array(41...50))
  func memoControl(id: Int) throws {
    let kind = id - 40
    let probe = SetDMemoProbe()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setD", String(id)), size: .init(width: 40, height: 8)
    ) {
      VStack {
        SetDMemoControl(kind: kind, probe: probe).equatable()
        Text("sibling \(probe.tick)")
      }
    }
    defer { h.shutdown() }
    let identity = try #require(h.runLoop.focusTracker.focusRegions.first?.identity)
    _ = try h.focus(identity)
    let number = try #require(probe.number)
    let flag = try #require(probe.flag)
    let text = try #require(probe.text)
    let numberSource = try #require(number.bindingSourceID)
    let flagSource = try #require(flag.bindingSourceID)
    let textSource = try #require(text.bindingSourceID)
    number.wrappedValue = 1
    flag.wrappedValue = true
    text.wrappedValue = "seedA"
    _ = try h.render()
    let before = probe.bodies
    try #require(before > 0)
    probe.tick = 1
    _ = try h.renderAfterExternalMutation()
    #expect(h.frame.contains("sibling 1"))
    if kind == 1 { #expect(probe.bodies == before) }
    #expect(probe.number?.bindingSourceID == numberSource)
    #expect(probe.flag?.bindingSourceID == flagSource)
    #expect(probe.text?.bindingSourceID == textSource)
    #expect(probe.number?.wrappedValue == 1)
    #expect(probe.flag?.wrappedValue == true)
    #expect(probe.text?.wrappedValue == "seedA")
    #expect(h.runLoop.focusTracker.currentFocusIdentity == identity)
    switch kind {
    case 1, 10: _ = try h.pressKey(.init(.return))
    case 2: _ = try h.pressKey(.init(.space))
    case 3, 4, 6: _ = try h.pressKey(.init(.arrowRight))
    case 5: _ = try h.pressKey(.init(.arrowDown))
    default:
      _ = try h.pressKey(.init(.end))
      _ = try h.pressKey(.init(.character("z")))
    }
    switch kind {
    case 1, 3...6: #expect(probe.number?.wrappedValue == 2)
    case 2, 10: #expect(probe.flag?.wrappedValue == false)
    default: #expect(probe.text?.wrappedValue == "seedAz")
    }
  }
}

@MainActor
private final class SetDMemoProbe {
  var bodies = 0
  var tick = 0
  var number: Binding<Int>?
  var flag: Binding<Bool>?
  var text: Binding<String>?
}

private struct SetDMemoControl: View, Equatable {
  let kind: Int
  let probe: SetDMemoProbe
  @State private var number = 0
  @State private var flag = false
  @State private var text = "seed"
  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.kind == rhs.kind && lhs.probe === rhs.probe
  }
  var body: some View {
    probe.bodies += 1
    probe.number = $number
    probe.flag = $flag
    probe.text = $text
    return SetDControlForm(kind: kind, number: $number, flag: $flag, text: $text)
  }
}
