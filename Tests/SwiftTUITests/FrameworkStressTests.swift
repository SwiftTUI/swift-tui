import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI framework stress behavior", .serialized)
struct FrameworkStressTests {
  @Test("mixed deferred runtime surfaces survive repeated teardown and recreation")
  func mixedDeferredRuntimeSurfacesSurviveRepeatedTeardownAndRecreation() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("MixedDeferredStressRoot"),
      size: .init(width: 72, height: 20)
    ) {
      MixedDeferredStressFixture()
    }
    defer { harness.shutdown() }

    var maxLifecycleRegistrations = harness.lifecycleRegistrationCount

    for cycle in 1...6 {
      let rootButtonPoint = try #require(harness.point(forText: "Increment Root"))

      var frame = try harness.clickText("Increment Root")
      #expect(frame.contains("Root count \(cycle)"))

      frame = try harness.clickText("Open Sheet")
      #expect(frame.contains("Sheet body"))
      #expect(frame.contains("Root count \(cycle)"))
      frame = try harness.click(rootButtonPoint)
      #expect(frame.contains("Sheet body"))
      #expect(frame.contains("Root count \(cycle)"))
      #expect(!frame.contains("Root count \(cycle + 1)"))
      frame = try harness.clickText("Close Sheet", chooseLast: true)
      #expect(!frame.contains("Sheet body"))
      #expect(frame.contains("Root count \(cycle)"))

      frame = try harness.clickText("Next Tab")
      #expect(frame.contains("Nav root"))
      #expect(frame.contains("Root count \(cycle)"))
      frame = try harness.clickText("Push Detail")
      #expect(frame.contains("Destination body"))
      frame = try harness.clickText("Pop Detail", chooseLast: true)
      #expect(!frame.contains("Destination body"))
      #expect(frame.contains("Nav root"))

      frame = try harness.clickText("Next Tab")
      #expect(frame.contains("Presentation root"))
      #expect(frame.contains("Root count \(cycle)"))
      frame = try harness.clickText("Open Confirm")
      #expect(frame.contains("Confirm body"))
      frame = try harness.clickText("Close Confirm", chooseLast: true)
      #expect(!frame.contains("Confirm body"))
      frame = try harness.clickText("Open Popover")
      #expect(frame.contains("Popover body"))
      frame = try harness.clickText("Close Popover", chooseLast: true)
      #expect(!frame.contains("Popover body"))

      frame = try harness.clickText("Next Tab")
      #expect(frame.contains("Geometry tab"))
      #expect(frame.contains("Root count \(cycle)"))
      #expect(!frame.contains("Destination body"))
      #expect(!frame.contains("Confirm body"))
      #expect(!frame.contains("Popover body"))

      maxLifecycleRegistrations = max(
        maxLifecycleRegistrations,
        harness.lifecycleRegistrationCount
      )
    }

    #expect(
      maxLifecycleRegistrations <= 24,
      """
      Deferred surface churn must not accumulate lifecycle handlers without \
      bound; max=\(maxLifecycleRegistrations)
      """
    )
  }

  @Test(".task(id:) stays bounded across lazy-tab selection, descriptor, and identity churn")
  func taskIDStaysBoundedAcrossLazyTabSelectionDescriptorAndIdentityChurn() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TaskCancellationStressRoot"),
      size: .init(width: 48, height: 12)
    ) {
      TaskCancellationStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.activeTaskCount == 1)
    var maxActiveTasks = harness.activeTaskCount

    for generation in 1...40 {
      let frame = try harness.clickText("Cycle Task")
      maxActiveTasks = max(maxActiveTasks, harness.activeTaskCount)

      #expect(frame.contains("generation \(generation)"))
      #expect(harness.activeTaskCount == 1)
      #expect(harness.activeTaskDescriptorCount == 1)
    }

    #expect(maxActiveTasks == 1)
    harness.shutdown()
    #expect(harness.activeTaskCount == 0)
  }

  @Test("lazy tab actions keep hoisted state isolated across repeated recreation")
  func lazyTabActionsKeepHoistedStateIsolatedAcrossRepeatedRecreation() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("LazyTabStateStressRoot"),
      size: .init(width: 52, height: 12)
    ) {
      LazyTabStateStressFixture()
    }
    defer { harness.shutdown() }

    var frame = harness.frame
    #expect(frame.contains("Totals alpha 0 beta 0"))
    #expect(frame.contains("Alpha action view"))
    #expect(!frame.contains("Beta action view"))

    for iteration in 1...12 {
      frame = try harness.clickText("Increment Alpha")
      #expect(frame.contains("Totals alpha \(iteration) beta \(iteration - 1)"))
      #expect(frame.contains("Alpha action view"))
      #expect(!frame.contains("Beta action view"))

      frame = try harness.clickText("Next Counter Tab")
      #expect(frame.contains("Totals alpha \(iteration) beta \(iteration - 1)"))
      #expect(frame.contains("Beta action view"))
      #expect(!frame.contains("Alpha action view"))

      frame = try harness.clickText("Increment Beta")
      #expect(frame.contains("Totals alpha \(iteration) beta \(iteration)"))
      #expect(frame.contains("Beta action view"))
      #expect(!frame.contains("Alpha action view"))

      frame = try harness.clickText("Next Counter Tab")
      #expect(frame.contains("Totals alpha \(iteration) beta \(iteration)"))
      #expect(frame.contains("Alpha action view"))
      #expect(!frame.contains("Beta action view"))
    }
  }
}

