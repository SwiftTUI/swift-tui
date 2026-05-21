import Dispatch
@_spi(Runners) @_spi(Testing) import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import GalleryDemoViews

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@MainActor
@Suite(.serialized)
struct GalleryTabSwitchTests {
  @Test("gallery tabs collapse into the overflow trigger instead of ellipsizing")
  func galleryTabsCollapseIntoOverflowTrigger() {
    var env = EnvironmentValues()
    env.terminalSize = .init(width: 80, height: 24)

    let artifacts = DefaultRenderer().render(
      GalleryView(),
      context: .init(
        identity: Identity(components: [.named("GalleryTabOverflowSurfaceTest")]),
        environmentValues: env
      ),
      proposal: .init(width: 40, height: 24)
    )

    let surface = artifacts.rasterSurface.lines.prefix(3).joined(separator: "\n")
    #expect(surface.contains("▾"))
    #expect(surface.contains("…") == false)
  }

  @Test("clicking a gallery tab switches tabs without crashing")
  func clickingGalleryTabSwitchesSelection() async throws {
    let terminalSize = CellSize(width: 80, height: 24)
    let rootIdentity = Identity(components: [.named("GalleryTabSwitchClickTest")])
    let todoClickCenter = try Self.centerOfText(
      "Todo",
      in: GalleryView(),
      terminalSize: terminalSize,
      rootIdentity: Identity(components: [
        .named("GalleryTabSwitchClickTest.BoundsProbe")
      ])
    )

    let host = GalleryTabSwitchRecordingHost(size: terminalSize)
    _ = try await Self.runHarness(
      host: host,
      terminalSize: terminalSize,
      events: [
        .mouse(.init(kind: .down(.primary), location: todoClickCenter)),
        .mouse(.init(kind: .up(.primary), location: todoClickCenter)),
      ],
      rootIdentity: rootIdentity,
      viewBuilder: { GalleryView() }
    )

    let lastPresented = try #require(host.lastPresentedSurface)
    let surface = lastPresented.lines.joined(separator: "\n")
    #expect(
      surface.contains("remaining"),
      "expected Todo tab content after clicking the Todo tab; surface was:\n\(surface)"
    )
  }

  @Test("deleting the top todo row does not switch the gallery back to Counter")
  func deletingTopTodoRowKeepsTodoSelected() async throws {
    let terminalSize = CellSize(width: 80, height: 24)
    let rootIdentity = Identity(components: [.named("GalleryTodoDeleteSelectionRegression")])
    let todoClickCenter = try Self.centerOfText(
      "Todo",
      in: GallerySelectionSeedHarness(initialSelection: .counter),
      terminalSize: terminalSize,
      rootIdentity: Identity(
        components: [.named("GalleryTodoDeleteSelectionRegression.TodoBoundsProbe")]
      )
    )
    let deleteClickCenter = try Self.centerOfText(
      "×",
      in: GallerySelectionSeedHarness(initialSelection: .todo),
      terminalSize: terminalSize,
      rootIdentity: Identity(
        components: [.named("GalleryTodoDeleteSelectionRegression.DeleteBoundsProbe")]
      ),
      chooseTopMost: true
    )

    let host = GalleryTabSwitchRecordingHost(size: terminalSize)
    _ = try await Self.runHarness(
      host: host,
      terminalSize: terminalSize,
      events: [
        .mouse(.init(kind: .down(.primary), location: todoClickCenter)),
        .mouse(.init(kind: .up(.primary), location: todoClickCenter)),
        .mouse(.init(kind: .down(.primary), location: deleteClickCenter)),
        .mouse(.init(kind: .up(.primary), location: deleteClickCenter)),
      ],
      rootIdentity: rootIdentity,
      viewBuilder: { GallerySelectionSeedHarness(initialSelection: .counter) }
    )

    let surface = try #require(host.lastPresentedSurface).lines.joined(separator: "\n")
    #expect(
      surface.contains("remaining"),
      "expected the Todo tab to stay selected after deleting the top row; surface was:\n\(surface)"
    )
  }

  @Test("real terminal host stays on Todo after deleting the top todo row")
  func realTerminalHostDeletingTopTodoRowKeepsTodoVisible() async throws {
    let terminalSize = CellSize(width: 80, height: 24)
    let rootIdentity = Identity(components: [.named("GalleryTodoDeleteRealTerminalHost")])
    let todoClickCenter = try Self.centerOfText(
      "Todo",
      in: GallerySelectionSeedHarness(initialSelection: .counter),
      terminalSize: terminalSize,
      rootIdentity: Identity(components: [
        .named("GalleryTodoDeleteRealTerminalHost.TodoBoundsProbe")
      ])
    )
    let deleteClickCenter = try Self.centerOfText(
      "×",
      in: GallerySelectionSeedHarness(initialSelection: .todo),
      terminalSize: terminalSize,
      rootIdentity: Identity(
        components: [.named("GalleryTodoDeleteRealTerminalHost.DeleteBoundsProbe")]
      ),
      chooseTopMost: true
    )

    let pty = try #require(Self.makePseudoTerminal(size: terminalSize))
    defer {
      _ = close(pty.master)
      _ = close(pty.slave)
    }

    let host = TerminalHost(
      inputFileDescriptor: pty.slave,
      outputFileDescriptor: pty.slave,
      fallbackSize: terminalSize,
      capabilityProfile: .previewUnicode
    )
    let inputReader = InputReader(fileDescriptor: pty.slave)

    let runTask = Task {
      try await Self.runHarness(
        presentationSurface: host,
        terminalInputReader: inputReader,
        terminalSize: terminalSize,
        rootIdentity: rootIdentity,
        viewBuilder: { GallerySelectionSeedHarness(initialSelection: .counter) }
      )
    }

    var screen = PTYVisibleScreen(size: terminalSize)

    let initialScreen = try await Self.waitForScreen(
      on: pty.master,
      screen: &screen
    ) { rendered in
      rendered.contains("Counter") && rendered.contains("Todo")
    }
    #expect(
      initialScreen.contains("Counter"),
      "expected the initial gallery frame to render; screen was:\n\(initialScreen)"
    )

    try Self.writeAllBytes(
      Self.sgrPrimaryClick(at: todoClickCenter),
      to: pty.master
    )

    let todoScreen = try await Self.waitForScreen(
      on: pty.master,
      screen: &screen
    ) { rendered in
      rendered.contains("remaining") && rendered.contains("Write docs")
    }
    #expect(
      todoScreen.contains("remaining"),
      "expected the Todo tab after clicking Todo; screen was:\n\(todoScreen)"
    )

    try Self.writeAllBytes(
      Self.sgrPrimaryClick(at: deleteClickCenter),
      to: pty.master
    )

    let afterDeleteScreen = try await Self.waitForScreen(
      on: pty.master,
      screen: &screen
    ) { rendered in
      rendered.contains("remaining") && !rendered.contains("Write docs")
    }

    let stableAfterDeleteScreen = try await Self.observeScreenWhileAbsent(
      on: pty.master,
      screen: &screen,
      timeoutNanoseconds: 400_000_000
    ) { rendered in
      rendered.contains("A SwiftUI-shaped terminal UI")
    }

    _ = close(pty.master)

    _ = try await runTask.value

    #expect(
      afterDeleteScreen.contains("remaining"),
      "expected the Todo tab to remain visible after deleting the top row; screen was:\n\(afterDeleteScreen)"
    )
    #expect(
      !afterDeleteScreen.contains("A SwiftUI-shaped terminal UI"),
      "expected not to snap back to the Counter tab; screen was:\n\(afterDeleteScreen)"
    )
    #expect(
      !stableAfterDeleteScreen.contains("A SwiftUI-shaped terminal UI"),
      "expected follow-up frames to stay on Todo after deleting the top row; screen was:\n\(stableAfterDeleteScreen)"
    )
    #expect(
      stableAfterDeleteScreen.contains("2 remaining"),
      "expected the deletion to persist across follow-up frames; screen was:\n\(stableAfterDeleteScreen)"
    )
  }

  @Test(
    "opening and dismissing the palette keeps Physics progress while Physics stays selected")
  func paletteOpenAndDismissKeepsPhysicsProgress() async throws {
    let terminalSize = CellSize(width: 80, height: 24)
    let rootIdentity = Identity(components: [.named("GalleryPhysicsPaletteContinuity")])
    let view = GallerySelectionSeedHarness(initialSelection: .physics)
    let host = GalleryTabSwitchRecordingHost(size: terminalSize)
    let capture = GallerySurfaceCapture()

    let result = try await Self.runHarness(
      presentationSurface: host,
      terminalInputReader: GalleryTabSwitchAwaitedInputReader(
        frameSignal: host.frameSignal,
        stageClock: host.stageClock,
        steps: [
          .awaitCondition {
            let surfaces = deduplicated(host.surfaces)
            guard surfaces.count >= 2 else {
              return false
            }
            capture.initialPhysicsSurface = capture.initialPhysicsSurface ?? surfaces.first
            capture.prePaletteSurface = surfaces.last
            return capture.prePaletteSurface != capture.initialPhysicsSurface
          },
          .event(.key(KeyPress(.character("k"), modifiers: .ctrl))),
          .awaitCondition {
            let text = host.lastPresentedSurface?.lines.joined(separator: "\n") ?? ""
            return text.contains("Command palette")
          },
          .event(.key(KeyPress(.escape, modifiers: []))),
          .awaitCondition {
            guard let surface = host.lastPresentedSurface else {
              return false
            }
            let text = surface.lines.joined(separator: "\n")
            guard !text.contains("Command palette"), !text.contains("palette sheet") else {
              return false
            }
            capture.postDismissSurface = surface
            return true
          },
          .event(.key(KeyPress(.character("d"), modifiers: .ctrl))),
        ]),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      viewBuilder: { view }
    )

    let initialPhysicsSurface = try #require(capture.initialPhysicsSurface)
    let prePaletteSurface = try #require(capture.prePaletteSurface)
    let postDismissSurface = try #require(capture.postDismissSurface)
    let postDismissText = postDismissSurface.lines.joined(separator: "\n")

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(
      prePaletteSurface != initialPhysicsSurface,
      "expected fullscreen animation to advance before opening the palette"
    )
    #expect(
      postDismissSurface != initialPhysicsSurface,
      "dismissing the palette should not recreate the physics tab at its initial spawn frame"
    )
    #expect(
      !postDismissText.contains("A SwiftUI-shaped terminal UI"),
      "dismissing the palette should keep the Full Screen tab selected; surface was:\n\(postDismissText)"
    )
  }

  @Test("selecting the gallery physics tab starts its gravity loop")
  func selectingPhysicsTabStartsGravityLoop() async throws {
    let terminalSize = CellSize(width: 160, height: 24)
    let rootIdentity = Identity(components: [.named("GalleryPhysicsSelectionStartsLoop")])
    let view = GallerySelectionSeedHarness(initialSelection: .counter)
    let tabClickCenter = try Self.centerOfText(
      "Full Screen",
      in: view,
      terminalSize: terminalSize,
      rootIdentity: Identity(components: [
        .named("GalleryPhysicsSelectionStartsLoop.BoundsProbe")
      ])
    )
    let host = GalleryTabSwitchRecordingHost(size: terminalSize)
    let capture = GalleryPhysicsSelectionCapture()

    let result = try await Self.runHarness(
      presentationSurface: host,
      terminalInputReader: GalleryTabSwitchAwaitedInputReader(
        frameSignal: host.frameSignal,
        stageClock: host.stageClock,
        steps: [
          .event(.mouse(.init(kind: .down(.primary), location: tabClickCenter))),
          .event(.mouse(.init(kind: .up(.primary), location: tabClickCenter))),
          .awaitCondition {
            guard let surface = host.lastPresentedSurface,
              Self.containsBrailleDrawing(surface)
            else {
              return false
            }
            capture.surfaceCountAtFirstPhysicsFrame = deduplicated(host.surfaces).count
            return true
          },
          .awaitCondition {
            deduplicated(host.surfaces).count >= capture.surfaceCountAtFirstPhysicsFrame + 2
          },
          .event(.key(KeyPress(.character("d"), modifiers: .ctrl))),
        ]),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      viewBuilder: { view }
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))

    let uniqueSurfaces = deduplicated(host.surfaces)
    #expect(
      uniqueSurfaces.count >= capture.surfaceCountAtFirstPhysicsFrame + 2,
      "expected selecting the gallery Physics tab to start gravity-driven frames"
    )
  }

  @Test("selecting the overflowed gallery physics tab starts its gravity loop")
  func selectingOverflowedPhysicsTabStartsGravityLoop() async throws {
    let terminalSize = CellSize(width: 80, height: 24)
    let rootIdentity = Identity(components: [.named("GalleryOverflowPhysicsSelectionStartsLoop")])
    let view = GallerySelectionSeedHarness(initialSelection: .counter)
    let overflowTriggerCenter = try Self.centerOfText(
      "▾",
      in: view,
      terminalSize: terminalSize,
      rootIdentity: Identity(components: [
        .named("GalleryOverflowPhysicsSelectionStartsLoop.BoundsProbe")
      ])
    )
    let host = GalleryTabSwitchRecordingHost(size: terminalSize)
    let capture = GalleryPhysicsSelectionCapture()

    let result = try await Self.runHarness(
      presentationSurface: host,
      terminalInputReader: GalleryTabSwitchAwaitedInputReader(
        frameSignal: host.frameSignal,
        stageClock: host.stageClock,
        steps: [
          .event(.mouse(.init(kind: .down(.primary), location: overflowTriggerCenter))),
          .event(.mouse(.init(kind: .up(.primary), location: overflowTriggerCenter))),
          .awaitCondition {
            guard let surface = host.lastPresentedSurface,
              let itemBounds = Self.boundsOfText("Full Screen", in: surface)
            else {
              return false
            }
            capture.overflowItemCenter = Self.centerPoint(of: itemBounds)
            return true
          },
          .eventFrom {
            .mouse(.init(kind: .down(.primary), location: capture.overflowItemCenter))
          },
          .eventFrom {
            .mouse(.init(kind: .up(.primary), location: capture.overflowItemCenter))
          },
          .awaitCondition {
            guard let surface = host.lastPresentedSurface,
              Self.containsBrailleDrawing(surface)
            else {
              return false
            }
            capture.surfaceCountAtFirstPhysicsFrame = deduplicated(host.surfaces).count
            return true
          },
          .awaitCondition {
            deduplicated(host.surfaces).count >= capture.surfaceCountAtFirstPhysicsFrame + 2
          },
          .event(.key(KeyPress(.character("d"), modifiers: .ctrl))),
        ]),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      viewBuilder: { view }
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))

    let uniqueSurfaces = deduplicated(host.surfaces)
    #expect(
      uniqueSurfaces.count >= capture.surfaceCountAtFirstPhysicsFrame + 2,
      "expected selecting overflowed Physics to start gravity-driven frames"
    )
  }

  @Test("gallery physics tab keeps advancing after a drag release")
  func physicsTabKeepsAdvancingAfterDragRelease() async throws {
    let terminalSize = CellSize(width: 80, height: 24)
    let rootIdentity = Identity(components: [.named("GalleryPhysicsReleaseContinuity")])
    let view = GallerySelectionSeedHarness(initialSelection: .physics)
    let host = GalleryTabSwitchRecordingHost(size: terminalSize)
    let capture = GalleryPhysicsReleaseCapture()

    let result = try await Self.runHarness(
      presentationSurface: host,
      terminalInputReader: GalleryTabSwitchAwaitedInputReader(
        frameSignal: host.frameSignal,
        stageClock: host.stageClock,
        steps: [
          .awaitCondition {
            let surfaces = deduplicated(host.surfaces)
            guard surfaces.count >= 4,
              let bounds = surfaces.last.flatMap(Self.brailleBounds(in:))
            else {
              return false
            }
            let start = Self.centerPoint(of: bounds)
            capture.dragStart = start
            capture.dragEnd = Point(x: start.x + 12, y: start.y - 5)
            return true
          },
          .eventFrom {
            .mouse(.init(kind: .down(.primary), location: capture.dragStart))
          },
          .eventFrom(
            delayNanoseconds: 30_000_000
          ) {
            .mouse(.init(kind: .dragged(.primary), location: capture.dragEnd))
          },
          .eventFrom(
            delayNanoseconds: 30_000_000
          ) {
            .mouse(.init(kind: .up(.primary), location: capture.dragEnd))
          },
          .awaitCondition {
            capture.surfaceCountAtRelease = deduplicated(host.surfaces).count
            return true
          },
          .awaitCondition {
            deduplicated(host.surfaces).count >= capture.surfaceCountAtRelease + 3
          },
          .event(.key(KeyPress(.character("d"), modifiers: .ctrl))),
        ]),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      viewBuilder: { view }
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(
      capture.surfaceCountAtRelease >= 4,
      "expected gravity-driven frames before dragging the gallery Physics tab"
    )

    let uniqueSurfaces = deduplicated(host.surfaces)
    #expect(
      uniqueSurfaces.count >= capture.surfaceCountAtRelease + 3,
      "expected multiple physics-driven frames after release, not only drag/release frames"
    )
    let postReleaseCenters =
      uniqueSurfaces
      .dropFirst(max(0, capture.surfaceCountAtRelease - 1))
      .compactMap { Self.brailleBounds(in: $0).map(Self.centerPoint(of:)) }
    let xPositions = Set(postReleaseCenters.map { $0.containingCell.x })
    let yPositions = Set(postReleaseCenters.map { $0.containingCell.y })

    #expect(
      xPositions.count >= 2,
      "expected the released Physics ball to keep horizontal momentum; centers: \(postReleaseCenters)"
    )
    #expect(
      yPositions.count >= 2,
      "expected the released Physics ball to keep responding to gravity; centers: \(postReleaseCenters)"
    )
  }

  @Test("real terminal host keeps gallery physics moving after drag release")
  func realTerminalHostPhysicsDragReleaseKeepsMoving() async throws {
    try await Self.realTerminalHostPhysicsDragReleaseKeepsMoving(
      mouseInputResolution: .preResolved(.cell),
      inputEncoding: .cells
    )
  }

  @Test("real terminal pixel mouse input keeps gallery physics moving after drag release")
  func realTerminalPixelMousePhysicsDragReleaseKeepsMoving() async throws {
    try await Self.realTerminalHostPhysicsDragReleaseKeepsMoving(
      mouseInputResolution: .preResolved(
        .sgrPixels(metrics: .init(width: 9, height: 18, source: .reported))
      ),
      inputEncoding: .pixels(width: 9, height: 18)
    )
  }

  @Test("scene-hosted real terminal keeps gallery physics moving")
  func sceneHostedRealTerminalPhysicsKeepsMoving() async throws {
    let terminalSize = CellSize(width: 80, height: 24)
    let pty = try #require(Self.makePseudoTerminal(size: terminalSize))
    defer {
      _ = close(pty.master)
      _ = close(pty.slave)
    }

    let host = TerminalHost(
      inputFileDescriptor: pty.slave,
      outputFileDescriptor: pty.slave,
      fallbackSize: terminalSize,
      capabilityProfile: .ansi16,
      mouseInputResolution: .preResolved(.cell)
    )
    let inputReader = InputReader(fileDescriptor: pty.slave)
    let runTask = Task {
      try await Self.runSceneHarness(
        scene: WindowGroup("Gallery Window") {
          GallerySelectionSeedHarness(initialSelection: .physics)
        },
        presentationSurface: host,
        terminalInputReader: inputReader,
        sessionName: "GalleryTabSwitchTests.SceneHostedPhysics"
      )
    }

    var screen = PTYVisibleScreen(size: terminalSize)
    let bounds = try await Self.collectDistinctBrailleBounds(
      on: pty.master,
      screen: &screen,
      minimumCount: 4
    )
    _ = close(pty.master)
    _ = try await runTask.value

    let centers = bounds.map(Self.centerPoint(of:))
    let yPositions = Set(centers.map { $0.containingCell.y })
    #expect(
      yPositions.count >= 2,
      "expected scene-hosted Physics to advance under gravity; centers: \(centers)"
    )
  }

  private static func realTerminalHostPhysicsDragReleaseKeepsMoving(
    mouseInputResolution: TerminalMouseInputResolution,
    inputEncoding: SGRMouseInputEncoding
  ) async throws {
    let terminalSize = CellSize(width: 80, height: 24)
    let rootIdentity = Identity(components: [.named("GalleryPhysicsRealTerminalRelease")])
    let pty = try #require(Self.makePseudoTerminal(size: terminalSize))
    defer {
      _ = close(pty.master)
      _ = close(pty.slave)
    }

    let host = TerminalHost(
      inputFileDescriptor: pty.slave,
      outputFileDescriptor: pty.slave,
      fallbackSize: terminalSize,
      capabilityProfile: .ansi16,
      mouseInputResolution: mouseInputResolution
    )
    let inputReader = InputReader(fileDescriptor: pty.slave)
    let runTask = Task {
      try await Self.runHarness(
        presentationSurface: host,
        terminalInputReader: inputReader,
        terminalSize: terminalSize,
        rootIdentity: rootIdentity,
        viewBuilder: { GallerySelectionSeedHarness(initialSelection: .physics) }
      )
    }

    var screen = PTYVisibleScreen(size: terminalSize)
    let preDragBounds = try await Self.collectDistinctBrailleBounds(
      on: pty.master,
      screen: &screen,
      minimumCount: 4
    )
    let start = Self.centerPoint(of: try #require(preDragBounds.last))
    let end = Point(x: start.x + 12, y: start.y - 5)

    // The press must land in an earlier read cycle than the drag/release, so
    // the velocity tracker sees a non-zero interval between its first and
    // last samples: wait for the runtime to present a frame in response to
    // the press before continuing.
    try Self.writeAllBytes(Self.sgrPrimaryDown(at: start, encoding: inputEncoding), to: pty.master)
    try await Self.waitForNextFrame(on: pty.master, screen: &screen)

    // The drag and release are written back to back with no suspension point
    // between them. `DragGestureRecognizer.computeVelocity` derives release
    // velocity from samples inside a trailing ~100ms window; the drag and the
    // release share a location, so if a slow read cycle let more than 100ms
    // elapse between parsing them the tracker would fall back to the
    // stationary drag sample and report zero horizontal momentum. Keeping
    // them in the same parser pass bounds that interval to the read loop,
    // well under the window, with no wall-clock dependency.
    try Self.writeAllBytes(Self.sgrPrimaryDrag(at: end, encoding: inputEncoding), to: pty.master)
    try Self.writeAllBytes(Self.sgrPrimaryUp(at: end, encoding: inputEncoding), to: pty.master)

    let postReleaseBounds = try await Self.collectDistinctBrailleBounds(
      on: pty.master,
      screen: &screen,
      minimumCount: 4
    )
    _ = close(pty.master)
    _ = try await runTask.value

    let centers = postReleaseBounds.map(Self.centerPoint(of:))
    let xPositions = Set(centers.map { $0.containingCell.x })
    let yPositions = Set(centers.map { $0.containingCell.y })

    #expect(
      xPositions.count >= 2,
      "expected real-terminal drag release to preserve horizontal momentum; centers: \(centers)"
    )
    #expect(
      yPositions.count >= 2,
      "expected real-terminal drag release to resume gravity; centers: \(centers)"
    )
  }

  @Test("gallery command palette lists tab commands")
  func galleryCommandPaletteListsTabCommands() async throws {
    let terminalSize = CellSize(width: 80, height: 24)
    let rootIdentity = Identity(components: [.named("GalleryCommandPaletteCommands")])
    let host = GalleryTabSwitchRecordingHost(size: terminalSize)
    let capture = GalleryCommandPaletteCapture()

    let result = try await Self.runHarness(
      presentationSurface: host,
      terminalInputReader: GalleryTabSwitchAwaitedInputReader(
        frameSignal: host.frameSignal,
        stageClock: host.stageClock,
        steps: [
          .awaitCondition {
            host.lastPresentedSurface != nil
          },
          .event(.key(KeyPress(.character("k"), modifiers: .ctrl))),
          .awaitCondition {
            guard let surface = host.lastPresentedSurface else {
              return false
            }
            let text = surface.lines.joined(separator: "\n")
            guard text.contains("Command palette") else {
              return false
            }
            capture.paletteSurface = surface
            return true
          },
          .event(.key(KeyPress(.character("d"), modifiers: .ctrl))),
        ]),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      viewBuilder: { GalleryView() }
    )

    let paletteSurface = try #require(capture.paletteSurface)
    let paletteText = paletteSurface.lines.joined(separator: "\n")
    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(
      !paletteText.contains("No commands in the current scope."),
      "expected gallery palette commands; surface was:\n\(paletteText)"
    )
    #expect(
      paletteText.contains("File Drop"),
      "expected the gallery palette to include tab commands; surface was:\n\(paletteText)"
    )
    #expect(
      paletteText.contains("Popovers"),
      "expected the gallery palette to include the popovers tab command; surface was:\n\(paletteText)"
    )
  }

  @Test("scene-hosted gallery stays on Todo after deleting the top todo row")
  func sceneHostedGalleryDeletingTopTodoRowKeepsTodoVisible() async throws {
    let terminalSize = CellSize(width: 80, height: 24)
    let todoClickCenter = try Self.centerOfText(
      "Todo",
      in: GalleryView(),
      terminalSize: terminalSize,
      rootIdentity: Identity(components: [
        .named("GalleryTodoDeleteSceneHostedBounds.TodoProbe")
      ])
    )
    let deleteClickCenter = try Self.centerOfText(
      "×",
      in: GallerySelectionSeedHarness(initialSelection: .todo),
      terminalSize: terminalSize,
      rootIdentity: Identity(components: [
        .named("GalleryTodoDeleteSceneHostedBounds.DeleteProbe")
      ]),
      chooseTopMost: true
    )

    let pty = try #require(Self.makePseudoTerminal(size: terminalSize))
    defer {
      _ = close(pty.master)
      _ = close(pty.slave)
    }

    let host = TerminalHost(
      inputFileDescriptor: pty.slave,
      outputFileDescriptor: pty.slave,
      fallbackSize: terminalSize,
      capabilityProfile: .previewUnicode
    )
    let inputReader = InputReader(fileDescriptor: pty.slave)

    let runTask = Task {
      try await Self.runSceneHarness(
        scene: WindowGroup("Gallery Window") {
          GalleryView()
        },
        presentationSurface: host,
        terminalInputReader: inputReader,
        sessionName: "GalleryTabSwitchTests.SceneHostedGalleryDelete"
      )
    }

    var screen = PTYVisibleScreen(size: terminalSize)

    let initialScreen = try await Self.waitForScreen(
      on: pty.master,
      screen: &screen
    ) { rendered in
      rendered.contains("Counter") && rendered.contains("Todo")
    }
    #expect(
      initialScreen.contains("Counter"),
      "expected the initial gallery frame to render; screen was:\n\(initialScreen)"
    )

    try Self.writeAllBytes(
      Self.sgrPrimaryClick(at: todoClickCenter),
      to: pty.master
    )

    let todoScreen = try await Self.waitForScreen(
      on: pty.master,
      screen: &screen
    ) { rendered in
      rendered.contains("remaining") && rendered.contains("Write docs")
    }
    #expect(
      todoScreen.contains("remaining"),
      "expected the Todo tab after clicking Todo; screen was:\n\(todoScreen)"
    )

    try Self.writeAllBytes(
      Self.sgrPrimaryClick(at: deleteClickCenter),
      to: pty.master
    )

    let afterDeleteScreen = try await Self.waitForScreen(
      on: pty.master,
      screen: &screen
    ) { rendered in
      rendered.contains("remaining") && !rendered.contains("Write docs")
    }

    let stableAfterDeleteScreen = try await Self.observeScreenWhileAbsent(
      on: pty.master,
      screen: &screen,
      timeoutNanoseconds: 400_000_000
    ) { rendered in
      rendered.contains("A SwiftUI-shaped terminal UI")
    }

    _ = close(pty.master)

    _ = try await runTask.value

    #expect(
      afterDeleteScreen.contains("remaining"),
      "expected the Todo tab to remain visible after deleting the top row; screen was:\n\(afterDeleteScreen)"
    )
    #expect(
      !afterDeleteScreen.contains("A SwiftUI-shaped terminal UI"),
      "expected not to snap back to the Counter tab; screen was:\n\(afterDeleteScreen)"
    )
    #expect(
      !stableAfterDeleteScreen.contains("A SwiftUI-shaped terminal UI"),
      "expected follow-up frames to stay on Todo after deleting the top row; screen was:\n\(stableAfterDeleteScreen)"
    )
    #expect(
      stableAfterDeleteScreen.contains("2 remaining"),
      "expected the deletion to persist across follow-up frames; screen was:\n\(stableAfterDeleteScreen)"
    )
  }

  private static func boundsOfText(
    _ target: String,
    in node: PlacedNode,
    chooseTopMost: Bool = false
  ) -> CellRect? {
    var matches: [CellRect] = []
    collectBoundsOfText(target, in: node, into: &matches)
    guard !matches.isEmpty else {
      return nil
    }
    if chooseTopMost {
      return matches.min(by: {
        if $0.origin.y == $1.origin.y {
          return $0.origin.x < $1.origin.x
        }
        return $0.origin.y < $1.origin.y
      })
    }
    return matches.first
  }

  private static func boundsOfText(
    _ target: String,
    in surface: RasterSurface
  ) -> CellRect? {
    for (row, line) in surface.lines.enumerated() {
      guard let range = line.range(of: target) else {
        continue
      }

      let column = line.distance(from: line.startIndex, to: range.lowerBound)
      return CellRect(
        origin: CellPoint(x: column, y: row),
        size: CellSize(width: target.count, height: 1)
      )
    }
    return nil
  }

  private static func centerOfText(
    _ target: String,
    in view: some View,
    terminalSize: CellSize,
    rootIdentity: Identity,
    chooseTopMost: Bool = false
  ) throws -> Point {
    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let artifacts = DefaultRenderer().render(
      AnyView(view),
      context: .init(identity: rootIdentity, environmentValues: env),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )
    let bounds = try #require(
      Self.boundsOfText(target, in: artifacts.placedTree, chooseTopMost: chooseTopMost)
    )
    return Self.centerPoint(of: bounds)
  }

  private static func collectBoundsOfText(
    _ target: String,
    in node: PlacedNode,
    into matches: inout [CellRect]
  ) {
    if case .text(let content) = node.drawPayload, content == target {
      matches.append(node.bounds)
    }
    for child in node.children {
      collectBoundsOfText(target, in: child, into: &matches)
    }
  }

  private static func centerPoint(of rect: CellRect) -> Point {
    Point(
      CellPoint(
        x: rect.origin.x + rect.size.width / 2,
        y: rect.origin.y + rect.size.height / 2
      )
    )
  }

  private static func firstShapeBounds(in node: PlacedNode) -> CellRect? {
    if case .shape = node.drawPayload {
      return node.bounds
    }
    for child in node.children {
      if let match = firstShapeBounds(in: child) {
        return match
      }
    }
    return nil
  }

  private static func containsBrailleDrawing(_ surface: RasterSurface) -> Bool {
    surface.lines.contains { line in
      line.unicodeScalars.contains { scalar in
        (0x2800...0x28FF).contains(Int(scalar.value))
      }
    }
  }

  private static func brailleBounds(in surface: RasterSurface) -> CellRect? {
    var minX = Int.max
    var minY = Int.max
    var maxX = Int.min
    var maxY = Int.min

    for (y, line) in surface.lines.enumerated() {
      var x = 0
      for scalar in line.unicodeScalars {
        if (0x2800...0x28FF).contains(Int(scalar.value)) {
          minX = min(minX, x)
          minY = min(minY, y)
          maxX = max(maxX, x)
          maxY = max(maxY, y)
        }
        x += 1
      }
    }

    guard minX <= maxX, minY <= maxY else {
      return nil
    }
    return CellRect(
      origin: CellPoint(x: minX, y: minY),
      size: CellSize(width: maxX - minX + 1, height: maxY - minY + 1)
    )
  }

  private static func brailleBounds(in rendered: String) -> CellRect? {
    var minX = Int.max
    var minY = Int.max
    var maxX = Int.min
    var maxY = Int.min

    for (y, line) in rendered.split(separator: "\n", omittingEmptySubsequences: false)
      .enumerated()
    {
      var x = 0
      for scalar in line.unicodeScalars {
        if (0x2800...0x28FF).contains(Int(scalar.value)) {
          minX = min(minX, x)
          minY = min(minY, y)
          maxX = max(maxX, x)
          maxY = max(maxY, y)
        }
        x += 1
      }
    }

    guard minX <= maxX, minY <= maxY else {
      return nil
    }
    return CellRect(
      origin: CellPoint(x: minX, y: minY),
      size: CellSize(width: maxX - minX + 1, height: maxY - minY + 1)
    )
  }

  @MainActor
  private static func runHarness<V: View>(
    host: GalleryTabSwitchRecordingHost,
    terminalSize: CellSize,
    events: [InputEvent],
    rootIdentity: Identity,
    viewBuilder: @escaping () -> V
  ) async throws -> RunLoopResult<Int> {
    try await runHarness(
      presentationSurface: host,
      terminalInputReader: GalleryTabSwitchScriptedInput(events: events),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      viewBuilder: viewBuilder
    )
  }

  @MainActor
  private static func runHarness<V: View>(
    presentationSurface: any PresentationSurface,
    terminalInputReader: GalleryTabSwitchAwaitedInputReader,
    terminalSize: CellSize,
    rootIdentity: Identity,
    viewBuilder: @escaping () -> V
  ) async throws -> RunLoopResult<Int> {
    let result = try await runHarness(
      presentationSurface: presentationSurface,
      terminalInputReader: terminalInputReader as any TerminalInputReading,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      viewBuilder: viewBuilder
    )
    try await terminalInputReader.requireNoWaitFailure()
    return result
  }

  @MainActor
  private static func runHarness<V: View>(
    presentationSurface: any PresentationSurface,
    terminalInputReader: any TerminalInputReading,
    terminalSize: CellSize,
    rootIdentity: Identity,
    viewBuilder: @escaping () -> V
  ) async throws -> RunLoopResult<Int> {
    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: presentationSurface,
      terminalInputReader: terminalInputReader,
      signalReader: GalleryTabSwitchEmptySignals(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: env,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in viewBuilder() }
    )
    // These gallery tests exercise tab, gesture, and scene composition. The
    // async frame-tail contract is covered separately, so keep this harness on
    // the deterministic sync path under Linux load.
    runLoop.renderMode = .sync
    return try await runLoop.run()
  }

  @MainActor
  private static func runSceneHarness<S: Scene>(
    scene: S,
    presentationSurface: any PresentationSurface,
    terminalInputReader: any TerminalInputReading,
    sessionName: String
  ) async throws -> RunLoopResult<SceneSessionState> {
    let selections = collectWindowSceneSelections(from: scene)
    guard let selection = selections.first else {
      throw AppLaunchError.noScenes
    }
    guard selections.count == 1 else {
      fatalError("expected a single scene for the gallery test harness")
    }

    return try await selection.run(
      sessionName: sessionName,
      resources: .init(
        presentationSurface: presentationSurface,
        terminalInputReader: terminalInputReader,
        signalReader: GalleryTabSwitchEmptySignals(),
        scheduler: FrameScheduler(),
        renderMode: .sync
      ),
      stateContainer: StateContainer(
        initialState: SceneSessionState(),
        invalidationIdentities: [selection.rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [selection.rootIdentity]
      )
    )
  }

  private static func makePseudoTerminal(
    size: CellSize
  ) -> (master: Int32, slave: Int32)? {
    var master: Int32 = -1
    var slave: Int32 = -1
    var windowSize = winsize(
      ws_row: UInt16(max(1, size.height)),
      ws_col: UInt16(max(1, size.width)),
      ws_xpixel: 0,
      ws_ypixel: 0
    )

    guard
      openpty(
        &master,
        &slave,
        nil,
        nil,
        &windowSize
      ) == 0
    else {
      return nil
    }

    let currentFlags = fcntl(master, F_GETFL)
    guard currentFlags >= 0 else {
      _ = close(master)
      _ = close(slave)
      return nil
    }
    guard fcntl(master, F_SETFL, currentFlags | O_NONBLOCK) == 0 else {
      _ = close(master)
      _ = close(slave)
      return nil
    }

    return (master, slave)
  }

  private static func writeAllBytes(
    _ bytes: [UInt8],
    to fileDescriptor: Int32
  ) throws {
    var totalBytesWritten = 0

    try unsafe bytes.withUnsafeBytes { rawBuffer in
      guard let baseAddress = rawBuffer.baseAddress else {
        return
      }

      while totalBytesWritten < bytes.count {
        let nextAddress = unsafe baseAddress.advanced(by: totalBytesWritten)
        let bytesRemaining = bytes.count - totalBytesWritten
        let bytesWritten = unsafe write(fileDescriptor, nextAddress, bytesRemaining)
        guard bytesWritten >= 0 else {
          throw TerminalHostError.failedToWrite(errno: errno)
        }
        totalBytesWritten += bytesWritten
      }
    }
  }

  private static func sgrPrimaryClick(
    at point: Point
  ) -> [UInt8] {
    sgrMouse(encodedButton: 0, terminator: "M", at: point)
      + sgrMouse(encodedButton: 0, terminator: "m", at: point)
  }

  private static func sgrPrimaryDown(
    at point: Point,
    encoding: SGRMouseInputEncoding = .cells
  ) -> [UInt8] {
    sgrMouse(encodedButton: 0, terminator: "M", at: point, encoding: encoding)
  }

  private static func sgrPrimaryDrag(
    at point: Point,
    encoding: SGRMouseInputEncoding = .cells
  ) -> [UInt8] {
    sgrMouse(encodedButton: 32, terminator: "M", at: point, encoding: encoding)
  }

  private static func sgrPrimaryUp(
    at point: Point,
    encoding: SGRMouseInputEncoding = .cells
  ) -> [UInt8] {
    sgrMouse(encodedButton: 0, terminator: "m", at: point, encoding: encoding)
  }

  private static func sgrMouse(
    encodedButton: Int,
    terminator: String,
    at point: Point,
    encoding: SGRMouseInputEncoding = .cells
  ) -> [UInt8] {
    let encoded = encoding.encodedCoordinates(for: point)
    return Array(
      "\u{001B}[<\(encodedButton);\(encoded.x);\(encoded.y)\(terminator)"
        .utf8
    )
  }

  private enum ScreenWaitError: Error, CustomStringConvertible {
    case timedOut(rendered: String)
    case forbiddenStateObserved(rendered: String)

    var description: String {
      switch self {
      case .timedOut(let rendered):
        "Timed out waiting for screen condition; last screen was:\n\(rendered)"
      case .forbiddenStateObserved(let rendered):
        "Observed forbidden screen state:\n\(rendered)"
      }
    }
  }

  private static func waitForScreen(
    on fileDescriptor: Int32,
    screen: inout PTYVisibleScreen,
    condition: (String) -> Bool
  ) async throws -> String {
    var rendered = screen.renderedText
    let initial = try readAvailableBytes(from: fileDescriptor)
    if !initial.bytes.isEmpty {
      screen.feed(initial.bytes)
      rendered = screen.renderedText
    }
    if condition(rendered) {
      return rendered
    }

    let readable = PTYReadableSource(fileDescriptor: fileDescriptor)
    var outcome: Result<String, any Error> = .failure(
      ScreenWaitError.timedOut(rendered: rendered)
    )
    for await _ in readable.events {
      let next: (bytes: [UInt8], reachedEOF: Bool)
      do {
        next = try readAvailableBytes(from: fileDescriptor)
      } catch {
        outcome = .failure(error)
        break
      }
      if !next.bytes.isEmpty {
        screen.feed(next.bytes)
        rendered = screen.renderedText
      }
      if condition(rendered) {
        outcome = .success(rendered)
        break
      }
      if next.reachedEOF {
        // The PTY closed before the screen reached the awaited state — the
        // condition can never hold now, so fail rather than await forever.
        outcome = .failure(ScreenWaitError.timedOut(rendered: rendered))
        break
      }
    }
    // Tear the read source fully down *before* returning, so the caller may
    // safely close the file descriptor.
    await readable.cancel()
    return try outcome.get()
  }

  private static func observeScreenWhileAbsent(
    on fileDescriptor: Int32,
    screen: inout PTYVisibleScreen,
    timeoutNanoseconds: UInt64,
    pollNanoseconds: UInt64 = 5_000_000,
    forbidden: (String) -> Bool
  ) async throws -> String {
    // A bounded *negative* assertion: confirm `forbidden` stays false for a
    // fixed observation window. There is no event that signals "nothing
    // happened", so this deliberately keeps a wall-clock loop — a documented
    // test-sync ratchet exception.
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    var rendered = screen.renderedText
    if forbidden(rendered) {
      throw ScreenWaitError.forbiddenStateObserved(rendered: rendered)
    }

    while DispatchTime.now().uptimeNanoseconds < deadline {
      let chunk = try readAvailableBytes(from: fileDescriptor)
      if !chunk.bytes.isEmpty {
        screen.feed(chunk.bytes)
        rendered = screen.renderedText
      }
      if forbidden(rendered) {
        throw ScreenWaitError.forbiddenStateObserved(rendered: rendered)
      }
      try await Task.sleep(nanoseconds: pollNanoseconds)
    }

    let finalChunk = try readAvailableBytes(from: fileDescriptor)
    if !finalChunk.bytes.isEmpty {
      screen.feed(finalChunk.bytes)
    }
    rendered = screen.renderedText
    if forbidden(rendered) {
      throw ScreenWaitError.forbiddenStateObserved(rendered: rendered)
    }
    return rendered
  }

  private static func collectDistinctBrailleBounds(
    on fileDescriptor: Int32,
    screen: inout PTYVisibleScreen,
    minimumCount: Int
  ) async throws -> [CellRect] {
    var bounds: [CellRect] = []

    func absorb(_ chunk: (bytes: [UInt8], reachedEOF: Bool)) -> [CellRect]? {
      if !chunk.bytes.isEmpty {
        screen.feed(chunk.bytes)
      }
      if let next = brailleBounds(in: screen.renderedText), bounds.last != next {
        bounds.append(next)
        if bounds.count >= minimumCount {
          return bounds
        }
      }
      return nil
    }

    if let collected = absorb(try readAvailableBytes(from: fileDescriptor)) {
      return collected
    }

    let readable = PTYReadableSource(fileDescriptor: fileDescriptor)
    var outcome: Result<[CellRect], any Error> = .failure(
      ScreenWaitError.timedOut(rendered: screen.renderedText)
    )
    for await _ in readable.events {
      let chunk: (bytes: [UInt8], reachedEOF: Bool)
      do {
        chunk = try readAvailableBytes(from: fileDescriptor)
      } catch {
        outcome = .failure(error)
        break
      }
      if let collected = absorb(chunk) {
        outcome = .success(collected)
        break
      }
      if chunk.reachedEOF {
        outcome = .failure(ScreenWaitError.timedOut(rendered: screen.renderedText))
        break
      }
    }
    await readable.cancel()
    return try outcome.get()
  }

  /// Awaits one frame's worth of PTY output, draining it into `screen`.
  ///
  /// Used to pace scripted drag input: the next byte sequence is written only
  /// once the runtime has actually responded to the previous one, so the
  /// input parser stamps the down/drag/up events at genuinely separated
  /// times — with no fixed wall-clock sleep between them.
  private static func waitForNextFrame(
    on fileDescriptor: Int32,
    screen: inout PTYVisibleScreen
  ) async throws {
    let readable = PTYReadableSource(fileDescriptor: fileDescriptor)
    var readError: (any Error)?
    for await _ in readable.events {
      do {
        let chunk = try readAvailableBytes(from: fileDescriptor)
        if !chunk.bytes.isEmpty {
          screen.feed(chunk.bytes)
          break
        }
        if chunk.reachedEOF {
          break
        }
      } catch {
        readError = error
        break
      }
    }
    await readable.cancel()
    if let readError {
      throw readError
    }
  }

  private static func readAvailableBytes(
    from fileDescriptor: Int32
  ) throws -> (bytes: [UInt8], reachedEOF: Bool) {
    var collected: [UInt8] = []

    while true {
      var buffer = Array(repeating: UInt8(0), count: 4096)
      let bytesRead = unsafe read(fileDescriptor, &buffer, buffer.count)

      if bytesRead > 0 {
        collected.append(contentsOf: buffer.prefix(Int(bytesRead)))
        continue
      }

      if bytesRead == 0 {
        return (collected, true)
      }

      if errno == EAGAIN || errno == EWOULDBLOCK {
        return (collected, false)
      }

      throw TerminalHostError.failedToReadWindowSize(errno: errno)
    }
  }
}

