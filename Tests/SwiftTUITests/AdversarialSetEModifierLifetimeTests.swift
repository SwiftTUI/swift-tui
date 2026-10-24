import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Campaign F3 registered modifier lifetimes", .serialized)
struct AdversarialSetEModifierLifetimeTests {
  @Test(arguments: Array(11...20))
  func modifierLifetime(id: Int) throws {
    let probe = SetEModifierProbe()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setE", String(id)), size: .init(width: 40, height: 10)
    ) { SetEModifierLifetimeRoot(kind: id, probe: probe) }
    defer { h.shutdown() }
    let baseline = setECensus(h)
    var mounted: [String: Int]?
    for cycle in 1...3 {
      _ = try h.clickText("Toggle lifetime")
      let current = setECensus(h)
      try #require(current != baseline)
      if let mounted { #expect(current == mounted) } else { mounted = current }
      let point = try #require(h.point(forText: "Subject"))
      _ = try h.focusText("Subject")
      let before = probe.calls
      switch id {
      case 11, 12: _ = try h.pressKey(.init(.character("z")))
      case 13, 14: _ = try h.scrollPointer(at: point, deltaY: 1)
      case 15: _ = try h.movePointer(to: point)
      case 16, 17: _ = try h.click(point)
      case 18:
        let result = try h.requestTermination(.userExit(.init(.escape)))
        #expect(result.disposition == .cancel)
      case 19: #expect(probe.appears == cycle)
      default: #expect(probe.preferences.last == 7)
      }
      if id <= 18 { #expect(probe.calls - before == (id == 12 || id == 14 ? 2 : 1)) }
      _ = try h.clickText("Toggle lifetime")
      #expect(setECensus(h) == baseline)
      if id == 19 { #expect(probe.disappears == cycle) }
      let departed = probe.calls
      _ = try h.pressKey(.init(.character("z")))
      _ = try h.scrollPointer(at: point, deltaY: 1)
      _ = try h.movePointer(to: point)
      _ = try h.click(point)
      let result = try h.requestTermination(.userExit(.init(.escape)))
      #expect(result.disposition == .allow)
      #expect(probe.calls == departed)
      #expect(setECensus(h) == baseline)
    }
  }
}

@MainActor
private final class SetEModifierProbe {
  var calls = 0
  var appears = 0
  var disappears = 0
  var preferences: [Int] = []
}

private struct SetELifetimePreference: PreferenceKey {
  static var defaultValue: Int { 0 }
  static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
}

private struct SetEModifierLifetimeRoot: View {
  let kind: Int
  let probe: SetEModifierProbe
  @State private var mounted = false
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Button("Toggle lifetime") { mounted.toggle() }
      if mounted { subject }
    }
  }
  private var label: some View { Text("Subject").focusable() }
  @ViewBuilder private var subject: some View {
    switch kind {
    case 11:
      label.onKeyPress(.character("z")) { _ in
        probe.calls += 1
        return .handled
      }
    case 12:
      label.onKeyPress(.character("z")) { _ in
        probe.calls += 1
        return .handled
      }
      .onKeyPress(.character("z")) { _ in
        probe.calls += 1
        return .ignored
      }
    case 13:
      label.onScrollWheel { _ in
        probe.calls += 1
        return .handled
      }
    case 14:
      label.onScrollWheel { _ in
        probe.calls += 1
        return .ignored
      }
      .onScrollWheel { _ in
        probe.calls += 1
        return .ignored
      }
    case 15: label.onPointerHover { _ in probe.calls += 1 }
    case 16: label.gesture(TapGesture().onEnded { probe.calls += 1 })
    case 17: label.gesture(SpatialTapGesture().onEnded { _ in probe.calls += 1 })
    case 18:
      label.onTerminationRequest { _ in
        probe.calls += 1
        return .cancel
      }
    case 19: label.onAppear { probe.appears += 1 }.onDisappear { probe.disappears += 1 }
    default:
      label.preference(key: SetELifetimePreference.self, value: 7)
        .onPreferenceChange(SetELifetimePreference.self) { probe.preferences.append($0) }
    }
  }
}
