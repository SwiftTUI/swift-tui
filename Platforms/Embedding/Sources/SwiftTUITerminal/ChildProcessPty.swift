import Foundation
public import SwiftTUICore
import SwiftTUIPTYCPrimitives
public import SwiftTUIPTYPrimitives

#if canImport(Darwin)
  import Darwin
  @unsafe @preconcurrency import Dispatch
#elseif canImport(Glibc)
  import Glibc
  @unsafe @preconcurrency import Dispatch
#endif

public actor ChildProcessPty {
  public enum ExitStatus: Sendable, Equatable {
    case exited(code: Int32)
    case signalled(signal: Int32)
    case unknown
  }

  public private(set) var pair: PTYPair!
  public private(set) var pid: Int32 = 0

  private let executable: String
  private let arguments: [String]
  private let environment: [String: String]?
  private let workingDirectory: String?
  private let initialSize: CellSize
  private var exitContinuation: CheckedContinuation<ExitStatus, Never>?
  private var exitSource: (any DispatchSourceProcess)?
  private var exitStatus: ExitStatus?
  private var hasStarted = false

  public init(
    executable: String,
    arguments: [String] = [],
    environment: [String: String]? = nil,
    workingDirectory: String? = nil,
    initialSize: CellSize
  ) {
    self.executable = executable
    self.arguments = arguments
    self.environment = environment
    self.workingDirectory = workingDirectory
    self.initialSize = initialSize
  }

  public func start() async throws(PTYError) {
    guard !hasStarted else {
      throw .alreadyStarted
    }
    hasStarted = true

    var argv = try unsafe CStringVector([executable] + arguments)
    defer { unsafe argv.deallocate() }

    let childEnvironment = environment ?? ProcessInfo.processInfo.environment
    var envp = try unsafe CStringVector(Self.environmentStrings(from: childEnvironment))
    defer { unsafe envp.deallocate() }

    var childWorkingDirectory = try unsafe CStringBox(workingDirectory)
    defer { unsafe childWorkingDirectory.deallocate() }

    let handles = try openPTY()
    let childPair = PTYPair(handles: handles, retainSlaveFD: true)
    pair = childPair
    try? await childPair.resize(initialSize)

    let forkedPID = unsafe argv.withUnsafeMutablePointer { argvPointer in
      unsafe envp.withUnsafeMutablePointer { envpPointer in
        unsafe swift_tui_pty_fork_exec(
          handles.masterFD,
          handles.slaveFD,
          childWorkingDirectory.pointer,
          argvPointer,
          envpPointer
        )
      }
    }

    if forkedPID < 0 {
      let failureErrno = errno
      await childPair.close()
      pair = nil
      hasStarted = false
      throw .spawnFailed(errno: failureErrno)
    }

    pid = Int32(forkedPID)
    installExitSource(pid: forkedPID)
    await Self.waitUntilProcessGroupExists(pid: forkedPID)
    await childPair.releaseAndCloseSlaveFD()
  }

  public func waitForExit() async -> ExitStatus {
    if let exitStatus {
      return exitStatus
    }

    return await withCheckedContinuation { continuation in
      if let exitStatus {
        continuation.resume(returning: exitStatus)
      } else if exitContinuation == nil {
        exitContinuation = continuation
      } else {
        continuation.resume(returning: .unknown)
      }
    }
  }

  public func sendSignal(_ signal: Int32) throws(PTYError) {
    guard pid > 0 else {
      throw .notStarted
    }

    let processGroupResult = kill(-pid, signal)
    let processGroupErrno = errno
    let processResult = kill(pid, signal)
    if processGroupResult != 0 && processResult != 0 {
      throw .spawnFailed(errno: processGroupErrno)
    }
  }

  private func installExitSource(pid: pid_t) {
    let source = DispatchSource.makeProcessSource(
      identifier: pid,
      eventMask: .exit,
      queue: DispatchQueue.global(qos: .userInitiated)
    )
    source.setEventHandler { [weak self] in
      guard let self else {
        return
      }

      Task {
        await self.reapChild()
      }
    }
    source.setCancelHandler {}
    exitSource = source
    source.resume()
  }

  private func reapChild() async {
    guard pid > 0 else {
      completeExit(.unknown)
      return
    }

    var status: Int32 = 0
    while true {
      let result = unsafe waitpid(pid_t(pid), &status, WNOHANG)
      if result == 0 {
        return
      }
      if result < 0 && errno == EINTR {
        continue
      }
      if result < 0 {
        completeExit(.unknown)
      } else {
        completeExit(Self.decodeExitStatus(status))
      }
      await pair?.close()
      return
    }
  }

  private func completeExit(_ status: ExitStatus) {
    guard exitStatus == nil else {
      return
    }

    exitStatus = status
    exitSource?.cancel()
    exitSource = nil
    let continuation = exitContinuation
    exitContinuation = nil
    continuation?.resume(returning: status)
  }

  private static func environmentStrings(from environment: [String: String]) -> [String] {
    environment.map { key, value in "\(key)=\(value)" }
  }

  private static func decodeExitStatus(_ status: Int32) -> ExitStatus {
    let signal = status & 0x7f
    if signal == 0 {
      return .exited(code: (status >> 8) & 0xff)
    }
    if signal != 0x7f {
      return .signalled(signal: signal)
    }
    return .unknown
  }

  private static func waitUntilProcessGroupExists(pid: pid_t) async {
    for _ in 0..<50 {
      if kill(-pid, 0) == 0 || errno != ESRCH {
        return
      }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }
}

@unsafe
private struct CStringVector {
  private var storage: [UnsafeMutablePointer<CChar>?]

  init(_ strings: [String]) throws(PTYError) {
    var storage: [UnsafeMutablePointer<CChar>?] = unsafe []
    unsafe storage.reserveCapacity(strings.count + 1)
    for string in strings {
      guard let pointer = unsafe duplicateCString(string) else {
        throw .spawnFailed(errno: ENOMEM)
      }
      unsafe storage.append(pointer)
    }
    unsafe storage.append(nil)
    unsafe self.storage = storage
  }

  mutating func withUnsafeMutablePointer<R>(
    _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> R
  ) -> R {
    unsafe storage.withUnsafeMutableBufferPointer { buffer in
      unsafe body(buffer.baseAddress)
    }
  }

  mutating func deallocate() {
    unsafe storage.forEach { pointer in
      if let pointer = unsafe pointer {
        unsafe freeCString(pointer)
      }
    }
    unsafe storage.removeAll()
  }
}

@unsafe
private struct CStringBox {
  var pointer: UnsafeMutablePointer<CChar>?

  init(_ string: String?) throws(PTYError) {
    guard let string else {
      unsafe pointer = nil
      return
    }

    guard let pointer = unsafe duplicateCString(string) else {
      throw .spawnFailed(errno: ENOMEM)
    }
    unsafe self.pointer = pointer
  }

  mutating func deallocate() {
    if let pointer = unsafe pointer {
      unsafe freeCString(pointer)
      unsafe self.pointer = nil
    }
  }
}

private func duplicateCString(_ string: String) -> UnsafeMutablePointer<CChar>? {
  unsafe string.withCString { cString in
    unsafe strdup(cString)
  }
}

private func freeCString(_ pointer: UnsafeMutablePointer<CChar>) {
  #if canImport(Darwin)
    unsafe Darwin.free(pointer)
  #elseif canImport(Glibc)
    unsafe Glibc.free(pointer)
  #endif
}
