import SwiftTUI
import SwiftTUICore
import Synchronization
import Testing

@testable import SwiftTUITerminal

@MainActor
@Suite("TerminalView layout")
struct TerminalViewLayoutTests {
  @Test("TerminalView accepts the parent's full proposal")
  func acceptsProposal() {
    let session = StubTerminalSession(grid: ForeignGrid.empty)
    let artifacts = DefaultRenderer().render(
      TerminalView(session: session),
      proposal: ProposedSize(width: 40, height: 12)
    )

    #expect(artifacts.rasterSurface.size == CellSize(width: 40, height: 12))
  }

  @Test("draw emits exactly one foreignSurface command at the assigned bounds")
  func emitsForeignSurface() {
    let row = Array(repeating: RasterCell(character: "x"), count: 4)
    let grid = ForeignGrid(
      size: CellSize(width: 4, height: 2),
      cells: Array(repeating: row, count: 2)
    )
    let session = StubTerminalSession(grid: grid)
    let artifacts = DefaultRenderer().render(
      TerminalView(session: session),
      proposal: ProposedSize(width: 4, height: 2)
    )

    let surfaces = allCommands(in: artifacts.drawTree).compactMap { command -> CellRect? in
      if case .foreignSurface(let bounds, _) = command {
        return bounds
      }
      return nil
    }

    #expect(surfaces == [CellRect(origin: .zero, size: CellSize(width: 4, height: 2))])
  }

  @Test("render registers one lifecycle task for start, resize, and event consumption")
  func registersLifecycleTask() {
    let session = StubTerminalSession(grid: ForeignGrid.empty)
    let artifacts = DefaultRenderer().render(
      TerminalView(session: session),
      proposal: ProposedSize(width: 7, height: 3)
    )

    let taskStarts = artifacts.commitPlan.lifecycle.compactMap { entry -> TaskDescriptor? in
      if case .taskStart(let descriptor) = entry.operation {
        return descriptor
      }
      return nil
    }

    #expect(taskStarts.count == 1)
    #expect(taskStarts.first?.priority == .userInitiated)
  }
}

private final class StubTerminalSession: TerminalSession {
  private let snapshotStorage: Mutex<ForeignGrid>

  init(grid: ForeignGrid) {
    snapshotStorage = Mutex(grid)
  }

  var cachedSnapshot: ForeignGrid {
    snapshotStorage.withLock { $0 }
  }

  func start() async throws {}

  func snapshot() async -> ForeignGrid {
    cachedSnapshot
  }

  func currentTitle() async -> String? {
    nil
  }

  func currentWorkingDirectory() async -> String? {
    nil
  }

  func currentLifecycle() async -> TerminalLifecycle {
    .notStarted
  }

  func send(key _: TerminalEmulatorKey) async {}

  func send(paste _: String) async {}

  func send(mouse _: TerminalEmulatorMouse) async {}

  func resize(_ size: CellSize) async throws {
    snapshotStorage.withLock { grid in
      grid.size = size
    }
  }

  func events() -> AsyncStream<TerminalEmulatorEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private func allCommands(in node: DrawNode) -> [DrawCommand] {
  node.commands
    + node.children.flatMap(allCommands(in:))
    + node.postCommands
}
