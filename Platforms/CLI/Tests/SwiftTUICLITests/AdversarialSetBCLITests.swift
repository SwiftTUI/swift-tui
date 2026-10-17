// Adversarial set B, pass 4: CLI runner and attach (361–370).
//
// The terminal runner resolves SwiftTUIOptions over the environment baseline,
// parses its own verbs with a fall-through to app mode, and advertises scenes
// over a line-framed Unix socket whose path the server reports. These probes
// feed the resolver an empty --scene and env-enabled web sub-options, give
// the verbs conflicting selectors and malformed argument lists, push a line
// terminator and C0 controls through the scene protocol, split a request
// across two writes, hand the discovery server a path longer than sun_path,
// and run the instances verb under a web configuration.
//
// Excluded from Windows builds like the other attach tests: the subsystem's
// POSIX half builds empty there.
#if !os(Windows)

  import Foundation
  import SwiftTUIArguments
  import SwiftTUIPlatformIO
  @_spi(Testing) import SwiftTUITestSupport
  import Synchronization
  import Testing

  @testable import SwiftTUICLIAttach
  @testable import SwiftTUITerminalCLI

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #endif

  @MainActor
  @Suite("Adversarial set B: CLI runner and attach", .serialized)
  struct AdversarialSetBCLITests {
    // An empty `--scene` means "no scene selection", exactly as the
    // SWIFTTUI_WEB_SCENE resolver treats an empty value; it does not select a
    // scene named "window".
    @Test func setB361EmptySceneOptionSelectsNoScene() throws {
      let fromEnvironment = try SwiftTUIOptions.parse([]).runtimeConfiguration(
        environment: ["SWIFTTUI_WEB": "1", "SWIFTTUI_WEB_SCENE": ""], isStdoutTTY: false)
      #expect(fromEnvironment.web != nil)
      #expect(fromEnvironment.web?.sceneID == nil, "\(String(describing: fromEnvironment.web))")
      let options = try? SwiftTUIOptions.parse(["--web", "--scene", ""])
      let sceneID = options?.runtimeConfiguration(environment: [:], isStdoutTTY: false).web?
        .sceneID
      withKnownIssue(
        "--scene maps straight through WindowIdentifier, which normalizes an empty string to \"window\""
      ) {
        #expect(options == nil || sceneID == nil, "\(String(describing: sceneID))")
      }
    }

    // CLI web sub-options override the environment's values even when the
    // web session itself was enabled by SWIFTTUI_WEB rather than by --web.
    @Test func setB362WebSubOptionsOverrideAnEnvironmentEnabledWebSession() throws {
      let options = try SwiftTUIOptions.parse(["--port", "9000", "--scene", "details"])
      let configuration = options.runtimeConfiguration(
        environment: ["SWIFTTUI_WEB": "1", "SWIFTTUI_PORT": "8080"], isStdoutTTY: false)
      let web = try #require(configuration.web)
      withKnownIssue(
        "the CLI port/bind/open/scene values are read only inside `if self.web`; an env-enabled session keeps the env values"
      ) {
        #expect(web.port == 9000, "\(web)")
        #expect(web.sceneID == WindowIdentifier("details"), "\(web)")
      }
      let explicit = try SwiftTUIOptions.parse(["--web", "--port", "9000"]).runtimeConfiguration(
        environment: ["SWIFTTUI_PORT": "8080"], isStdoutTTY: false)
      #expect(explicit.web?.port == 9000, "\(String(describing: explicit.web))")
    }

    // `--pid` and `--instance` are alternative selectors; giving both is a
    // usage error, not a silent preference for the PID.
    @Test func setB363ConflictingInstanceSelectorsAreRejected() {
      let conflicting = ["attach", "dash", "--pid", "1", "--instance", "dev"]
      let mode = CLIMode.parse(["app"] + conflicting)
      withKnownIssue(
        "neither Scenes nor Attach validates selector exclusivity; selector(pid:name:) prefers pid"
      ) {
        #expect(throws: (any Error).self, "\(mode)") {
          _ = try RunnerCLI.parseAsRoot(conflicting)
        }
        #expect(throws: (any Error).self) {
          _ = try RunnerCLI.parseAsRoot(["scenes", "--pid", "1", "--instance", "dev"])
        }
      }
      let single = CLIMode.parse(["app", "scenes", "--instance", "dev"])
      #expect(single == .listScenes(selector: .name("dev")), "\(single)")
    }

    // A runner verb with a malformed argument list (a missing scene id, an
    // out-of-range or non-numeric --pid, an extra value, a verb behind `--`
    // or behind an option) is not an error to the bare-mode runner: it falls
    // through to plain app mode.
    @Test func setB364MalformedRunnerVerbsFallThroughToAppMode() {
      let malformed: [[String]] = [
        ["app", "attach"],
        ["app", "attach", "dash", "--pid", "99999999999"],
        ["app", "scenes", "--pid", "x"],
        ["app", "instances", "extra"],
        ["app", "--", "instances"],
        ["app", "--instance", "dev", "instances"],
      ]
      for arguments in malformed {
        let mode = CLIMode.parse(arguments)
        #expect(mode == .app(instanceName: nil), "\(arguments) -> \(mode)")
      }
      let wellFormed = CLIMode.parse(["app", "attach", "dash", "--pid", "2147483647"])
      #expect(wellFormed == .attach(sceneID: "dash", selector: .pid(Int32.max)), "\(wellFormed)")
    }

    // The request parser forgives a missing trailing LF but nothing else: a
    // CRLF terminator, a lowercase verb, surrounding spaces or a doubled LF are
    // unknown commands; a CRLF pair is one grapheme, so `hasSuffix("\n")` strips
    // nothing and the reported command keeps the whole terminator.
    @Test func setB365RequestParsingIsTerminatorTolerantButByteExact() throws {
      let bare = try SocketRequest.parse("LIST")
      #expect(bare == .list)
      let bareAttach = try SocketRequest.parse("ATTACH dash")
      #expect(bareAttach == .attach(sceneID: "dash"))
      var reported: String?
      do {
        _ = try SocketRequest.parse("LIST\r\n")
      } catch SocketProtocolError.unknownCommand(let command) {
        reported = command
      }
      #expect(reported == "LIST\r\n", "\(String(describing: reported))")
      #expect(throws: SocketProtocolError.self) { try SocketRequest.parse("list\n") }
      #expect(throws: SocketProtocolError.self) { try SocketRequest.parse(" LIST\n") }
      #expect(throws: SocketProtocolError.self) { try SocketRequest.parse("LIST \n") }
      #expect(throws: SocketProtocolError.self) { try SocketRequest.parse("LIST\n\n") }
    }

    // A scene identifier cannot carry a line terminator: the request parser
    // confines ATTACH to one line, and an error response stays one line, so
    // the client's read-to-first-newline receives the whole message.
    @Test func setB366SceneIdentifierIsConfinedToOneLine() throws {
      let parsed = try? SocketRequest.parse("ATTACH dash\nLIST\n")
      let registry = SceneInfoRegistry(entries: [
        .init(id: "dash", title: nil, ptyPath: "/dev/pts/9", isPrimary: false)
      ])
      let encoded = try registry.attachResponse(for: "dash\nLIST").encode()
      #expect(encoded.hasPrefix("ERR "), "\(encoded.debugDescription)")
      #expect(encoded.hasSuffix("\n"), "\(encoded.debugDescription)")
      withKnownIssue(
        "parse drops exactly one trailing LF and keeps interior ones; SocketResponse.encode does not escape the message"
      ) {
        #expect(
          parsed == nil || parsed == .attach(sceneID: "dash"), "\(String(describing: parsed))")
        #expect(!encoded.dropLast().contains("\n"), "\(encoded.debugDescription)")
      }
    }

    // The scene list is JSON: C0 control characters in a title are escaped, so
    // a LIST response decodes and never carries raw terminal controls.
    @Test func setB367SceneListEscapesControlCharacters() throws {
      let tabbed = SceneInfo(id: "dash", title: "a\tb", ptyPath: nil, isAttached: false)
      let tabbedBody = try Data(SocketResponse.sceneList([tabbed]).encode().dropFirst(3).utf8)
      let decodedTab = try JSONDecoder().decode([SceneInfo].self, from: tabbedBody)
      #expect(decodedTab.first?.title == "a\tb", "\(decodedTab)")
      let styled = SceneInfo(
        id: "dash", title: "Red\u{1B}[31m\u{01}", ptyPath: nil, isAttached: false)
      let json = styled.jsonString()
      let body = try Data(SocketResponse.sceneList([styled]).encode().dropFirst(3).utf8)
      withKnownIssue(
        "jsonStringLiteral escapes only quote, backslash and \\b \\f \\n \\r \\t (adjacent to STUI-864)"
      ) {
        #expect(
          !json.unicodeScalars.contains(where: { $0.value < 0x20 }), "\(json.debugDescription)")
        #expect(throws: Never.self) { try JSONDecoder().decode([SceneInfo].self, from: body) }
      }
    }

    // The discovery server waits for the line terminator before parsing a
    // request: a client that writes the line in two pieces gets one answer.
    @Test func setB368ServerWaitsForTheLineTerminator() async throws {
      let appName = SetBDiscovery.uniqueAppName()
      let server = SetBDiscovery.makeServer(appName: appName, identifier: "split")
      let task = await SetBDiscovery.start(server)
      defer {
        task.cancel()
        try? FileManager.default.removeItem(atPath: "/tmp/swifttui/\(appName)")
      }
      let probe = try SetBSocketProbe(path: server.socketPath)
      #expect(probe.write("LIS") == 3)
      let early = probe.read(timeoutMilliseconds: 500)
      _ = probe.write("T\n")
      let late = probe.read(timeoutMilliseconds: 300)
      withKnownIssue("handleClient parses the bytes of a single read() as the whole request") {
        #expect(early == nil, "\(String(describing: early))")
        #expect(late?.hasPrefix("OK ") == true, "\(String(describing: late))")
      }
      task.cancel()
      _ = try? await task.value
    }

    // A socket path longer than sun_path is refused instead of being bound at
    // a silently truncated path that the reported socketPath and instance
    // discovery never see.
    @Test(.timeLimit(.minutes(1)))
    func setB369OverlongSocketPathIsRefusedNotTruncated() async throws {
      let appName = SetBDiscovery.uniqueAppName()
      let identifier = String(repeating: "x", count: 120)
      let server = SetBDiscovery.makeServer(appName: appName, identifier: identifier)
      let sunPathCapacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1
      try #require(server.socketPath.utf8.count > sunPathCapacity)
      let truncatedPath = String(
        decoding: Array(server.socketPath.utf8).prefix(sunPathCapacity), as: UTF8.self)
      // `run` either reaches `onReady` (bound) or throws (refused); each arm
      // records its outcome and fires the same event, so the test awaits the
      // settlement directly instead of polling.
      let outcome = Mutex<String?>(nil)
      let settled = AsyncEvent()
      let task = Task {
        do {
          try await server.run(onReady: {
            outcome.withLock { $0 = $0 ?? "bound" }
            settled.fire()
          })
        } catch {
          outcome.withLock { $0 = $0 ?? "refused: \(error)" }
          settled.fire()
        }
      }
      defer {
        task.cancel()
        _ = sceneUnlink(truncatedPath)
        try? FileManager.default.removeItem(atPath: "/tmp/swifttui/\(appName)")
      }
      await settled.wait()
      let result = outcome.withLock { $0 } ?? "pending"
      let bound = result == "bound"
      let reportedPathExists = FileManager.default.fileExists(atPath: server.socketPath)
      let truncatedPathExists = FileManager.default.fileExists(atPath: truncatedPath)
      let discovered = SocketClient.discoverInstances(appName: appName).map(\.identifier)
      withKnownIssue(
        "sceneSocketAddress strncpy-truncates the path to sun_path; the server binds the prefix and reports the full path (adjacent to STUI-860)"
      ) {
        #expect(!bound || reportedPathExists, "\(result) truncated=\(truncatedPathExists)")
        #expect(!bound || discovered == [identifier], "\(discovered)")
      }
      task.cancel()
      await task.value
    }

    // The `instances` verb needs no web host: a web configuration (for
    // example SWIFTTUI_WEB=1 in the environment) must not stop it.
    @Test func setB370InstancesVerbRunsUnderAWebConfiguration() async throws {
      try await TerminalRunner.launch(
        SetBVerbApp(), configuration: .default, arguments: ["app", "instances"])
      await withKnownIssue(
        "launch throws webHostNotLinked before CLIMode routes the verb (STUI-870)"
      ) {
        try await TerminalRunner.launch(
          SetBVerbApp(), configuration: .init(web: .init()), arguments: ["app", "instances"])
      }
    }
  }

  @MainActor
  private struct SetBVerbApp: App {
    var body: some Scene {
      WindowGroup { EmptyView() }
    }
  }

  private enum SetBProbeError: Error {
    case socket(Int32)
    case connect(Int32)
  }

  private enum SetBDiscovery {
    static func uniqueAppName() -> String {
      "swifttuiscenes-setb-\(UUID().uuidString)"
    }

    static func makeServer(appName: String, identifier: String) -> SceneDiscoveryServer {
      SceneDiscoveryServer(
        appName: appName,
        identifier: identifier,
        sceneProvider: {
          [SceneInfo(id: "primary", title: "Primary", ptyPath: nil, isAttached: true)]
        },
        attachHandler: { _ in .error("unsupported") }
      )
    }

    /// Starts `server` and returns once it is bound and listening.
    static func start(_ server: SceneDiscoveryServer) async -> Task<Void, any Error> {
      let ready = AsyncEvent()
      let task = Task {
        try await server.run(onReady: { ready.fire() })
      }
      await ready.wait()
      return task
    }
  }

  /// A raw client connection to a discovery socket.
  private final class SetBSocketProbe {
    let fd: Int32

    init(path: String) throws {
      let fd = sceneSocket()
      guard fd >= 0 else { throw SetBProbeError.socket(errno) }
      var address = sceneSocketAddress(for: path)
      guard sceneConnect(fd, &address) == 0 else {
        let code = errno
        sceneClose(fd)
        throw SetBProbeError.connect(code)
      }
      self.fd = fd
    }

    deinit {
      sceneClose(fd)
    }

    func write(_ text: String) -> Int {
      text.withCString { pointer in
        unsafe sceneWrite(fd, pointer, unsafe strlen(pointer))
      }
    }

    /// Whatever arrives within `timeoutMilliseconds`: nil when nothing does,
    /// an empty string at end of file.
    func read(timeoutMilliseconds: Int32) -> String? {
      var buffer = [UInt8](repeating: 0, count: 4096)
      var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
      let ready = unsafe poll(&descriptor, 1, timeoutMilliseconds)
      guard ready > 0 else { return nil }
      let count = unsafe sceneRead(fd, &buffer, buffer.count)
      guard count > 0 else { return "" }
      return String(decoding: buffer.prefix(count), as: UTF8.self)
    }
  }

#endif
