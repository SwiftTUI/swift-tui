import Foundation
import Testing

@_spi(Runners) @testable import SwiftTUI
@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct AppRuntimeTests {
  @Test("App body resolves a single WindowGroup into a terminal scene")
  func appBodyResolvesSingleWindowGroup() throws {
    var visitor = AppRuntimeSceneVisitor()
    let selection = try #require(
      withFirstWindowSceneConfiguration(
        in: GreetingApp().body,
        visitor: &visitor
      )
    )

    #expect(selection.identifier == WindowIdentifier("Greeting-Window"))
    #expect(selection.rootIdentity == testIdentity("App", "Greeting-Window"))
    #expect(selection.artifacts.resolvedTree.descendant(withText: "Hello from App") != nil)
  }

  @Test("App body preserves multiple WindowGroup scenes without collapsing them")
  func appBodyPreservesMultipleScenes() {
    let descriptors = collectWindowSceneDescriptors(from: MultiWindowApp().body)

    #expect(descriptors.count == 2)
    #expect(descriptors.map(\.id) == [WindowIdentifier("One"), WindowIdentifier("Two")])
  }

  @MainActor
  @Test("App launcher renders stateful WindowGroup scenes and invokes local button actions")
  func appLauncherRunsWindowGroupScene() async throws {
    let terminal = RecordingTerminalHost()
    let actionRecorder = ActionRecorder()

    let result = try await runTestSceneSession(
      scene: WindowGroup("Action Window") {
        ActionWindow(actionRecorder: actionRecorder)
      },
      sessionName: "AppRuntimeTests.ActionWindow",
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [
        KeyPress(.return), KeyPress(.character("d"), modifiers: .ctrl),
      ]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(actionRecorder.count == 1)

    let firstFrame = try #require(terminal.frames.first)
    let lastFrame = try #require(terminal.frames.last)
    let firstMetrics = try #require(terminal.presentationMetrics.first)
    let firstSurfaceSize = try #require(terminal.presentedSurfaceSizes.first)
    #expect(firstFrame.contains("Launcher"))
    #expect(firstFrame.contains("Increment"))
    #expect(lastFrame.contains("Count 1"))
    #expect(lastFrame.contains("ctrl-d exits"))
    #expect(firstMetrics.usedFullRepaint)
    #expect(firstMetrics.cellsChanged == firstSurfaceSize.width * firstSurfaceSize.height)
  }

  @MainActor
  @Test("WindowGroup scenes present at the terminal canvas size even for small roots")
  func windowGroupScenesPresentAtTerminalCanvasSize() async throws {
    let terminal = RecordingTerminalHost(surfaceSize: .init(width: 20, height: 4))

    let result = try await runTestSceneSession(
      scene: WindowGroup("Canvas Window") {
        Text("Hello")
      },
      sessionName: "AppRuntimeTests.CanvasWindow",
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [KeyPress(.character("d"), modifiers: .ctrl)]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
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

    let result = try await runTestSceneSession(
      scene: WindowGroup("Clipped Window") {
        Rectangle()
          .fill(Color.red)
          .frame(width: 40, height: 10)
      },
      sessionName: "AppRuntimeTests.ClippedWindow",
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [KeyPress(.character("d"), modifiers: .ctrl)]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(terminal.presentedSurfaceSizes == [terminal.surfaceSize])
  }

  @MainActor
  @Test("App launcher preserves @State text-field bindings across runtime frames")
  func appLauncherPersistsStatefulTextFieldBindings() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await runTestSceneSession(
      scene: WindowGroup("Form Window") {
        StatefulFormWindow()
      },
      sessionName: "AppRuntimeTests.StatefulFormWindow",
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(
        events: [
          KeyPress(.return),
          KeyPress(.character("H")),
          KeyPress(.character("i")),
          KeyPress(.character("d"), modifiers: .ctrl),
        ]
      ),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))

    let lastFrame = try #require(terminal.frames.last)
    #expect(lastFrame.contains("Hi_"))
    #expect(lastFrame.contains("Name: Hi"))
    #expect(lastFrame.contains("ctrl-d exits"))
  }

  @MainActor
  @Test("App launcher preserves multiline TextEditor bindings across runtime frames")
  func appLauncherPersistsStatefulTextEditorBindings() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await runTestSceneSession(
      scene: WindowGroup("Editor Window") {
        StatefulTextEditorWindow()
      },
      sessionName: "AppRuntimeTests.StatefulTextEditorWindow",
      presentationSurface: terminal,
      inputReader: AwaitedScriptedInputReader(steps: [
        .press(KeyPress(.character("H"))),
        .press(KeyPress(.character("i"))),
        .press(KeyPress(.return)),
        .press(KeyPress(.character("!"))),
        .waitUntil {
          guard let lastFrame = terminal.frames.last else {
            return false
          }
          return lastFrame.contains("Lines: 2") && lastFrame.contains("Preview: Hi | !")
        },
        .press(KeyPress(.character("d"), modifiers: .ctrl)),
      ]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))

    let lastFrame = try #require(terminal.frames.last)
    #expect(lastFrame.contains("Hi"))
    #expect(lastFrame.contains("Lines: 2"))
    #expect(lastFrame.contains("Preview: Hi | !"))
  }

  @MainActor
  @Test("App launcher dismisses alert overlays and returns the workspace surface")
  func appLauncherDismissesAlertOverlays() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await runTestSceneSession(
      scene: WindowGroup("Alert Window") {
        AlertWindow()
      },
      sessionName: "AppRuntimeTests.AlertWindow",
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [
        KeyPress(.return), KeyPress(.character("d"), modifiers: .ctrl),
      ]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(result.renderedFrames >= 2)

    let firstFrame = try #require(terminal.frames.first)
    let lastFrame = try #require(terminal.frames.last)
    #expect(firstFrame.contains("Archive task"))
    #expect(firstFrame.contains("Dismiss"))
    #expect(!lastFrame.contains("Archive task"))
    #expect(lastFrame.contains("Background"))
  }

  @MainActor
  @Test("App launcher presents sheet overlays without resetting parent state")
  func appLauncherPresentsSheetOverlaysWithoutResettingParentState() async throws {
    let terminal = RecordingTerminalHost(surfaceSize: .init(width: 40, height: 12))

    let result = try await runTestSceneSession(
      scene: WindowGroup("Sheet Window") {
        SheetPresentationWindow()
      },
      sessionName: "AppRuntimeTests.SheetPresentationWindow",
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [
        KeyPress(.return), KeyPress(.character("d"), modifiers: .ctrl),
      ]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(result.renderedFrames >= 2)

    let firstFrame = try #require(terminal.frames.first)
    let lastFrame = try #require(terminal.frames.last)
    #expect(firstFrame.contains("Count 0"))
    #expect(lastFrame.contains("Count 1"))
    #expect(lastFrame.contains("Sheet body"))
  }

  @MainActor
  @Test("Pressing Escape dismisses an active sheet")
  func pressingEscapeDismissesActiveSheet() async throws {
    let terminal = RecordingTerminalHost(surfaceSize: .init(width: 40, height: 12))

    // Script: Enter presses the "Present" button (sheet opens), then
    // Escape dismisses, then Ctrl+D exits. The last rendered frame must not
    // contain the sheet body — the framework's Escape path has taken it
    // down, even though focus was inside the sheet's TextField (edit
    // interactions) at the time the key fired.
    let result = try await runTestSceneSession(
      scene: WindowGroup("Sheet Window") {
        SheetPresentationWindow()
      },
      sessionName: "AppRuntimeTests.SheetPresentationWindow.Escape",
      presentationSurface: terminal,
      inputReader: AwaitedScriptedInputReader(steps: [
        .press(KeyPress(.return)),
        .waitUntil {
          terminal.frames.contains { $0.contains("Sheet body") }
        },
        .press(KeyPress(.escape)),
        .waitUntil {
          guard let lastFrame = terminal.frames.last else {
            return false
          }
          return !lastFrame.contains("Sheet body") && lastFrame.contains("Count 1")
        },
        .press(KeyPress(.character("d"), modifiers: .ctrl)),
      ]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))

    let openedFrame = try #require(
      terminal.frames.first { $0.contains("Sheet body") },
      "Sheet never opened — Enter on Present should have raised it."
    )
    _ = openedFrame

    let lastFrame = try #require(terminal.frames.last)
    #expect(!lastFrame.contains("Sheet body"))
    // Parent state is preserved across the sheet lifecycle.
    #expect(lastFrame.contains("Count 1"))
  }

  @MainActor
  @Test("dismissing a sheet restores focus to the previously focused base control")
  func dismissingSheetRestoresFocusToThePreviouslyFocusedBaseControl() async throws {
    let terminal = RecordingTerminalHost(surfaceSize: .init(width: 72, height: 14))

    let result = try await runTestSceneSession(
      scene: WindowGroup("Sheet Focus Restoration") {
        SheetFocusRestorationWindow()
      },
      sessionName: "AppRuntimeTests.SheetFocusRestorationWindow",
      presentationSurface: terminal,
      inputReader: AwaitedScriptedInputReader(steps: [
        .press(KeyPress(.return)),
        .waitUntil {
          terminal.frames.contains { $0.contains("Sheet focus active: true") }
        },
        .press(KeyPress(.escape)),
        .waitUntil {
          guard let lastFrame = terminal.frames.last else {
            return false
          }
          return !lastFrame.contains("Sheet focus active: true")
            && lastFrame.contains("Base focused: true")
        },
        .press(KeyPress(.character("d"), modifiers: .ctrl)),
      ]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(result.renderedFrames >= 3)

    let firstFrame = try #require(terminal.frames.first)
    let sheetFrame = try #require(
      terminal.frames.first { $0.contains("Sheet focus active: true") }
    )
    let lastFrame = try #require(terminal.frames.last)

    #expect(firstFrame.contains("Base focused: true"))
    #expect(sheetFrame.contains("Sheet focus active: true"))
    #expect(lastFrame.contains("Base focused: true"))
  }

  @MainActor
  @Test("runtime focus movement writes back into the rendered focus identity")
  func runtimeFocusMovementWritesBackIntoRenderedFocusIdentity() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await runTestSceneSession(
      scene: WindowGroup("Focus Window") {
        FocusReadoutWindow()
      },
      sessionName: "AppRuntimeTests.FocusWindow",
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [
        KeyPress(.tab), KeyPress(.character("d"), modifiers: .ctrl),
      ]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
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

    let result = try await runTestSceneSession(
      scene: WindowGroup("Disappear Window") {
        DisappearingFocusWindow()
      },
      sessionName: "AppRuntimeTests.DisappearingFocusWindow",
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [
        KeyPress(.tab), KeyPress(.return), KeyPress(.character("d"), modifiers: .ctrl),
      ]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(result.renderedFrames >= 3)

    let lastFrame = try #require(terminal.frames.last)
    #expect(lastFrame.contains("Focus: FirstFocus"))
    #expect(lastFrame.contains("Second visible: false"))
  }

  @MainActor
  @Test("arrow keys use geometry-aware top-level focus traversal")
  func arrowKeysUseGeometryAwareTopLevelFocusTraversal() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await runTestSceneSession(
      scene: WindowGroup("Geometry Focus Window") {
        GeometryFocusWindow()
      },
      sessionName: "AppRuntimeTests.GeometryFocusWindow",
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [
        KeyPress(.arrowRight), KeyPress(.character("d"), modifiers: .ctrl),
      ]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(result.renderedFrames == 2)

    let lastFrame = try #require(terminal.frames.last)
    #expect(lastFrame.contains("Focus: Geometry/TopRight"))
  }

  @MainActor
  @Test("runtime focus sync writes the currently focused control into a bool FocusState binding")
  func runtimeFocusSyncWritesBoolFocusState() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await runTestSceneSession(
      scene: WindowGroup("Bool Focus Window") {
        BoolFocusStateWindow()
      },
      sessionName: "AppRuntimeTests.BoolFocusStateWindow",
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [KeyPress(.character("d"), modifiers: .ctrl)]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))

    let lastFrame = try #require(terminal.frames.last)
    #expect(lastFrame.contains("First focused: true"))
    #expect(lastFrame.contains("Focus: BoolFocusWindow/First"))
  }

  @MainActor
  @Test("programmatic bool FocusState requests move runtime focus before presentation")
  func programmaticBoolFocusStateRequestsMoveFocus() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await runTestSceneSession(
      scene: WindowGroup("Requested Focus Window") {
        RequestedBoolFocusWindow()
      },
      sessionName: "AppRuntimeTests.RequestedBoolFocusWindow",
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [KeyPress(.character("d"), modifiers: .ctrl)]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))

    let firstFrame = try #require(terminal.frames.first)
    #expect(firstFrame.contains("Focus: BoolFocusWindow/Second"))
    #expect(firstFrame.contains("Second requested: true"))
  }

  @MainActor
  @Test("optional FocusState equals bindings track runtime focus changes across controls")
  func optionalFocusStateTracksRuntimeFocusChanges() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await runTestSceneSession(
      scene: WindowGroup("Optional Focus Window") {
        OptionalFocusStateWindow()
      },
      sessionName: "AppRuntimeTests.OptionalFocusStateWindow",
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [
        KeyPress(.tab), KeyPress(.character("d"), modifiers: .ctrl),
      ]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))

    let firstFrame = try #require(terminal.frames.first)
    let lastFrame = try #require(terminal.frames.last)
    #expect(firstFrame.contains("Field: first"))
    #expect(lastFrame.contains("Field: second"))
    #expect(lastFrame.contains("Focus: OptionalFocusWindow/SecondField"))
  }

  @Test("focus synchronization rerender budget trips after the configured limit")
  func focusSynchronizationRerenderBudgetTripsAtTheConfiguredLimit() {
    var budget = FocusSyncRerenderBudget(maximumRerenders: 3)
    let recordRerender = {
      budget.recordRerender()
    }

    #expect(recordRerender())
    #expect(recordRerender())
    #expect(!recordRerender())
    #expect(budget.rerenderCount == 3)
  }

  @MainActor
  @Test("FocusedValue reads the value published by the currently focused control")
  func focusedValueTracksFocusedControl() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await runTestSceneSession(
      scene: WindowGroup("Focused Value Window") {
        FocusedValueWindow()
      },
      sessionName: "AppRuntimeTests.FocusedValueWindow",
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [
        KeyPress(.tab), KeyPress(.character("d"), modifiers: .ctrl),
      ]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))

    let firstFrame = try #require(terminal.frames.first)
    let lastFrame = try #require(terminal.frames.last)
    #expect(firstFrame.contains("Focused title: First"))
    #expect(lastFrame.contains("Focused title: Second"))
  }

  @MainActor
  @Test("FocusedValue includes ancestor publishers for a focused descendant")
  func focusedValueIncludesAncestorPublishers() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await runTestSceneSession(
      scene: WindowGroup("Focused Ancestor Window") {
        FocusedAncestorValueWindow()
      },
      sessionName: "AppRuntimeTests.FocusedAncestorValueWindow",
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [
        KeyPress(.tab), KeyPress(.character("d"), modifiers: .ctrl),
      ]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))

    let firstFrame = try #require(terminal.frames.first)
    let lastFrame = try #require(terminal.frames.last)
    #expect(firstFrame.contains("Focused group: Primary"))
    #expect(lastFrame.contains("Focused group: Secondary"))
  }

  @MainActor
  @Test("defaultFocus seeds focus through a FocusState binding on first presentation")
  func defaultFocusSeedsFocusState() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await runTestSceneSession(
      scene: WindowGroup("Default Focus Window") {
        DefaultFocusWindow()
      },
      sessionName: "AppRuntimeTests.DefaultFocusWindow",
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [KeyPress(.character("d"), modifiers: .ctrl)]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))

    let firstFrame = try #require(terminal.frames.first)
    #expect(firstFrame.contains("Field: second"))
    #expect(firstFrame.contains("Focus: DefaultFocusWindow/Second"))
  }

  @MainActor
  @Test("namespace default focus seeds and resetFocus restores the preferred candidate")
  func namespaceDefaultFocusSeedsAndResets() async throws {
    let terminal = RecordingTerminalHost()

    let result = try await runTestSceneSession(
      scene: WindowGroup("Namespace Default Focus Window") {
        NamespaceDefaultFocusWindow()
      },
      sessionName: "AppRuntimeTests.NamespaceDefaultFocusWindow",
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [
        KeyPress(.tab), KeyPress(.return), KeyPress(.character("d"), modifiers: .ctrl),
      ]),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))

    let firstFrame = try #require(terminal.frames.first)
    #expect(firstFrame.contains("Focus: NamespaceDefaultFocusWindow/Second"))

    let lastFrame = try #require(terminal.frames.last)
    #expect(lastFrame.contains("Reset count: 1"))
    #expect(lastFrame.contains("Focus: NamespaceDefaultFocusWindow/Second"))
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

