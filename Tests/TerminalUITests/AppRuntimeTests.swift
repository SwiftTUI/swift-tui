import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import TerminalUIScenes
@testable import View

@MainActor
@Suite
struct AppRuntimeTests {
  @Test("App body resolves a single WindowGroup into a terminal scene")
  func appBodyResolvesSingleWindowGroup() throws {
    let configurations = collectWindowSceneConfigurations(from: GreetingApp().body)
    #expect(configurations.count == 1)
    let configuration = try #require(configurations.first)

    #expect(configuration.identifier == WindowIdentifier("Greeting-Window"))
    #expect(configuration.rootIdentity == testIdentity("App", "Greeting-Window"))

    let artifacts = DefaultRenderer().render(
      configuration.makeRootView(),
      context: .init(identity: configuration.rootIdentity)
    )

    #expect(artifacts.resolvedTree.descendant(withText: "Hello from App") != nil)
  }

  @Test("App body preserves multiple WindowGroup scenes without collapsing them")
  func appBodyPreservesMultipleScenes() {
    let configurations = collectWindowSceneConfigurations(from: MultiWindowApp().body)

    #expect(configurations.count == 2)
    #expect(configurations.map(\.identifier) == [WindowIdentifier("One"), WindowIdentifier("Two")])
  }

  @MainActor
  @Test("App launcher renders stateful WindowGroup scenes and invokes local button actions")
  func appLauncherRunsWindowGroupScene() async throws {
    let terminal = RecordingTerminalHost()
    let actionRecorder = ActionRecorder()

    let result = try await MultiSceneLauncher.run(
      scene: WindowGroup("Action Window") {
        ActionWindow(actionRecorder: actionRecorder)
      },
      sessionName: "AppRuntimeTests.ActionWindow",
      terminalHost: terminal,
      inputReader: ScriptedInputReader(events: [.return, .character("q")]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .quitKey)
    #expect(actionRecorder.count == 1)

    let firstFrame = try #require(terminal.frames.first)
    let lastFrame = try #require(terminal.frames.last)
    let firstMetrics = try #require(terminal.presentationMetrics.first)
    let firstSurfaceSize = try #require(terminal.presentedSurfaceSizes.first)
    #expect(firstFrame.contains("Launcher"))
    #expect(firstFrame.contains("Increment"))
    #expect(lastFrame.contains("Count 1"))
    #expect(lastFrame.contains("q quits"))
    #expect(firstMetrics.usedFullRepaint)
    #expect(firstMetrics.cellsChanged == firstSurfaceSize.width * firstSurfaceSize.height)
  }

  @MainActor
  @Test("WindowGroup scenes present at the terminal canvas size even for small roots")
  func windowGroupScenesPresentAtTerminalCanvasSize() async throws {
    let terminal = RecordingTerminalHost(surfaceSize: .init(width: 20, height: 4))

    let result = try await MultiSceneLauncher.run(
      scene: WindowGroup("Canvas Window") {
        Text("Hello")
      },
      sessionName: "AppRuntimeTests.CanvasWindow",
      terminalHost: terminal,
      inputReader: ScriptedInputReader(events: [.character("q")]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .quitKey)
    #expect(terminal.presentedSurfaceSizes == [terminal.surfaceSize])

    let firstFrame = try #require(terminal.frames.first)
    let lines = firstFrame.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(lines.count == terminal.surfaceSize.height)
    #expect(String(lines[0]).hasPrefix("Hello"))
  }

  @MainActor
  @Test("WindowGroup clips overflowing content to the terminal canvas")
  func windowGroupClipsOverflowingContentToTerminalCanvas() async throws {
    let terminal = RecordingTerminalHost(surfaceSize: .init(width: 16, height: 4))

    let result = try await MultiSceneLauncher.run(
      scene: WindowGroup("Clipped Window") {
        Rectangle()
          .fill(Color.red)
          .frame(width: 40, height: 10)
      },
      sessionName: "AppRuntimeTests.ClippedWindow",
      terminalHost: terminal,
      inputReader: ScriptedInputReader(events: [.character("q")]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .quitKey)
    #expect(terminal.presentedSurfaceSizes == [terminal.surfaceSize])
  }

  @MainActor
  @Test("App launcher preserves @State text-field bindings across runtime frames")
  func appLauncherPersistsStatefulTextFieldBindings() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await MultiSceneLauncher.run(
      scene: WindowGroup("Form Window") {
        StatefulFormWindow()
      },
      sessionName: "AppRuntimeTests.StatefulFormWindow",
      terminalHost: terminal,
      inputReader: ScriptedInputReader(
        events: [
          KeyPress(.return),
          KeyPress(.character("H")),
          KeyPress(.character("i")),
          KeyPress(.character("c"), modifiers: .ctrl),
        ]
      ),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .ctrlC)

    let lastFrame = try #require(terminal.frames.last)
    #expect(lastFrame.contains("Hi_"))
    #expect(lastFrame.contains("Name: Hi"))
    #expect(lastFrame.contains("ctrl-c exits"))
  }

  @MainActor
  @Test("App launcher preserves multiline TextEditor bindings across runtime frames")
  func appLauncherPersistsStatefulTextEditorBindings() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await MultiSceneLauncher.run(
      scene: WindowGroup("Editor Window") {
        StatefulTextEditorWindow()
      },
      sessionName: "AppRuntimeTests.StatefulTextEditorWindow",
      terminalHost: terminal,
      inputReader: ScriptedInputReader(
        events: [
          KeyPress(.character("H")),
          KeyPress(.character("i")),
          KeyPress(.return),
          KeyPress(.character("!")),
          KeyPress(.character("c"), modifiers: .ctrl),
        ]
      ),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .ctrlC)

    let lastFrame = try #require(terminal.frames.last)
    #expect(lastFrame.contains("Hi"))
    #expect(lastFrame.contains("!_"))
    #expect(lastFrame.contains("Lines: 2"))
    #expect(lastFrame.contains("Preview: Hi | !"))
  }

  @MainActor
  @Test("App launcher dismisses alert overlays and returns the workspace surface")
  func appLauncherDismissesAlertOverlays() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await MultiSceneLauncher.run(
      scene: WindowGroup("Alert Window") {
        AlertWindow()
      },
      sessionName: "AppRuntimeTests.AlertWindow",
      terminalHost: terminal,
      inputReader: ScriptedInputReader(events: [.return, .character("q")]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .quitKey)
    #expect(result.renderedFrames >= 2)

    let firstFrame = try #require(terminal.frames.first)
    let lastFrame = try #require(terminal.frames.last)
    #expect(firstFrame.contains("Archive task"))
    #expect(firstFrame.contains("Dismiss"))
    #expect(!lastFrame.contains("Archive task"))
    #expect(lastFrame.contains("Background"))
  }

  @MainActor
  @Test("runtime focus movement writes back into the rendered focus identity")
  func runtimeFocusMovementWritesBackIntoRenderedFocusIdentity() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await MultiSceneLauncher.run(
      scene: WindowGroup("Focus Window") {
        FocusReadoutWindow()
      },
      sessionName: "AppRuntimeTests.FocusWindow",
      terminalHost: terminal,
      inputReader: ScriptedInputReader(events: [.tab, .character("q")]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .quitKey)
    #expect(result.renderedFrames == 2)

    let firstFrame = try #require(terminal.frames.first)
    let secondFrame = try #require(terminal.frames.last)
    #expect(firstFrame.contains("Focus: none"))
    #expect(secondFrame.contains("Focus: SecondFocus"))
    #expect(secondFrame.contains("First"))
    #expect(secondFrame.contains("Second"))
  }

  @MainActor
  @Test("runtime focus falls back to the remaining control when the focused control disappears")
  func runtimeFocusFallsBackWhenFocusedControlDisappears() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await MultiSceneLauncher.run(
      scene: WindowGroup("Disappear Window") {
        DisappearingFocusWindow()
      },
      sessionName: "AppRuntimeTests.DisappearingFocusWindow",
      terminalHost: terminal,
      inputReader: ScriptedInputReader(events: [.tab, .return, .character("q")]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .quitKey)
    #expect(result.renderedFrames >= 3)

    let lastFrame = try #require(terminal.frames.last)
    #expect(lastFrame.contains("Focus: FirstFocus"))
    #expect(lastFrame.contains("Second visible: false"))
  }

  @MainActor
  @Test("arrow keys use geometry-aware top-level focus traversal")
  func arrowKeysUseGeometryAwareTopLevelFocusTraversal() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await MultiSceneLauncher.run(
      scene: WindowGroup("Geometry Focus Window") {
        GeometryFocusWindow()
      },
      sessionName: "AppRuntimeTests.GeometryFocusWindow",
      terminalHost: terminal,
      inputReader: ScriptedInputReader(events: [.arrowRight, .character("q")]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .quitKey)
    #expect(result.renderedFrames == 2)

    let lastFrame = try #require(terminal.frames.last)
    #expect(lastFrame.contains("Focus: Geometry/TopRight"))
  }

  @MainActor
  @Test("runtime focus sync writes the currently focused control into a bool FocusState binding")
  func runtimeFocusSyncWritesBoolFocusState() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await MultiSceneLauncher.run(
      scene: WindowGroup("Bool Focus Window") {
        BoolFocusStateWindow()
      },
      sessionName: "AppRuntimeTests.BoolFocusStateWindow",
      terminalHost: terminal,
      inputReader: ScriptedInputReader(events: [.character("q")]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .quitKey)

    let lastFrame = try #require(terminal.frames.last)
    #expect(lastFrame.contains("First focused: true"))
    #expect(lastFrame.contains("Focus: BoolFocusWindow/First"))
  }

  @MainActor
  @Test("programmatic bool FocusState requests move runtime focus before presentation")
  func programmaticBoolFocusStateRequestsMoveFocus() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await MultiSceneLauncher.run(
      scene: WindowGroup("Requested Focus Window") {
        RequestedBoolFocusWindow()
      },
      sessionName: "AppRuntimeTests.RequestedBoolFocusWindow",
      terminalHost: terminal,
      inputReader: ScriptedInputReader(events: [.character("q")]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .quitKey)

    let firstFrame = try #require(terminal.frames.first)
    #expect(firstFrame.contains("Focus: BoolFocusWindow/Second"))
    #expect(firstFrame.contains("Second requested: true"))
  }

  @MainActor
  @Test("optional FocusState equals bindings track runtime focus changes across controls")
  func optionalFocusStateTracksRuntimeFocusChanges() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await MultiSceneLauncher.run(
      scene: WindowGroup("Optional Focus Window") {
        OptionalFocusStateWindow()
      },
      sessionName: "AppRuntimeTests.OptionalFocusStateWindow",
      terminalHost: terminal,
      inputReader: ScriptedInputReader(events: [.tab, .character("q")]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .quitKey)

    let firstFrame = try #require(terminal.frames.first)
    let lastFrame = try #require(terminal.frames.last)
    #expect(firstFrame.contains("Field: first"))
    #expect(lastFrame.contains("Field: second"))
    #expect(lastFrame.contains("Focus: OptionalFocusWindow/SecondField"))
  }

  @MainActor
  @Test("FocusedValue reads the value published by the currently focused control")
  func focusedValueTracksFocusedControl() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await MultiSceneLauncher.run(
      scene: WindowGroup("Focused Value Window") {
        FocusedValueWindow()
      },
      sessionName: "AppRuntimeTests.FocusedValueWindow",
      terminalHost: terminal,
      inputReader: ScriptedInputReader(events: [.tab, .character("q")]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .quitKey)

    let firstFrame = try #require(terminal.frames.first)
    let lastFrame = try #require(terminal.frames.last)
    #expect(firstFrame.contains("Focused title: First"))
    #expect(lastFrame.contains("Focused title: Second"))
  }

  @MainActor
  @Test("FocusedValue includes ancestor publishers for a focused descendant")
  func focusedValueIncludesAncestorPublishers() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await MultiSceneLauncher.run(
      scene: WindowGroup("Focused Ancestor Window") {
        FocusedAncestorValueWindow()
      },
      sessionName: "AppRuntimeTests.FocusedAncestorValueWindow",
      terminalHost: terminal,
      inputReader: ScriptedInputReader(events: [.tab, .character("q")]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .quitKey)

    let firstFrame = try #require(terminal.frames.first)
    let lastFrame = try #require(terminal.frames.last)
    #expect(firstFrame.contains("Focused group: Primary"))
    #expect(lastFrame.contains("Focused group: Secondary"))
  }

  @MainActor
  @Test("defaultFocus seeds focus through a FocusState binding on first presentation")
  func defaultFocusSeedsFocusState() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await MultiSceneLauncher.run(
      scene: WindowGroup("Default Focus Window") {
        DefaultFocusWindow()
      },
      sessionName: "AppRuntimeTests.DefaultFocusWindow",
      terminalHost: terminal,
      inputReader: ScriptedInputReader(events: [.character("q")]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .quitKey)

    let firstFrame = try #require(terminal.frames.first)
    #expect(firstFrame.contains("Field: second"))
    #expect(firstFrame.contains("Focus: DefaultFocusWindow/Second"))
  }

  @Test("FocusedBinding reads binding values published through focusedSceneValue")
  func focusedBindingTracksFocusedSceneValue() {
    let registry = LocalFocusedValuesRegistry()
    let view = FocusedBindingWindow()

    let initialArtifacts = DefaultRenderer().render(
      view,
      context: .init(
        identity: testIdentity("Root"),
        localFocusedValuesRegistry: registry,
        applyEnvironmentValues: true
      )
    )
    let focusedValues = registry.focusedValues(
      for: testIdentity("FocusedBindingWindow", "Second"),
      in: initialArtifacts.resolvedTree
    )

    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("FocusedBindingWindow", "Second")
    environmentValues.focusedValues = focusedValues

    let focusedArtifacts = DefaultRenderer().render(
      view,
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      )
    )

    let surface = focusedArtifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Focused number: 2"))
  }

