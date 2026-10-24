import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Campaign F3 focus and action-scope departure", .serialized)
struct AdversarialSetEFocusLifetimeTests {
  @Test(arguments: Array(96...100))
  func focusLifetime(id: Int) throws {
    let probe = SetEFocusProbe()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setE", String(id)), size: .init(width: 40, height: 12)
    ) { SetEFocusLifetimeRoot(kind: id, probe: probe) }
    defer { h.shutdown() }
    let baseline = setECensus(h)
    for cycle in 1...3 {
      _ = try h.clickText("Open")
      _ = try h.focusText("Remove self")
      if id == 96 { try #require(h.frame.contains("Boolean true")) }
      if id == 97 { try #require(h.frame.contains("Optional 1")) }
      if id == 98 { try #require(h.defaultFocusRegistrationCount > 1) }
      if id == 99 {
        try #require(h.runLoop.currentFocusedValues[SetELifetimeFocusKey.self] == 7)
        try #require(h.frame.contains("Export 7"))
      }
      if id == 100 {
        _ = try h.drop(paths: [DroppedPath("fixture.txt")])
        #expect(probe.drops == cycle)
      }
      _ = try h.pressKey(.init(.return))
      try #require(!h.frame.contains("Remove self"))
      if id == 96 { #expect(h.frame.contains("Boolean false")) }
      if id == 97 { #expect(h.frame.contains("Optional nil")) }
      if id == 99 {
        #expect(h.runLoop.currentFocusedValues[SetELifetimeFocusKey.self] == nil)
        #expect(h.frame.contains("Export nil"))
      }
      #expect(setECensus(h) == baseline)
      if id == 100 {
        _ = try h.focusText("Open")
        _ = try h.drop(paths: [DroppedPath("fixture.txt")])
        #expect(probe.drops == cycle)
      }
    }
  }
}

@MainActor
private final class SetEFocusProbe { var drops = 0 }

private enum SetELifetimeFocusKey: FocusedValueKey { typealias Value = Int }

extension FocusedValues {
  fileprivate var setELifetimeValue: Int? {
    get { self[SetELifetimeFocusKey.self] }
    set { self[SetELifetimeFocusKey.self] = newValue }
  }
}

private struct SetEFocusLifetimeRoot: View {
  let kind: Int
  let probe: SetEFocusProbe
  @State private var shown = false
  @FocusState private var booleanFocus: Bool
  @FocusState private var optionalFocus: Int?
  @Namespace private var focusScope
  @FocusedValue(\.setELifetimeValue) private var exported: Int?
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Button("Open") { shown = true }
      Text("Boolean \(booleanFocus)")
      Text("Optional \(optionalFocus.map(String.init) ?? "nil")")
      Text("Export \(exported.map(String.init) ?? "nil")")
      if shown { subject }
    }.focusScope(focusScope)
  }
  private var remover: some View { Button("Remove self") { shown = false } }
  @ViewBuilder private var subject: some View {
    switch kind {
    case 96: remover.focused($booleanFocus)
    case 97: remover.focused($optionalFocus, equals: 1)
    case 98: remover.prefersDefaultFocus(in: focusScope)
    case 99: remover.focusedValue(\.setELifetimeValue, 7)
    default:
      Panel(id: "drop-owner") { remover }.dropDestination { _ in
        probe.drops += 1
        return true
      }
    }
  }
}
