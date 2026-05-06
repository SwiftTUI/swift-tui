import Foundation
@_spi(Runners) import SwiftTUI
import Synchronization
import Testing

@testable import SwiftTUIWebHost

@Suite(.serialized)
@MainActor
struct WebHostRunnerTests {
  @Test("runner rejects apps with no scenes")
  func runnerRejectsAppsWithNoScenes() async throws {
    do {
      try await WebHostRunner.run(
        NoSceneApp(),
        configuration: .init(web: .init()),
        server: FakeWebHostServer(),
        token: WebHostToken(rawValue: "test-token"),
        browserOpener: RecordingBrowserOpener(),
        bannerWriter: RecordingBannerWriter()
      )
      Issue.record("Expected no-scene launch to fail.")
    } catch let error as AppLaunchError {
      #expect(error == .noScenes)
    } catch {
      Issue.record("Expected AppLaunchError.noScenes, got \(error).")
    }
  }

  @Test("runner rejects multiple scenes in V1")
  func runnerRejectsMultipleScenesInV1() async throws {
    do {
      try await WebHostRunner.run(
        MultipleSceneApp(),
        configuration: .init(web: .init()),
        server: FakeWebHostServer(),
        token: WebHostToken(rawValue: "test-token"),
        browserOpener: RecordingBrowserOpener(),
        bannerWriter: RecordingBannerWriter()
      )
      Issue.record("Expected multiple-scene launch to fail.")
    } catch let error as WebHostRunnerError {
      #expect(error == .multipleScenesUnsupported(count: 2))
      #expect(error.description.contains("supports exactly one scene"))
    } catch {
      Issue.record("Expected WebHostRunnerError.multipleScenesUnsupported, got \(error).")
    }
  }

  @Test("runner prints tokenized banner and does not open browser by default")
  func runnerPrintsTokenizedBannerAndDoesNotOpenBrowserByDefault() async throws {
    let server = FakeWebHostServer()
    let opener = RecordingBrowserOpener()
    let banner = RecordingBannerWriter()
    let task = Task { @MainActor in
      try await WebHostRunner.run(
        SingleSceneApp(),
        configuration: .init(web: .init(openBrowser: false)),
        server: server,
        token: WebHostToken(rawValue: "test-token"),
        browserOpener: opener,
        bannerWriter: banner
      )
    }

    let session = await server.startedSession()
    try await waitUntil("banner write") {
      banner.messages.contains(
        WebHostBanner.message(for: session, configuration: .init(port: 0))
      )
    }

    #expect(opener.openedURLs.isEmpty)
    await cancelAndDrain(task)
  }

  @Test("runner opens browser once when configured")
  func runnerOpensBrowserOnceWhenConfigured() async throws {
    let server = FakeWebHostServer()
    let opener = RecordingBrowserOpener()
    let banner = RecordingBannerWriter()
    let task = Task { @MainActor in
      try await WebHostRunner.run(
        SingleSceneApp(),
        configuration: .init(web: .init(openBrowser: true)),
        server: server,
        token: WebHostToken(rawValue: "test-token"),
        browserOpener: opener,
        bannerWriter: banner
      )
    }

    let session = await server.startedSession()
    try await waitUntil("browser open") {
      opener.openedURLs.count == 1
    }

    #expect(opener.openedURLs == [session.url(path: "/")])
    await cancelAndDrain(task)
  }

  @Test("runner commits an initial frame to the connected WebSocket channel")
  func runnerCommitsInitialFrameToConnectedWebSocketChannel() async throws {
    let server = FakeWebHostServer()
    let task = Task { @MainActor in
      try await WebHostRunner.run(
        SingleSceneApp(),
        configuration: .init(web: .init()),
        server: server,
        token: WebHostToken(rawValue: "test-token"),
        browserOpener: RecordingBrowserOpener(),
        bannerWriter: RecordingBannerWriter()
      )
    }

    let session = await server.startedSession()
    let output = await session.channel.attach(client: AsyncStream { _ in })
    let recorder = WebSocketOutputRecorder()
    let outputTask = Task {
      for await message in output {
        await recorder.record(message)
      }
    }

    try await waitUntil("initial web-surface frame") {
      await recorder.containsSurfaceFrame()
    }

    outputTask.cancel()
    await cancelAndDrain(task)
  }
}

@MainActor
private struct NoSceneApp: App {
  var body: some Scene {
    EmptyScene()
  }
}