  @Test("isFocused and isFocusEffectEnabled reflect the focused subtree context")
  func focusEnvironmentReflectsFocusedSubtreeContext() throws {
    let initialArtifacts = DefaultRenderer().render(
      FocusEnvironmentWindow(),
      context: .init(identity: testIdentity("FocusEnvironmentWindow"))
    )
    let focusedIdentity = try #require(
      initialArtifacts.semanticSnapshot.focusRegions.first?.identity
    )

    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = focusedIdentity
    let artifacts = DefaultRenderer().render(
      FocusEnvironmentWindow(),
      context: .init(
        identity: testIdentity("FocusEnvironmentWindow"),
        environmentValues: environmentValues
      )
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Outer true"))
    #expect(surface.contains("Inner true false"))
  }
}

private struct GreetingApp: App {
  var body: some Scene {
    WindowGroup("Greeting Window") {
      GreetingScreen()
    }
  }
}

private struct MultiWindowApp: App {
  var body: some Scene {
    WindowGroup("One") {
      Text("One")
    }
    WindowGroup("Two") {
      Text("Two")
    }
  }
}

private struct GreetingScreen: View {
  var body: some View {
    GroupBox("Greeting") {
      Text("Hello from App")
    }
  }
}

private struct ActionWindow: View {
  let actionRecorder: ActionRecorder
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Launcher")
        .bold()
      GroupBox("Actions") {
        Text("The first button is focused automatically.")
        Text("Count \(count)")
        Button(
          "Increment",
          action: {
            count += 1
            actionRecorder.count = count
          }
        )
        .buttonStyle(.borderedProminent)
      }
      Text("Count \(count) | q quits")
        .foregroundStyle(.muted)
    }
  }
}

