#if os(macOS) || os(Linux)
  import Dispatch
  import Foundation
  import SwiftTUIRuntime
  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #elseif canImport(Musl)
    import Musl
  #endif

  @MainActor
  final class ReloadDriver {
    let options: DevOptions
    let spool: URL
    let swiftly: URL
    private var child: Process?
    private var commandProcess: Process?
    private var stopRequested = false
    private var sequence: UInt64 = 0
    private var eventHandle: FileHandle?
    private var targetDirectory: URL!
    private var targetName = ""
    private var binaryDirectory: URL!
    private var contract: [String: Data] = [:]
    private var dependencyDirectories: [URL] = []
    private var sourceDirectories: [URL] = []
    private var dependencies: [String: Data] = [:]
    private var toolchainText = ""
    private var observed: [String: Data] = [:]
    private var pending: [String: Data]?
    private var changedAt = ProcessInfo.processInfo.systemUptime
    private var observationError: (any Error)?
    private var foregroundGroup: pid_t?
    private var pendingDiagnostic: String?
    private struct ApplicationCommand: Decodable {
      let moduleName: String
      let importPath: String
      let sources: [String]
      let otherArguments: [String]
      let isLibrary: Bool
    }
    private var applicationCommand: ApplicationCommand?

    init(options: DevOptions) throws {
      self.options = options
      let manager = FileManager.default
      spool = manager.temporaryDirectory.appendingPathComponent("swifttui-dev-\(UUID().uuidString)")
      let bin = ProcessInfo.processInfo.environment["SWIFTLY_BIN_DIR"]
        ?? manager.homeDirectoryForCurrentUser.appendingPathComponent(".swiftly/bin").path
      swiftly = URL(fileURLWithPath: bin).appendingPathComponent("swiftly")
      guard manager.isExecutableFile(atPath: swiftly.path) else {
        throw DevError("Swiftly is required; set SWIFTLY_BIN_DIR to its installation directory")
      }
      try manager.createDirectory(at: spool, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      var initialized = false
      defer { if !initialized { try? manager.removeItem(at: spool) } }
      guard manager.createFile(atPath: spool.appendingPathComponent("diagnostics.log").path, contents: nil) else {
        throw DevError("Cannot create compiler diagnostics log")
      }
      if let log = options.eventLog {
        guard manager.createFile(atPath: log.path, contents: nil) else {
          throw DevError("Cannot create event log: \(log.path)")
        }
        eventHandle = try FileHandle(forWritingTo: log)
      }
      initialized = true
    }

    func run() async throws -> Int32 {
      defer {
        if let foregroundGroup { _ = tcsetpgrp(STDIN_FILENO, foregroundGroup) }
        if let pendingDiagnostic {
          FileHandle.standardError.write(Data("swifttui-dev: \(pendingDiagnostic)\n".utf8))
        }
        try? eventHandle?.close()
        try? FileManager.default.removeItem(at: spool)
      }
      do { return try await runSession() }
      catch {
        if let child, child.isRunning {
          child.terminate()
          let deadline = ProcessInfo.processInfo.systemUptime + 2
          while child.isRunning {
            if ProcessInfo.processInfo.systemUptime >= deadline {
              _ = kill(child.processIdentifier, SIGKILL)
            }
            try? await Task.sleep(for: .milliseconds(10))
          }
        }
        throw error
      }
    }

    private func runSession() async throws -> Int32 {
      let sources = installSignalSources()
      defer { sources.forEach { $0.cancel() } }
      toolchainText = try await swift(["--version"])
      let token = Self.fingerprint(Data(toolchainText.utf8))
      let scalarSource = spool.appendingPathComponent("Contract.swift")
      let scalarObject = spool.appendingPathComponent("Contract.o")
      try """
        @_cdecl("swifttui_hot_reload_abi")
        public func abi() -> UInt64 { \(HotReloadABI.version) }
        @_cdecl("swifttui_hot_reload_toolchain")
        public func toolchain() -> UInt64 { \(token) }
        """.write(to: scalarSource, atomically: true, encoding: .utf8)
      _ = try await command(["run", "swiftc", "-parse-as-library", "-emit-object",
        scalarSource.path, "-o", scalarObject.path])
      #if os(macOS)
        let exportFlag = "-export_dynamic"
      #else
        let exportFlag = "--export-dynamic"
      #endif
      try await discoverTarget()
      observed = try sourceSnapshot()
      contract = try contractSnapshot()
      dependencies = try dependencySnapshot()
      message("Building \(options.product). During the session, follow compiler diagnostics at \(spool.path)/diagnostics.log")
      _ = try await swift(["build", "-c", "debug", "--product", options.product,
        "-Xswiftc", "-DSWIFTTUI_HOT_RELOAD",
        "-Xlinker", scalarObject.path, "-Xlinker", exportFlag])
      try validateBuildInputs()
      try loadApplicationCommand()
      let executable = binaryDirectory.appendingPathComponent(options.product)
      let process = Process()
      process.executableURL = executable
      process.currentDirectoryURL = options.packagePath
      process.arguments = options.applicationArguments
      var environment = ProcessInfo.processInfo.environment
      environment["SWIFTTUI_HOT_RELOAD_SPOOL"] = spool.path
      environment["SWIFTTUI_HOT_RELOAD_MODULE"] = applicationCommand?.moduleName
      process.environment = environment
      process.standardInput = FileHandle.standardInput
      process.standardOutput = FileHandle.standardOutput
      process.standardError = FileHandle.standardError
      child = process
      try process.run()
      if isatty(STDIN_FILENO) == 1 {
        let previous = tcgetpgrp(STDIN_FILENO)
        let childGroup = getpgid(process.processIdentifier)
        if previous > 0, childGroup > 0 {
          _ = signal(SIGTTOU, SIG_IGN)
          guard tcsetpgrp(STDIN_FILENO, childGroup) == 0 else {
            throw DevError("Cannot hand the foreground terminal to the app")
          }
          foregroundGroup = previous
          _ = kill(process.processIdentifier, SIGCONT)
        }
      }
      let ready = try await awaitStatus { $0.first == "ready" }
      guard ready.count == 4, UInt64(ready[2]) == HotReloadABI.version, UInt64(ready[3]) == token else {
        throw DevError("Running app and driver have different ABI/toolchain contracts")
      }
      record("ready", fields: ["pid": process.processIdentifier])
      // Keep observing while compiler processes suspend this task. In-flight
      // edits retain their original observation time and debounce deadline.
      let observer = Task { @MainActor [weak self] in
        while !Task.isCancelled {
          do {
            try self?.observeSources()
            try await Task.sleep(for: .milliseconds(50))
          } catch is CancellationError { return }
          catch { self?.observationError = error; return }
        }
      }
      defer { observer.cancel() }
      var lastDependencyCheck = ProcessInfo.processInfo.systemUptime
      while process.isRunning, !stopRequested {
        try observeSources()
        guard try contractSnapshot() == contract else {
          record("restart_required")
          throw DevError("Package.swift, Package.resolved or .swift-version changed; restart swifttui-dev")
        }
        if ProcessInfo.processInfo.systemUptime - lastDependencyCheck >= 1 {
          try validateBuildInputs()
          lastDependencyCheck = ProcessInfo.processInfo.systemUptime
        }
        if let candidate = pending,
          ProcessInfo.processInfo.systemUptime - changedAt >= Double(options.debounceMilliseconds) / 1000 {
          if sequence >= options.maximumReloads {
            message("Image limit reached; restart swifttui-dev to release loaded code")
            record("restart_required")
            process.terminate()
            break
          }
          let candidateEditedAt = changedAt
          pending = nil
          try validateBuildInputs()
          guard try await swift(["--version"]) == toolchainText else {
            throw DevError("Swift toolchain changed; restart swifttui-dev")
          }
          let began = ProcessInfo.processInfo.systemUptime
          record("build_start")
          let image = spool.appendingPathComponent(imageName(sequence + 1))
          do {
            try await compileApplicationImage(image, scalarObject: scalarObject)
          } catch {
            try? FileManager.default.removeItem(at: image)
            record("build_failed", fields: ["detail": String(describing: error)])
            message("Build failed; the current app is still running. \(error)")
            continue
          }
          try validateBuildInputs()
          try observeSources()
          if observed != candidate {
            try? FileManager.default.removeItem(at: image)
            record("discarded")
            continue
          }
          try validateBuildInputs()
          guard try await swift(["--version"]) == toolchainText else {
            try? FileManager.default.removeItem(at: image)
            throw DevError("Dependency or toolchain changed during compilation; restart swifttui-dev")
          }
          // Version probing is asynchronous too; reject edits that arrived
          // after relinking, immediately before publication.
          try observeSources()
          if observed != candidate {
            try? FileManager.default.removeItem(at: image)
            record("discarded")
            continue
          }
          try validateBuildInputs()
          if pending == candidate { pending = nil }
          sequence += 1
          try "SwiftTUIReload1\n\(sequence)\n\(image.lastPathComponent)\n".write(
            to: spool.appendingPathComponent("pending"), atomically: true, encoding: .utf8)
          guard kill(process.processIdentifier, SIGUSR1) == 0 else {
            throw DevError("The app exited before reload delivery")
          }
          let status = try await awaitStatus {
            ($0.first == "committed" || $0.first == "error") && $0.count >= 2 && UInt64($0[1]) == self.sequence
          }
          if status.first == "error" {
            record("load_failed", fields: ["detail": status.dropFirst(2).joined(separator: " ")])
            message("Reload refused: \(status.dropFirst(2).joined(separator: " "))")
          } else {
            pendingDiagnostic = nil
            record("committed", fields: [
              "buildToFrameMilliseconds": (ProcessInfo.processInfo.systemUptime - began) * 1000,
              "observedEditToFrameMilliseconds": (ProcessInfo.processInfo.systemUptime - candidateEditedAt) * 1000,
              "droppedSlots": status.count > 2 ? Int(status[2]) ?? 0 : 0,
              "loadedImages": status.count > 3 ? Int(status[3]) ?? 0 : 0,
            ])
          }
        }
        try await Task.sleep(for: .milliseconds(50))
      }
      if process.isRunning { process.terminate() }
      while process.isRunning { try await Task.sleep(for: .milliseconds(10)) }
      return stopRequested ? 0 : process.terminationStatus
    }

    private func swift(_ arguments: [String]) async throws -> String {
      try await command(["run", "swift"] + arguments)
    }

    private func command(_ arguments: [String]) async throws -> String {
      let process = Process()
      process.executableURL = swiftly
      process.currentDirectoryURL = options.packagePath
      process.arguments = arguments
      let stdout = spool.appendingPathComponent("stdout.log")
      let stderr = spool.appendingPathComponent("stderr.log")
      guard FileManager.default.createFile(atPath: stdout.path, contents: nil),
        FileManager.default.createFile(atPath: stderr.path, contents: nil) else {
        throw DevError("Cannot create compiler output files")
      }
      let out = try FileHandle(forWritingTo: stdout)
      let err = try FileHandle(forWritingTo: stderr)
      defer { try? out.close(); try? err.close(); commandProcess = nil }
      process.standardOutput = out
      process.standardError = err
      process.standardInput = FileHandle.nullDevice
      commandProcess = process
      let status: Int32 = try await withCheckedThrowingContinuation { continuation in
        process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
        do { try process.run() } catch { continuation.resume(throwing: error) }
      }
      guard status == 0 else {
        let diagnostics = ((try? String(contentsOf: stdout, encoding: .utf8)) ?? "")
          + ((try? String(contentsOf: stderr, encoding: .utf8)) ?? "")
        throw DevError("Command exited \(status): \(diagnostics.suffix(6000))")
      }
      return try String(contentsOf: stdout, encoding: .utf8)
    }

    private func discoverTarget() async throws {
      struct Description: Decodable {
        struct Product: Decodable { let name: String; let targets: [String] }
        struct Target: Decodable { let name: String; let type: String; let path: String }
        let products: [Product]
        let targets: [Target]
      }
      let data = Data(try await swift(["package", "describe", "--type", "json"]).utf8)
      let description = try JSONDecoder().decode(Description.self, from: data)
      guard let product = description.products.first(where: { $0.name == options.product }),
        let name = options.target ?? (product.targets.count == 1 ? product.targets.first : nil),
        product.targets.contains(name), let target = description.targets.first(where: { $0.name == name }),
        target.type == "executable"
      else { throw DevError("Select one Swift executable target with --target") }
      targetName = name
      targetDirectory = options.packagePath.appendingPathComponent(target.path).standardizedFileURL
      sourceDirectories = description.targets.map {
        options.packagePath.appendingPathComponent($0.path).standardizedFileURL
      }
      struct Dependency: Decodable {
        let path: String
        let dependencies: [Dependency]
      }
      let dependencyData = Data(try await swift(["package", "show-dependencies", "--format", "json"]).utf8)
      let root = try JSONDecoder().decode(Dependency.self, from: dependencyData)
      func paths(_ node: Dependency) -> [URL] {
        node.dependencies.flatMap { [URL(fileURLWithPath: $0.path)] + paths($0) }
      }
      dependencyDirectories = Array(Set(paths(root))).sorted { $0.path < $1.path }
      let path = try await swift(["build", "-c", "debug", "--show-bin-path"])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      binaryDirectory = URL(fileURLWithPath: path)
    }

    private func loadApplicationCommand() throws {
      struct Plan: Decodable { let swiftCommands: [String: ApplicationCommand] }
      let plan = try JSONDecoder().decode(Plan.self,
        from: Data(contentsOf: binaryDirectory.appendingPathComponent("description.json")))
      let candidates = plan.swiftCommands.values.filter { command in
        !command.isLibrary && !command.sources.isEmpty
          && command.sources.allSatisfy {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath().path.hasPrefix(targetDirectory.path + "/")
          }
      }
      guard candidates.count == 1, let command = candidates.first,
        !command.otherArguments.contains("-module-abi-name"),
        !command.otherArguments.contains(where: {
          ["-load-plugin-executable", "-load-plugin-library", "-load-resolved-plugin"].contains($0)
        }),
        command.moduleName.unicodeScalars.allSatisfy({
          CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "_"
        })
      else { throw DevError("Unsupported SwiftPM executable command; generated sources and compiler plugins are not supported") }
      applicationCommand = ApplicationCommand(moduleName: command.moduleName, importPath: command.importPath,
        sources: command.sources.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
        otherArguments: command.otherArguments, isLibrary: command.isLibrary)
    }

    private func compileApplicationImage(_ image: URL, scalarObject: URL) async throws {
      guard let applicationCommand else { throw DevError("No SwiftPM application compile command") }
      let current = try sourceSnapshot()
      let swiftFiles = Set(current.keys.filter { $0.hasPrefix(targetDirectory.path + "/") && $0.hasSuffix(".swift") })
      guard swiftFiles == Set(applicationCommand.sources) else {
        throw DevError("The target's source-file set changed; restart swifttui-dev to refresh its build plan")
      }
      for source in applicationCommand.sources {
        if let text = String(data: current[source] ?? Data(), encoding: .utf8),
          text.range(of: #"@objc\s*\("#, options: .regularExpression) != nil {
          throw DevError("Explicit Objective-C names are process-global; this target requires a restart")
        }
      }
      var flags: [String] = []
      let original = applicationCommand.otherArguments
      var index = 0
      while index < original.count {
        let flag = original[index]
        index += 1
        if ["-incremental", "-enable-batch-mode", "-serialize-diagnostics", "-parseable-output"].contains(flag)
          || flag.hasPrefix("-j") { continue }
        if flag == "-index-store-path" { index += 1; continue }
        if flag == "-Xfrontend", index + 2 < original.count,
          original[index] == "-entry-point-function-name", original[index + 1] == "-Xfrontend" {
          index += 3
          continue
        }
        flags.append(flag)
      }
      // Each image gets its own Swift/Objective-C type namespace. Keep the
      // source module name for qualified references, and change only its ABI
      // name. The graph compares declared logical type aliases, never objects.
      let abiName = "\(applicationCommand.moduleName)_SwiftTUIReload_\(sequence + 1)"
      var arguments = ["run", "swiftc", "-emit-library", "-module-name", applicationCommand.moduleName,
        "-Xfrontend", "-module-abi-name", "-Xfrontend", abiName,
        "-I", applicationCommand.importPath] + flags + applicationCommand.sources
        + [scalarObject.path, "-o", image.path]
      #if os(macOS)
        arguments += ["-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup"]
      #else
        arguments += ["-Xlinker", "-Bsymbolic"]
      #endif
      _ = try await command(arguments)
    }

    private func sourceSnapshot() throws -> [String: Data] {
      var result: [String: Data] = [:]
      for directory in sourceDirectories {
        guard let files = FileManager.default.enumerator(at: directory,
          includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { continue }
        for case let file as URL in files {
          guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
          result[file.standardizedFileURL.path] = try Data(contentsOf: file)
        }
      }
      return result
    }

    private func dependencySnapshot() throws -> [String: Data] {
      var result: [String: Data] = [:]
      for directory in dependencyDirectories {
        guard let files = FileManager.default.enumerator(at: directory,
          includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else {
          throw DevError("Cannot inspect dependency: \(directory.path)")
        }
        for case let file as URL in files {
          let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
          if values.isDirectory == true {
            if file.lastPathComponent == "node_modules" {
              files.skipDescendants()
            }
            continue
          }
          guard values.isRegularFile == true else { continue }
          // Source, module definitions, resources and manifests can all alter
          // dependency objects. Hidden build/VCS directories are excluded.
          result[file.standardizedFileURL.path] = try Data(contentsOf: file)
        }
      }
      return result
    }

    private func validateBuildInputs() throws {
      guard try contractSnapshot() == contract, try dependencySnapshot() == dependencies else {
        record("restart_required")
        throw DevError("A dependency, manifest or lockfile changed; restart swifttui-dev")
      }
    }

    private func observeSources() throws {
      if let observationError { throw observationError }
      let current = try sourceSnapshot()
      guard current != observed else { return }
      try validateChangedSources(from: observed, to: current)
      observed = current
      pending = current
      changedAt = ProcessInfo.processInfo.systemUptime
    }

    private func contractSnapshot() throws -> [String: Data] {
      var result: [String: Data] = [:]
      let variants = try FileManager.default.contentsOfDirectory(atPath: options.packagePath.path)
        .filter { $0.hasPrefix("Package@swift-") && $0.hasSuffix(".swift") }
      for name in ["Package.swift", "Package.resolved", ".swift-version"] + variants {
        let file = options.packagePath.appendingPathComponent(name)
        result[name] = FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : Data()
      }
      return result
    }

    private func validateChangedSources(from before: [String: Data], to after: [String: Data]) throws {
      guard Set(before.keys) == Set(after.keys) else {
        record("restart_required")
        throw DevError("The source-file set changed; restart swifttui-dev to refresh its build plan")
      }
      let changed = Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
      guard changed.allSatisfy({ $0.hasPrefix(targetDirectory.path + "/") && $0.hasSuffix(".swift") }) else {
        record("restart_required")
        throw DevError("A source dependency changed during the build; restart swifttui-dev")
      }
    }

    private func awaitStatus(_ accepts: ([Substring]) -> Bool) async throws -> [Substring] {
      let deadline = ProcessInfo.processInfo.systemUptime + 15
      while child?.isRunning == true, !stopRequested, ProcessInfo.processInfo.systemUptime < deadline {
        if let text = try? String(contentsOf: spool.appendingPathComponent("status"), encoding: .utf8) {
          let fields = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t", omittingEmptySubsequences: false)
          if accepts(fields) { return fields }
        }
        try await Task.sleep(for: .milliseconds(10))
      }
      throw DevError("No reload acknowledgement; check the root export and terminal host")
    }

    private func installSignalSources() -> [any DispatchSourceSignal] {
      [SIGINT, SIGTERM].map { number in
        _ = signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
        source.setEventHandler { [weak self] in
          Task { @MainActor in
            self?.stopRequested = true
            self?.child?.terminate()
            self?.commandProcess?.terminate()
          }
        }
        source.resume()
        return source
      }
    }

    private func record(_ event: String, fields: [String: Any] = [:]) {
      var entry = fields
      entry["event"] = event
      entry["sequence"] = sequence
      entry["time"] = Date().timeIntervalSince1970
      if let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) {
        try? eventHandle?.write(contentsOf: data + Data([10]))
      }
    }

    private func message(_ text: String) {
      if child?.isRunning == true {
        // The application owns the terminal screen. Interleaving diagnostics
        // with its raster bytes leaves text the renderer cannot know to erase.
        pendingDiagnostic = text
        let log = spool.appendingPathComponent("diagnostics.log")
        if !FileManager.default.fileExists(atPath: log.path) {
          _ = FileManager.default.createFile(atPath: log.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: log) {
          defer { try? handle.close() }
          _ = try? handle.seekToEnd()
          try? handle.write(contentsOf: Data("\(text)\n".utf8))
        }
      } else {
        FileHandle.standardError.write(Data("\r\nswifttui-dev: \(text)\r\n".utf8))
      }
    }

    private func imageName(_ sequence: UInt64) -> String {
      #if os(macOS)
        "generation-\(sequence).dylib"
      #else
        "generation-\(sequence).so"
      #endif
    }

    private static func fingerprint(_ data: Data) -> UInt64 {
      data.reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
    }
  }
#endif
