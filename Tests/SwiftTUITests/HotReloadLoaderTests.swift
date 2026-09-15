#if DEBUG && (os(macOS) || os(Linux))
  import Foundation
  import SwiftTUITestSupport
  import Testing
  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #elseif canImport(Musl)
    import Musl
  #endif

  @testable import SwiftTUICore
  @testable import SwiftTUIRuntime
  @testable import SwiftTUIViews

  @MainActor
  private final class ReloadImageFixture {
    let root: URL
    let loader: HotReloadLoader
    let moduleName: String
    init() throws {
      root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      moduleName = "ReloadFixture_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      loader = try HotReloadLoader(spoolPath: root.path, expectedToolchain: 12345,
        logicalModule: moduleName)
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
    func image(_ sequence: UInt64, version: String = "one", abi: UInt64 = HotReloadABI.version,
      toolchain: UInt64 = 12345, nilRoot: Bool = false
    ) throws {
      let source = root.appendingPathComponent("Root.swift")
      try """
        import SwiftTUIRuntime
        import SwiftTUIViews
        \(abi == HotReloadABI.version ? "final class" : "struct") ReloadFixtureReference: Codable {
          var value = 7
        }
        struct ReloadFixtureRoot: View {
          @State private var count = 0
          @State private var reference = ReloadFixtureReference()
          var body: some View {
            VStack {
              Text("image \(version) count=\\(count) reference=\\(reference.value)")
              Button("Increment") { count += 1; reference.value += 1 }
            }
          }
        }
        @_cdecl("swifttui_hot_reload_abi")
        public func abi() -> UInt64 { \(abi) }
        @_cdecl("swifttui_hot_reload_toolchain")
        public func toolchain() -> UInt64 { \(toolchain) }
        @_cdecl("swifttui_hot_reload_root")
        @MainActor public func root() -> UnsafeMutableRawPointer? {
          \(nilRoot ? "return nil" : "return HotReloadExport.retainedRoot { ReloadFixtureRoot() }")
        }
        """.write(to: source, atomically: true, encoding: .utf8)
      let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
      let process = Process()
      let swiftlyDirectory = ProcessInfo.processInfo.environment["SWIFTLY_BIN_DIR"]
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".swiftly/bin").path
      process.executableURL = URL(fileURLWithPath: swiftlyDirectory).appendingPathComponent("swiftly")
      var arguments = ["run", "swiftc", "-swift-version", "6", "-D", "DEBUG",
        "-emit-library", "-module-name", moduleName,
        "-Xfrontend", "-module-abi-name", "-Xfrontend", "\(moduleName)_SwiftTUIReload_\(sequence)",
        "-I", repo.appendingPathComponent(".build/debug/Modules").path, source.path,
        "-o", root.appendingPathComponent(HotReloadLoader.imageName(sequence)).path]
      #if os(macOS)
        arguments += ["-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup"]
      #else
        arguments += ["-Xlinker", "-Bsymbolic"]
      #endif
      process.arguments = arguments
      let log = root.appendingPathComponent("compiler.log")
      _ = FileManager.default.createFile(atPath: log.path, contents: nil)
      let output = try FileHandle(forWritingTo: log)
      defer { try? output.close() }
      process.standardOutput = output
      process.standardError = output
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        throw HotReloadLoadError(try String(contentsOf: log, encoding: .utf8))
      }
      try publish(sequence)
    }
    func publish(_ sequence: UInt64) throws {
      try "SwiftTUIReload1\n\(sequence)\n\(HotReloadLoader.imageName(sequence))\n"
        .write(to: root.appendingPathComponent("pending"), atomically: true, encoding: .utf8)
    }
  }

  @MainActor
  @Suite("Guarded native reload images", .serialized, FailOnSoundnessViolationGrowth())
  struct HotReloadLoaderTests {
    @Test func realImagesExecuteNewCodeAndReplayStateThroughTheRuntime() throws {
      let fixture = try ReloadImageFixture()
      defer { fixture.clean() }
      try fixture.image(1)
      let first = try #require(try fixture.loader.loadPending())
      let session = HotReloadSession(content: first)
      let surface = RecordingPresentationSurface(surfaceSize: .init(width: 40, height: 6))
      let identity = Identity(components: ["LoadedRoot"])
      let loop = RunLoop(rootIdentity: identity, presentationSurface: surface,
        terminalInputReader: InjectedTerminalInputReader(),
        stateContainer: StateContainer(initialState: 0, invalidationIdentities: [identity]),
        focusTracker: FocusTracker(invalidationIdentities: [identity]),
        proposal: .init(width: 40, height: 6)
      ) { _, _ in HotReloadHost(session: session) }
      loop.installHotReloadSession(session)
      loop.hotReloadLoader = fixture.loader
      var frames = 0
      loop.scheduler.requestInput()
      try loop.renderPendingFrames(renderedFrames: &frames)
      _ = loop.handle(.input(.key(KeyPress(.return))))
      try loop.renderPendingFrames(renderedFrames: &frames)
      #expect(surface.frames.last?.contains("image one count=1") == true)
      try fixture.image(2, version: "two")
      _ = loop.handle(.signal("SIGUSR1"))
      #expect(session.generation == 0)
      try loop.renderPendingFrames(renderedFrames: &frames)
      #expect(surface.frames.last?.contains("image two count=1 reference=8") == true,
        "\(surface.frames.last ?? "") \(session.lastReport)")
      #expect(fixture.loader.loadedImageCount == 2)
      #expect(!FileManager.default.fileExists(atPath:
        fixture.root.appendingPathComponent(HotReloadLoader.imageName(2)).path))
      let status = try String(contentsOf: fixture.root.appendingPathComponent("status"), encoding: .utf8)
      #expect(status.hasPrefix("committed\t2\t"))
      try fixture.image(3, abi: 999)
      _ = loop.handle(.signal("SIGUSR1"))
      try loop.renderPendingFrames(renderedFrames: &frames)
      #expect(session.generation == 1)
      #expect(surface.frames.last?.contains("image two count=1") == true)
    }

    @Test func mismatchedScalarsNilRootsAndUnsafeSpoolsAreRefused() throws {
      let fixture = try ReloadImageFixture()
      defer { fixture.clean() }
      for (sequence, abi, toolchain, nilRoot) in [
        (UInt64(1), UInt64(999), UInt64(12345), false),
        (2, HotReloadABI.version, 67890, false),
        (3, HotReloadABI.version, 12345, true),
      ] {
        try fixture.image(sequence, abi: abi, toolchain: toolchain, nilRoot: nilRoot)
        #expect(throws: HotReloadLoadError.self) { try fixture.loader.loadPending() }
      }
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.root.path)
      #expect(throws: HotReloadLoadError.self) { try fixture.loader.loadPending() }
      #expect(throws: HotReloadLoadError.self) {
        try HotReloadLoader(spoolPath: fixture.root.path, expectedToolchain: 12345)
      }
    }

    @Test func imageLimitIncludesRefusedImagesAndStopsBeforeOpeningAnother() throws {
      let fixture = try ReloadImageFixture()
      defer { fixture.clean() }
      try fixture.image(1, abi: 999)
      let image = try Data(contentsOf: fixture.root.appendingPathComponent(HotReloadLoader.imageName(1)))
      for sequence in UInt64(1)...UInt64(HotReloadABI.maximumImages) {
        if sequence != 1 {
          try image.write(to: fixture.root.appendingPathComponent(HotReloadLoader.imageName(sequence)))
          try fixture.publish(sequence)
        }
        #expect(throws: HotReloadLoadError.self) { try fixture.loader.loadPending() }
      }
      #expect(fixture.loader.loadedImageCount == 100)
      // No image exists for 101: the cap must win before an attempted dlopen.
      try fixture.publish(101)
      do {
        _ = try fixture.loader.loadPending()
        Issue.record("Image cap was not enforced")
      } catch {
        #expect(String(describing: error).contains("100 image limit"))
      }
      #expect(fixture.loader.loadedImageCount == 100)
    }

    @Test func symlinkImagesAndTraversalManifestsAreRefused() throws {
      let fixture = try ReloadImageFixture()
      defer { fixture.clean() }
      let target = fixture.root.appendingPathComponent("outside")
      try Data([1]).write(to: target)
      let image = fixture.root.appendingPathComponent(HotReloadLoader.imageName(1))
      try FileManager.default.createSymbolicLink(at: image, withDestinationURL: target)
      try fixture.publish(1)
      #expect(throws: HotReloadLoadError.self) { try fixture.loader.loadPending() }
      #expect(FileManager.default.fileExists(atPath: target.path))
      try "SwiftTUIReload1\n2\n../outside\n".write(
        to: fixture.root.appendingPathComponent("pending"), atomically: true, encoding: .utf8)
      #expect(throws: HotReloadLoadError.self) { try fixture.loader.loadPending() }
      #expect(fixture.loader.loadedImageCount == 0)
    }

    @Test func fifoManifestsAndImagesAreRefusedWithoutBlocking() throws {
      let fixture = try ReloadImageFixture()
      defer { fixture.clean() }
      let pending = fixture.root.appendingPathComponent("pending").path
      #expect(pending.withCString { unsafe mkfifo($0, 0o600) } == 0)
      #expect(throws: HotReloadLoadError.self) { try fixture.loader.loadPending() }
      let image = fixture.root.appendingPathComponent(HotReloadLoader.imageName(1)).path
      #expect(image.withCString { unsafe mkfifo($0, 0o600) } == 0)
      try fixture.publish(1)
      #expect(throws: HotReloadLoadError.self) { try fixture.loader.loadPending() }
    }
  }
#endif
