#if !os(Windows)
  import Foundation
  @_spi(Runners) import SwiftTUIRuntime
  @_spi(Testing) import SwiftTUITestSupport
  import Testing
  @testable import SwiftTUITerminalCLI
  @testable import SwiftTUIWebHost

  @Suite(.serialized) @MainActor
  struct WebHostCompanionTests {
    @Test(
      "companion attaches to an already edited terminal graph and survives browser departure",
      .timeLimit(.minutes(1)))
    func terminalAndBrowserShareState() async throws {
      let selection = collectWindowSceneSelections(
        from: WindowGroup("Counter", id: "counter") {
          SharedCounterView()
        })[0]
      let terminal = CompanionTestSurface()
      let input = CompanionTestInput()
      let signals = InProcessSignalReader()
      let runtime = try SceneRuntime(
        selection: selection, isPrimary: true,
        resources: SceneSessionResources(
          presentationSurface: terminal, terminalInputReader: input, signalReader: signals))
      let endpoint = runtime.enableCompanion()
      let task = Task { try await runtime.run(sessionName: "CompanionTest") }
      defer {
        task.cancel()
        runtime.shutdown()
      }
      await terminal.changed.wait { terminal.text.contains("Count 0") }
      input.send(.key(.init(.tab)))
      input.send(.key(.init(.return)))
      await terminal.changed.wait { terminal.text.contains("Count 1") }
      let server = CompanionTestServer()
      let companion = try await WebHostCompanion.start(
        endpoints: [endpoint], configuration: .default, server: server)
      #expect(companion.url.contains("renderer=canvas"))
      let channel = try #require(await server.session?.channel)
      func attach() async -> (
        AsyncStream<WebHostSocketMessage>.Continuation, AsyncStream<WebHostSocketMessage>.Iterator
      ) {
        let (stream, continuation) = AsyncStream<WebHostSocketMessage>.makeStream()
        let output = await channel.attach(client: stream)
        continuation.yield(
          .data(
            Array(
              "\u{001E}caps:{\"geometryRevisions\":true,\"sharedViewport\":true}\n\u{001E}resize:18:5\n"
                .utf8)))
        return (continuation, output.makeAsyncIterator())
      }
      func read(_ expected: String, from iterator: inout AsyncStream<WebHostSocketMessage>.Iterator)
        async throws -> [String: Any]
      {
        while let message = await iterator.next(isolation: MainActor.shared) {
          guard case .data(let bytes) = message else { continue }
          let record = String(decoding: bytes, as: UTF8.self)
          guard record.hasPrefix("\u{001E}surface:") else { continue }
          let frame = try #require(
            JSONSerialization.jsonObject(
              with: Data(record.dropFirst("\u{001E}surface:".count).utf8)) as? [String: Any])
          let rows = frame["rows"] as? [[[Any]]] ?? []
          let text = rows.map { $0.compactMap { $0.count > 1 ? $0[1] as? String : nil }.joined() }
            .joined(separator: "\n")
          if text.contains(expected), frame["viewportRevision"] != nil { return frame }
        }
        Issue.record("Companion stream ended before \(expected)")
        return [:]
      }
      var (client, output) = await attach()
      let initial = try await read("Count 1", from: &output)
      let tree = try #require(initial["accessibilityTree"] as? [[String: Any]])
      let button = try #require(tree.first { ($0["label"] as? String) == "Increment" })
      let target = try #require(button["actionTarget"] as? String)
      let encodedTarget = target.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
      client.yield(.data(Array("\u{001E}accessibility:1:\(encodedTarget):activate\n".utf8)))
      let updated = try await read("Count 2", from: &output)
      #expect(
        (updated["accessibilityActionResponse"] as? [String: Any])?["result"] as? String
          == "accepted")
      await terminal.changed.wait { terminal.text.contains("Count 2") }
      #expect(terminal.lastSize == .init(width: 18, height: 5))
      client.finish()
      await terminal.changed.wait { terminal.lastSize == terminal.surfaceSize }
      input.send(.key(.init(.return)))
      await terminal.changed.wait { terminal.text.contains("Count 3") }
      var (nextClient, nextOutput) = await attach()
      let reattached = try await read("Count 3", from: &nextOutput)
      #expect(reattached["accessibilityActionResponse"] == nil)
      nextClient.yield(.data(Array("\u{001E}accessibility:1:\(encodedTarget):activate\n".utf8)))
      _ = try await read("Count 4", from: &nextOutput)
      await terminal.changed.wait { terminal.text.contains("Count 4") }
      nextClient.finish()
      await companion.stop()
      input.finish()
      let result = try await task.value
      #expect(result.exitReason == .inputEnded)
      #expect(await server.stopped)
    }
  }

  @MainActor private struct SharedCounterView: View {
    @State var count = 0
    var body: some View {
      VStack {
        Text("Count \(count)")
        Button("Increment") { count += 1 }
      }
    }
  }

  private final class CompanionTestSurface: PresentationSurface {
    let changed = MainActorConditionSignal()
    var text = ""
    var lastSize = CellSize(width: 0, height: 0)
    var surfaceSize = CellSize(width: 30, height: 8)
    let appearance: TerminalAppearance = .fallback
    let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
    func enableRawMode() throws {}
    func disableRawMode() throws {}
    func write(_ output: String) throws {}
    func clearScreen() throws {}
    func moveCursor(to point: CellPoint) throws {}
    func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
      text = surface.lines.joined(separator: "\n")
      lastSize = surface.size
      let signal = changed
      MainActor.assumeIsolated { signal.notify() }
      return .rasterHostMetrics(for: surface, damage: nil)
    }
  }

  private final class CompanionTestInput: TerminalInputReading {
    let stream: AsyncStream<InputEvent>
    let continuation: AsyncStream<InputEvent>.Continuation
    init() { (stream, continuation) = AsyncStream.makeStream() }
    func inputEvents() -> AsyncStream<InputEvent> { stream }
    func send(_ event: InputEvent) { continuation.yield(event) }
    func finish() { continuation.finish() }
  }

  private actor CompanionTestServer: WebHostServer {
    var session: WebHostServerSession?
    var stopped = false
    func start(configuration: WebHostConfig, token: WebHostToken, scenes: [WebHostSceneDescriptor])
      async throws -> WebHostServerSession
    {
      #expect(configuration.bind == "127.0.0.1")
      let channels = Dictionary(uniqueKeysWithValues: scenes.map { ($0.id, WebHostSceneChannel()) })
      let session = WebHostServerSession(
        baseURL: URL(string: "http://127.0.0.1:12345/")!,
        webSocketURL: URL(string: "ws://127.0.0.1:12345/ws/scene/\(scenes[0].id)")!, token: token,
        channel: channels[scenes[0].id]!, channels: channels, stopHandler: { await self.stop() })
      self.session = session
      return session
    }
    func stop() { stopped = true }
  }
#endif