/// A `DispatchSource`-backed "the PTY has bytes" signal.
///
/// Replaces fixed-interval polling of a PTY master fd: `events` yields once
/// per readable edge (data available, or EOF). The caller MUST `await
/// cancel()` before closing the file descriptor — `cancel()` tears the source
/// down and waits until libdispatch has released its hold on the fd, which
/// avoids the trap that closing the fd under a live source would cause.
private final class PTYReadableSource {
  let events: AsyncStream<Void>
  private let source: any DispatchSourceRead
  private let cancelled = AsyncEvent()

  init(fileDescriptor: Int32) {
    let source = DispatchSource.makeReadSource(
      fileDescriptor: fileDescriptor,
      queue: DispatchQueue(label: "GalleryTabSwitchTests.ptyReadable")
    )
    self.source = source

    var streamContinuation: AsyncStream<Void>.Continuation!
    events = AsyncStream<Void> { streamContinuation = $0 }
    let continuation = streamContinuation!
    let cancelledEvent = cancelled

    source.setEventHandler {
      continuation.yield(())
    }
    source.setCancelHandler {
      continuation.finish()
      cancelledEvent.fire()
    }
    source.resume()
  }

  /// Cancels the source and suspends until its cancel handler has run — i.e.
  /// until libdispatch has released the file descriptor.
  func cancel() async {
    source.cancel()
    await cancelled.wait()
  }
}

