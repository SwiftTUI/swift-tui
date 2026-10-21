import SwiftTUIRuntime
@_spi(Testing) import SwiftTUITestSupport
import SwiftTUIViews
import Testing

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ChangeLifecycleAuthoringOwnerTests {
  @Test("Geometry-reader focus changes publish blur validation")
  func geometryReaderBlurValidation() async throws {
    try await withStackedChangeSession(.blur) { session, recorder, probe in
      _ = try await recorder.wait("initial Name focus") { hasFocus("Name", in: $0) }
      session.send(.key(.tab))
      let frame = try await recorder.wait("Interval focus and Name blur error") {
        hasFocus("Interval", in: $0)
          && $0.raster.lines.contains { $0.contains("Name error") }
      }
      #expect(frame.focusedIdentity != nil)
      #expect(probe.events.contains { $0.contains("old=Name new=Interval read=Interval") })
      #expect(probe.events.contains { $0.contains("validation=true") })
    }
  }

  @Test("Reader change callbacks reveal a retained state target")
  func stateDrivenScrollReveal() async throws {
    try await withStackedChangeSession(.reveal) { session, recorder, probe in
      _ = try await recorder.wait("initial reader target") {
        $0.raster.lines.contains { $0.contains("Active 0") }
          && $0.focusedIdentity != nil
      }
      session.send(.key(.character("]")))
      let revealed = try await recorder.wait("next state target is revealed") {
        $0.raster.lines.contains { $0.contains("Active 1") }
          && ($0.semantics.scrollRoutes.first?.contentOffset.y ?? 0) > 0
      }
      #expect(probe.events.contains { $0 == "target old=0 new=1 read=1 accepted=true" })
      let inner = try #require(
        revealed.semantics.accessibilityNodes.first { $0.role == .button && $0.label == "Inner" })
      session.send([
        .mouse(.init(kind: .down(.primary), location: .cellFallback(inner.rect.origin))),
        .mouse(.init(kind: .up(.primary), location: .cellFallback(inner.rect.origin))),
      ])
      _ = try await recorder.wait("independent child updates") {
        $0.raster.lines.contains { $0.contains("Inner 1") }
      }
      #expect(probe.events.filter { $0.hasPrefix("target ") }.count == 1)
      #expect(probe.events.filter { $0.hasPrefix("scaled ") } == ["scaled old=0 new=10"])
      session.send(.key(.character("]")))
      _ = try await recorder.wait("second target after child update") {
        $0.raster.lines.contains { $0.contains("Active 2") }
          && probe.events.contains("target old=1 new=2 read=2 accepted=true")
      }
      #expect(
        probe.events.filter { $0.hasPrefix("scaled ") }
          == ["scaled old=0 new=10", "scaled old=10 new=20"])
    }
  }

  @Test("Stacked same-type observers preserve their baselines when resolved twice in one pass")
  func samePassStackedObservationBaselines() {
    let graph = ViewGraph()
    let registry = LocalLifecycleRegistry()
    let probe = StackedChangeProbe()
    var context = ResolveContext(
      identity: testIdentity("ChangeSamePass"), localLifecycleRegistry: registry,
      applyEnvironmentValues: true)
    context.viewGraph = graph

    func content(_ first: Int, _ second: Int) -> some View {
      GeometryReader { _ in Text("content") }
        .onChange(of: first) { old, new in probe.events.append("first \(old)->\(new)") }
        .onChange(of: second) { old, new in probe.events.append("second \(old)->\(new)") }
    }

    graph.beginFrame()
    let initial = Resolver().resolve(content(0, 100), in: context)
    _ = graph.finalizeFrame(rootIdentity: context.identity, resolved: initial, placed: nil)

    graph.beginFrame()
    _ = Resolver().resolve(content(1, 110), in: context)
    let repeated = Resolver().resolve(content(1, 110), in: context)
    let events = graph.finalizeFrame(
      rootIdentity: context.identity, resolved: repeated, placed: nil)
    for event in events {
      if case .change(let handlerIDs) = event.operation {
        for handlerID in handlerIDs { registry.changeHandler(for: handlerID)?() }
      }
    }
    #expect(probe.events.sorted() == ["first 0->1", "second 100->110"])
  }

  @Test(
    "Deferred reader change callbacks read their authored focus owner", arguments: [false, true])
  func deferredReaderFocus(usesValueArguments: Bool) async throws {
    let probe = ChangeOwnerProbe()
    let recorder = ChangeOwnerFrameRecorder()
    let surface = HostedRasterSurface(
      surfaceSize: CellSize(width: 60, height: 20), appearance: .fallback,
      onFrame: { recorder.receive($0) }
    )
    let session = try HostedSceneSession(
      for: ChangeOwnerApp(usesValueArguments: usesValueArguments, probe: probe),
      sceneID: "change-owner", surface: surface
    )
    let run = Task { try await session.start() }
    do {
      _ = try await recorder.wait("initial focus callback") {
        hasFocus("Name", in: $0) && !probe.readings.isEmpty
      }
      // Native focus can commit before lifecycle dispatch. Wait for the callback
      // record too, then inspect what that callback read under its dispatch scope.
      let initialCount = probe.readings.count
      session.send(.key(.tab))
      _ = try await recorder.wait("native focus callback") {
        hasFocus("Interval", in: $0) && probe.readings.count > initialCount
      }
      let reading = try #require(probe.readings.last)
      #expect(reading.focus == "Interval")
      if usesValueArguments { #expect(reading.newValue == "Interval") }
      session.stop()
      #expect(try await run.value == .inputEnded)
    } catch {
      session.stop()
      _ = await run.result
      throw error
    }
  }
}

