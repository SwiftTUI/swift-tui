import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct ScrollFocusRecoveryTests {
  @Test
  func returningFocusRevealsAnEarlierControl() throws {
    let ledger = RecoveryActivationLedger()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ReturningFocusRecovery"), size: CellSize(width: 48, height: 12)
    ) { RecoveryReturningFocusFixture(ledger: ledger) }
    defer { harness.shutdown() }
    _ = try harness.focusText("TARGET")
    let originalFocus = harness.runLoop.focusTracker.currentFocusIdentity
    _ = try harness.clickText("Away")
    try #require(harness.runLoop.focusTracker.currentFocusIdentity != originalFocus)
    try #require(!harness.frame.contains("TARGET"), "Away must hide target")
    _ = try harness.pressKey(KeyPress(.character("r"), modifiers: .ctrl))
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == originalFocus)
    #expect(
      harness.frame.contains("TARGET"), "returning focus must reveal target:\n\(harness.frame)")
    _ = try harness.pressKey(KeyPress(.return))
    #expect(ledger.activated == [1])
  }

  @Test(arguments: RecoveryScrollContainer.allCases, RecoveryGeometryChange.allCases)
  func activeControlSurvivesGeometryChange(
    container: RecoveryScrollContainer, change: RecoveryGeometryChange
  ) throws {
    let ledger = RecoveryActivationLedger()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ScrollFocusRecovery", container.rawValue, change.rawValue),
      size: CellSize(width: 64, height: 14)
    ) {
      RecoveryScrollFixture(container: container, change: change, ledger: ledger)
    }
    defer { harness.shutdown() }
    _ = try harness.focusText("R04")
    let originalFocus = harness.runLoop.focusTracker.currentFocusIdentity
    try #require(originalFocus != nil)
    try #require(harness.frame.contains("R04"))
    _ = try harness.pressKey(KeyPress(.character("g"), modifiers: .ctrl))
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == originalFocus)
    #expect(
      harness.frame.contains("R04"), "active control should remain visible:\n\(harness.frame)")
    _ = try harness.pressKey(KeyPress(.return))
    #expect(ledger.activated == [4])
  }

  @Test(arguments: RecoveryScrollContainer.allCases)
  func standardButtonStyleSurvivesViewportShrink(container: RecoveryScrollContainer) throws {
    let ledger = RecoveryActivationLedger()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StandardStyleFocusRecovery", container.rawValue),
      size: CellSize(width: 64, height: 14)
    ) {
      RecoveryScrollFixture(
        container: container, change: .viewportShrink, ledger: ledger, usesStandardStyle: true)
    }
    defer { harness.shutdown() }
    _ = try harness.focusText("R04")
    let originalFocus = try #require(harness.runLoop.focusTracker.currentFocusIdentity)
    try #require(harness.frame.contains("R04"))
    _ = try harness.pressKey(KeyPress(.character("g"), modifiers: .ctrl))
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == originalFocus)
    #expect(harness.frame.contains("R04"))
    _ = try harness.pressKey(KeyPress(.return))
    #expect(ledger.activated == [4])
  }

  @Test(arguments: [RecoveryScrollContainer.lazyVertical, .lazyHorizontal])
  func lazyRecoveryDoesNotEvaluateTheDataset(container: RecoveryScrollContainer) throws {
    let ledger = RecoveryActivationLedger()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("BoundedLazyFocusRecovery", container.rawValue),
      size: CellSize(width: 64, height: 14)
    ) {
      RecoveryScrollFixture(
        container: container, change: .precedingGrowth, ledger: ledger, rowCount: 1_000)
    }
    defer { harness.shutdown() }
    _ = try harness.focusText("R04")
    let originalFocus = try #require(harness.runLoop.focusTracker.currentFocusIdentity)
    _ = try harness.pressKey(KeyPress(.character("g"), modifiers: .ctrl))
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == originalFocus)
    #expect(harness.frame.contains("R04"))
    _ = try harness.pressKey(KeyPress(.return))
    #expect(ledger.activated == [4])
    #expect(ledger.rowEvaluations < 512)
    #expect(ledger.evaluatedRows.count < 64, "Recovery must evaluate a bounded viewport band")
    #expect(!ledger.evaluatedRows.contains(999))
  }

}