private struct GallerySelectionSeedHarness: View {
  @State private var selection: GalleryView.GalleryTab
  @State private var isPaletteOpen = false

  init(initialSelection: GalleryView.GalleryTab) {
    _selection = State(initialValue: initialSelection)
  }

  var body: some View {
    GallerySelectionRuntimeBridge(
      selection: $selection,
      isPaletteOpen: $isPaletteOpen
    )
  }
}

private struct GallerySelectionRuntimeBridge: View {
  @Binding var selection: GalleryView.GalleryTab
  @Binding var isPaletteOpen: Bool

  var body: some View {
    galleryBody()
  }

  private func galleryBody() -> some View {
    TabView(selection: $selection) {
      Tab("Counter", value: GalleryView.GalleryTab.counter) {
        CounterTab()
      }

      Tab("Todo", value: GalleryView.GalleryTab.todo) {
        TodoTab()
      }

      Tab("Text Input", value: GalleryView.GalleryTab.textInput) {
        TextInputTab()
      }

      Tab("Calculator", value: GalleryView.GalleryTab.calculator) {
        CalculatorTab()
      }

      Tab("Borders & Shapes", value: GalleryView.GalleryTab.bordersAndShapes) {
        BordersAndShapesTab()
      }

      Tab("Images", value: GalleryView.GalleryTab.images) {
        ImagesTab()
      }

      Tab("Animations", value: GalleryView.GalleryTab.animations) {
        AnimationsTab()
      }

      Tab("File Drop", value: GalleryView.GalleryTab.fileDrop) {
        FileDropTab()
      }

      Tab("Full Screen", value: GalleryView.GalleryTab.physics) {
        PhysicsTab()
      }
    }
    .tabViewStyle(.literalTabs)
    .toolbarItem(
      .init(
        title: "⌃K Palette",
        action: { openPalette() }
      )
    )
    .panel(id: "gallery")
    .keyCommand(
      "Command palette",
      key: .character("k"),
      modifiers: .ctrl,
      action: { openPalette() }
    )
    .paletteCommand(
      name: "Switch to Counter",
      action: { selection = .counter }
    )
    .paletteCommand(
      name: "Switch to Todo",
      action: { selection = .todo }
    )
    .paletteCommand(
      name: "Switch to Text Input",
      action: { selection = .textInput }
    )
    .paletteCommand(
      name: "Switch to Calculator",
      action: { selection = .calculator }
    )
    .paletteCommand(
      name: "Switch to Borders & Shapes",
      action: { selection = .bordersAndShapes }
    )
    .paletteCommand(
      name: "Switch to Images",
      action: { selection = .images }
    )
    .paletteCommand(
      name: "Switch to Animations",
      action: { selection = .animations }
    )
    .paletteCommand(
      name: "Switch to File Drop",
      action: { selection = .fileDrop }
    )
    .paletteCommand(
      name: "Switch to Full Screen",
      action: { selection = .physics }
    )
    .toolbar(style: DefaultBottomToolbarStyle())
    .paletteSheet("Command palette", isPresented: $isPaletteOpen) { commands in
      CommandPaletteList(
        commands: commands,
        dismiss: { isPaletteOpen = false }
      )
    }
  }

