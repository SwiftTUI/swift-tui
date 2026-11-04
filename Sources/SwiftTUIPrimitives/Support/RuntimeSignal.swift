/// A signal delivered to the runtime. Hosts may also define their own signal names.
public enum RuntimeSignal: Hashable, Sendable {
  case abort
  case hangup
  case illegalInstruction
  case interrupt
  case segmentationFault
  case terminate
  case user1
  case user2
  case alarm
  case quit
  case windowChange
  case busError
  case floatingPointException
  case trap
  case resume
  case brokenPipe
  case other(String)

  public init(name: String) {
    switch name {
    case "SIGABRT": self = .abort
    case "SIGHUP": self = .hangup
    case "SIGILL": self = .illegalInstruction
    case "SIGINT": self = .interrupt
    case "SIGSEGV": self = .segmentationFault
    case "SIGTERM": self = .terminate
    case "SIGUSR1": self = .user1
    case "SIGUSR2": self = .user2
    case "SIGALRM": self = .alarm
    case "SIGQUIT": self = .quit
    case "SIGWINCH": self = .windowChange
    case "SIGBUS": self = .busError
    case "SIGFPE": self = .floatingPointException
    case "SIGTRAP": self = .trap
    case "SIGCONT": self = .resume
    case "SIGPIPE": self = .brokenPipe
    default: self = .other(name)
    }
  }

  public var name: String {
    switch self {
    case .abort: "SIGABRT"
    case .hangup: "SIGHUP"
    case .illegalInstruction: "SIGILL"
    case .interrupt: "SIGINT"
    case .segmentationFault: "SIGSEGV"
    case .terminate: "SIGTERM"
    case .user1: "SIGUSR1"
    case .user2: "SIGUSR2"
    case .alarm: "SIGALRM"
    case .quit: "SIGQUIT"
    case .windowChange: "SIGWINCH"
    case .busError: "SIGBUS"
    case .floatingPointException: "SIGFPE"
    case .trap: "SIGTRAP"
    case .resume: "SIGCONT"
    case .brokenPipe: "SIGPIPE"
    case .other(let name): name
    }
  }
}