@MainActor
private struct AppRuntimeSceneSelection {
  let identifier: WindowIdentifier
  let rootIdentity: Identity
  let artifacts: FrameArtifacts
}

@MainActor
private struct AppRuntimeSceneVisitor: WindowSceneConfigurationVisitor {
  mutating func visit<Content: View>(
    descriptor _: SceneDescriptor,
    configuration: WindowSceneConfiguration<Content>
  ) -> WindowSceneConfigurationVisitResult<AppRuntimeSceneSelection> {
    .finish(
      AppRuntimeSceneSelection(
        identifier: configuration.identifier,
        rootIdentity: configuration.rootIdentity,
        artifacts: DefaultRenderer().render(
          configuration.makeScopedRootView(),
          context: .init(identity: configuration.rootIdentity)
        )
      )
    )
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
      Text("Count \(count) | ctrl-d exits")
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
      Text("Name: \(name) | ctrl-d exits")
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

private struct SheetPresentationWindow: View {
  @State private var count = 0
  @State private var isSheetPresented = false
  @State private var draftTitle = ""
  @FocusState private var titleFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Count \(count)")
      Button("Present") {
        count += 1
        draftTitle = ""
        isSheetPresented = true
      }
    }
    .sheet("Inspector", isPresented: $isSheetPresented) {
      VStack(alignment: .leading, spacing: 1) {
        Text("Sheet body")
        TextField("Draft", text: $draftTitle)
          .focused($titleFocused)
          .onAppear {
            titleFocused = true
          }
      }
    }
  }
}