enum RecoveryScrollContainer: String, CaseIterable, Sendable {
  case eagerVertical, lazyVertical, eagerHorizontal, lazyHorizontal

  var isHorizontal: Bool {
    self == .eagerHorizontal || self == .lazyHorizontal
  }
}

enum RecoveryGeometryChange: String, CaseIterable, Sendable {
  case precedingGrowth, viewportShrink
}

@MainActor
private final class RecoveryActivationLedger {
  var activated: [Int] = []
  var evaluatedRows: Set<Int> = []
  var rowEvaluations = 0
}

@MainActor
private struct RecoveryScrollFixture: View {
  let container: RecoveryScrollContainer
  let change: RecoveryGeometryChange
  let ledger: RecoveryActivationLedger
  var usesStandardStyle = false
  var rowCount = 20
  @State private var changed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ScrollView(container.isHorizontal ? .horizontal : .vertical) {
        content
      }
      .scrollIndicators(.hidden)
      .frame(
        width: container.isHorizontal && changed && change == .viewportShrink ? 24 : 48,
        height: !container.isHorizontal && changed && change == .viewportShrink ? 3 : 6,
        alignment: .topLeading)
      Text(changed ? "CHANGED" : "INITIAL")
    }
    .buttonStyle(buttonStyle)
    .onKeyPress(.character("g"), modifiers: .ctrl) { _ in
      changed = true
      return .handled
    }
  }

  private var buttonStyle: AnyButtonStyle {
    if usesStandardStyle { return .automatic }
    return AnyButtonStyle(RecoveryLabelButtonStyle())
  }

  @ViewBuilder
  private var content: some View {
    switch container {
    case .eagerVertical:
      VStack(alignment: .leading, spacing: 0) { rows }
    case .lazyVertical:
      LazyVStack(alignment: .leading, spacing: 0) { rows }
    case .eagerHorizontal:
      HStack(alignment: .top, spacing: 0) { rows }
    case .lazyHorizontal:
      LazyHStack(alignment: .top, spacing: 0) { rows }
    }
  }

  private var rows: some View {
    ForEach(0..<rowCount, id: \.self) { row in
      let _ = ledger.evaluatedRows.insert(row)
      let _ = { ledger.rowEvaluations += 1 }()
      let grew = changed && change == .precedingGrowth && row == 3
      Button {
        ledger.activated.append(row)
      } label: {
        Text("R" + String(("00" + String(row)).suffix(2)))
          .frame(
            width: container.isHorizontal ? (grew ? 32 : 8) : 12,
            height: container.isHorizontal ? 2 : (grew ? 6 : 1),
            alignment: .topLeading)
      }
      .id(row)
    }
  }
}

private struct RecoveryLabelButtonStyle: ButtonStyle {
  @MainActor
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    configuration.label
  }
}

@MainActor
private struct RecoveryReturningFocusFixture: View {
  let ledger: RecoveryActivationLedger
  @State private var position = ScrollCellOffset.zero
  @FocusState private var targetFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Away") { position = ScrollCellOffset(x: 0, y: 12) }
      ScrollView(.vertical, position: $position) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Before")
          Button("TARGET") { ledger.activated.append(1) }.focused($targetFocused)
          ForEach(0..<20, id: \.self) { row in Text("Tail \(row)") }
        }
      }
      .scrollIndicators(.hidden)
      .frame(width: 32, height: 4, alignment: .topLeading)
    }
    .buttonStyle(RecoveryLabelButtonStyle())
    .onKeyPress(.character("r"), modifiers: .ctrl) { _ in
      targetFocused = true
      return .handled
    }
  }
}
