import SwiftTUIViews
import Testing

@testable import SwiftTUIRuntime

@MainActor
@Suite(.serialized)
struct HostedSceneSessionTests {
  private struct HostedApp: App {
    var body: some Scene {
      WindowGroup("Primary", id: WindowIdentifier("primary")) {
        Text("Primary")
      }
      WindowGroup("Secondary", id: WindowIdentifier("secondary")) {
        Text("Secondary")
      }
    }
  }

  private struct FocusPresentationApp: App {
    var body: some Scene {
      WindowGroup("Primary", id: WindowIdentifier("primary")) {
        VStack {
          Text("Activate")
            .focusable(true, interactions: .activate)
          Text("Edit")
            .focusable(true, interactions: .edit)
        }
      }
    }
  }

  private struct AccessibilitySurfaceApp: App {
    var body: some Scene {
      WindowGroup("Primary", id: WindowIdentifier("primary")) {
        Button("Primary") {}
          .accessibilityLabel("Primary action")
      }
    }
  }

  private struct ClipboardSurfaceApp: App {
    var body: some Scene {
      WindowGroup("Primary", id: WindowIdentifier("primary")) {
        ClipboardTextEditorFixture()
      }
    }
  }

  private struct ClipboardTextEditorFixture: View {
    @State private var text = "hello"

    var body: some View {
      TextEditor(text: $text)
        .frame(width: 12, height: 3)
    }
  }

  @Test("hosted scene session rerenders when the hosted raster surface refreshes")
  func hostedSceneSessionRerendersOnSurfaceRefresh() async throws {
    let recorder = SurfaceRecorder()
    let surface = hostedSurface(surfaceRecorder: recorder)
    let session = try HostedSceneSession(
      for: HostedApp(),
      sceneID: WindowIdentifier("primary"),
      surface: surface
    )

    let task = Task {
      try await session.start()
    }

    try await waitUntil("first surface") {
      recorder.surfaceCount >= 1
    }

    surface.updateSurfaceSize(.init(width: 32, height: 8))
    session.requestSurfaceRefresh()

    try await waitUntil("second surface") {
      recorder.surfaceCount >= 2 && recorder.latestSurface?.size == .init(width: 32, height: 8)
    }

    session.sendInput([0x04])  // Ctrl+D
    let exitReason = try await task.value

    #expect(exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
  }

  @Test("hosted scene session publishes raster surfaces and accepts direct input events")
  func hostedSurfaceSessionPublishesRasterSurfaceAndAcceptsDirectInputEvents() async throws {
    let recorder = SurfaceRecorder()
    let session = try HostedSceneSession(
      for: HostedApp(),
      sceneID: WindowIdentifier("primary"),
      surface: hostedSurface(surfaceRecorder: recorder)
    )

    let task = Task {
      try await session.start()
    }

    try await waitUntil("first surface") {
      recorder.surfaceCount >= 1
    }

    #expect(recorder.latestSurface?.lines.first?.contains("Primary") == true)

    session.send(.key(.init(.character("d"), modifiers: .ctrl)))
    let exitReason = try await task.value

    #expect(exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
  }

  @Test("hosted raster surface forwards focused text clipboard writes")
  func hostedRasterSurfaceForwardsFocusedTextClipboardWrites() async throws {
    let surfaceRecorder = SurfaceRecorder()
    let clipboardRecorder = ClipboardRecorder()
    let session = try HostedSceneSession(
      for: ClipboardSurfaceApp(),
      sceneID: WindowIdentifier("primary"),
      surface: hostedSurface(
        surfaceRecorder: surfaceRecorder,
        clipboardRecorder: clipboardRecorder
      )
    )

    let task = Task {
      try await session.start()
    }

    try await waitUntil("first surface") {
      surfaceRecorder.surfaceCount >= 1
    }

    session.send(.key(.init(.character("a"), modifiers: .ctrl)))
    session.send(.key(.init(.character("c"), modifiers: .ctrl)))

    try await waitUntil("clipboard write") {
      clipboardRecorder.writes == ["hello"]
    }

    session.send(.key(.init(.character("d"), modifiers: .ctrl)))
    let exitReason = try await task.value
    #expect(exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
  }