private struct StatefulFormWindow: View {
  @State private var name = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Form")
        .bold()
      GroupBox("Entry") {
        TextField("Name", text: $name)
          .frame(width: 16, alignment: .leading)
        Text("Name: \(name)")
      }
      Text("Name: \(name) | ctrl-c exits")
        .foregroundStyle(.muted)
    }
  }
}

private struct StatefulTextEditorWindow: View {
  @State private var notes = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Editor")
        .bold()
      TextEditor(text: $notes)
        .frame(width: 18, height: 5, alignment: .topLeading)
      Text("Lines: \(notes.split(separator: "\n", omittingEmptySubsequences: false).count)")
      Text("Preview: \(notes.replacingOccurrences(of: "\n", with: " | "))")
        .foregroundStyle(.muted)
    }
  }
}

private struct AlertWindow: View {
  @State private var isAlertPresented = true

  var body: some View {
    Button("Background") {}
      .id(testIdentity("AlertWindow", "Background"))
      .alert("Archive task", isPresented: $isAlertPresented)
  }
}

private struct FocusReadoutWindow: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      EnvironmentReader(\.focusedIdentity) { focusedIdentity in
        Text("Focus: \(focusedIdentity.map(\.description) ?? "none")")
      }
      Button("First") {}
        .id(testIdentity("FirstFocus"))
      Button("Second") {}
        .id(testIdentity("SecondFocus"))
    }
  }
}