  private func openPalette() {
    isPaletteOpen = true
  }
}

private final class GalleryTabSwitchScriptedInput: TerminalInputReading {
  private let scriptedEvents: [InputEvent]

  init(events: [InputEvent]) {
    scriptedEvents = events
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      for event in scriptedEvents {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }
}

private enum SGRMouseInputEncoding {
  case cells
  case pixels(width: Int, height: Int)

  func encodedCoordinates(for point: Point) -> (x: Int, y: Int) {
    switch self {
    case .cells:
      let cell = point.containingCell
      return (cell.x + 1, cell.y + 1)
    case .pixels(let width, let height):
      return (
        Int(((point.x + 0.5) * Double(width)).rounded()) + 1,
        Int(((point.y + 0.5) * Double(height)).rounded()) + 1
      )
    }
  }
}

private enum GalleryTabSwitchAwaitedInputStep {
  case event(InputEvent, delayNanoseconds: UInt64 = 0)
  case eventFrom(
    delayNanoseconds: UInt64 = 0,
    provider: @MainActor () -> InputEvent
  )
  /// Suspends the input script until `predicate` holds.
  ///
  /// Unlike a timeout poll, the predicate is re-evaluated only when the host
  /// presents a new frame (the host's `frameSignal.notify()`), never on a
  /// clock. A starved run loop therefore slows the test down instead of
  /// timing the wait out and continuing prematurely.
  case awaitCondition(predicate: @MainActor () -> Bool)
}

private actor GalleryTabSwitchWaitFailureRecorder {
  private var failure: StageBudgetExceeded?

  func record(_ failure: StageBudgetExceeded) {
    self.failure = failure
  }

  func requireNoFailure() throws {
    if let failure {
      throw failure
    }
  }
}

private final class GalleryTabSwitchAwaitedInputReader: TerminalInputReading {
  private let steps: [GalleryTabSwitchAwaitedInputStep]
  private let frameSignal: MainActorConditionSignal
  private let stageClock: ManualStageClock
  private let waitBudget: ProgressBudget
  private let waitFailure = GalleryTabSwitchWaitFailureRecorder()