  @Test("hosted raster surface publishes damage-bearing semantic frames beside raster surfaces")
  func hostedRasterSurfacePublishesDamageBearingSemanticFramesBesideRasterSurfaces() async throws {
    let surfaceRecorder = SurfaceRecorder()
    let semanticRecorder = SemanticFrameRecorder()
    let session = try HostedSceneSession(
      for: AccessibilitySurfaceApp(),
      sceneID: WindowIdentifier("primary"),
      surface: hostedSurface(
        surfaceRecorder: surfaceRecorder,
        semanticRecorder: semanticRecorder
      )
    )

    let task = Task {
      try await session.start()
    }

    try await waitUntil("semantic frame") {
      surfaceRecorder.surfaceCount >= 1
        && semanticRecorder.frameCount >= 1
        && semanticRecorder.latestSnapshot?.accessibilityNodes.contains {
          $0.label == "Primary action"
        } == true
    }

    #expect(surfaceRecorder.latestSurface == semanticRecorder.latestSurface)
    #expect(semanticRecorder.frames.first?.sequence == 0)

    let stopExitReason = try await session.stopAndWait()
    let taskExitReason = try await task.value

    #expect(stopExitReason == .inputEnded)
    #expect(taskExitReason == .inputEnded)
  }

  @Test("hosted scene session throws when the requested scene does not exist")
  func hostedSceneSessionThrowsForUnknownScene() throws {
    do {
      _ = try HostedSceneSession(
        for: HostedApp(),
        sceneID: WindowIdentifier("missing"),
        surface: hostedSurface()
      )
      Issue.record("Expected a missing-scene error")
    } catch let error as HostedSceneSessionError {
      #expect(error == .sceneNotFound(WindowIdentifier("missing")))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("hosted scene session schedules a new frame after direct style updates")
  func hostedSceneSessionRerendersOnStyleUpdate() async throws {
    let recorder = SurfaceRecorder()
    let surface = hostedSurface(surfaceRecorder: recorder)
    let session = try HostedSceneSession(
      for: HostedApp(),
      sceneID: WindowIdentifier("primary"),
      surface: surface
    )

    let task = Task {
      try await session.start()
    }

    try await waitUntil("first surface") {
      recorder.surfaceCount >= 1
    }

    surface.updateStyle(
      .init(
        appearance: .init(
          foregroundColor: .black,
          backgroundColor: .white,
          tintColor: .blue,
          source: .override
        ),
        theme: .init(
          foreground: .hex("#0F172A"),
          background: .hex("#F8FAFC"),
          tint: .hex("#2563EB"),
          separator: .hex("#CBD5E1"),
          selection: .hex("#DBEAFE"),
          placeholder: .hex("#94A3B8"),
          link: .hex("#2563EB"),
          fill: .hex("#F1F5F9"),
          windowBackground: .hex("#E2E8F0"),
          success: .hex("#16A34A"),
          warning: .hex("#D97706"),
          danger: .hex("#DC2626"),
          info: .hex("#0284C7"),
          muted: .hex("#64748B")
        )
      )
    )
    session.requestSurfaceRefresh()

    try await waitUntil("second surface") {
      recorder.surfaceCount >= 2
    }

    session.sendInput([0x04])  // Ctrl+D
    let exitReason = try await task.value

    #expect(exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
  }

  @Test("hosted scene session publishes committed focus presentation changes")
  func hostedSceneSessionPublishesFocusPresentationChanges() async throws {
    let recorder = FocusPresentationRecorder()
    let session = try HostedSceneSession(
      for: FocusPresentationApp(),
      sceneID: WindowIdentifier("primary"),
      surface: hostedSurface(),
      onFocusPresentationChange: { presentation in
        recorder.record(presentation)
      }
    )

    let task = Task {
      try await session.start()
    }

    try await waitUntil("activate focus presentation") {
      session.currentFocusPresentation.semantics == .activate
    }
    #expect(session.currentFocusPresentation.prefersTextInput == false)

    session.sendInput([0x09])

    try await waitUntil("edit focus presentation") {
      session.currentFocusPresentation.semantics == .edit
    }
    #expect(session.currentFocusPresentation.prefersTextInput)

    let stopExitReason = try await session.stopAndWait()
    let taskExitReason = try await task.value

    #expect(stopExitReason == .inputEnded)
    #expect(taskExitReason == .inputEnded)
    #expect(session.currentFocusPresentation == .none)
    #expect(recorder.presentations.map(\.semantics) == [.activate, .edit, .none])
  }

  @Test("hosted scene session stopAndWait returns nil when the session was never started")
  func hostedSceneSessionStopAndWaitReturnsNilWhenNeverStarted() async throws {
    let session = try HostedSceneSession(
      for: HostedApp(),
      sceneID: WindowIdentifier("primary"),
      surface: hostedSurface()
    )

    let exitReason = try await session.stopAndWait()

    #expect(exitReason == nil)
    #expect(session.currentFocusPresentation == .none)
  }

  @Test(
    "hosted scene session stopAndWait owns shutdown after the original start waiter is cancelled"
  )
  func hostedSceneSessionStopAndWaitOwnsShutdownAfterCancelledStartWaiter() async throws {
    let recorder = SurfaceRecorder()
    let session = try HostedSceneSession(
      for: HostedApp(),
      sceneID: WindowIdentifier("primary"),
      surface: hostedSurface(surfaceRecorder: recorder)
    )

    let task = Task {
      try await session.start()
    }

    try await waitUntil("first surface") {
      recorder.surfaceCount >= 1
    }

    task.cancel()

    let stopExitReason = try await session.stopAndWait()
    let taskExitReason = try await task.value

    #expect(stopExitReason == .inputEnded)
    #expect(taskExitReason == .inputEnded)
  }

  private func hostedSurface(
    surfaceRecorder: SurfaceRecorder? = nil,
    semanticRecorder: SemanticFrameRecorder? = nil,
    clipboardRecorder: ClipboardRecorder? = nil
  ) -> HostedRasterSurface {
    HostedRasterSurface(
      surfaceSize: .init(width: 24, height: 6),
      appearance: .fallback,
      onFrame: { frame in
        surfaceRecorder?.record(frame.raster)
        semanticRecorder?.record(
          frame
        )
      },
      onClipboardWrite: { text in
        clipboardRecorder?.record(text)
        return clipboardRecorder != nil
      }
    )
  }
}

@MainActor
private final class SurfaceRecorder {
  private(set) var surfaces: [RasterSurface] = []

  var surfaceCount: Int {
    surfaces.count
  }

  var latestSurface: RasterSurface? {
    surfaces.last
  }

  func record(
    _ surface: RasterSurface
  ) {
    surfaces.append(surface)
  }
}

@MainActor
private final class SemanticFrameRecorder {
  private(set) var frames:
    [(
      sequence: UInt64,
      surface: RasterSurface,
      snapshot: SemanticSnapshot,
      focused: Identity?,
      damage: PresentationDamage?
    )] =
      []

  var frameCount: Int {
    frames.count
  }

  var latestSurface: RasterSurface? {
    frames.last?.surface
  }

  var latestSnapshot: SemanticSnapshot? {
    frames.last?.snapshot
  }

  func record(
    _ frame: SemanticHostFrame
  ) {
    frames.append(
      (
        sequence: frame.sequence,
        surface: frame.raster,
        snapshot: frame.semantics,
        focused: frame.focusedIdentity,
        damage: frame.rasterDamage
      )
    )
  }
}

@MainActor
private final class FocusPresentationRecorder {
  private(set) var presentations: [FocusPresentation] = []

  func record(
    _ presentation: FocusPresentation
  ) {
    presentations.append(presentation)
  }
}

@MainActor
private final class ClipboardRecorder {
  private(set) var writes: [String] = []

  func record(
    _ text: String
  ) {
    writes.append(text)
  }
}

@MainActor
private func waitUntil(
  _ label: String,
  timeoutNanoseconds: UInt64 = 15_000_000_000,
  pollNanoseconds: UInt64 = 20_000_000,
  condition: @escaping () async -> Bool
) async throws {
  let clock = ContinuousClock()
  let start = clock.now

  while !(await condition()) {
    if start.duration(to: clock.now) >= .nanoseconds(Int64(timeoutNanoseconds)) {
      throw HostedSceneTestTimeout(label)
    }
    try await Task.sleep(nanoseconds: pollNanoseconds)
  }
}

private struct HostedSceneTestTimeout: Error, CustomStringConvertible {
  let label: String

  init(_ label: String) {
    self.label = label
  }

  var description: String {
    "Timed out waiting for \(label)"
  }
}