private struct DisappearingFocusWindow: View {
  @State private var showSecond = true

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      EnvironmentReader(\.focusedIdentity) { focusedIdentity in
        Text("Focus: \(focusedIdentity.map(\.description) ?? "none")")
      }
      Button("First") {}
        .id(testIdentity("FirstFocus"))
      if showSecond {
        Button("Second") {
          showSecond = false
        }
        .id(testIdentity("SecondFocus"))
      }
      Text("Second visible: \(showSecond)")
    }
  }
}

private struct GeometryFocusWindow: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      EnvironmentReader(\.focusedIdentity) { focusedIdentity in
        Text("Focus: \(focusedIdentity.map(\.description) ?? "none")")
      }
      HStack(alignment: .top, spacing: 4) {
        VStack(alignment: .leading, spacing: 1) {
          Button("Top Left") {}
            .id(testIdentity("Geometry", "TopLeft"))
          Button("Bottom Left") {}
            .id(testIdentity("Geometry", "BottomLeft"))
        }
        VStack(alignment: .leading, spacing: 1) {
          Button("Top Right") {}
            .id(testIdentity("Geometry", "TopRight"))
          Button("Bottom Right") {}
            .id(testIdentity("Geometry", "BottomRight"))
        }
      }
    }
  }
}

private struct BoolFocusStateWindow: View {
  @FocusState private var isFirstFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      EnvironmentReader(\.focusedIdentity) { focusedIdentity in
        Text("Focus: \(focusedIdentity.map(\.description) ?? "none")")
      }
      Text("First focused: \(isFirstFocused)")
      Button("First") {}
        .id(testIdentity("BoolFocusWindow", "First"))
        .focused($isFirstFocused)
      Button("Second") {}
        .id(testIdentity("BoolFocusWindow", "Second"))
    }
  }
}

