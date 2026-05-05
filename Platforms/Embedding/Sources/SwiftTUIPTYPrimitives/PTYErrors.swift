public enum PTYError: Error, CustomStringConvertible, Sendable {
  case allocationFailed(errno: Int32)
  case slavePathUnavailable
  case spawnFailed(errno: Int32)
  case resizeFailed(errno: Int32)
  case writeFailed(errno: Int32)
  case readFailed(errno: Int32)
  case alreadyStarted
  case notStarted

  public var description: String {
    switch self {
    case .allocationFailed(let errno):
      "openpty failed: errno=\(errno)"
    case .slavePathUnavailable:
      "ttyname returned nil for slave fd"
    case .spawnFailed(let errno):
      "fork/execve failed: errno=\(errno)"
    case .resizeFailed(let errno):
      "TIOCSWINSZ failed: errno=\(errno)"
    case .writeFailed(let errno):
      "write failed: errno=\(errno)"
    case .readFailed(let errno):
      "read failed: errno=\(errno)"
    case .alreadyStarted:
      "PTY has already been started"
    case .notStarted:
      "PTY has not been started"
    }
  }
}