private struct SheetFocusRestorationWindow: View {
  @State private var isSheetPresented = false
  @State private var draft = ""
  @FocusState private var presentFocused: Bool
  @FocusState private var sheetFieldFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Base focused: \(presentFocused)")
      Button("Present") {
        isSheetPresented = true
      }
      .id(testIdentity("SheetFocusRestoration", "Present"))
      .focused($presentFocused)
      .onAppear {
        presentFocused = true
      }
    }
    .sheet("Inspector", isPresented: $isSheetPresented) {
      VStack(alignment: .leading, spacing: 1) {
        EnvironmentReader(\.focusedIdentity) { focusedIdentity in
          Text("Sheet focus active: \(focusedIdentity != nil)")
        }
        TextField("Draft", text: $draft)
          .focused($sheetFieldFocused)
          .onAppear {
            sheetFieldFocused = true
          }
        Button("Close") {
          isSheetPresented = false
        }
        .id(testIdentity("SheetFocusRestoration", "Close"))
      }
    }
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

private struct NamespaceDefaultFocusWindow: View {
  @Namespace private var namespace
  @State private var resetCount = 0

  var body: some View {
    EnvironmentReader(\.resetFocus) { resetFocus in
      VStack(alignment: .leading, spacing: 1) {
        EnvironmentReader(\.focusedIdentity) { focusedIdentity in
          Text("Focus: \(focusedIdentity.map(\.description) ?? "none")")
        }
        Text("Reset count: \(resetCount)")
        Button("First") {}
          .id(testIdentity("NamespaceDefaultFocusWindow", "First"))
        Button("Second") {}
          .id(testIdentity("NamespaceDefaultFocusWindow", "Second"))
          .prefersDefaultFocus(in: namespace)
        Button("Reset") {
          resetCount += 1
          resetFocus(in: namespace)
        }
        .id(testIdentity("NamespaceDefaultFocusWindow", "Reset"))
      }
      .focusScope(namespace)
    }
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

private final class ActionRecorder: Sendable {
  private let countStorage = LockedBox(0)

  var count: Int {
    get { countStorage.value }
    set { countStorage.value = newValue }
  }
}

private final class RecordingTerminalHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance
  private(set) var frames: [String] = []
  private(set) var presentationMetrics: [TerminalPresentationMetrics] = []
  private(set) var presentedSurfaceSizes: [CellSize] = []
  private var lastPresentedSurface: RasterSurface?

  init(
    surfaceSize: CellSize = .init(width: 60, height: 18),
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

private enum AwaitedInputStep {
  case press(KeyPress, delayNanoseconds: UInt64 = 0)
  case waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    predicate: @MainActor () -> Bool
  )
}

private final class AwaitedScriptedInputReader: InputReading {
  private let steps: [AwaitedInputStep]
  private let pollNanoseconds: UInt64

  init(
    steps: [AwaitedInputStep],
    pollNanoseconds: UInt64 = 10_000_000
  ) {
    self.steps = steps
    self.pollNanoseconds = pollNanoseconds
  }

  func events() -> AsyncStream<KeyPress> {
    AsyncStream { continuation in
      let steps = self.steps
      let pollNanoseconds = self.pollNanoseconds
      let task = Task { @MainActor in
        for step in steps {
          switch step {
          case .press(let event, let delayNanoseconds):
            if delayNanoseconds > 0 {
              try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            continuation.yield(event)
          case .waitUntil(let timeoutNanoseconds, let predicate):
            var elapsedNanoseconds: UInt64 = 0
            while !predicate() && elapsedNanoseconds < timeoutNanoseconds {
              try? await Task.sleep(nanoseconds: pollNanoseconds)
              elapsedNanoseconds += pollNanoseconds
            }
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