private struct MixedDeferredStressFixture: View {
  @State private var rootCount = 0
  @State private var selectedTab = "geometry"
  @State private var destinationPresented = false
  @State private var sheetPresented = false
  @State private var confirmationPresented = false
  @State private var popoverPresented = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Root count \(rootCount)")
      HStack(spacing: 1) {
        Button("Increment Root") { rootCount += 1 }
        Button("Next Tab") { selectedTab = nextTab(after: selectedTab) }
      }

      TabView(selection: $selectedTab) {
        Tab("Geometry", value: "geometry") {
          geometryTab
        }

        Tab("Navigation", value: "navigation") {
          navigationTab
        }

        Tab("Presentation", value: "presentation") {
          presentationTab
        }
      }
      .tabViewStyle(.literalTabs)
    }
    .frame(width: 72, height: 20, alignment: .topLeading)
  }

  private var geometryTab: some View {
    VStack(alignment: .leading, spacing: 0) {
      GeometryReader { proxy in
        VStack(alignment: .leading, spacing: 0) {
          Text("Geometry tab \(proxy.size.width)x\(proxy.size.height)")
            .onAppear {}
            .onDisappear {}
          Text("Geometry body")
        }
      }
      .frame(height: 2)

      ForEach(0..<6) { index in
        Text("Geometry row \(index)")
      }
      Button("Open Sheet") { sheetPresented = true }
    }
    .sheet("Stress Sheet", isPresented: $sheetPresented) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Sheet body")
        Button("Close Sheet") { sheetPresented = false }
      }
      .onAppear {}
      .onDisappear {}
    }
  }

  private var navigationTab: some View {
    NavigationStack(id: "mixed-deferred-stress-navigation") {
      VStack(alignment: .leading, spacing: 0) {
        Text("Nav root")
          .onAppear {}
          .onDisappear {}
        Button("Push Detail") { destinationPresented = true }
      }
      .navigationDestination(isPresented: $destinationPresented) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Destination body")
          Button("Pop Detail") { destinationPresented = false }
        }
        .onAppear {}
        .onDisappear {}
      }
    }
  }

  private var presentationTab: some View {
    let base = VStack(alignment: .leading, spacing: 0) {
      Text("Presentation root")
        .onAppear {}
        .onDisappear {}
      Button("Open Confirm") { confirmationPresented = true }
      Button("Open Popover") { popoverPresented = true }
    }

    return
      base
      .confirmationDialog(
        "Stress Confirm",
        isPresented: $confirmationPresented,
        actions: {
          Button("Close Confirm") { confirmationPresented = false }
        },
        message: {
          Text("Confirm body")
        }
      )
      .popover(isPresented: $popoverPresented, arrowEdge: .trailing) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Popover body")
          Button("Close Popover") { popoverPresented = false }
        }
        .onAppear {}
        .onDisappear {}
      }
  }

  private func nextTab(after current: String) -> String {
    switch current {
    case "geometry": "navigation"
    case "navigation": "presentation"
    default: "geometry"
    }
  }
}

private struct TaskCancellationStressFixture: View {
  @State private var selectedTab = "left"
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Cycle Task") {
        generation += 1
        selectedTab = selectedTab == "left" ? "right" : "left"
      }
      Text("selection \(selectedTab) generation \(generation)")

      TabView(selection: $selectedTab) {
        Tab("Left", value: "left") {
          TaskCancellationStressPane(label: "left", generation: generation)
            .id("left-\(generation % 5)")
        }

        Tab("Right", value: "right") {
          TaskCancellationStressPane(label: "right", generation: generation)
            .id("right-\(generation % 5)")
        }
      }
      .tabViewStyle(.literalTabs)
    }
    .frame(width: 48, height: 12, alignment: .topLeading)
  }
}

private struct TaskCancellationStressPane: View {
  let label: String
  let generation: Int

  var body: some View {
    GeometryReader { proxy in
      Text("task \(label) generation \(generation) size \(proxy.size.width)x\(proxy.size.height)")
        .task(
          id: TaskCancellationStressID(
            label: label,
            generation: generation,
            width: proxy.size.width,
            height: proxy.size.height
          )
        ) {
          while !Task.isCancelled {
            await Task.yield()
          }
        }
    }
  }
}