  init(
    frameSignal: MainActorConditionSignal,
    stageClock: ManualStageClock,
    waitBudget: ProgressBudget = ProgressBudget(stages: 480),
    steps: [GalleryTabSwitchAwaitedInputStep]
  ) {
    self.frameSignal = frameSignal
    self.stageClock = stageClock
    self.waitBudget = waitBudget
    self.steps = steps
  }

  @MainActor
  func requireNoWaitFailure() async throws {
    try await waitFailure.requireNoFailure()
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let steps = self.steps
      let frameSignal = self.frameSignal
      let stageClock = self.stageClock
      let waitBudget = self.waitBudget
      let waitFailure = self.waitFailure
      let task = Task { @MainActor in
        // Virtual clock: a step's delay advances the timestamp stamped onto
        // the event rather than being slept through, so drag-release velocity
        // is deterministic and independent of wall-clock pacing.
        var virtualClock = MonotonicInstant.now()
        for (index, step) in steps.enumerated() {
          switch step {
          case .event(let event, let delayNanoseconds):
            virtualClock = virtualClock.advanced(
              by: .nanoseconds(Int64(delayNanoseconds))
            )
            stageClock.advance()
            continuation.yield(restampedInputEvent(event, at: virtualClock))
          case .eventFrom(let delayNanoseconds, let provider):
            virtualClock = virtualClock.advanced(
              by: .nanoseconds(Int64(delayNanoseconds))
            )
            stageClock.advance()
            continuation.yield(restampedInputEvent(provider(), at: virtualClock))
          case .awaitCondition(let predicate):
            do {
              try await frameSignal.wait(
                until: predicate,
                for: "gallery tab-switch awaited input step \(index)",
                within: waitBudget,
                on: stageClock
              )
            } catch let failure as StageBudgetExceeded {
              await waitFailure.record(failure)
              continuation.finish()
              return
            } catch {
              continuation.finish()
              return
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

/// Re-stamps a scripted mouse event with a virtual timestamp so the runtime's
/// gesture velocity tracker sees a deterministic inter-event interval. Non-mouse
/// events are returned unchanged.
private func restampedInputEvent(
  _ event: InputEvent,
  at timestamp: MonotonicInstant
) -> InputEvent {
  guard case .mouse(var mouseEvent) = event else {
    return event
  }
  mouseEvent.timestamp = timestamp
  return .mouse(mouseEvent)
}

private final class GalleryTabSwitchEmptySignals: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class GalleryTabSwitchRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  let stageClock = ManualStageClock()
  private(set) var surfaces: [RasterSurface] = []
  private(set) var lastPresentedSurface: RasterSurface?

  /// Notified after every `present`, so an awaited input step can re-check its
  /// predicate the instant a new frame lands instead of polling under a timeout.
  let frameSignal = MainActorConditionSignal()

  init(size: CellSize) {
    surfaceSize = size
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    surfaces.append(surface)
    lastPresentedSurface = surface
    stageClock.advance()
    // The run loop only ever presents on the MainActor; `assumeIsolated`
    // bridges this nonisolated protocol witness to the MainActor-isolated
    // signal, and traps loudly rather than corrupting state if that ever
    // stops being true. Bind the (Sendable) signal to a local first so the
    // closure never has to capture the non-Sendable host itself.
    let frameSignal = self.frameSignal
    MainActor.assumeIsolated {
      frameSignal.notify()
    }
    return .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }
}

@MainActor
private final class GallerySurfaceCapture {
  var initialPhysicsSurface: RasterSurface?
  var prePaletteSurface: RasterSurface?
  var postDismissSurface: RasterSurface?
}

@MainActor
private final class GalleryPhysicsReleaseCapture {
  var surfaceCountAtRelease = 0
  var dragStart = Point.zero
  var dragEnd = Point.zero
}

@MainActor
private final class GalleryPhysicsSelectionCapture {
  var surfaceCountAtFirstPhysicsFrame = 0
  var overflowItemCenter = Point.zero
}

@MainActor
private final class GalleryCommandPaletteCapture {
  var paletteSurface: RasterSurface?
}

private func deduplicated(
  _ surfaces: [RasterSurface]
) -> [RasterSurface] {
  var result: [RasterSurface] = []
  result.reserveCapacity(surfaces.count)
  for surface in surfaces where result.last != surface {
    result.append(surface)
  }
  return result
}

private struct PTYVisibleScreen {
  private var size: CellSize
  private var cells: [[Character]]
  private var cursor = CellPoint.zero
  private var pendingBytes: [UInt8] = []

  init(size: CellSize) {
    self.size = size
    cells = Array(
      repeating: Array(repeating: " ", count: max(1, size.width)),
      count: max(1, size.height)
    )
  }

  var renderedText: String {
    cells
      .map { row in
        var endIndex = row.endIndex
        while endIndex > row.startIndex, row[row.index(before: endIndex)] == " " {
          endIndex = row.index(before: endIndex)
        }
        return String(row[..<endIndex])
      }
      .joined(separator: "\n")
  }

  mutating func feed(
    _ bytes: [UInt8]
  ) {
    pendingBytes.append(contentsOf: bytes)

    var index = 0
    while index < pendingBytes.count {
      let byte = pendingBytes[index]

      if byte == 0x1B {
        guard index + 1 < pendingBytes.count else {
          break
        }

        let next = pendingBytes[index + 1]
        if next == 0x5B {
          guard let consumed = consumeCSI(startingAt: index) else {
            break
          }
          index = consumed
          continue
        }

        if next == 0x5D || next == 0x5F {
          guard let consumed = consumeStringEscape(startingAt: index) else {
            break
          }
          index = consumed
          continue
        }

        index += 2
        continue
      }

      if byte == 0x0D {
        cursor.x = 0
        index += 1
        continue
      }

      if byte == 0x0A {
        cursor.x = 0
        cursor.y = min(max(0, size.height - 1), cursor.y + 1)
        index += 1
        continue
      }

      if byte < 0x20 {
        index += 1
        continue
      }

      if byte < 0x80 {
        write(Character(UnicodeScalar(Int(byte))!))
        index += 1
        continue
      }

      let sequenceLength = utf8SequenceLength(for: byte)
      guard index + sequenceLength <= pendingBytes.count else {
        break
      }
      let character =
        String(
          decoding: pendingBytes[index..<(index + sequenceLength)],
          as: UTF8.self
        ).first ?? "•"
      write(character)
      index += sequenceLength
    }

    if index > 0 {
      pendingBytes.removeFirst(index)
    }
  }

  private mutating func consumeCSI(
    startingAt startIndex: Int
  ) -> Int? {
    var index = startIndex + 2
    while index < pendingBytes.count {
      let byte = pendingBytes[index]
      if (0x40...0x7E).contains(byte) {
        let parameters = Array(pendingBytes[(startIndex + 2)..<index])
        applyCSI(parameters: parameters, command: byte)
        return index + 1
      }
      index += 1
    }
    return nil
  }

  private mutating func consumeStringEscape(
    startingAt startIndex: Int
  ) -> Int? {
    var index = startIndex + 2
    while index + 1 < pendingBytes.count {
      if pendingBytes[index] == 0x1B, pendingBytes[index + 1] == 0x5C {
        return index + 2
      }
      if pendingBytes[index] == 0x07 {
        return index + 1
      }
      index += 1
    }
    return nil
  }

  private mutating func applyCSI(
    parameters: [UInt8],
    command: UInt8
  ) {
    let parameterString = String(decoding: parameters, as: UTF8.self)
    let privateMode = parameterString.hasPrefix("?")
    let cleanedParameters =
      privateMode
      ? String(parameterString.dropFirst())
      : parameterString
    let values = cleanedParameters.split(separator: ";").compactMap { Int($0) }

    switch command {
    case 0x48, 0x66:  // H, f
      let row = max(1, values.first ?? 1) - 1
      let column = max(1, values.dropFirst().first ?? 1) - 1
      cursor = CellPoint(
        x: min(max(0, size.width - 1), column),
        y: min(max(0, size.height - 1), row)
      )
    case 0x4A:  // J
      if values.first == 2 || values.isEmpty {
        clearAll()
      }
    case 0x4B:  // K
      eraseToEndOfLine()
    case 0x43:  // C
      cursor.x = min(max(0, size.width - 1), cursor.x + max(1, values.first ?? 1))
    case 0x44:  // D
      cursor.x = max(0, cursor.x - max(1, values.first ?? 1))
    case 0x41:  // A
      cursor.y = max(0, cursor.y - max(1, values.first ?? 1))
    case 0x42:  // B
      cursor.y = min(max(0, size.height - 1), cursor.y + max(1, values.first ?? 1))
    case 0x47:  // G
      cursor.x = min(max(0, size.width - 1), max(1, values.first ?? 1) - 1)
    case 0x6D, 0x68, 0x6C:  // m, h, l
      return
    default:
      return
    }
  }

  private mutating func clearAll() {
    for row in cells.indices {
      for column in cells[row].indices {
        cells[row][column] = " "
      }
    }
    cursor = .zero
  }

  private mutating func eraseToEndOfLine() {
    guard cursor.y >= 0, cursor.y < cells.count else {
      return
    }
    let row = cursor.y
    guard cursor.x >= 0, cursor.x < cells[row].count else {
      return
    }
    for column in cursor.x..<cells[row].count {
      cells[row][column] = " "
    }
  }

  private mutating func write(
    _ character: Character
  ) {
    guard cursor.y >= 0, cursor.y < cells.count else {
      return
    }
    guard cursor.x >= 0, cursor.x < cells[cursor.y].count else {
      return
    }
    cells[cursor.y][cursor.x] = character
    cursor.x += 1
  }

  private func utf8SequenceLength(
    for byte: UInt8
  ) -> Int {
    switch byte {
    case 0xC0...0xDF:
      2
    case 0xE0...0xEF:
      3
    case 0xF0...0xF7:
      4
    default:
      1
    }
  }
}
