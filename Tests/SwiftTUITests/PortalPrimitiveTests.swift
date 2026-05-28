import Foundation
@_spi(Runners) import SwiftTUIProfiling
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct PortalPrimitiveTests {
  @Test("hoisted task state rerenders hosted content")
  func hoistedTaskStateRerendersHostedContent() async throws {
    let terminal = PortalPrimitiveRecordingTerminalHost(
      surfaceSize: .init(width: 40, height: 12)
    )
    let rootIdentity = testIdentity("PortalTaskRuntimeRoot")
    let diagnosticsURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-portal-task-\(UUID().uuidString).tsv")
    defer {
      try? FileManager.default.removeItem(at: diagnosticsURL)
    }

    let inputReader = PortalPrimitiveAwaitedInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .awaitCondition {
          terminal.frames.contains { $0.contains("Tick 1") }
        },
        .press(KeyPress(.character("d"), modifiers: .ctrl)),
      ])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: inputReader,
      signalReader: PortalPrimitiveEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 40, height: 12),
      viewBuilder: { _, _ in
        PortalTaskProbe()
      }
    )
    runLoop.frameSink = TSVFileSink(path: diagnosticsURL.path)
    #expect(runLoop.frameSink != nil)

    let result = try await runLoop.run()

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(terminal.frames.contains { $0.contains("Inspector") })
    #expect(terminal.frames.contains { $0.contains("Tick 0") })
    #expect(terminal.frames.contains { $0.contains("Tick 1") })

    let diagnostics = try String(contentsOf: diagnosticsURL, encoding: .utf8)
    let rows = portalPrimitiveDiagnosticRows(diagnostics)
    let stateTickRows = rows.dropFirst().filter { row in
      (row["causes"] ?? "").contains("invalidation")
        && (Int(row["invalidated"] ?? "") ?? 0) > 0
    }
    #expect(
      stateTickRows.contains { row in
        resolvedComputedCount(row["resolved_computed"] ?? "") > 0
          && (Int(row["present_cells"] ?? "") ?? 0) > 0
      })
  }

  @Test("hoisted spinner advances across async frames")
  func hoistedSpinnerAdvancesAcrossAsyncFrames() async throws {
    let terminal = PortalPrimitiveRecordingTerminalHost(
      surfaceSize: .init(width: 48, height: 12)
    )
    let rootIdentity = testIdentity("PortalSpinnerRuntimeRoot")
    let advancedGlyphs = Set(["⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"])

    let inputReader = PortalPrimitiveAwaitedInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.return)),
        .awaitCondition {
          terminal.frames.contains { $0.contains("Inspector") && $0.contains("⠋") }
            && terminal.frames.contains { frame in
              advancedGlyphs.contains { frame.contains($0) }
            }
        },
        .press(KeyPress(.character("d"), modifiers: .ctrl)),
      ])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: inputReader,
      signalReader: PortalPrimitiveEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 48, height: 12),
      viewBuilder: { _, _ in
        PortalSpinnerProbe()
      }
    )

    let result = try await runLoop.run()

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(terminal.frames.contains { $0.contains("Inspector") })
    #expect(terminal.frames.contains { $0.contains("⠋") })
    #expect(
      terminal.frames.contains { frame in
        advancedGlyphs.contains { frame.contains($0) }
      })
  }

  @Test("single root hoisted spinner advances across async frames")
  func singleRootHoistedSpinnerAdvancesAcrossAsyncFrames() async throws {
    let terminal = PortalPrimitiveRecordingTerminalHost(
      surfaceSize: .init(width: 48, height: 12)
    )
    let rootIdentity = testIdentity("PortalSingleSpinnerRuntimeRoot")
    let expectedGlyphs = Set(["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"])

    let inputReader = PortalPrimitiveAwaitedInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.return)),
        .awaitCondition {
          observedSpinnerGlyphs(
            in: terminal.frames,
            expectedGlyphs: expectedGlyphs
          ).count >= 7
        },
        .press(KeyPress(.character("d"), modifiers: .ctrl)),
      ])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: inputReader,
      signalReader: PortalPrimitiveEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 48, height: 12),
      viewBuilder: { _, _ in
        PortalSingleSpinnerProbe()
      }
    )

    let result = try await runLoop.run()

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(terminal.frames.contains { $0.contains("Inspector") })
    #expect(terminal.frames.contains { $0.contains("⠋") })
    #expect(
      observedSpinnerGlyphs(
        in: terminal.frames,
        expectedGlyphs: expectedGlyphs
      ).count >= 7)
  }
}

private struct PortalTaskProbe: View {
  @State private var isPresented = true

  var body: some View {
    Text("Base")
      .sheet("Inspector", isPresented: $isPresented) {
        PortalTaskContent()
      }
  }
}

private struct PortalTaskContent: View {
  @State private var tick = 0

  var body: some View {
    Text("Tick \(tick)")
      .task(id: "advance") {
        // Yield once so the update lands on a later runtime turn (the test
        // asserts both the "Tick 0" and "Tick 1" frames) without pinning the
        // hand-off to a wall-clock sleep.
        await Task.yield()
        tick = 1
      }
  }
}

