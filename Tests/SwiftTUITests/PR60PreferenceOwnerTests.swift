import SwiftTUIRuntime
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUIViews

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct PR60PreferenceOwnerTests {
  @Test("Preference callbacks inside deferred readers read their authored focus owner")
  func deferredReaderPreferenceFocus() async throws {
    let probe = PR60PreferenceOwnerProbe()
    let recorder = PR60PreferenceOwnerFrameRecorder()
    let surface = HostedRasterSurface(
      surfaceSize: CellSize(width: 60, height: 20), appearance: .fallback,
      onFrame: { recorder.receive($0) }
    )
    let session = try HostedSceneSession(
      for: PR60PreferenceOwnerApp(usesValueArguments: true, probe: probe),
      sceneID: "change-owner", surface: surface
    )
    let run = Task { try await session.start() }
    do {
      _ = try await recorder.wait("initial preference callback") {
        hasFocus("Name", in: $0) && !probe.readings.isEmpty
      }
      let initialCount = probe.readings.count
      session.send(.key(.tab))
      _ = try await recorder.wait("native focus preference callback") {
        hasFocus("Interval", in: $0) && probe.readings.count > initialCount
      }
      let reading = try #require(probe.readings.last)
      #expect(reading.newValue == "Interval")
      #expect(reading.focus == "Interval")
      #expect(
        reading.ownerMatches,
        "registration must preserve the declaration owner independently of wrapper capture")
      session.stop()
      #expect(try await run.value == .inputEnded)
    } catch {
      session.stop()
      _ = await run.result
      throw error
    }
  }
}

private enum PR60FocusPreferenceKey: PreferenceKey {
  static let defaultValue: String? = nil
  static func reduce(value: inout String?, nextValue: () -> String?) {
    value = nextValue() ?? value
  }
}

private struct PR60PreferenceOwnerApp: App {
  let usesValueArguments: Bool
  let probe: PR60PreferenceOwnerProbe

  nonisolated init() {
    usesValueArguments = false
    probe = PR60PreferenceOwnerProbe()
  }

  nonisolated init(usesValueArguments: Bool, probe: PR60PreferenceOwnerProbe) {
    self.usesValueArguments = usesValueArguments
    self.probe = probe
  }

  var body: some Scene {
    WindowGroup(id: "change-owner") {
      PR60PreferenceOwnerView(usesValueArguments: usesValueArguments, probe: probe)
    }.exitOnKeys([])
  }
}

@MainActor
private struct PR60PreferenceOwnerView: View {
  @Environment(\.terminalSize) private var terminalSize
  @State private var revision = 0
  @State private var name = "Name"
  @State private var interval = "5"
  @State private var observation = "Pending"
  let usesValueArguments: Bool
  let probe: PR60PreferenceOwnerProbe
  @FocusState private var focus: String?

  private var fields: some View {
    VStack {
      GroupBox("Workspace") {
        PR60PreferenceOwnerField("Name") {
          TextField("Name", text: $name)
            .accessibilityLabel("Name")
            .focused($focus, equals: "Name")
        }
        .id("name")
      }
      GroupBox("Automation") {
        PR60PreferenceOwnerField("Interval") {
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
    let declarationOwner = currentAuthoringContext()?.stateOwnerHandle
    return ScrollViewReader { _ in
      observingOtherChanges(
        contents
          .preference(key: PR60FocusPreferenceKey.self, value: focus)
          .onPreferenceChange(PR60FocusPreferenceKey.self) { current in
            probe.readings.append(
              PR60PreferenceOwnerProbe.Reading(
                newValue: current, focus: focus,
                ownerMatches: declarationOwner != nil
                  && currentAuthoringContext()?.stateOwnerHandle == declarationOwner))
            observation = "Callback \(probe.readings.count)"
          })
    }
  }
}

@MainActor
private struct PR60PreferenceOwnerField<Content: View>: View {
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
private final class PR60PreferenceOwnerProbe {
  struct Reading {
    let newValue: String?
    let focus: String?
    let ownerMatches: Bool
  }
  var readings: [Reading] = []
  nonisolated init() {}
}

@MainActor
private final class PR60PreferenceOwnerFrameRecorder {
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