private enum StackedChangeScenario: Sendable {
  case blur, reveal
}

@MainActor
private final class StackedChangeProbe {
  var events: [String] = []
  nonisolated init() {}
}

private struct StackedChangeApp: App {
  let scenario: StackedChangeScenario
  let probe: StackedChangeProbe

  nonisolated init() {
    scenario = .blur
    probe = StackedChangeProbe()
  }

  nonisolated init(scenario: StackedChangeScenario, probe: StackedChangeProbe) {
    self.scenario = scenario
    self.probe = probe
  }

  var body: some Scene {
    WindowGroup(id: "change-followup") {
      switch scenario {
      case .blur: StackedChangeForm(probe: probe)
      case .reveal: StackedChangeReader(probe: probe)
      }
    }.exitOnKeys([])
  }
}

@MainActor
private struct StackedChangeForm: View {
  @State private var name = ""
  @State private var interval = ""
  @State private var wasNameExited = false
  @FocusState private var focus: String?
  let probe: StackedChangeProbe

  var body: some View {
    ScrollViewReader { proxy in
      GeometryReader { geometry in
        VStack {
          ScrollView {
            VStack {
              AuthoredChangeOwnerField("Name") {
                TextField("Name", text: $name)
                  .accessibilityLabel("Name")
                  .focused($focus, equals: "Name")
              }
              .id("Name")
              if wasNameExited { Text("Name error") }
              AuthoredChangeOwnerField("Interval") {
                TextField("Interval", text: $interval)
                  .accessibilityLabel("Interval")
                  .focused($focus, equals: "Interval")
              }
              .id("Interval")
            }
          }
          Button("Save") {}
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
      }
      .onAppear { focus = "Name" }
      .onChange(of: focus) { old, new in
        probe.events.append("focus old=\(old ?? "nil") new=\(new ?? "nil") read=\(focus ?? "nil")")
        if old == "Name" {
          wasNameExited = true
          probe.events.append("validation=\(wasNameExited)")
        }
        if let focus {
          probe.events.append("scroll accepted=\(proxy.scrollTo(focus, anchor: .top))")
        }
      }
      .onChange(of: wasNameExited) {
        probe.events.append("validation callback read=\(wasNameExited)")
      }
    }
  }
}

@MainActor
private struct StackedChangeReader: View {
  @Environment(\.terminalSize) private var terminalSize
  @State private var target = 0
  @State private var position = ScrollCellOffset.zero
  @FocusState private var isReaderFocused: Bool
  let probe: StackedChangeProbe

  var body: some View {
    ScrollViewReader { proxy in
      VStack {
        Text("Active \(target)")
        ScrollView(position: $position) {
          VStack {
            ForEach(0..<3, id: \.self) { index in
              Text("Target \(index)").frame(height: 8, alignment: .topLeading).id(index)
            }
          }
        }
        .focused($isReaderFocused)
        .defaultFocus($isReaderFocused, true)
        .frame(height: 8)
        StackedChangeCounter()
      }
      .onKeyPress { press in
        guard press == KeyPress(.character("]")) else { return .ignored }
        target = min(2, target + 1)
        return .handled
      }
      .onChange(of: target) { old, new in
        let read = target
        let accepted = proxy.scrollTo(target, anchor: .top)
        probe.events.append("target old=\(old) new=\(new) read=\(read) accepted=\(accepted)")
      }
      .onChange(of: "file") {}
      .onChange(of: target * 10) { old, new in
        probe.events.append("scaled old=\(old) new=\(new)")
      }
      .onChange(of: target > 0) {}
      .onChange(of: terminalSize) {}
    }
  }
}

@MainActor
private struct StackedChangeCounter: View {
  @State private var count = 0