@MainActor
private struct MultipleSceneApp: App {
  var body: some Scene {
    WindowGroup("Primary", id: WindowIdentifier("primary")) {
      Text("Primary")
    }
    WindowGroup("Secondary", id: WindowIdentifier("secondary")) {
      Text("Secondary")
    }
  }
}

@MainActor
private struct SingleSceneApp: App {
  var body: some Scene {
    WindowGroup("Primary", id: WindowIdentifier("primary")) {
      Text("Hello WebHost")
    }
  }
}

private actor FakeWebHostServer: WebHostServer {
  private var session: WebHostServerSession?
  private var continuation: CheckedContinuation<WebHostServerSession, Never>?
  private(set) var stopCount = 0

  func start(
    configuration: WebHostConfig,
    token: WebHostToken,
    scene: WebHostSceneDescriptor
  ) async throws -> WebHostServerSession {
    let channel = WebHostSceneChannel()
    let session = WebHostServerSession(
      baseURL: URL(
        string: "http://127.0.0.1:\(configuration.port == 0 ? 9123 : configuration.port)/")!,
      webSocketURL: URL(
        string: "ws://127.0.0.1:9123/ws/scene/\(scene.id)?token=\(token.rawValue)")!,
      token: token,
      channel: channel,
      stopHandler: {
        await self.recordStop()
      }
    )
    self.session = session
    continuation?.resume(returning: session)
    continuation = nil
    return session
  }

  func startedSession() async -> WebHostServerSession {
    if let session {
      return session
    }
    return await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  private func recordStop() {
    stopCount += 1
  }
}

private final class RecordingBrowserOpener: BrowserOpening, Sendable {
  private let storage = Mutex<[URL]>([])

  var openedURLs: [URL] {
    storage.withLock { $0 }
  }

  func open(
    _ url: URL
  ) throws {
    storage.withLock {
      $0.append(url)
    }
  }
}

private final class RecordingBannerWriter: WebHostBannerWriting, Sendable {
  private let storage = Mutex<[String]>([])

  var messages: [String] {
    storage.withLock { $0 }
  }

  func write(
    _ message: String
  ) {
    storage.withLock {
      $0.append(message)
    }
  }
}

private actor WebSocketOutputRecorder {
  private var messages: [WebHostSocketMessage] = []

  func record(
    _ message: WebHostSocketMessage
  ) {
    messages.append(message)
  }

  func containsSurfaceFrame() -> Bool {
    messages.contains { message in
      guard case .data(let bytes) = message else {
        return false
      }
      let output = String(decoding: bytes, as: UTF8.self)
      return output.contains("\u{1E}surface:")
    }
  }
}

private func waitUntil(
  _ label: String,
  timeoutNanoseconds: UInt64 = 2_000_000_000,
  pollNanoseconds: UInt64 = 10_000_000,
  predicate: () async -> Bool
) async throws {
  let clock = ContinuousClock()
  let start = clock.now
  while !(await predicate()) {
    if start.duration(to: clock.now) >= .nanoseconds(Int64(timeoutNanoseconds)) {
      throw WebHostRunnerTestError.timeout(label)
    }
    try await Task.sleep(nanoseconds: pollNanoseconds)
  }
}

private func waitUntil(
  _ label: String,
  timeoutNanoseconds: UInt64 = 2_000_000_000,
  pollNanoseconds: UInt64 = 10_000_000,
  predicate: () -> Bool
) async throws {
  let clock = ContinuousClock()
  let start = clock.now
  while !predicate() {
    if start.duration(to: clock.now) >= .nanoseconds(Int64(timeoutNanoseconds)) {
      throw WebHostRunnerTestError.timeout(label)
    }
    try await Task.sleep(nanoseconds: pollNanoseconds)
  }
}

private func cancelAndDrain(
  _ task: Task<Void, any Error>
) async {
  task.cancel()
  _ = try? await value(of: task, timeoutNanoseconds: 1_000_000_000)
}

private func value<T>(
  of task: Task<T, any Error>,
  timeoutNanoseconds: UInt64
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask {
      try await task.value
    }
    group.addTask {
      try await Task.sleep(nanoseconds: timeoutNanoseconds)
      throw WebHostRunnerTestError.timeout("task")
    }
    let value = try await group.next()!
    group.cancelAll()
    return value
  }
}

private enum WebHostRunnerTestError: Error, Equatable {
  case timeout(String)
}
