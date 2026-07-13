@_spi(Runners) import SwiftTUI

/// Reconstructs the composition shape used by the larger example apps without
/// depending on `swift-tui-examples`.
///
/// The workflow combines the surfaces missing from the older synthetic probes:
/// app chrome, a scrollable main pane, a side inspector, a popover/dropdown, a
/// sheet, a panel boundary, and a localized chrome state toggle. It is not a
/// replacement for real gallery/GIF-editor overlay runs; it is a committed
/// framework-only calibration signal for "real app shell" composition.
public struct ExampleAppShellWorkflowScenario: PerfScenario {
  public let name: PerfScenarioName = .exampleAppShellWorkflow
  public let defaultTerminalSize = PerfTerminalSize(columns: 110, rows: 36)
  public let scriptedEvents = [
    "scroll task list, open/close menu popover, open/close save sheet, toggle inspector"
  ]
  public let visualMarkers = ["App shell workload"]
  public let settlingDescription = "first frame that shows the app shell"

  private static let defaultTaskCount = 72

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let taskCount = Self.resolvedTaskCount()
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfExampleAppShellView(taskCount: taskCount)
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "App shell workload")
      let dispatchTime = monotonicSeconds()
      var lastFrame = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0

      let firstTaskCell = try driver.cell(containing: "task 0")
      driver.sendScroll(deltaY: 6, at: firstTaskCell)
      let scrolled = try await driver.waitForFrame(
        containing: "App shell workload",
        afterFrame: lastFrame
      )
      lastFrame = scrolled.frameNumber

      let menuCell = try driver.cell(containing: "open menu")
      driver.sendClick(at: menuCell)
      let menuOpened = try await driver.waitForFrame(
        containing: "Menu body",
        afterFrame: lastFrame
      )
      lastFrame = menuOpened.frameNumber

      let closeMenuCell = try driver.cell(containing: "close menu")
      driver.sendClick(at: closeMenuCell)
      let menuClosed = try await Self.waitForFrameNotContaining(
        "Menu body",
        afterFrame: lastFrame,
        in: driver
      )
      lastFrame = menuClosed.frameNumber

      let saveCell = try driver.cell(containing: "save sheet")
      driver.sendClick(at: saveCell)
      let sheetOpened = try await driver.waitForFrame(
        containing: "Save sheet body",
        afterFrame: lastFrame
      )
      lastFrame = sheetOpened.frameNumber

      let closeSheetCell = try driver.cell(containing: "close sheet")
      driver.sendClick(at: closeSheetCell)
      let sheetClosed = try await Self.waitForFrameNotContaining(
        "Save sheet body",
        afterFrame: lastFrame,
        in: driver
      )
      lastFrame = sheetClosed.frameNumber

      let inspectorCell = try driver.cell(containing: "toggle inspector")
      driver.sendClick(at: inspectorCell)
      let inspectorToggled = try await driver.waitForFrame(
        containing: "Inspector hidden",
        afterFrame: lastFrame
      )
      lastFrame = inspectorToggled.frameNumber

      let settled = driver.terminalHost.presentedFrames.last
      return [
        PerfEventRecord(
          eventID: "example-app-shell-workflow",
          eventType: "mixed_interaction",
          dispatchTimeSeconds: dispatchTime,
          expectedVisualMarker: "Inspector hidden",
          firstMatchingFrame: lastFrame,
          firstMatchingTimeSeconds: settled?.timestampSeconds ?? dispatchTime,
          finalSettledFrame: settled?.frameNumber ?? lastFrame,
          finalSettledTimeSeconds: settled?.timestampSeconds ?? dispatchTime
        )
      ]
    }
  }

  @MainActor
  private static func waitForFrameNotContaining(
    _ marker: String,
    afterFrame frameNumber: Int,
    in driver: PerfScenarioDriver,
    timeout: Duration = .seconds(2),
    hardCap: Duration = .seconds(30)
  ) async throws -> PerfPresentedFrame {
    let clock = ContinuousClock()
    let hardDeadline = clock.now.advanced(by: hardCap)
    var deadline = clock.now.advanced(by: timeout)
    var newestObserved = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0
    while clock.now < deadline && clock.now < hardDeadline {
      if let frame = driver.terminalHost.presentedFrames.last(where: {
        $0.frameNumber > frameNumber && !$0.text.contains(marker)
      }) {
        return frame
      }
      // Progress-gated deadline (never fixed wall-clock): while the run loop
      // keeps presenting new frames the scenario is advancing — just slowly,
      // e.g. on a loaded CI runner — so re-arm the idle window. The hard cap
      // bounds the wait even when continuous animation frames keep arriving.
      if let newest = driver.terminalHost.presentedFrames.last?.frameNumber,
        newest > newestObserved
      {
        newestObserved = newest
        deadline = clock.now.advanced(by: timeout)
      }
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    throw PerfScenarioError.markerTimedOut("!\(marker)")
  }

  private static func resolvedTaskCount() -> Int {
    guard let raw = environmentValue("TERMUI_PERF_APP_SHELL_TASKS"),
      let parsed = Int(raw),
      parsed > 0
    else {
      return defaultTaskCount
    }
    return parsed
  }
}

