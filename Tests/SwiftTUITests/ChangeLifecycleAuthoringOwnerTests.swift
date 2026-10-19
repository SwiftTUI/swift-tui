import SwiftTUIRuntime
@_spi(Testing) import SwiftTUITestSupport
import SwiftTUIViews
import Testing

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ChangeLifecycleAuthoringOwnerTests {
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
            probe.readings.append(.init(newValue: current, focus: focus))
            observation = "Callback \(probe.readings.count)"
          })
      } else {
        observingOtherChanges(
          contents.onChange(of: focus) {
            probe.readings.append(.init(newValue: nil, focus: focus))
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