private struct TaskCancellationStressID: Equatable, Sendable {
  var label: String
  var generation: Int
  var width: Int
  var height: Int
}

private struct LazyTabStateStressFixture: View {
  @State private var selectedTab = "alpha"
  @State private var alphaTotal = 0
  @State private var betaTotal = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Next Counter Tab") {
        selectedTab = selectedTab == "alpha" ? "beta" : "alpha"
      }
      Text("counter selection \(selectedTab)")
      Text("Totals alpha \(alphaTotal) beta \(betaTotal)")

      TabView(selection: $selectedTab) {
        Tab("Alpha", value: "alpha") {
          LazyTabCounterPane(label: "Alpha") {
            alphaTotal += 1
          }
        }

        Tab("Beta", value: "beta") {
          LazyTabCounterPane(label: "Beta") {
            betaTotal += 1
          }
        }
      }
      .tabViewStyle(.literalTabs)
    }
    .frame(width: 52, height: 12, alignment: .topLeading)
  }
}

private struct LazyTabCounterPane: View {
  let label: String
  let increment: @MainActor () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("\(label) action view")
      Button("Increment \(label)") { increment() }
    }
    .onAppear {}
    .onDisappear {}
  }
}

@MainActor
private final class StressRuntimeHarness<Content: View> {
  private let terminal: StressRecordingHost
  private let runLoop: SwiftTUIRuntime.RunLoop<Int, Content>
  private var renderedFrames = 0
  private var didShutdown = false

  init(
    rootIdentity: Identity,
    size: CellSize,
    @ViewBuilder content: @escaping () -> Content
  ) throws {
    let terminal = StressRecordingHost(surfaceSize: size)
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: StressEmptyKeyReader(),
      signalReader: StressEmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      proposal: .init(width: size.width, height: size.height),
      viewBuilder: { _, _ in content() }
    )
    focusTracker.invalidator = scheduler
    self.terminal = terminal
    self.runLoop = runLoop

    scheduler.requestInvalidation(of: [rootIdentity])
    _ = try render()
  }

  var frame: String {
    terminal.frames.last ?? ""
  }

  var activeTaskCount: Int {
    runLoop.lifecycleCoordinator.activeTaskCount
  }

  var activeTaskDescriptorCount: Int {
    runLoop.lifecycleCoordinator.activeTaskDescriptors.values.reduce(0) {
      $0 + $1.count
    }
  }

  var lifecycleRegistrationCount: Int {
    let snapshot = runLoop.localLifecycleRegistry.snapshot()
    return snapshot.appearHandlers.count
      + snapshot.disappearHandlers.count
      + snapshot.changeHandlers.count
  }

  func shutdown() {
    guard !didShutdown else {
      return
    }
    didShutdown = true
    runLoop.lifecycleCoordinator.shutdown()
  }

  @discardableResult
  func render() throws -> String {
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    return try #require(terminal.frames.last)
  }

  func point(forText text: String, chooseLast: Bool = false) -> Point? {
    terminal.centerOfText(text, chooseLast: chooseLast)
  }

  @discardableResult
  func clickText(_ label: String, chooseLast: Bool = false) throws -> String {
    let point = try #require(
      terminal.centerOfText(label, chooseLast: chooseLast),
      "could not find '\(label)' in frame:\n\(frame)"
    )
    return try click(point)
  }

  @discardableResult
  func click(_ point: Point) throws -> String {
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .down(.primary), location: point)))
      ) == nil
    )
    _ = try render()
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .up(.primary), location: point)))
      ) == nil
    )
    return try render()
  }
}

private final class StressRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var frames: [String] = []
  private var lastPresentedSurface: RasterSurface?

  init(surfaceSize: CellSize) {
    self.surfaceSize = surfaceSize
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let rendered = TerminalSurfaceRenderer(capabilityProfile: capabilityProfile).render(surface)
    frames.append(String(rendered.filter { $0 != "\r" }))
    lastPresentedSurface = surface
    return .init(
      bytesWritten: 0,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }

  func write(_ output: String) throws {
    frames.append(String(output.filter { $0 != "\r" }))
  }

  func centerOfText(_ target: String, chooseLast: Bool = false) -> Point? {
    guard let surface = lastPresentedSurface else {
      return nil
    }

    let rows = chooseLast ? Array(surface.lines.indices.reversed()) : Array(surface.lines.indices)
    for row in rows {
      let line = surface.lines[row]
      let options: String.CompareOptions = chooseLast ? .backwards : []
      guard let range = line.range(of: target, options: options) else {
        continue
      }
      let column = line.distance(from: line.startIndex, to: range.lowerBound)
      return Point(CellPoint(x: column + target.count / 2, y: row))
    }
    return nil
  }
}

private final class StressEmptyKeyReader: InputReading {
  func events() -> AsyncStream<KeyPress> {
    AsyncStream { $0.finish() }
  }
}

private final class StressEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
