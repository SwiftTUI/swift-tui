import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
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
      inputReader: AwaitedScriptedInputReader(
        frameSignal: terminal.frameSignal,
        steps: [
          .press(KeyPress(.character("H"))),
          .press(KeyPress(.character("i"))),
          .press(KeyPress(.return)),
          .press(KeyPress(.character("!"))),
          .awaitCondition {
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
      inputReader: AwaitedScriptedInputReader(
        frameSignal: terminal.frameSignal,
        steps: [
          .press(KeyPress(.return)),
          .awaitCondition {
            terminal.frames.contains { $0.contains("Sheet body") }
          },
          .press(KeyPress(.escape)),
          .awaitCondition {
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
  @Test("activating a sheet button dismisses the active sheet")
  func activatingSheetButtonDismissesActiveSheet() throws {
    let terminal = RecordingTerminalHost(surfaceSize: .init(width: 44, height: 12))
    let rootIdentity = testIdentity("SheetButtonDismissalRoot")
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [KeyPress]()),
      signalReader: EmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      proposal: .init(width: 44, height: 12),
      viewBuilder: { _, _ in
        SheetButtonDismissalWindow()
      }
    )
    focusTracker.invalidator = scheduler

    func render() throws -> String {
      var rendered = 0
      try runLoop.renderPendingFrames(renderedFrames: &rendered)
      return try #require(terminal.frames.last)
    }

    scheduler.requestInvalidation(of: [rootIdentity])
    _ = try render()

    #expect(runLoop.handle(RuntimeEvent.input(InputEvent.key(KeyPress(.return)))) == nil)
    let openedFrame = try render()
    #expect(openedFrame.contains("Sheet action body"))

    #expect(runLoop.handle(RuntimeEvent.input(InputEvent.key(KeyPress(.tab)))) == nil)
    _ = try render()
    let focusedSheetAction = try #require(focusTracker.currentFocusIdentity)
    #expect(
      runLoop.activationIdentity(for: focusedSheetAction) != nil,
      "Focused sheet action has no activation handler: \(focusedSheetAction)"
    )

    #expect(runLoop.handle(RuntimeEvent.input(InputEvent.key(KeyPress(.return)))) == nil)
    let lastFrame = try render()

    #expect(!lastFrame.contains("Sheet action body"))
    #expect(lastFrame.contains("Close count 1"))
  }

  @MainActor
  @Test("activating a confirmation-dialog action dismisses the active dialog")
  func activatingConfirmationDialogActionDismissesActiveDialog() throws {
    let terminal = RecordingTerminalHost(surfaceSize: .init(width: 52, height: 12))
    let rootIdentity = testIdentity("ConfirmationButtonDismissalRoot")
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [KeyPress]()),
      signalReader: EmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      proposal: .init(width: 52, height: 12),
      viewBuilder: { _, _ in
        ConfirmationDialogButtonDismissalWindow()
      }
    )
    focusTracker.invalidator = scheduler

    func render() throws -> String {
      var rendered = 0
      try runLoop.renderPendingFrames(renderedFrames: &rendered)
      return try #require(terminal.frames.last)
    }

    scheduler.requestInvalidation(of: [rootIdentity])
    _ = try render()

    #expect(runLoop.handle(RuntimeEvent.input(InputEvent.key(KeyPress(.return)))) == nil)
    let openedFrame = try render()
    #expect(openedFrame.contains("Reset presentation state?"))

    #expect(runLoop.handle(RuntimeEvent.input(InputEvent.key(KeyPress(.tab)))) == nil)
    _ = try render()
    #expect(runLoop.handle(RuntimeEvent.input(InputEvent.key(KeyPress(.tab)))) == nil)
    _ = try render()
    let focusedDialogAction = try #require(focusTracker.currentFocusIdentity)
    #expect(
      runLoop.activationIdentity(for: focusedDialogAction) != nil,
      "Focused confirmation-dialog action has no activation handler: \(focusedDialogAction)"
    )

    #expect(runLoop.handle(RuntimeEvent.input(InputEvent.key(KeyPress(.return)))) == nil)
    let lastFrame = try render()

    #expect(!lastFrame.contains("Reset presentation state?"))
    #expect(lastFrame.contains("Dialog actions 1"))
  }

  @MainActor
  @Test("clicking a sheet button dismisses the active sheet")
  func clickingSheetButtonDismissesActiveSheet() throws {
    let terminal = RecordingTerminalHost(surfaceSize: .init(width: 44, height: 12))
    let rootIdentity = testIdentity("SheetButtonClickDismissalRoot")
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [KeyPress]()),
      signalReader: EmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      proposal: .init(width: 44, height: 12),
      viewBuilder: { _, _ in
        SheetButtonDismissalWindow()
      }
    )
    focusTracker.invalidator = scheduler

    func render() throws -> String {
      var rendered = 0
      try runLoop.renderPendingFrames(renderedFrames: &rendered)
      return try #require(terminal.frames.last)
    }

    scheduler.requestInvalidation(of: [rootIdentity])
    _ = try render()

    #expect(runLoop.handle(RuntimeEvent.input(InputEvent.key(KeyPress(.return)))) == nil)
    let openedFrame = try render()
    #expect(openedFrame.contains("Sheet action body"))

    let closePoint = try #require(terminal.centerOfText("Close", chooseLast: true))
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .down(.primary), location: closePoint)))
      ) == nil
    )
    _ = try render()
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .up(.primary), location: closePoint)))
      ) == nil
    )
    let lastFrame = try render()

    #expect(!lastFrame.contains("Sheet action body"))
    #expect(lastFrame.contains("Close count 1"))
  }

  @MainActor
  @Test("clicking a confirmation-dialog action dismisses the active dialog")
  func clickingConfirmationDialogActionDismissesActiveDialog() throws {
    let terminal = RecordingTerminalHost(surfaceSize: .init(width: 52, height: 12))
    let rootIdentity = testIdentity("ConfirmationButtonClickDismissalRoot")
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [KeyPress]()),
      signalReader: EmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      proposal: .init(width: 52, height: 12),
      viewBuilder: { _, _ in
        ConfirmationDialogButtonDismissalWindow()
      }
    )
    focusTracker.invalidator = scheduler

    func render() throws -> String {
      var rendered = 0
      try runLoop.renderPendingFrames(renderedFrames: &rendered)
      return try #require(terminal.frames.last)
    }

    scheduler.requestInvalidation(of: [rootIdentity])
    _ = try render()

    #expect(runLoop.handle(RuntimeEvent.input(InputEvent.key(KeyPress(.return)))) == nil)
    let openedFrame = try render()
    #expect(openedFrame.contains("Reset presentation state?"))

    let resetPoint = try #require(terminal.centerOfText("Reset", chooseLast: true))
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .down(.primary), location: resetPoint)))
      ) == nil
    )
    _ = try render()
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .up(.primary), location: resetPoint)))
      ) == nil
    )
    let lastFrame = try render()

    #expect(!lastFrame.contains("Reset presentation state?"))
    #expect(lastFrame.contains("Dialog actions 1"))
  }

  @MainActor
  @Test("gallery-like presentation tab sheet and confirmation actions stay clickable")
  func galleryLikePresentationTabSheetAndConfirmationActionsStayClickable() throws {
    let terminal = RecordingTerminalHost(surfaceSize: .init(width: 80, height: 24))
    let rootIdentity = testIdentity("GalleryLikePresentationLabActionClick")
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [KeyPress]()),
      signalReader: EmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        GalleryLikePresentationLabWindow()
      }
    )
    focusTracker.invalidator = scheduler

    func render() throws -> String {
      var rendered = 0
      try runLoop.renderPendingFrames(renderedFrames: &rendered)
      return try #require(terminal.frames.last)
    }

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

    scheduler.requestInvalidation(of: [rootIdentity])
    let initialFrame = try render()
    #expect(initialFrame.contains("Presentation Lab"))
    #expect(initialFrame.contains("Last event: No presentation opened yet"))

    let sheetPoint = try #require(terminal.centerOfText("Sheet"))
    let sheetFrame = try click(sheetPoint)
    #expect(sheetFrame.contains("Sheet content"))

    let closePoint = try #require(terminal.centerOfText("Close"))
    let closedFrame = try click(closePoint)
    #expect(!closedFrame.contains("Sheet content"))
    #expect(closedFrame.contains("Last event: Sheet closed"))

    let confirmPoint = try #require(terminal.centerOfText("Confirm"))
    let dialogFrame = try click(confirmPoint)
    #expect(dialogFrame.contains("Reset presentation state?"))

    let resetPoint = try #require(terminal.centerOfText("Reset", chooseLast: true))
    let resetFrame = try click(resetPoint)
    #expect(!resetFrame.contains("Reset presentation state?"))
    #expect(resetFrame.contains("Last event: Confirmation reset"))
  }

  /// Direct framework reduction of the gallery "Presentation Lab overlays are
  /// sometimes unclosable; in that state the background remains interactive"
  /// bug (root `TODO.md`). Unlike
  /// `PresentationRouteSuppressionTests` (a bare `@State` fixture that passes),
  /// this drives the sheet behind the `TabView(.literalTabs)` shell — the seam
  /// the gallery integration oracle reproduces — and clicks the *background*
  /// trigger while the sheet is open. That suppressed-background-click step is
  /// what the existing gallery-like test never exercises.
  @Test("a sheet behind the TabView shell suppresses the background trigger and stays closable")
  func galleryLikePresentationTabSuppressesBackgroundClickWhileSheetOpen() throws {
    let terminal = RecordingTerminalHost(surfaceSize: .init(width: 80, height: 24))
    let rootIdentity = testIdentity("GalleryLikePresentationLabBackgroundSuppression")
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [KeyPress]()),
      signalReader: EmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        GalleryLikePresentationLabWindow()
      }
    )
    focusTracker.invalidator = scheduler

    func render() throws -> String {
      var rendered = 0
      try runLoop.renderPendingFrames(renderedFrames: &rendered)
      return try #require(terminal.frames.last)
    }

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

    scheduler.requestInvalidation(of: [rootIdentity])
    let initialFrame = try render()
    #expect(initialFrame.contains("Presentation Lab"))

    // Record the background "Confirm" trigger BEFORE any overlay is up.
    let confirmPoint = try #require(terminal.centerOfText("Confirm"))
    let sheetPoint = try #require(terminal.centerOfText("Sheet"))

    let opened = try click(sheetPoint)
    #expect(opened.contains("Sheet content"), "sheet did not open; frame:\n\(opened)")

    // Click the recorded background "Confirm" location while the sheet is open.
    // Correct behavior: the sheet disables base interaction, so the confirmation
    // dialog does NOT open and the sheet stays up. The reported bug lets the
    // background fire and/or drops the sheet.
    let afterBackgroundClick = try click(confirmPoint)
    #expect(
      !afterBackgroundClick.contains("Reset presentation state?"),
      "background Confirm trigger fired while the sheet was open; frame:\n\(afterBackgroundClick)"
    )
    #expect(
      afterBackgroundClick.contains("Sheet content"),
      "the sheet must stay open after a suppressed background click; frame:\n\(afterBackgroundClick)"
    )

    // The sheet's own Close control must dismiss it ("unclosable" guard).
    let closePoint = try #require(
      terminal.centerOfText("Close"),
      "the sheet Close control went missing; frame:\n\(afterBackgroundClick)"
    )
    let closed = try click(closePoint)
    #expect(
      !closed.contains("Sheet content"),
      "the sheet was un-closable via its own Close control; frame:\n\(closed)"
    )

    // Background routing is live again after dismissal.
    let afterReopen = try click(confirmPoint)
    #expect(
      afterReopen.contains("Reset presentation state?"),
      "background routing was not restored after the sheet closed; frame:\n\(afterReopen)"
    )
  }

  /// Framework reduction of the gallery "clicking the page background drops
  /// down the tab strip's arrow/more menu" regression (Navigation &
  /// Collections / Focus Context tabs). The selected tab lives in the
  /// overflow set and its page hosts a focusable region that declines the
  /// press (a non-overflowing `ScrollView` — the gallery shape at a large
  /// terminal), so the release falls through to the action-registry walk.
  /// That walk must not reach the `TabView` root action: it is registered at
  /// the control identity that also spans the whole page, but it is
  /// keyboard-only by contract (`tabViewSemanticMetadata` pins the root's
  /// interaction rect to zero so no pointer location is ever inside it).
  @Test("clicking the tab page background does not drop down the overflow menu")
  func tabPageBackgroundClickDoesNotDropDownOverflowMenu() throws {
    let terminal = RecordingTerminalHost(surfaceSize: .init(width: 80, height: 24))
    let rootIdentity = testIdentity("GalleryLikeOverflowBackgroundClick")
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [KeyPress]()),
      signalReader: EmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        GalleryLikeOverflowNavigationWindow()
      }
    )
    focusTracker.invalidator = scheduler

    func render() throws -> String {
      var rendered = 0
      try runLoop.renderPendingFrames(renderedFrames: &rendered)
      return try #require(terminal.frames.last)
    }

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

    scheduler.requestInvalidation(of: [rootIdentity])
    let initialFrame = try render()
    #expect(initialFrame.contains("Navigation content"))
    #expect(
      initialFrame.contains("▼"),
      "the selected tab must sit in the overflow set; frame:\n\(initialFrame)"
    )
    #expect(!initialFrame.contains("Popovers"))

    // Click empty page background: below the strip, inside the page's
    // full-width scroll region but right of its list and text content.
    let afterBackground = try click(Point(CellPoint(x: 60, y: 8)))
    #expect(
      !afterBackground.contains("Popovers") && !afterBackground.contains("▲"),
      "a background click dropped down the overflow menu; frame:\n\(afterBackground)"
    )
    #expect(afterBackground.contains("Navigation content"))

    // The trigger itself must keep opening the menu on a real click.
    let triggerPoint = try #require(terminal.centerOfText("▼"))
    let opened = try click(triggerPoint)
    #expect(
      opened.contains("▲") && opened.contains("Popovers"),
      "the overflow trigger stopped opening the menu; frame:\n\(opened)"
    )
  }

  /// Companion guard for the background-click regression test above: the
  /// `TabView` root action stays keyboard-reachable. Enter on the focused
  /// strip expands the overflow menu when the resolved tab sits in the
  /// overflow set — constraining *pointer* activation must not sever this.
  @Test("Enter on the focused strip still drops down the overflow menu")
  func tabStripEnterStillDropsDownOverflowMenu() throws {
    let terminal = RecordingTerminalHost(surfaceSize: .init(width: 80, height: 24))
    let rootIdentity = testIdentity("GalleryLikeOverflowStripEnter")
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: ScriptedInputReader(events: [KeyPress]()),
      signalReader: EmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        GalleryLikeOverflowNavigationWindow()
      }
    )
    focusTracker.invalidator = scheduler

    func render() throws -> String {
      var rendered = 0
      try runLoop.renderPendingFrames(renderedFrames: &rendered)
      return try #require(terminal.frames.last)
    }

    scheduler.requestInvalidation(of: [rootIdentity])
    let initialFrame = try render()
    #expect(initialFrame.contains("▼"))
    #expect(!initialFrame.contains("Popovers"))

    // Tab reaches the strip (the window's first focusable control); Enter
    // activates the root action, which expands the menu because the
    // resolved focused tab is the selected overflow tab.
    #expect(runLoop.handle(RuntimeEvent.input(InputEvent.key(KeyPress(.tab)))) == nil)
    _ = try render()
    #expect(runLoop.handle(RuntimeEvent.input(InputEvent.key(KeyPress(.return)))) == nil)
    let expanded = try render()
    #expect(
      expanded.contains("▲") && expanded.contains("Popovers"),
      "Enter on the focused strip must still expand the overflow menu; frame:\n\(expanded)"
    )
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
      inputReader: AwaitedScriptedInputReader(
        frameSignal: terminal.frameSignal,
        steps: [
          .press(KeyPress(.return)),
          .awaitCondition {
            terminal.frames.contains { $0.contains("Sheet focus active: true") }
          },
          .press(KeyPress(.escape)),
          .awaitCondition {
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
    #expect(result.renderedFrames >= 2)

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
  let artifacts: RenderSnapshot
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

private struct SheetButtonDismissalWindow: View {
  @State private var isSheetPresented = false
  @State private var closeCount = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Close count \(closeCount)")
      Button("Present") {
        isSheetPresented = true
      }
    }
    .sheet("Inspector", isPresented: $isSheetPresented) {
      VStack(alignment: .leading, spacing: 1) {
        Text("Sheet action body")
        Button("Close") {
          closeCount += 1
          isSheetPresented = false
        }
      }
    }
  }
}

private struct ConfirmationDialogButtonDismissalWindow: View {
  @State private var isDialogPresented = false
  @State private var actionCount = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Dialog actions \(actionCount)")
      Button("Confirm") {
        isDialogPresented = true
      }
    }
    .confirmationDialog(
      "Reset presentation state?",
      isPresented: $isDialogPresented,
      actions: {
        Button("Reset") {
          actionCount += 1
          isDialogPresented = false
        }
      },
      message: {
        Text("Confirmation dialogs sit near the invoking surface.")
      }
    )
  }
}

