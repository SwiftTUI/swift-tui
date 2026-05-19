import Foundation
@_spi(Runners) import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
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

  @Test("runner defaults to the default scene for multi-scene apps")
  func runnerDefaultsToDefaultSceneForMultiSceneApps() async throws {
    let server = FakeWebHostServer()
    let task = Task { @MainActor in
      try await WebHostRunner.run(
        MultipleSceneApp(),
        configuration: .init(web: .init()),
        server: server,
        token: WebHostToken(rawValue: "test-token"),
        browserOpener: RecordingBrowserOpener(),
        bannerWriter: RecordingBannerWriter()
      )
    }

    let scene = await server.startedScene()
    #expect(scene.id == "primary")
    #expect(scene.isDefault == true)
    await cancelAndDrain(task)
  }

  @Test("runner launches requested scene for multi-scene apps")
  func runnerLaunchesRequestedSceneForMultiSceneApps() async throws {
    let server = FakeWebHostServer()
    let task = Task { @MainActor in
      try await WebHostRunner.run(
        MultipleSceneApp(),
        configuration: .init(web: .init(sceneID: WindowIdentifier("secondary"))),
        server: server,
        token: WebHostToken(rawValue: "test-token"),
        browserOpener: RecordingBrowserOpener(),
        bannerWriter: RecordingBannerWriter()
      )
    }

    let scene = await server.startedScene()
    #expect(scene.id == "secondary")
    #expect(scene.title == "Secondary")
    #expect(scene.isDefault == false)
    await cancelAndDrain(task)
  }

  @Test("runner reports missing requested scene")
  func runnerReportsMissingRequestedScene() async throws {
    do {
      try await WebHostRunner.run(
        MultipleSceneApp(),
        configuration: .init(web: .init(sceneID: WindowIdentifier("missing"))),
        server: FakeWebHostServer(),
        token: WebHostToken(rawValue: "test-token"),
        browserOpener: RecordingBrowserOpener(),
        bannerWriter: RecordingBannerWriter()
      )
      Issue.record("Expected missing-scene launch to fail.")
    } catch let error as WebHostRunnerError {
      #expect(
        error
          == .sceneNotFound(
            WindowIdentifier("missing"),
            available: [WindowIdentifier("primary"), WindowIdentifier("secondary")]
          )
      )
      #expect(error.description.contains("Available scenes: primary, secondary"))
    } catch {
      Issue.record("Expected WebHostRunnerError.sceneNotFound, got \(error).")
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
    await banner.wrote.wait {
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
    await opener.opened.wait { opener.openedURLs.count == 1 }

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

    await recorder.waitForSurfaceFrame()

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
  private var scene: WebHostSceneDescriptor?
  private var continuation: CheckedContinuation<WebHostServerSession, Never>?
  private var sceneContinuation: CheckedContinuation<WebHostSceneDescriptor, Never>?
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
    self.scene = scene
    continuation?.resume(returning: session)
    continuation = nil
    sceneContinuation?.resume(returning: scene)
    sceneContinuation = nil
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

  func startedScene() async -> WebHostSceneDescriptor {
    if let scene {
      return scene
    }
    return await withCheckedContinuation { continuation in
      self.sceneContinuation = continuation
    }
  }

  private func recordStop() {
    stopCount += 1
  }
}

private final class RecordingBrowserOpener: BrowserOpening, Sendable {
  private let storage = Mutex<[URL]>([])

  /// Fires after each `open`, so tests await a browser open directly.
  let opened = ConditionSignal()

  var openedURLs: [URL] {
    storage.withLock { $0 }
  }

  func open(
    _ url: URL
  ) throws {
    storage.withLock {
      $0.append(url)
    }
    opened.notify()
  }
}

private final class RecordingBannerWriter: WebHostBannerWriting, Sendable {
  private let storage = Mutex<[String]>([])

  /// Fires after each `write`, so tests await a banner message directly.
  let wrote = ConditionSignal()

  var messages: [String] {
    storage.withLock { $0 }
  }

  func write(
    _ message: String
  ) {
    storage.withLock {
      $0.append(message)
    }
    wrote.notify()
  }
}

private actor WebSocketOutputRecorder {
  private var messages: [WebHostSocketMessage] = []
  private var surfaceFrameWaiters: [CheckedContinuation<Void, Never>] = []

  func record(
    _ message: WebHostSocketMessage
  ) {
    messages.append(message)
    if containsSurfaceFrame() {
      let waiters = surfaceFrameWaiters
      surfaceFrameWaiters = []
      for waiter in waiters {
        waiter.resume()
      }
    }
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

  /// Suspends until a recorded message carries a web-surface frame.
  func waitForSurfaceFrame() async {
    if containsSurfaceFrame() {
      return
    }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      surfaceFrameWaiters.append(continuation)
    }
  }
}

private func cancelAndDrain(
  _ task: Task<Void, any Error>
) async {
  task.cancel()
  // The runner honours cancellation, so awaiting its completion is bounded
  // without a timeout.
  _ = try? await task.value
}
