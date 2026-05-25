import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct SurfaceDamageContractTests {
  @Test("sheet open and dismiss damage covers actual raster diffs")
  func sheetOpenAndDismissDamageCoversActualRasterDiffs() throws {
    let rootIdentity = testIdentity("SurfaceDamageSheetRoot")
    let sourceIdentity = testIdentity("SurfaceDamageSheetSource")
    let terminalSize = CellSize(width: 48, height: 12)
    let surface = SurfaceDamageRecordingSurface(surfaceSize: terminalSize)
    let stateContainer = StateContainer(
      initialState: SurfaceDamagePresentationState(isPresented: false, count: 1),
      invalidationIdentities: [sourceIdentity]
    )
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: surface,
      terminalInputReader: SurfaceDamageEmptyInputReader(),
      signalReader: SurfaceDamageEmptySignalReader(),
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    ) { state, _ in
      SurfaceDamageSheetFixture(
        state: state,
        sourceIdentity: sourceIdentity
      )
    }

    focusTracker.clearFocus()
    stateContainer.invalidator = runLoop.scheduler
    focusTracker.invalidator = runLoop.scheduler

    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()

    stateContainer.replace(with: .init(isPresented: true, count: 1))
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    stateContainer.replace(with: .init(isPresented: false, count: 1))
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    guard surface.records.count == 3 else {
      Issue.record("expected initial, open, and dismiss frames")
      return
    }
    let closed = surface.records[0]
    let opened = surface.records[1]
    let dismissed = surface.records[2]

    let openedText = opened.surface.lines.joined(separator: "\n")
    let dismissedText = dismissed.surface.lines.joined(separator: "\n")
    #expect(openedText.contains("Command palette"))
    #expect(openedText.contains("Counter"))
    #expect(!dismissedText.contains("Command palette"))
    #expect(!dismissedText.contains("Counter"))

    assertDamageEqualsActualDiff(
      previous: closed.surface,
      current: opened.surface,
      damage: opened.damage
    )
    assertDamageEqualsActualDiff(
      previous: opened.surface,
      current: dismissed.surface,
      damage: dismissed.damage
    )
  }

  @Test("ordinary text update keeps narrow actual damage")
  func ordinaryTextUpdateKeepsNarrowActualDamage() {
    let renderer = DefaultRenderer()
    let rootIdentity = testIdentity("SurfaceDamageTextRoot")
    let proposal = ProposedSize(width: 32, height: 4)

    let first = renderer.render(
      SurfaceDamageTextFixture(count: 1),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )
    let second = renderer.render(
      SurfaceDamageTextFixture(count: 2),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )

    assertDamageEqualsActualDiff(
      previous: first.rasterSurface,
      current: second.rasterSurface,
      damage: second.presentationDamage
    )
    let diagnostics = second.presentationDamage.map {
      PresentationDamageDiagnostics(
        damage: $0,
        surfaceWidth: second.rasterSurface.size.width
      )
    }
    #expect((diagnostics?.textCellCount ?? Int.max) < 10)
  }
}

private struct SurfaceDamagePresentationState: Equatable, Sendable {
  var isPresented: Bool
  var count: Int
}

private struct SurfaceDamageSheetFixture: View {
  var state: SurfaceDamagePresentationState
  var sourceIdentity: Identity

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Base \(state.count)")
      Text("Content behind overlay")
    }
    .id(sourceIdentity)
    .sheet("Command palette", isPresented: .constant(state.isPresented)) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Command palette")
        Text("Filter commands")
        Text("Counter")
        Text("Life")
      }
    }
  }
}

private struct SurfaceDamageTextFixture: View {
  var count: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Count \(count)")
      Text("Stable")
    }
  }
}

private struct SurfaceDamageRecordedFrame {
  var surface: RasterSurface
  var damage: PresentationDamage?
}

private final class SurfaceDamageRecordingSurface:
  PresentationSurface, DamageAwarePresentationSurface
{
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var records: [SurfaceDamageRecordedFrame] = []

  init(surfaceSize: CellSize) {
    self.surfaceSize = surfaceSize
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    records.append(.init(surface: surface, damage: nil))
    return TerminalPresentationMetrics.rasterHostMetrics(for: surface, damage: nil)
  }

  @discardableResult
  func present(
    _ surface: RasterSurface,
    damage: PresentationDamage?
  ) throws -> TerminalPresentationMetrics {
    records.append(.init(surface: surface, damage: damage))
    return TerminalPresentationMetrics.rasterHostMetrics(for: surface, damage: damage)
  }
}

private final class SurfaceDamageEmptyInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class SurfaceDamageEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private func assertDamageEqualsActualDiff(
  previous: RasterSurface,
  current: RasterSurface,
  damage: PresentationDamage?,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  let expected = RasterSurfaceDamageDiff.diff(previous: previous, current: current)
  #expect(
    damage == expected,
    "expected host damage to equal actual raster diff",
    sourceLocation: sourceLocation
  )
}
