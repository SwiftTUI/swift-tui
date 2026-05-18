import SwiftTUICore
import SwiftTUIViews
import Testing

@testable import SwiftTUIRuntime

@MainActor
@Suite
struct PipelineDriverParityTests {
  @Test("Sync and async renders of the same view produce equal artifacts")
  func syncAsyncParity() async {
    let proposal = ProposedSize(width: .finite(40), height: .finite(20))
    for entry in RenderDriverCharacterizationTests.matrix {
      let syncRenderer = DefaultRenderer()
      let asyncRenderer = DefaultRenderer()
      let syncArtifacts = syncRenderer.render(entry.view, proposal: proposal)
      let asyncArtifacts = await asyncRenderer.renderAsync(entry.view, proposal: proposal)
      #expect(
        syncArtifacts.rasterSurface == asyncArtifacts.rasterSurface,
        "\(entry.name): sync and async raster must match")
      #expect(
        syncArtifacts.semanticSnapshot == asyncArtifacts.semanticSnapshot,
        "\(entry.name): sync and async semantics must match")
      #expect(
        syncArtifacts.placedTree == asyncArtifacts.placedTree,
        "\(entry.name): sync and async placement must match")
    }
  }

  /// Drives one frame through the synchronous `renderPendingFrames` entry
  /// point and one through the asynchronous `renderPendingFramesAsync` entry
  /// point over equivalent `RunLoop`s. Both entry points delegate to the same
  /// shared per-frame body (ADR-0021); this pins that their observable
  /// committed result — the frame count and `latestSemanticSnapshot` — stays
  /// identical.
  @Test("Sync and async frame-driver entry points commit equivalent frames")
  func frameDriverEntryPointParity() async throws {
    let proposal = ProposedSize(width: .finite(40), height: .finite(20))
    for entry in RenderDriverCharacterizationTests.matrix {
      // Synchronous entry point.
      let syncRoot = testIdentity("ParitySyncRoot-\(entry.name)")
      let syncTerminal = ParityTestTerminalHost()
      let syncRunLoop = RunLoop<Int, AnyView>(
        rootIdentity: syncRoot,
        presentationSurface: syncTerminal,
        terminalInputReader: InjectedTerminalInputReader(),
        scheduler: FrameScheduler(),
        stateContainer: StateContainer(initialState: 0, invalidationIdentities: [syncRoot]),
        focusTracker: FocusTracker(invalidationIdentities: [syncRoot]),
        proposal: proposal,
        viewBuilder: ScopedMapper { _ in entry.view }
      )
      syncRunLoop.focusTracker.invalidator = syncRunLoop.scheduler
      syncRunLoop.scheduler.requestInvalidation(of: [syncRoot])
      var syncFrames = 0
      try syncRunLoop.renderPendingFrames(renderedFrames: &syncFrames)

      // Asynchronous entry point.
      let asyncRoot = testIdentity("ParityAsyncRoot-\(entry.name)")
      let asyncTerminal = ParityTestTerminalHost()
      let asyncRunLoop = RunLoop<Int, AnyView>(
        rootIdentity: asyncRoot,
        presentationSurface: asyncTerminal,
        terminalInputReader: InjectedTerminalInputReader(),
        scheduler: FrameScheduler(),
        stateContainer: StateContainer(initialState: 0, invalidationIdentities: [asyncRoot]),
        focusTracker: FocusTracker(invalidationIdentities: [asyncRoot]),
        proposal: proposal,
        viewBuilder: ScopedMapper { _ in entry.view }
      )
      asyncRunLoop.focusTracker.invalidator = asyncRunLoop.scheduler
      asyncRunLoop.scheduler.requestInvalidation(of: [asyncRoot])
      var asyncFrames = 0
      try await asyncRunLoop.renderPendingFramesAsync(renderedFrames: &asyncFrames)

      #expect(
        syncFrames == asyncFrames,
        "\(entry.name): sync and async entry points must commit the same frame count")
      #expect(
        syncRunLoop.latestSemanticSnapshot == asyncRunLoop.latestSemanticSnapshot,
        "\(entry.name): sync and async entry points must commit the same semantic snapshot")
    }
  }
}

/// Minimal raster-only presentation surface for driving the frame-driver
/// entry points in parity tests.
private final class ParityTestTerminalHost: PresentationSurface, DamageAwarePresentationSurface {
  let surfaceSize = CellSize(width: 40, height: 20)
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  var graphicsCapabilities: TerminalGraphicsCapabilities { .init() }
  var theme: Theme? { nil }
  private(set) var presentedSurfaces: [RasterSurface] = []

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    presentedSurfaces.append(surface)
    return TerminalPresentationMetrics(
      bytesWritten: 0,
      linesTouched: surface.lines.count,
      cellsChanged: 0
    )
  }

  @discardableResult
  func present(
    _ surface: RasterSurface,
    damage _: PresentationDamage?
  ) throws -> TerminalPresentationMetrics {
    try present(surface)
  }
}
