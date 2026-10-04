// Excluded from Windows builds (Windows plan, Stage 6 item 3): exercises the
// WebHost server stack, whose modules build empty on Windows
// (whole-file-guarded).
#if !os(Windows)

  import Foundation
  @_spi(Runners) import SwiftTUIRuntime
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
      #expect(Set(await server.startedSession().channels.keys) == ["primary", "secondary"])
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
      #expect(scene.isDefault == true)
      await cancelAndDrain(task)
    }

    @Test(
      "all scene graphs retain state across browser detach and reattach", .timeLimit(.minutes(1)))
    func allScenesRetainStateAcrossReattach() async throws {
      let server = FakeWebHostServer()
      let task = Task { @MainActor in
        try await WebHostRunner.run(
          MultipleCounterApp(), configuration: .init(web: .init()), server: server,
          token: WebHostToken(rawValue: "test-token"),
          browserOpener: RecordingBrowserOpener(), bannerWriter: RecordingBannerWriter())
      }
      let session = await server.startedSession()
      func attach(_ id: String) async -> (
        AsyncStream<WebHostSocketMessage>.Continuation,
        AsyncStream<WebHostSocketMessage>.Iterator
      ) {
        let (input, continuation) = AsyncStream<WebHostSocketMessage>.makeStream()
        let output = await session.channels[id]!.attach(client: input)
        continuation.yield(.data(Array("\u{001E}caps:{\"acceptsDeltaFrames\":false}\n".utf8)))
        return (continuation, output.makeAsyncIterator())
      }
      func read(_ expected: String, from iterator: inout AsyncStream<WebHostSocketMessage>.Iterator)
        async throws
      {
        while let message = await iterator.next(isolation: MainActor.shared) {
          guard case .data(let bytes) = message else { continue }
          let record = String(decoding: bytes, as: UTF8.self)
          guard record.hasPrefix("\u{001E}surface:") else { continue }
          let frame = try decodedSurfaceFrame(record)
          let rows = frame["rows"] as? [[[Any]]] ?? []
          let text = rows.map { row in
            row.compactMap { $0.count > 1 ? $0[1] as? String : nil }.joined()
          }.joined(separator: "\n")
          if text.contains(expected) { return }
        }
        Issue.record("Scene stream ended before \(expected)")
      }
      var (primary, primaryOutput) = await attach("primary")
      var (secondary, secondaryOutput) = await attach("secondary")
      try await read("Primary count 0", from: &primaryOutput)
      try await read("Secondary count 0", from: &secondaryOutput)
      secondary.yield(.data(Array("\u{001E}key:tab:0\n\u{001E}key:return:0\n".utf8)))
      try await read("Secondary count 1", from: &secondaryOutput)
      secondary.finish()
      var (reattached, reattachedOutput) = await attach("secondary")
      try await read("Secondary count 1", from: &reattachedOutput)
      primary.yield(.data(Array("\u{001E}key:tab:0\n\u{001E}key:return:0\n".utf8)))
      try await read("Primary count 1", from: &primaryOutput)
      reattached.yield(.data(Array("\u{001E}key:return:0\n".utf8)))
      try await read("Secondary count 2", from: &reattachedOutput)
      primary.finish()
      reattached.finish()
      await cancelAndDrain(task)
      for channel in session.channels.values {
        #expect(await channel.consumeObservations().sceneInputFinished)
      }
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
      var clientContinuation: AsyncStream<WebHostSocketMessage>.Continuation?
      let client = AsyncStream<WebHostSocketMessage> { clientContinuation = $0 }
      let output = await session.channel.attach(client: client)
      let recorder = WebSocketOutputRecorder()
      let outputTask = Task {
        for await message in output {
          await recorder.record(message)
        }
      }

      // A newly attached client is pre-capabilities: surface records are dropped
      // until its declaration re-anchors the encoder. The browser client sends
      // this record first on every socket, so the runner's reader is what turns
      // the session surface-active.
      clientContinuation?.yield(
        .data(Array("\u{001E}caps:{\"acceptsDeltaFrames\":true}\n".utf8)))

      await recorder.waitForSurfaceFrame()

      outputTask.cancel()
      clientContinuation?.finish()
      await cancelAndDrain(task)
    }

    @Test("runner fully renders the resized WebSocket surface without further input")
    func runnerRendersResizedWebSocketSurface() async throws {
      let server = FakeWebHostServer()
      let task = Task { @MainActor in
        try await WebHostRunner.run(
          ResizableSceneApp(),
          configuration: .init(web: .init()),
          server: server,
          token: WebHostToken(rawValue: "test-token"),
          browserOpener: RecordingBrowserOpener(),
          bannerWriter: RecordingBannerWriter()
        )
      }

      let session = await server.startedSession()
      var clientContinuation: AsyncStream<WebHostSocketMessage>.Continuation?
      let client = AsyncStream<WebHostSocketMessage> { clientContinuation = $0 }
      let output = await session.channel.attach(client: client)
      let recorder = WebSocketOutputRecorder()
      let outputTask = Task {
        for await message in output {
          await recorder.record(message)
        }
      }

      clientContinuation?.yield(
        .data(Array("\u{001E}caps:{\"acceptsDeltaFrames\":true}\n".utf8))
      )
      await recorder.waitForSurfaceFrameCount(1)

      clientContinuation?.yield(
        .data(Array("\u{001E}resize:100:40:9:18\n".utf8))
      )
      await recorder.waitForSurfaceFrameCount(2)

      let resizedFrame = try #require(await recorder.surfaceFrameOutputs().last)
      let decodedFrame = try decodedSurfaceFrame(resizedFrame)
      #expect(decodedFrame["width"] as? Int == 100)
      #expect(decodedFrame["height"] as? Int == 40)
      #expect(row(of: "B", in: decodedFrame) == 39)

      outputTask.cancel()
      clientContinuation?.finish()
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
  private struct MultipleCounterApp: App {
    var body: some Scene {
      WindowGroup("Primary", id: WindowIdentifier("primary")) { RetainedCounter(name: "Primary") }
      WindowGroup("Secondary", id: WindowIdentifier("secondary")) {
        RetainedCounter(name: "Secondary")
      }
    }
  }

  private struct RetainedCounter: View {
    let name: String
    @State private var count = 0
    var body: some View {
      VStack {
        Text("\(name) count \(count)")
        Button("Increment") { count += 1 }
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

  @MainActor
  private struct ResizableSceneApp: App {
    var body: some Scene {
      WindowGroup("Resizable", id: WindowIdentifier("resizable")) {
        VStack {
          Text("T")
          Spacer()
          Text("B")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  private func decodedSurfaceFrame(
    _ output: String
  ) throws -> [String: Any] {
    let prefix = "\u{001E}surface:"
    let line = output.trimmingCharacters(in: .newlines)
    let json = String(line.dropFirst(prefix.count))
    return try #require(
      JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    )
  }

  private func row(
    of character: String,
    in frame: [String: Any]
  ) -> Int? {
    guard let rows = frame["rows"] as? [[[Any]]] else {
      return nil
    }
    return rows.firstIndex { cells in
      cells.contains { cell in
        cell.count > 1 && cell[1] as? String == character
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
      scenes: [WebHostSceneDescriptor]
    ) async throws -> WebHostServerSession {
      let scene = scenes.first(where: \.isDefault) ?? scenes[0]
      let channels = Dictionary(uniqueKeysWithValues: scenes.map { ($0.id, WebHostSceneChannel()) })
      let channel = channels[scene.id]!
      let session = WebHostServerSession(
        baseURL: URL(
          string: "http://127.0.0.1:\(configuration.port == 0 ? 9123 : configuration.port)/")!,
        webSocketURL: URL(
          string: "ws://127.0.0.1:9123/ws/scene/\(scene.id)?token=\(token.rawValue)")!,
        token: token,
        channel: channel,
        channels: channels,
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
    private var surfaceFrameWaiters:
      [(
        count: Int,
        continuation: CheckedContinuation<Void, Never>
      )] = []

    func record(
      _ message: WebHostSocketMessage
    ) {
      messages.append(message)
      let frameCount = surfaceFrameOutputs().count
      if frameCount > 0 {
        let ready = surfaceFrameWaiters.filter { frameCount >= $0.count }
        surfaceFrameWaiters.removeAll { frameCount >= $0.count }
        for waiter in ready {
          waiter.continuation.resume()
        }
      }
    }

    /// Suspends until a recorded message carries a web-surface frame.
    func waitForSurfaceFrame() async {
      await waitForSurfaceFrameCount(1)
    }

    func waitForSurfaceFrameCount(
      _ count: Int
    ) async {
      if surfaceFrameOutputs().count >= count {
        return
      }
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        surfaceFrameWaiters.append((count, continuation))
      }
    }

    func surfaceFrameOutputs() -> [String] {
      messages.compactMap { message in
        guard case .data(let bytes) = message else {
          return nil
        }
        let output = String(decoding: bytes, as: UTF8.self)
        return output.contains("\u{1E}surface:") ? output : nil
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

#endif