private struct GalleryLikePresentationLabWindow: View {
  @State private var selection = "presentation"

  var body: some View {
    TabView(selection: $selection) {
      Tab("Counter", value: "counter") {
        Text("Counter content")
      }

      Tab("Presentation Lab", value: "presentation") {
        GalleryLikePresentationLabTab()
      }

      Tab("Pointer Lab", value: "pointer-lab") {
        Text("Pointer Lab content")
      }
    }
    .tabViewStyle(.literalTabs)
  }
}

private struct GalleryLikePresentationLabTab: View {
  @State private var showConfirmation = false
  @State private var showSheet = false
  @State private var lastEvent = "No presentation opened yet"

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Presentation Lab")
      Divider()
      ControlGroup("Modals") {
        Button("Confirm") {
          showConfirmation = true
        }
        Button("Sheet") {
          showSheet = true
        }
      }
      Text("Last event: \(lastEvent)")
      Spacer(minLength: 0)
    }
    .padding(2)
    .confirmationDialog(
      "Reset presentation state?",
      isPresented: $showConfirmation,
      actions: {
        Button("Reset", role: .destructive) {
          lastEvent = "Confirmation reset"
          showConfirmation = false
        }
        Button("Cancel") {
          showConfirmation = false
        }
      },
      message: {
        Text("Confirmation dialogs sit near the invoking surface.")
      }
    )
    .sheet("Presentation Sheet", isPresented: $showSheet) {
      VStack(alignment: .leading, spacing: 1) {
        Text("Sheet content")
        Text("Sheets can host arbitrary SwiftTUI views.")
        Button("Close") {
          lastEvent = "Sheet closed"
          showSheet = false
        }
      }
      .padding(1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

/// Gallery-shaped overflow strip: the tab list is wide enough that the
/// literal-tabs style folds the tail — including the selected "Navigation &
/// Collections" tab — into the arrow/more menu at an 80-column terminal.
private struct GalleryLikeOverflowNavigationWindow: View {
  @State private var selection = "navigation"

  var body: some View {
    TabView(selection: $selection) {
      Tab("Logo", value: "logo") {
        Text("Logo content")
      }

      Tab("Counter", value: "counter") {
        Text("Counter content")
      }

      Tab("Life", value: "life") {
        Text("Life content")
      }

      Tab("Todo", value: "todo") {
        Text("Todo content")
      }

      Tab("Forms & Containers", value: "forms") {
        Text("Forms content")
      }

      Tab("Text Input", value: "text-input") {
        Text("Text Input content")
      }

      Tab("Scroll Control", value: "scroll-control") {
        Text("Scroll Control content")
      }

      Tab("Calculator", value: "calculator") {
        Text("Calculator content")
      }

      Tab("Borders & Shapes", value: "borders") {
        Text("Borders content")
      }

      Tab("Presentation Lab", value: "presentation") {
        Text("Presentation content")
      }

      Tab("Navigation & Collections", value: "navigation") {
        GalleryLikeNavigationCollectionsTab()
      }

      Tab("Images", value: "images") {
        Text("Images content")
      }

      Tab("Animations", value: "animations") {
        Text("Animations content")
      }

      Tab("File Drop", value: "file-drop") {
        Text("File Drop content")
      }

      Tab("Popovers", value: "popovers") {
        Text("Popovers content")
      }

      Tab("Focus Context", value: "focus-context") {
        Text("Focus Context content")
      }

      Tab("Progress", value: "progress") {
        Text("Progress content")
      }
    }
    .tabViewStyle(.literalTabs)
  }
}

/// The Navigation & Collections page shape that reproduces the background
/// click: a `NavigationStack`-hosted scroll container fills the page but its
/// content does not overflow the viewport (a large terminal), so the scroll
/// pointer handler declines the press and the click falls through to the
/// action-registry walk — while still minting the full-page focusable region
/// that lets the press arm at all.
private struct GalleryLikeNavigationCollectionsTab: View {
  @State private var selectedDoc = "overview"

  var body: some View {
    NavigationStack(id: "gallery-like-navigation-collections") {
      ScrollView {
        VStack(alignment: .leading, spacing: 1) {
          Text("Navigation content")
          List(selection: $selectedDoc) {
            Text("Overview").tag("overview")
            Text("Build lanes").tag("build-lanes")
          }
          .frame(width: 24, height: 4)
          Button("Open selected detail") {}
          Spacer(minLength: 0)
        }
        .padding(1)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

  /// Notified after every appended frame, so an awaited input step can
  /// re-check its predicate the instant a frame lands instead of polling.
  let frameSignal = MainActorConditionSignal()

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
    notifyFrameObservers()
    return metrics
  }

  func write(_ output: String) throws {
    frames.append(output.replacingOccurrences(of: "\r\n", with: "\n"))
    notifyFrameObservers()
  }

  func centerOfText(_ target: String, chooseLast: Bool = false) -> Point? {
    guard let surface = lastPresentedSurface else {
      return nil
    }

    if chooseLast {
      for row in surface.lines.indices.reversed() {
        let line = surface.lines[row]
        guard let range = line.range(of: target, options: .backwards) else {
          continue
        }
        let column = line.distance(from: line.startIndex, to: range.lowerBound)
        return Point(CellPoint(x: column + target.count / 2, y: row))
      }
      return nil
    }

    for (row, line) in surface.lines.enumerated() {
      guard let range = line.range(of: target) else {
        continue
      }
      let column = line.distance(from: line.startIndex, to: range.lowerBound)
      return Point(CellPoint(x: column + target.count / 2, y: row))
    }
    return nil
  }

  /// The run loop only ever presents on the MainActor; `assumeIsolated`
  /// bridges these nonisolated protocol witnesses to the MainActor-isolated
  /// signal.
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
  case press(KeyPress)
  /// Suspends the input script until `predicate` holds, re-evaluated only when
  /// the host appends a frame (`frameSignal.notify()`) rather than on a clock.
  case awaitCondition(predicate: @MainActor () -> Bool)
}

private final class AwaitedScriptedInputReader: InputReading {
  private let steps: [AwaitedInputStep]
  private let frameSignal: MainActorConditionSignal

  init(
    frameSignal: MainActorConditionSignal,
    steps: [AwaitedInputStep]
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
