import Foundation
import Synchronization

/// Errors produced when invoking `git` via Foundation `Process`.
enum GitProcessError: Error, CustomStringConvertible, Sendable {
  case launchFailed(message: String)
  case nonzeroExit(command: [String], status: Int32, stderr: String)
  case decodingFailed(command: [String])

  var description: String {
    switch self {
    case .launchFailed(let message):
      return "git: failed to launch — \(message)"
    case .nonzeroExit(let command, let status, let stderr):
      let summary = command.joined(separator: " ")
      let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty
        ? "git \(summary) exited with status \(status)"
        : "git \(summary) exited with status \(status): \(trimmed)"
    case .decodingFailed(let command):
      return "git \(command.joined(separator: " ")): could not decode stdout as UTF-8"
    }
  }
}

/// Internal `Process` invoker. Synchronous because gitviz is a CLI script,
/// not a long-running daemon.
enum GitProcess {
  /// Runs `git <arguments>` with `workingDirectory` as the cwd and returns
  /// the stdout buffer decoded as UTF-8.
  static func run(
    workingDirectory: URL,
    arguments: [String]
  ) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    process.currentDirectoryURL = workingDirectory

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    // Don't inherit interactive paging behavior.
    var environment = ProcessInfo.processInfo.environment
    environment["GIT_PAGER"] = "cat"
    environment["PAGER"] = "cat"
    environment["LC_ALL"] = "C"
    process.environment = environment

    do {
      try process.run()
    } catch {
      throw GitProcessError.launchFailed(message: "\(error)")
    }

    // Drain stdout / stderr concurrently with the subprocess. macOS pipe
    // buffers are ~64KB; once they fill, `git` blocks on write() and we'd
    // deadlock if we waitUntilExit() before reading. Spawning two reader
    // threads keeps the pipes drained while the child runs.
    let stdoutHandle = stdoutPipe.fileHandleForReading
    let stderrHandle = stderrPipe.fileHandleForReading
    let stdoutBox = DataBox()
    let stderrBox = DataBox()
    let stdoutReader = Thread {
      let data = stdoutHandle.readDataToEndOfFile()
      stdoutBox.set(data)
    }
    let stderrReader = Thread {
      let data = stderrHandle.readDataToEndOfFile()
      stderrBox.set(data)
    }
    stdoutReader.start()
    stderrReader.start()
    process.waitUntilExit()
    // Both reader threads exit when the child closes its pipe ends. Join
    // them before reading the boxes to ensure publication.
    while stdoutReader.isExecuting || stderrReader.isExecuting {
      Thread.sleep(forTimeInterval: 0.001)
    }
    let stdoutData = stdoutBox.get()
    let stderrData = stderrBox.get()
    let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

    if process.terminationStatus != 0 {
      throw GitProcessError.nonzeroExit(
        command: ["git"] + arguments,
        status: process.terminationStatus,
        stderr: stderrText
      )
    }

    guard let output = String(data: stdoutData, encoding: .utf8) else {
      throw GitProcessError.decodingFailed(command: ["git"] + arguments)
    }
    return output
  }
}

/// Thread-safe Data holder used to publish the result of a background
/// pipe-draining `Thread`.
private final class DataBox: Sendable {
  private let storage = Mutex<Data>(Data())

  func set(_ data: Data) {
    storage.withLock { value in
      value = data
    }
  }

  func get() -> Data {
    storage.withLock { $0 }
  }
}