private struct PerfExampleAppShellView: View {
  let taskCount: Int

  @State private var menuPresented = false
  @State private var savePresented = false
  @State private var inspectorVisible = true
  @State private var selectedTask = 0
  @State private var revision = 0

  var body: some View {
    ZStack(alignment: .topLeading) {
      VStack(alignment: .leading, spacing: 0) {
        chrome
        Divider()
        HStack(alignment: .top, spacing: 1) {
          taskList
          if inspectorVisible {
            inspector
          }
        }
        Divider()
        statusBar
      }

      if menuPresented {
        menu
          .offset(x: 1, y: 1)
      }
    }
    .padding(1)
    .panel(id: "perf-app-shell")
    .sheet("Save", isPresented: $savePresented) {
      VStack(alignment: .leading, spacing: 1) {
        Text("Save sheet body")
        Text("selected task \(selectedTask)")
        Button("close sheet") {
          savePresented = false
          revision &+= 1
        }
      }
      .padding(1)
    }
  }

  private var chrome: some View {
    HStack(spacing: 2) {
      Text("App shell workload")
        .foregroundStyle(.tint)
      Button("open menu") {
        menuPresented = true
      }
      Button("save sheet") {
        savePresented = true
      }
      Button("toggle inspector") {
        inspectorVisible.toggle()
        revision &+= 1
      }
      Spacer(minLength: 1)
      Text("rev \(revision)")
        .foregroundStyle(.muted)
    }
  }

  private var taskList: some View {
    ScrollView(.vertical, showsIndicators: true) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(0..<taskCount, id: \.self) { index in
          Button("task \(index)  \(index == selectedTask ? "selected" : "open")") {
            selectedTask = index
            revision &+= 1
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .border(.separator)
  }

  private var inspector: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Inspector visible")
        .foregroundStyle(.muted)
      Divider()
      ForEach(0..<10, id: \.self) { index in
        Text("field \(index): task \(selectedTask)")
      }
    }
    .padding(1)
    .frame(width: 30, alignment: .topLeading)
    .frame(maxHeight: .infinity, alignment: .topLeading)
    .border(.separator)
  }

  private var statusBar: some View {
    HStack(spacing: 2) {
      Text(inspectorVisible ? "Inspector visible" : "Inspector hidden")
      Spacer(minLength: 1)
      Text("selected \(selectedTask)")
        .foregroundStyle(.separator)
    }
  }

  private var menu: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Menu body")
        .foregroundStyle(.muted)
      Button("pick task 12") {
        selectedTask = min(12, max(0, taskCount - 1))
        revision &+= 1
        menuPresented = false
      }
      Button("close menu") {
        menuPresented = false
      }
    }
    .padding(1)
    .border(.tint)
  }
}