private struct RequestedBoolFocusWindow: View {
  @FocusState private var isSecondFocused: Bool

  init() {
    _isSecondFocused = FocusState()
    isSecondFocused = true
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      EnvironmentReader(\.focusedIdentity) { focusedIdentity in
        Text("Focus: \(focusedIdentity.map(\.description) ?? "none")")
      }
      Text("Second requested: \(isSecondFocused)")
      Button("First") {}
        .id(testIdentity("BoolFocusWindow", "First"))
      Button("Second") {}
        .id(testIdentity("BoolFocusWindow", "Second"))
        .focused($isSecondFocused)
    }
  }
}

private enum OptionalFocusField: String, Hashable {
  case first
  case second
}

private enum FocusedTitleKey: FocusedValueKey {
  typealias Value = String
}

private enum FocusedGroupKey: FocusedValueKey {
  typealias Value = String
}

private enum FocusedNumberKey: FocusedValueKey {
  typealias Value = Binding<Int>
}

extension FocusedValues {
  fileprivate var focusedTitle: String? {
    get { self[FocusedTitleKey.self] }
    set { self[FocusedTitleKey.self] = newValue }
  }

  fileprivate var focusedGroup: String? {
    get { self[FocusedGroupKey.self] }
    set { self[FocusedGroupKey.self] = newValue }
  }

  fileprivate var focusedNumber: Binding<Int>? {
    get { self[FocusedNumberKey.self] }
    set { self[FocusedNumberKey.self] = newValue }
  }
}

private struct OptionalFocusStateWindow: View {
  @FocusState private var focusedField: OptionalFocusField?

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      EnvironmentReader(\.focusedIdentity) { focusedIdentity in
        Text("Focus: \(focusedIdentity.map(\.description) ?? "none")")
      }
      Text("Field: \(focusedField?.rawValue ?? "none")")
      Button("First") {}
        .id(testIdentity("OptionalFocusWindow", "FirstField"))
        .focused($focusedField, equals: .first)
      Button("Second") {}
        .id(testIdentity("OptionalFocusWindow", "SecondField"))
        .focused($focusedField, equals: .second)
    }
  }
}

private struct FocusedValueWindow: View {
  @FocusedValue(\.focusedTitle) private var focusedTitle

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Focused title: \(focusedTitle ?? "none")")
      Button("First") {}
        .id(testIdentity("FocusedValueWindow", "First"))
        .focusedValue(\.focusedTitle, "First")
      Button("Second") {}
        .id(testIdentity("FocusedValueWindow", "Second"))
        .focusedValue(\.focusedTitle, "Second")
    }
  }
}

private struct FocusedAncestorValueWindow: View {
  @FocusedValue(\.focusedGroup) private var focusedGroup

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Focused group: \(focusedGroup ?? "none")")
      VStack(alignment: .leading, spacing: 1) {
        Button("First") {}
          .id(testIdentity("FocusedAncestorWindow", "First"))
      }
      .focusedValue(\.focusedGroup, "Primary")
      VStack(alignment: .leading, spacing: 1) {
        Button("Second") {}
          .id(testIdentity("FocusedAncestorWindow", "Second"))
      }
      .focusedValue(\.focusedGroup, "Secondary")
    }
  }
}

