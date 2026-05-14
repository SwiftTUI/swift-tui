public import ArgumentParser

/// The framework-owned option group flattened into every `SwiftTUICommand`.
///
/// Consumers using power mode flatten this directly:
///
/// ```swift
/// @OptionGroup(title: "SwiftTUI Options")
/// var swiftTUIOptions: SwiftTUIOptions
/// ```
///
/// Consumers using the `SwiftTUICommand` protocol get this through the
/// required `swiftTUIOptions` property.
///
/// Reserved long flag names (consumers must not redeclare): see
/// `docs/proposals/ARGUMENT_PARSING.md` § Reserved namespace.
public struct SwiftTUIOptions: ParsableArguments, Sendable {
  // ─── Color and appearance ────────────────────────────────────────

  @Flag(
    name: .customLong("no-color"),
    help: "Disable color output. Equivalent to NO_COLOR=1. [env: NO_COLOR]"
  )
  public var noColor: Bool = false

  @Flag(
    name: .customLong("force-color"),
    help: "Force color output even when stdout is not a TTY. [env: FORCE_COLOR]"
  )
  public var forceColor: Bool = false

  // ─── Accessibility ──────────────────────────────────────────────

  @Flag(
    name: .customLong("accessible"),
    help:
      "Accessible mode: drop the TUI for a linear, append-only render. [env: SWIFTTUI_ACCESSIBLE]"
  )
  public var accessible: Bool = false

  @Flag(
    name: .customLong("ascii"),
    help: "ASCII-only mode: no Unicode glyphs, box drawing, or emoji. [env: SWIFTTUI_ASCII]"
  )
  public var ascii: Bool = false

  @Flag(
    name: .customLong("reduce-motion"),
    help: "Suppress animations and spinners. [env: SWIFTTUI_REDUCE_MOTION]"
  )
  public var reduceMotion: Bool = false

  @Flag(
    name: .customLong("no-progress"),
    help: "Replace progress bars with static status messages. [env: SWIFTTUI_NO_PROGRESS]"
  )
  public var noProgress: Bool = false

  @Flag(
    name: .customLong("plain"),
    help: "Plain text only: implies --no-color, --ascii, --reduce-motion. [env: SWIFTTUI_PLAIN]"
  )
  public var plain: Bool = false

  @Flag(
    name: .customLong("linear"),
    help: "Accessible linear output: drop the TUI for append-only text. [env: SWIFTTUI_LINEAR]"
  )
  public var linear: Bool = false

  @Flag(
    name: .customLong("cursor-follows-focus"),
    help: "Move the terminal cursor to focus in TUI output. [env: SWIFTTUI_CURSOR_FOLLOWS_FOCUS]"
  )
  public var cursorFollowsFocus: Bool = false

  // ─── Output mode ────────────────────────────────────────────────

  @Flag(
    name: .customLong("json"),
    help: "Output JSON instead of rendering a TUI (where supported). [env: SWIFTTUI_JSON]"
  )
  public var json: Bool = false

  // ─── Web host ───────────────────────────────────────────────────

  @Flag(
    name: .customLong("web"),
    help: "Serve the app over HTTP instead of a local terminal. [env: SWIFTTUI_WEB]"
  )
  public var web: Bool = false

  @Option(
    name: .customLong("port"),
    help: "Port for --web. 0 = auto-assign. [env: SWIFTTUI_PORT]"
  )
  public var port: Int = 0

  @Option(
    name: .customLong("bind"),
    help: "Bind address for --web. [env: SWIFTTUI_BIND]"
  )
  public var bind: String = "127.0.0.1"

  @Flag(
    name: .customLong("open"),
    help: "Open the browser when serving with --web. [env: SWIFTTUI_OPEN]"
  )
  public var open: Bool = false

  @Option(
    name: .customLong("scene"),
    help: "Scene identifier to launch when serving with --web. [env: SWIFTTUI_WEB_SCENE]"
  )
  public var scene: String?

  // ─── Logging / diagnostics ─────────────────────────────────────

  @Flag(
    name: .shortAndLong,
    help: "Verbose logging. Use -vv or -vvv for higher levels. [env: SWIFTTUI_VERBOSE]"
  )
  public var verbose: Int

  @Flag(
    name: .customLong("quiet"),
    help: "Suppress non-error log output. [env: SWIFTTUI_QUIET]"
  )
  public var quiet: Bool = false

  @Flag(
    name: .customLong("debug"),
    help: "Enable framework-internal debug instrumentation. [env: SWIFTTUI_DEBUG]"
  )
  public var debug: Bool = false

  public init() {}
}
