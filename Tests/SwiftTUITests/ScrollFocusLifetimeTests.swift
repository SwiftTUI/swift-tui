import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct ScrollFocusLifetimeTests {
  @Test(arguments: FocusedChildChange.allCases)
  func survivingLazyRowDoesNotKeepAnUnavailableControlFocused(change: FocusedChildChange) throws {
    let ledger = FocusLifetimeLedger()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("FocusLifetime", change.rawValue),
      size: CellSize(width: 48, height: 12)
    ) { FocusLifetimeFixture(change: change, ledger: ledger) }
    defer { harness.shutdown() }
    _ = try harness.focusText("R04")
    let original = try #require(harness.runLoop.focusTracker.currentFocusIdentity)
    try #require(harness.frame.contains("R04"))
    _ = try harness.pressKey(KeyPress(.character("m"), modifiers: .ctrl))
    try #require(harness.frame.contains("CHANGED"))
    #expect(harness.runLoop.focusTracker.currentFocusIdentity != original)
    _ = try harness.pressKey(KeyPress(.return))
    #expect(!ledger.activated.contains(4), "A removed or disabled control must not activate")
  }

  @Test
  func replacingAnOffsetBindingDoesNotRecoverThePreviousViewport() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("FocusBindingReplacement"),
      size: CellSize(width: 48, height: 12)
    ) { FocusBindingReplacementFixture() }
    defer { harness.shutdown() }
    _ = try harness.focusText("TARGET")
    try #require(harness.frame.contains("TARGET"))
    _ = try harness.pressKey(KeyPress(.character("m"), modifiers: .ctrl))
    try #require(harness.frame.contains("REBOUND"))
    #expect(harness.frame.contains("Secondary: 0"), "\(harness.frame)")
    #expect(!harness.frame.contains("TARGET"))
    _ = try harness.render()
    #expect(harness.frame.contains("Secondary: 0"), "\(harness.frame)")
  }
}

enum FocusedChildChange: String, CaseIterable, Sendable {
  case removed, disabled, replaced
}

@MainActor
private final class FocusLifetimeLedger {
  var activated: [Int] = []
}

private struct FocusLifetimeButtonStyle: ButtonStyle {
  @MainActor
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    configuration.label
  }
}

private struct FocusLifetimeFixture: View {
  let change: FocusedChildChange
  let ledger: FocusLifetimeLedger
  @State private var changed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ScrollView(.vertical) {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<30, id: \.self) { row in
            VStack(alignment: .leading, spacing: 0) {
              if changed && row == 4 && change == .removed {
                Text("REMOVED")
              } else if changed && row == 4 && change == .replaced {
                Button("REPLACEMENT") { ledger.activated.append(44) }.id("replacement")
              } else {
                Button("R" + String(("00" + String(row)).suffix(2))) {
                  ledger.activated.append(row)
                }
                .disabled(changed && row == 4 && change == .disabled)
                .id("original")
              }
            }
            .frame(height: changed && row == 3 ? 6 : 1, alignment: .topLeading)
          }
        }
      }
      .scrollIndicators(.hidden)
      .frame(width: 32, height: changed ? 3 : 6, alignment: .topLeading)
      Text(changed ? "CHANGED" : "INITIAL")
    }
    .buttonStyle(FocusLifetimeButtonStyle())
    .onKeyPress(.character("m"), modifiers: .ctrl) { _ in
      changed = true
      return .handled
    }
  }
}

private struct FocusBindingReplacementFixture: View {
  @State private var primary = ScrollCellOffset.zero
  @State private var secondary = ScrollCellOffset.zero
  @State private var rebound = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ScrollView(.vertical, position: rebound ? $secondary : $primary) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Before").frame(height: rebound ? 12 : 1, alignment: .topLeading)
          Button("TARGET") {}
          ForEach(0..<20, id: \.self) { row in Text("After \(row)") }
        }
      }
      .scrollIndicators(.hidden)
      .frame(width: 32, height: 6, alignment: .topLeading)
      Text(rebound ? "REBOUND" : "INITIAL")
      Text("Secondary: \(secondary.y)")
    }
    .buttonStyle(FocusLifetimeButtonStyle())
    .onKeyPress(.character("m"), modifiers: .ctrl) { _ in
      rebound = true
      return .handled
    }
  }
}