private struct PortalSpinnerProbe: View {
  @State private var isPresented = false

  var body: some View {
    Button("Open") {
      isPresented = true
    }
    .sheet("Inspector", isPresented: $isPresented) {
      HStack(spacing: 1) {
        Spinner(.brailleLoop)
        Text("Loading")
      }
    }
  }
}

private struct PortalSingleSpinnerProbe: View {
  @State private var isPresented = false

  var body: some View {
    Button("Open") {
      isPresented = true
    }
    .sheet("Inspector", isPresented: $isPresented) {
      Spinner(.brailleLoop)
    }
  }
}

private final class PortalPrimitiveRecordingTerminalHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance
  private(set) var frames: [String] = []
  private var lastPresentedSurface: RasterSurface?

  /// Notified after every appended frame, so an awaited input step can
  /// re-check its predicate the instant a frame lands instead of polling.
  let frameSignal = MainActorConditionSignal()

  init(
    surfaceSize: CellSize,
    capabilityProfile: TerminalCapabilityProfile = .previewUnicode,
    appearance: TerminalAppearance = .fallback
  ) {
    self.surfaceSize = surfaceSize
    self.capabilityProfile = capabilityProfile
    self.appearance = appearance
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let renderer = TerminalSurfaceRenderer(
      capabilityProfile: capabilityProfile
    )
    let rendered = renderer.render(surface)
    let plan = TerminalPresentationPlanner(
      capabilityProfile: capabilityProfile
    ).plan(
      previousSurface: lastPresentedSurface,
      currentSurface: surface
    )
    let bytesWritten: Int =
      switch plan.strategy {
      case .fullRepaint:
        TerminalPresentationMetrics.fullRepaint(
          for: surface,
          capabilityProfile: capabilityProfile
        ).bytesWritten
      case .incremental:
        plan.rowBatches.reduce(0) { partial, rowBatch in
          partial
            + cursorSequence(row: rowBatch.row, column: rowBatch.anchorColumn).utf8.count
            + rowBatch.renderedBatch.utf8.count
        }
      }
    let metrics = TerminalPresentationMetrics(
      bytesWritten: bytesWritten,
      linesTouched: plan.linesTouched,
      cellsChanged: plan.cellsChanged,
      strategy: plan.strategy == .fullRepaint ? .fullRepaint : .incremental
    )
    frames.append(rendered.replacingOccurrences(of: "\r\n", with: "\n"))
    lastPresentedSurface = surface
    notifyFrameObservers()
    return metrics
  }

  func write(_ output: String) throws {
    frames.append(output.replacingOccurrences(of: "\r\n", with: "\n"))
    notifyFrameObservers()
  }

  /// The run loop only ever presents on the MainActor; `assumeIsolated`
  /// bridges these nonisolated protocol witnesses to the MainActor-isolated
  /// signal, trapping loudly rather than racing if that ever stops holding.
  private func notifyFrameObservers() {
    let frameSignal = self.frameSignal
    MainActor.assumeIsolated {
      frameSignal.notify()
    }
  }

  private func cursorSequence(row: Int, column: Int) -> String {
    "\u{001B}[\(max(1, row + 1));\(max(1, column + 1))H"
  }
}

private enum PortalPrimitiveInputStep {
  case press(KeyPress)
  /// Suspends the input script until `predicate` holds, re-evaluated only when
  /// the host appends a frame (`frameSignal.notify()`) rather than on a clock.
  case awaitCondition(predicate: @MainActor () -> Bool)
}

private final class PortalPrimitiveAwaitedInputReader: InputReading {
  private let steps: [PortalPrimitiveInputStep]
  private let frameSignal: MainActorConditionSignal

  init(
    frameSignal: MainActorConditionSignal,
    steps: [PortalPrimitiveInputStep]
  ) {
    self.frameSignal = frameSignal
    self.steps = steps
  }

  func events() -> AsyncStream<KeyPress> {
    AsyncStream { continuation in
      let steps = self.steps
      let frameSignal = self.frameSignal
      let task = Task { @MainActor in
        for step in steps {
          switch step {
          case .press(let event):
            continuation.yield(event)
          case .awaitCondition(let predicate):
            await frameSignal.wait(until: predicate)
          }
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

private final class PortalPrimitiveEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private func portalPrimitiveDiagnosticRows(_ text: String) -> [[String: String]] {
  let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
  guard let headerLine = lines.first else {
    return []
  }
  let headers = headerLine.components(separatedBy: "\t")
  return lines.dropFirst().map { line in
    let fields = line.components(separatedBy: "\t")
    var row: [String: String] = [:]
    for (index, header) in headers.enumerated() where index < fields.count {
      row[header] = fields[index]
    }
    return row
  }
}

private func resolvedComputedCount(_ value: String) -> Int {
  Int(value.split(separator: "/").first ?? "") ?? 0
}

private func observedSpinnerGlyphs(
  in frames: [String],
  expectedGlyphs: Set<String>
) -> Set<String> {
  frames.reduce(into: Set<String>()) { partial, frame in
    for glyph in expectedGlyphs where frame.contains(glyph) {
      partial.insert(glyph)
    }
  }
}
