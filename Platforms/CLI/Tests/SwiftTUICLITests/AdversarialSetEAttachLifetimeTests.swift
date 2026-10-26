// Campaign two F3 pass 2 (setE136–setE144): attach discovery cleanup and
// descriptor lifetimes. Stale-socket cleanup removes only sockets; any other
// entry with the suffix is not ours (STUI-1227, SocketClient.swift). The
// server's own pre-bind cleanup, its start/cancel lifecycle and the client's
// probes are checked against descriptor and directory-entry counts.
//
// Excluded from Windows builds like the other attach tests.
#if !os(Windows)

  import Foundation
  import SwiftTUIPlatformIO
  @_spi(Testing) import SwiftTUITestSupport
  import Synchronization
  import Testing

  @testable import SwiftTUICLIAttach

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #endif

  @Suite("Campaign F3 pass 2 attach discovery lifetimes", .serialized)
  struct AdversarialSetEAttachLifetimeTests {
    // The server's pre-bind cleanup unlinks whatever is not a live socket
    // (SocketServer.swift); discovery keeps non-socket entries (STUI-1227).
    @Test func setE136ServerStartKeepsRegularSockNamedFile() async throws {
      let fixture = try SetEAttachDirectory()
      defer { fixture.remove() }
      let path = fixture.path("blocked.sock")
      try Data("keep".utf8).write(to: URL(fileURLWithPath: path))
      let run = await SetEServerRun.start(fixture.server(identifier: "blocked"))
      defer { run.cancel() }
      setEKnownAttach(newFive) {
        #expect(setEEntryType(path) == S_IFREG, "the regular file was replaced")
        #expect(FileManager.default.contents(atPath: path) == Data("keep".utf8))
      }
      run.cancel()
      _ = await run.finish()
    }

    @Test func setE137ServerStartKeepsSockNamedSymlink() async throws {
      let fixture = try SetEAttachDirectory()
      defer { fixture.remove() }
      let target = fixture.path("target.txt")
      try Data("keep".utf8).write(to: URL(fileURLWithPath: target))
      let link = fixture.path("linked.sock")
      try #require(unsafe symlink(target, link) == 0)
      let run = await SetEServerRun.start(fixture.server(identifier: "linked"))
      defer { run.cancel() }
      setEKnownAttach(newFive) {
        #expect(setEEntryType(link) == S_IFLNK, "the symbolic link was replaced")
      }
      #expect(FileManager.default.contents(atPath: target) == Data("keep".utf8))
      run.cancel()
      _ = await run.finish()
    }

    @Test func setE138ServerStartOverSockNamedDirectoryNamesNoRunningInstance() async throws {
      let fixture = try SetEAttachDirectory()
      defer { fixture.remove() }
      let path = fixture.path("folder.sock")
      try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
      let run = await SetEServerRun.start(fixture.server(identifier: "folder"))
      defer { run.cancel() }
      if run.isReady { run.cancel() }
      let outcome = await run.finish()
      #expect(setEEntryType(path) == S_IFDIR)
      guard case .threw(let error) = outcome else {
        Issue.record("the server bound over a directory: \(outcome)")
        return
      }
      setEKnownAttach(newSix) {
        if case .identifierAlreadyInUse = error as? SceneDiscoveryServerError {
          Issue.record("no instance runs, but the error names one: \(error)")
        }
      }
    }

    @Test func setE139ServerLifecycleReturnsDescriptorsAndEntry() async throws {
      let fixture = try SetEAttachDirectory()
      defer { fixture.remove() }
      let baseline = setEOpenDescriptorCount()
      for cycle in 1...3 {
        let server = fixture.server(identifier: "cycle")
        let run = await SetEServerRun.start(server)
        try #require(run.isReady, "cycle \(cycle) never became ready")
        #expect(setEEntryType(server.socketPath) == S_IFSOCK)
        run.cancel()
        let outcome = await run.finish()
        #expect(outcome.didReturn, "\(outcome)")
        #expect(setEEntryType(server.socketPath) == nil, "cycle \(cycle) left its entry")
        #expect(setEOpenDescriptorCount() == baseline, "cycle \(cycle) leaked a descriptor")
      }
    }

    @Test func setE140SecondServerLeavesLiveSocket() async throws {
      let fixture = try SetEAttachDirectory()
      defer { fixture.remove() }
      let first = fixture.server(identifier: "shared")
      let live = await SetEServerRun.start(first)
      defer { live.cancel() }
      try #require(live.isReady)
      let second = await SetEServerRun.start(fixture.server(identifier: "shared"))
      let outcome = await second.finish()
      guard case .threw(let error) = outcome,
        case .identifierAlreadyInUse = error as? SceneDiscoveryServerError
      else {
        Issue.record("a second server for a live identifier did not refuse: \(outcome)")
        return
      }
      #expect(setEEntryType(first.socketPath) == S_IFSOCK)
      let response = try SocketClient.sendRequest(
        socketPath: first.socketPath, request: "LIST\n", timeoutMilliseconds: 5_000)
      #expect(response == "OK []\n")
      live.cancel()
      #expect(await live.finish().didReturn)
    }

    @Test func setE141DiscoveryScansReturnDescriptors() async throws {
      let fixture = try SetEAttachDirectory()
      defer { fixture.remove() }
      let run = await SetEServerRun.start(fixture.server(identifier: "live"))
      defer { run.cancel() }
      try #require(run.isReady)
      let stale = fixture.path("stale.sock")
      let descriptor = sceneSocket()
      try #require(descriptor >= 0)
      var address = try #require(sceneSocketAddress(for: stale))
      try #require(sceneBind(descriptor, &address) == 0)
      sceneClose(descriptor)
      let baseline = setEOpenDescriptorCount()
      for scan in 1...5 {
        let instances = SocketClient.discoverInstances(appName: fixture.appName)
        #expect(instances.map(\.identifier) == ["live"], "scan \(scan)")
        #expect(setEOpenDescriptorCount() == baseline, "scan \(scan) leaked a probe descriptor")
      }
      #expect(setEEntryType(stale) == nil)
      run.cancel()
      run.cancel()
      _ = await run.finish()
    }

    @Test func setE142RequestToSilentListenerTimesOutAndCloses() throws {
      let path = "/tmp/setE142-\(UUID().uuidString.prefix(8)).sock"
      let listener = sceneSocket()
      try #require(listener >= 0)
      defer {
        sceneClose(listener)
        _ = sceneUnlink(path)
      }
      var address = try #require(sceneSocketAddress(for: path))
      try #require(sceneBind(listener, &address) == 0)
      try #require(sceneListen(listener, 4) == 0)
      let baseline = setEOpenDescriptorCount()
      let started = ContinuousClock.now
      do {
        _ = try SocketClient.sendRequest(
          socketPath: path, request: "LIST\n", timeoutMilliseconds: 100)
        Issue.record("a silent listener answered")
      } catch .readTimedOut {
      } catch .sendTimedOut {
      } catch {
        Issue.record("unexpected failure: \(error)")
      }
      #expect(ContinuousClock.now - started < .seconds(2))
      #expect(setEOpenDescriptorCount() == baseline)
    }

    @Test func setE143CancelledServerReleasesPartialClient() async throws {
      let fixture = try SetEAttachDirectory()
      defer { fixture.remove() }
      let baseline = setEOpenDescriptorCount()
      let server = fixture.server(identifier: "partial")
      let run = await SetEServerRun.start(server)
      defer { run.cancel() }
      try #require(run.isReady)
      let client = sceneSocket()
      try #require(client >= 0)
      var address = try #require(sceneSocketAddress(for: server.socketPath))
      try #require(sceneConnect(client, &address) == 0)
      let partial = Array("LI".utf8)
      let sent = partial.withUnsafeBytes { unsafe sceneWrite(client, $0.baseAddress, 2) }
      #expect(sent == 2)
      run.cancel()
      #expect(await run.finish().didReturn)
      var byte: UInt8 = 0
      let received = unsafe sceneRead(client, &byte, 1)
      #expect(received <= 0, "the cancelled server answered a partial request")
      sceneClose(client)
      #expect(setEEntryType(server.socketPath) == nil)
      #expect(setEOpenDescriptorCount() == baseline)
    }

    // A disposable child with every descriptor slot taken: the server must
    // throw its documented error and leave no entry.
    @Test func setE144ServerUnderDescriptorExhaustionThrowsAndLeavesNoEntry() async {
      await #expect(processExitsWith: .success) {
        let fixture = try SetEAttachDirectory()
        let server = fixture.server(identifier: "exhausted")
        #if canImport(Glibc)
          let resource = __rlimit_resource_t(RLIMIT_NOFILE.rawValue)
        #else
          let resource = RLIMIT_NOFILE
        #endif
        var highest: Int32 = 0
        for fd in Int32(0)..<Int32(1024) where fcntl(fd, F_GETFD) != -1 { highest = fd }
        var limit = rlimit()
        try #require(unsafe getrlimit(resource, &limit) == 0)
        limit.rlim_cur = rlim_t(Int(highest) + 1)
        try #require(unsafe setrlimit(resource, &limit) == 0)
        var fillers: [Int32] = []
        while true {
          let filler = sceneOpen("/dev/null", O_RDONLY)
          guard filler >= 0 else { break }
          fillers.append(filler)
        }
        var thrown: (any Error)?
        do {
          try await server.run(onReady: nil)
        } catch {
          thrown = error
        }
        for filler in fillers { _ = close(filler) }
        guard case .failedToCreateSocket(let code) = thrown as? SceneDiscoveryServerError else {
          Issue.record("expected failedToCreateSocket, got \(String(describing: thrown))")
          return
        }
        #expect(code == EMFILE)
        #expect(setEEntryType(server.socketPath) == nil)
        fixture.remove()
      }
    }
  }

  private let newFive =
    "NEW-5: discovery server start deletes a regular file or symbolic link that has its socket name; the pre-bind cleanup unlinks any existing non-live path without the lstat socket check (SocketServer.swift:210-215); contract: STUI-1227 stale-socket rule, SocketClient.swift:93-96; adjacent STUI-1227"
  private let newSix =
    "NEW-6: discovery server start over a *.sock directory fails as identifierAlreadyInUse (a running instance) although none runs; the failed unlink is ignored and bind EADDRINUSE maps to identifierAlreadyInUse (SocketServer.swift:210-237); contract: SceneDiscoveryServerError.identifierAlreadyInUse (SocketServer.swift:144-145); adjacent STUI-1227"

  private func setEKnownAttach(_ message: String, _ body: () -> Void) {
    if ProcessInfo.processInfo.environment["SWIFTTUI_SETE_UNMARKED"] == "1" {
      body()
    } else {
      withKnownIssue(Comment(rawValue: message)) { body() }
    }
  }

  /// Counts the process's open descriptors below 4096.
  private func setEOpenDescriptorCount() -> Int {
    var count = 0
    for fd in Int32(0)..<Int32(4096) where fcntl(fd, F_GETFD) != -1 { count += 1 }
    return count
  }

  /// The `lstat(2)` file type of the entry itself, or nil when it is absent.
  private func setEEntryType(_ path: String) -> mode_t? {
    var status = stat()
    guard unsafe lstat(path, &status) == 0 else { return nil }
    return status.st_mode & S_IFMT
  }

  /// A unique discovery directory under `/tmp/swifttui`, removed afterwards.
  private struct SetEAttachDirectory {
    let appName = "setE-\(UUID().uuidString.prefix(8))"
    var directory: String { "/tmp/swifttui/\(appName)" }

    init() throws {
      try FileManager.default.createDirectory(
        atPath: "/tmp/swifttui/\(appName)", withIntermediateDirectories: true)
    }

    func path(_ name: String) -> String { "\(directory)/\(name)" }

    func server(identifier: String) -> SceneDiscoveryServer {
      SceneDiscoveryServer(
        appName: appName, identifier: identifier, sceneProvider: { [] },
        attachHandler: { _ in .error("unsupported") })
    }

    func remove() {
      try? FileManager.default.removeItem(atPath: directory)
    }
  }

  /// One `run(onReady:)` of a discovery server. `start` returns once the
  /// server is listening or `run` has already ended, whichever comes first.
  private final class SetEServerRun: Sendable {
    enum Outcome: CustomStringConvertible {
      case returned
      case threw(any Error)
      var didReturn: Bool {
        if case .returned = self { return true }
        return false
      }
      var description: String {
        switch self {
        case .returned: "returned"
        case .threw(let error): "threw \(error)"
        }
      }
    }

    private final class Flag: Sendable {
      private let state = Mutex(false)
      var value: Bool { state.withLock { $0 } }
      func set() { state.withLock { $0 = true } }
    }

    private let ready: Flag
    private let task: Task<Outcome, Never>

    private init(ready: Flag, task: Task<Outcome, Never>) {
      self.ready = ready
      self.task = task
    }

    static func start(_ server: SceneDiscoveryServer) async -> SetEServerRun {
      let settled = AsyncEvent()
      let ready = Flag()
      let task = Task<Outcome, Never> {
        defer { settled.fire() }
        do {
          try await server.run(onReady: {
            ready.set()
            settled.fire()
          })
          return .returned
        } catch {
          return .threw(error)
        }
      }
      await settled.wait()
      return SetEServerRun(ready: ready, task: task)
    }

    var isReady: Bool { ready.value }

    func cancel() { task.cancel() }

    func finish() async -> Outcome {
      await task.value
    }
  }
#endif
