import Testing
import View

@testable import TerminalUI
@testable import TerminalUIScenes

@MainActor
@Suite
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

  @Test("hosted scene session rerenders on resize without exiting")
  func hostedSceneSessionRerendersOnResize() async throws {
    let recorder = OutputRecorder()
    let session = try HostedSceneSession(
      for: HostedApp(),
      sceneID: WindowIdentifier("primary"),
      initialSize: .init(width: 24, height: 6),
      appearance: .fallback,
      onOutput: { output in
        Task {
          await recorder.record(output)
        }
      }
    )

    let task = Task {
      try await session.start()
    }

    try await waitUntil("first frame") {
      await recorder.frameCount >= 1
    }

    session.resize(to: .init(width: 32, height: 8))

    try await waitUntil("second frame") {
      await recorder.frameCount >= 2
    }

    session.sendInput(Array("q".utf8))
    let exitReason = try await task.value

    #expect(exitReason == .quitKey)
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
        Task {
          await recorder.record(output)
        }
      }
    )

    let task = Task {
      try await session.start()
    }

    try await waitUntil("first frame") {
      await recorder.frameCount >= 1
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
      await recorder.frameCount >= 2
    }

    session.sendInput(Array("q".utf8))
    let exitReason = try await task.value

    #expect(exitReason == .quitKey)
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
        Task {
          await recorder.record(output)
        }
      }
    )

    let task = Task {
      try await session.start()
    }

    try await waitUntil("first frame") {
      await recorder.frameCount >= 1
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
      await recorder.frameCount >= 2
    }

    session.sendInput(Array("q".utf8))
    let exitReason = try await task.value

    #expect(exitReason == .quitKey)
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
}

private actor OutputRecorder {
  private(set) var frameCount = 0

  func record(
    _ output: String
  ) {
    if output.contains("\u{001B}[2J") {
      frameCount += 1
    }
  }
}

@MainActor
private func waitUntil(
  _ label: String,
  timeoutNanoseconds: UInt64 = 2_000_000_000,
  pollNanoseconds: UInt64 = 20_000_000,
  condition: @escaping @Sendable () async -> Bool
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