  var body: some View {
    Button("Inner \(count)") { count += 1 }.accessibilityLabel("Inner")
  }
}

@MainActor
private func withStackedChangeSession(
  _ scenario: StackedChangeScenario,
  perform:
    @MainActor (HostedSceneSession, ChangeOwnerFrameRecorder, StackedChangeProbe) async throws ->
    Void
) async throws {
  let probe = StackedChangeProbe()
  let recorder = ChangeOwnerFrameRecorder()
  let surface = HostedRasterSurface(
    surfaceSize: CellSize(width: 60, height: 20), appearance: .fallback,
    onFrame: { recorder.receive($0) }
  )
  let session = try HostedSceneSession(
    for: StackedChangeApp(scenario: scenario, probe: probe), sceneID: "change-followup",
    surface: surface
  )
  let run = Task { try await session.start() }
  do {
    try await perform(session, recorder, probe)
    session.stop()
    #expect(try await run.value == .inputEnded)
  } catch {
    print("Stacked change evidence: \(probe.events)")
    session.stop()
    _ = await run.result
    throw error
  }
}

private struct ChangeOwnerApp: App {
  let usesValueArguments: Bool
  let probe: ChangeOwnerProbe

  nonisolated init() {
    usesValueArguments = false
    probe = ChangeOwnerProbe()
  }

  nonisolated init(usesValueArguments: Bool, probe: ChangeOwnerProbe) {
    self.usesValueArguments = usesValueArguments
    self.probe = probe
  }

  var body: some Scene {
    WindowGroup(id: "change-owner") {
      ChangeOwnerView(usesValueArguments: usesValueArguments, probe: probe)
    }.exitOnKeys([])
  }
}

@MainActor
private struct ChangeOwnerView: View {
  @Environment(\.terminalSize) private var terminalSize
  @State private var revision = 0
  @State private var name = "Name"
  @State private var interval = "5"
  @State private var observation = "Pending"
  let usesValueArguments: Bool
  let probe: ChangeOwnerProbe
  @FocusState private var focus: String?

  private var fields: some View {
    VStack {
      GroupBox("Workspace") {
        AuthoredChangeOwnerField("Name") {
          TextField("Name", text: $name)
            .accessibilityLabel("Name")
            .focused($focus, equals: "Name")
        }
        .id("name")
      }
      GroupBox("Automation") {
        AuthoredChangeOwnerField("Interval") {
          TextField("Interval", text: $interval)
            .accessibilityLabel("Interval")
            .focused($focus, equals: "Interval")
        }
        .id("interval")
      }
    }
  }

  private var contents: some View {
    VStack {
      ScrollView { fields }.frame(height: 10)
      Text(observation)
      Button("Save") {}
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color.black)
    .onAppear { focus = "Name" }
    .onSubmit { revision += 1 }
  }

  // Preserve the composed form boundary around the deferred reader observer.
  private func observingOtherChanges<Content: View>(_ content: Content) -> some View {
    content
      .onChange(of: revision) {}
      .onChange(of: terminalSize) {}
      .onChange(of: name.isEmpty) {}
      .onKeyPress { _ in .ignored }
  }

  var body: some View {
    ScrollViewReader { _ in
      if usesValueArguments {
        observingOtherChanges(
          contents.onChange(of: focus) { _, current in
            probe.readings.append(ChangeOwnerProbe.Reading(newValue: current, focus: focus))
            observation = "Callback \(probe.readings.count)"
          })
      } else {
        observingOtherChanges(
          contents.onChange(of: focus) {
            probe.readings.append(ChangeOwnerProbe.Reading(newValue: nil, focus: focus))
            observation = "Callback \(probe.readings.count)"
          })
      }
    }
  }
}

@MainActor
private struct AuthoredChangeOwnerField<Content: View>: View {
  @Environment(\.terminalSize) private var terminalSize
  let title: String
  let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack {
      Text(title)
      content
      if terminalSize.height > 12 { Text("Field help") }
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}

@MainActor
private final class ChangeOwnerProbe {
  struct Reading {
    let newValue: String?
    let focus: String?
  }
  var readings: [Reading] = []
  nonisolated init() {}
}

@MainActor
private final class ChangeOwnerFrameRecorder {
  private var latest: SemanticHostFrame?
  private let updates = MainActorConditionSignal()
  private let stages = ManualStageClock()

  func receive(_ frame: SemanticHostFrame) {
    latest = frame
    stages.advance()
    updates.notify()
  }

  func wait(
    _ label: String,
    matching predicate: @escaping @MainActor @Sendable (SemanticHostFrame) -> Bool
  ) async throws -> SemanticHostFrame {
    do {
      try await updates.wait(
        until: { self.latest.map(predicate) == true }, for: label,
        within: ProgressBudget(stages: 32), on: stages
      )
    } catch let error as StageBudgetExceeded {
      throw FrameDeadlineExceeded(
        expectation: error.description,
        lastRaster: latest?.raster.lines.joined(separator: "\n") ?? "No frame received"
      )
    }
    return try #require(latest)
  }

  private struct FrameDeadlineExceeded: Error, CustomStringConvertible {
    let expectation: String
    let lastRaster: String
    var description: String { "Timed out waiting for \(expectation). Last raster:\n\(lastRaster)" }
  }
}

private func hasFocus(_ label: String, in frame: SemanticHostFrame) -> Bool {
  frame.semantics.accessibilityNodes.contains {
    $0.identity == frame.focusedIdentity && $0.label == label
  }
}
