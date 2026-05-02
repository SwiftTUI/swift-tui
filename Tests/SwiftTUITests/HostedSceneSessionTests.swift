import Synchronization
import Testing
import View

@testable import SwiftTUI

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

  @Test("hosted scene session rerenders on resize without exiting")
  func hostedSceneSessionRerendersOnResize() async throws {
    let recorder = OutputRecorder()
    let session = try HostedSceneSession(
      for: HostedApp(),
      sceneID: WindowIdentifier("primary"),
      initialSize: .init(width: 24, height: 6),
      appearance: .fallback,
      onOutput: { output in
        recorder.record(output)
      }
    )

    let task = Task {
      try await session.start()
    }

    try await waitUntil("first frame") {
      recorder.frameCount >= 1
    }

    session.resize(to: .init(width: 32, height: 8))

    try await waitUntil("second frame") {
      recorder.frameCount >= 2
    }

    session.sendInput([0x03])  // Ctrl+C
    let exitReason = try await task.value

    #expect(exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
  }

  @Test("hosted surface session publishes raster surfaces and accepts direct input events")
  func hostedSurfaceSessionPublishesRasterSurfaceAndAcceptsDirectInputEvents() async throws {
    let recorder = SurfaceRecorder()
    let session = try HostedSceneSession(
      for: HostedApp(),
      sceneID: WindowIdentifier("primary"),
      initialSize: .init(width: 24, height: 6),
      appearance: .fallback,
      onSurface: { surface in
        recorder.record(surface)
      }
    )

    let task = Task {
      try await session.start()
    }

    try await waitUntil("first surface") {
      recorder.surfaceCount >= 1
    }

    #expect(recorder.latestSurface?.lines.first?.contains("Primary") == true)

    session.send(.key(.init(.character("c"), modifiers: .ctrl)))
    let exitReason = try await task.value

    #expect(exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
  }

  @Test("hosted surface session rerenders on resize")
  func hostedSurfaceSessionRerendersOnResize() async throws {
    let recorder = SurfaceRecorder()
    let session = try HostedSceneSession(
      for: HostedApp(),
      sceneID: WindowIdentifier("primary"),
      initialSize: .init(width: 24, height: 6),
      appearance: .fallback,
      onSurface: { surface in
        recorder.record(surface)
      }
    )

    let task = Task {
      try await session.start()
    }

    try await waitUntil("first surface") {
      recorder.surfaceCount >= 1
    }

    session.resize(to: .init(width: 32, height: 8), cellPixelSize: .init(width: 8, height: 16))

    try await waitUntil("second surface") {
      recorder.surfaceCount >= 2 && recorder.latestSurface?.size == .init(width: 32, height: 8)
    }

    session.send(.key(.init(.character("c"), modifiers: .ctrl)))
    let exitReason = try await task.value

    #expect(exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
  }

  @Test("hosted surface session throws when the requested scene does not exist")
  func hostedSurfaceSessionThrowsForUnknownScene() throws {
    do {
      _ = try HostedSceneSession(
        for: HostedApp(),
        sceneID: WindowIdentifier("missing"),
        initialSize: .init(width: 24, height: 6),
        appearance: .fallback,
        onSurface: { _ in }
      )
      Issue.record("Expected a missing-scene error")
    } catch let error as HostedSceneSessionError {
      #expect(error == .sceneNotFound(WindowIdentifier("missing")))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("hosted scene session schedules a new frame on appearance update")
  func hostedSceneSessionRerendersOnAppearanceUpdate() async throws {
    let recorder = OutputRecorder()
    let session = try HostedSceneSession(
      for: HostedApp(),
      sceneID: WindowIdentifier("primary"),
      initialSize: .init(width: 24, height: 6),
      appearance: .fallback,
      onOutput: { output in
        recorder.record(output)
      }
    )

    let task = Task {
      try await session.start()
    }

    try await waitUntil("first frame") {
      recorder.frameCount >= 1
    }

    session.updateAppearance(
      TerminalAppearance(
        foregroundColor: .black,
        backgroundColor: .white,
        tintColor: .blue,
        source: .override
      )
    )

    try await waitUntil("second frame") {
      recorder.frameCount >= 2
    }

    session.sendInput([0x03])  // Ctrl+C
    let exitReason = try await task.value

    #expect(exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
  }

  @Test("hosted scene session schedules a new frame on style update")
  func hostedSceneSessionRerendersOnStyleUpdate() async throws {
    let recorder = OutputRecorder()
    let session = try HostedSceneSession(
      for: HostedApp(),
      sceneID: WindowIdentifier("primary"),
      initialSize: .init(width: 24, height: 6),
      appearance: .fallback,
      onOutput: { output in
        recorder.record(output)
      }
    )

    let task = Task {
      try await session.start()
    }

    try await waitUntil("first frame") {
      recorder.frameCount >= 1
    }

    session.updateStyle(
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

    try await waitUntil("second frame") {
      recorder.frameCount >= 2
    }

    session.sendInput([0x03])  // Ctrl+C
    let exitReason = try await task.value

    #expect(exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
  }

  @Test("hosted scene session throws when the requested scene does not exist")
  func hostedSceneSessionThrowsForUnknownScene() throws {
    do {
      _ = try HostedSceneSession(
        for: HostedApp(),
        sceneID: WindowIdentifier("missing"),
        initialSize: .init(width: 24, height: 6),
        appearance: .fallback,
        onOutput: { _ in }
      )
      Issue.record("Expected a missing-scene error")
    } catch let error as HostedSceneSessionError {
      #expect(error == .sceneNotFound(WindowIdentifier("missing")))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("hosted scene session publishes committed focus presentation changes")
  func hostedSceneSessionPublishesFocusPresentationChanges() async throws {
    let recorder = FocusPresentationRecorder()
    let session = try HostedSceneSession(
      for: FocusPresentationApp(),
      sceneID: WindowIdentifier("primary"),
      initialSize: .init(width: 24, height: 6),
      appearance: .fallback,
      onOutput: { _ in },
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
      initialSize: .init(width: 24, height: 6),
      appearance: .fallback,
      onOutput: { _ in }
    )

    let exitReason = try await session.stopAndWait()

    #expect(exitReason == nil)
    #expect(session.currentFocusPresentation == .none)
  }

  @Test(
    "hosted scene session stopAndWait owns shutdown after the original start waiter is cancelled")
  func hostedSceneSessionStopAndWaitOwnsShutdownAfterCancelledStartWaiter() async throws {
    let recorder = OutputRecorder()
    let session = try HostedSceneSession(
      for: HostedApp(),
      sceneID: WindowIdentifier("primary"),
      initialSize: .init(width: 24, height: 6),
      appearance: .fallback,
      onOutput: { output in
        recorder.record(output)
      }
    )

    let task = Task {
      try await session.start()
    }

    try await waitUntil("first frame") {
      recorder.frameCount >= 1
    }

    task.cancel()

    let stopExitReason = try await session.stopAndWait()
    let taskExitReason = try await task.value

    #expect(stopExitReason == .inputEnded)
    #expect(taskExitReason == .inputEnded)
  }
}

private final class OutputRecorder: Sendable {
  private let frameCountStorage = Mutex(0)

  var frameCount: Int {
    frameCountStorage.withLock { $0 }
  }

  func record(
    _ output: String
  ) {
    if output.contains("\u{001B}[2J") {
      frameCountStorage.withLock { $0 += 1 }
    }
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
private final class FocusPresentationRecorder {
  private(set) var presentations: [FocusPresentation] = []

  func record(
    _ presentation: FocusPresentation
  ) {
    presentations.append(presentation)
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
