public struct RuntimeConfiguration: Sendable, Equatable {
  public enum ColorMode: String, Sendable, Equatable {
    /// Auto-detect from TTY status and env vars (`NO_COLOR`, `FORCE_COLOR`, ...).
    case auto
    /// Force color on regardless of TTY status.
    case always
    /// Disable color regardless of TTY status.
    case never
  }

  public enum GlyphMode: String, Sendable, Equatable {
    case unicode
    case ascii
  }

  public enum MotionMode: String, Sendable, Equatable {
    case normal
    case reduced
  }

  public enum OutputMode: String, Sendable, Equatable {
    /// Render the SwiftTUI surface to the terminal.
    case tui
    /// Emit JSON instead of a TUI (consumer-defined where supported).
    case json
    /// Linear, append-only render for screen readers / CI logs.
    case accessible
  }

  public enum Verbosity: Sendable, Equatable {
    case quiet
    case normal
    /// `-v`, `-vv`, `-vvv` — level is 1, 2, 3.
    case verbose(level: Int)

    public var rawLevel: Int {
      switch self {
      case .quiet: return -1
      case .normal: return 0
      case .verbose(let level): return level
      }
    }
  }

  public struct WebConfig: Sendable, Equatable {
    public let port: Int
    public let bind: String
    public let openBrowser: Bool

    public init(port: Int = 0, bind: String = "127.0.0.1", openBrowser: Bool = true) {
      self.port = port
      self.bind = bind
      self.openBrowser = openBrowser
    }
  }

  public var color: ColorMode
  public var glyphs: GlyphMode
  public var motion: MotionMode
  public var output: OutputMode
  public var verbosity: Verbosity
  public var web: WebConfig?
  public var startIn: String?
  public var debug: Bool
  public var noProgress: Bool
  public var linear: Bool

  public init(
    color: ColorMode = .auto,
    glyphs: GlyphMode = .unicode,
    motion: MotionMode = .normal,
    output: OutputMode = .tui,
    verbosity: Verbosity = .normal,
    web: WebConfig? = nil,
    startIn: String? = nil,
    debug: Bool = false,
    noProgress: Bool = false,
    linear: Bool = false
  ) {
    self.color = color
    self.glyphs = glyphs
    self.motion = motion
    self.output = output
    self.verbosity = verbosity
    self.web = web
    self.startIn = startIn
    self.debug = debug
    self.noProgress = noProgress
    self.linear = linear
  }

  /// The framework's documented defaults: unicode, normal motion, auto color, TUI output.
  public static let `default` = RuntimeConfiguration()
}
