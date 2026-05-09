/// The resolved runtime configuration handed to a SwiftTUI runner. Produced by argument parsers
/// and env-var resolvers; consumed by `TerminalRunner.run(_:configuration:)` and peer runners.
/// Foundation-free, `Sendable`, value-typed.
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
    /// Allow the full Unicode glyph repertoire including box-drawing and emoji.
    case unicode
    /// Restrict output to 7-bit ASCII glyphs (no box-drawing, emoji, or non-ASCII Unicode).
    case ascii
  }

  public enum MotionMode: String, Sendable, Equatable {
    /// Animations and spinners run as authored.
    case normal
    /// Suppress animations and spinners; honor accessibility / `prefers-reduced-motion` semantics.
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
    /// Suppress non-error log output.
    case quiet
    /// Default log level.
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

  /// Configuration for serving a SwiftTUI app over HTTP via a runner that supports it (e.g., the embedded web host).
  public struct WebConfig: Sendable, Equatable {
    /// TCP port. `0` means OS-assigned ephemeral port.
    public let port: Int
    /// Bind address. Defaults to `127.0.0.1` (loopback only).
    public let bind: String
    /// Whether the runner should auto-open the user's browser when serving.
    public let openBrowser: Bool

    public init(port: Int = 0, bind: String = "127.0.0.1", openBrowser: Bool = false) {
      self.port = port
      self.bind = bind
      self.openBrowser = openBrowser
    }
  }

  /// Color rendering mode.
  public var color: ColorMode
  /// Glyph repertoire.
  public var glyphs: GlyphMode
  /// Animation/motion policy.
  public var motion: MotionMode
  /// Top-level output strategy (TUI render, JSON, or accessible linear render).
  public var output: OutputMode
  /// Log verbosity level for framework-internal diagnostics.
  public var verbosity: Verbosity
  /// If non-nil, serve the app over HTTP using these settings instead of (or in addition to) a local terminal.
  public var web: WebConfig?
  /// Enable framework-internal debug instrumentation (frame timings, render-tree diagnostics).
  public var debug: Bool
  /// Replace progress bars with static status messages.
  public var noProgress: Bool
  /// Linearize side-by-side layouts (e.g., HStacks) top-to-bottom for narrow terminals or screen readers.
  public var linear: Bool
  /// Move the terminal hardware cursor to the focused accessibility node after each TUI commit.
  public var cursorFollowsFocus: Bool

  public init(
    color: ColorMode = .auto,
    glyphs: GlyphMode = .unicode,
    motion: MotionMode = .normal,
    output: OutputMode = .tui,
    verbosity: Verbosity = .normal,
    web: WebConfig? = nil,
    debug: Bool = false,
    noProgress: Bool = false,
    linear: Bool = false,
    cursorFollowsFocus: Bool = false
  ) {
    self.color = color
    self.glyphs = glyphs
    self.motion = motion
    self.output = output
    self.verbosity = verbosity
    self.web = web
    self.debug = debug
    self.noProgress = noProgress
    self.linear = linear
    self.cursorFollowsFocus = cursorFollowsFocus
  }

  /// The framework's documented defaults: unicode, normal motion, auto color, TUI output.
  public static let `default` = RuntimeConfiguration()
}