private enum DefaultFocusField: String, Hashable {
  case first
  case second
}

private struct DefaultFocusWindow: View {
  @FocusState private var focusedField: DefaultFocusField?

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      EnvironmentReader(\.focusedIdentity) { focusedIdentity in
        Text("Focus: \(focusedIdentity.map(\.description) ?? "none")")
      }
      Text("Field: \(focusedField?.rawValue ?? "none")")
      Button("First") {}
        .id(testIdentity("DefaultFocusWindow", "First"))
        .focused($focusedField, equals: .first)
      Button("Second") {}
        .id(testIdentity("DefaultFocusWindow", "Second"))
        .focused($focusedField, equals: .second)
    }
    .defaultFocus($focusedField, .second)
  }
}

private struct FocusedBindingWindow: View {
  @State private var first = 1
  @State private var second = 2
  @FocusedBinding(\.focusedNumber) private var focusedNumber

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Focused number: \(focusedNumber.map(String.init) ?? "none")")
      Button("First \(first)") {}
        .id(testIdentity("FocusedBindingWindow", "First"))
        .focusedSceneValue(\.focusedNumber, $first)
      Button("Second \(second)") {}
        .id(testIdentity("FocusedBindingWindow", "Second"))
        .focusedSceneValue(\.focusedNumber, $second)
    }
  }
}

private struct FocusEnvironmentWindow: View {
  var body: some View {
    EnvironmentReader(\.isFocused) { isFocused in
      VStack(alignment: .leading, spacing: 1) {
        Text("Outer \(isFocused)")
        Button(action: {}) {
          EnvironmentReader(\.isFocused) { isFocused in
            EnvironmentReader(\.isFocusEffectEnabled) { isFocusEffectEnabled in
              Text("Inner \(isFocused) \(isFocusEffectEnabled)")
            }
          }
        }
        .focusEffectDisabled()
      }
    }
  }
}

private final class ActionRecorder: @unchecked Sendable {
  var count = 0
}

private final class RecordingTerminalHost: TerminalHosting {
  let surfaceSize: Size
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance
  private(set) var frames: [String] = []
  private(set) var presentationMetrics: [TerminalPresentationMetrics] = []
  private(set) var presentedSurfaceSizes: [Size] = []
  private var lastPresentedSurface: RasterSurface?

  init(
    surfaceSize: Size = .init(width: 60, height: 18),
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
  func moveCursor(to _: Point) throws {}

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
          renderedOutput: rendered
        ).bytesWritten
      case .incremental:
        plan.spanUpdates.reduce(0) { partial, update in
          partial
            + cursorSequence(row: update.row, column: update.column).utf8.count
            + update.renderedSpan.utf8.count
        }
      }
    let metrics = TerminalPresentationMetrics(
      bytesWritten: bytesWritten,
      linesTouched: plan.linesTouched,
      cellsChanged: plan.cellsChanged,
      strategy: plan.strategy == .fullRepaint ? .fullRepaint : .incremental
    )
    presentationMetrics.append(metrics)
    presentedSurfaceSizes.append(surface.size)
    frames.append(rendered.replacingOccurrences(of: "\r\n", with: "\n"))
    lastPresentedSurface = surface
    return metrics
  }

  func write(_ output: String) throws {
    frames.append(output.replacingOccurrences(of: "\r\n", with: "\n"))
  }

  private func cursorSequence(row: Int, column: Int) -> String {
    "\u{001B}[\(max(1, row + 1));\(max(1, column + 1))H"
  }
}

private final class ScriptedInputReader: InputReading {
  private let scriptedEvents: [KeyPress]

  init(events: [KeyPress]) {
    scriptedEvents = events
  }

  convenience init(events: [KeyEvent]) {
    self.init(events: events.map { KeyPress($0) })
  }

  func events() -> AsyncStream<KeyPress> {
    AsyncStream { continuation in
      for event in scriptedEvents {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }
}

private final class EmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

extension ResolvedNode {
  fileprivate func descendant(withText text: String) -> ResolvedNode? {
    if drawPayload == .text(text) {
      return self
    }

    for child in children {
      if let match = child.descendant(withText: text) {
        return match
      }
    }

    return nil
  }
}
