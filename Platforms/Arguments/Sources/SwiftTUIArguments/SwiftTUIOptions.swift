public import ArgumentParser
import SwiftTUIRuntime

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
/// All long flag names declared by this struct are reserved.
/// Consumers must not redeclare them in their own `ParsableArguments`.
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
      "Accessible mode: implies --reduce-motion and --cursor-follows-focus. [env: \(SwiftTUIEnvironmentVariable.accessible.rawValue)]"
  )
  public var accessible: Bool = false

  @Flag(
    name: .customLong("reader"), inversion: .prefixedNo,
    help:
      "Start the sequential terminal reader. F12 switches modes. [env: \(SwiftTUIEnvironmentVariable.reader.rawValue)]"
  )
  public var reader: Bool?

  @Flag(
    name: .customLong("ascii"),
    help:
      "ASCII-only mode: no Unicode glyphs, box drawing, or emoji. [env: \(SwiftTUIEnvironmentVariable.ascii.rawValue)]"
  )
  public var ascii: Bool = false

  @Flag(
    name: .customLong("reduce-motion"),
    help:
      "Suppress animations and spinners. [env: \(SwiftTUIEnvironmentVariable.reduceMotion.rawValue)]"
  )
  public var reduceMotion: Bool = false

  @Flag(
    name: .customLong("stable-output"),
    help:
      "Suppress built-in motion for deterministic capture. [env: \(SwiftTUIEnvironmentVariable.stableOutput.rawValue)]"
  )
  public var stableOutput: Bool = false

  @Flag(
    name: .customLong("cursor-follows-focus"),
    help:
      "Move the terminal cursor to focus in TUI output. [env: \(SwiftTUIEnvironmentVariable.cursorFollowsFocus.rawValue)]"
  )
  public var cursorFollowsFocus: Bool = false

  /// `auto` inherits host detection; `on` and `off` are explicit choices.
  public enum AccessibilityChoice: String, CaseIterable, ExpressibleByArgument, Sendable {
    case auto, on, off

    package var boolValue: Bool? {
      switch self {
      case .auto: nil
      case .on: true
      case .off: false
      }
    }
  }

  @Option(
    name: .customLong("motion-preference"),
    help:
      "Reduced motion: auto, on, off. Overrides the environment; --accessible/--reduce-motion still enable it."
  )
  public var motionPreference: AccessibilityChoice?

  @Option(
    name: .customLong("contrast-preference"),
    help:
      "Increased contrast: auto, on, off. [env: \(SwiftTUIEnvironmentVariable.increaseContrast.rawValue)]"
  )
  public var contrastPreference: AccessibilityChoice?

  @Option(
    name: .customLong("differentiate-without-color"),
    help:
      "Use cues beyond color: auto, on, off. [env: \(SwiftTUIEnvironmentVariable.differentiateWithoutColor.rawValue)]"
  )
  public var differentiateWithoutColor: AccessibilityChoice?

  @Option(
    name: .customLong("reduce-transparency"),
    help:
      "Reduce transparency: auto, on, off. [env: \(SwiftTUIEnvironmentVariable.reduceTransparency.rawValue)]"
  )
  public var reduceTransparency: AccessibilityChoice?

  @Option(
    name: .customLong("color-profile"),
    help:
      "Palette: auto, standard, monochrome, protanopia, deuteranopia, tritanopia. [env: \(SwiftTUIEnvironmentVariable.colorProfile.rawValue)]",
    transform: { value in
      guard value == "auto" || AccessibilityColorProfile(rawValue: value) != nil else {
        throw ValidationError("Unknown accessibility color profile: \(value)")
      }
      return value
    })
  public var colorProfile: String?

  // ─── Output mode ────────────────────────────────────────────────

  @Flag(
    name: .customLong("json"),
    help:
      "Output JSON instead of rendering a TUI (where supported). Ignored in web sessions. [env: \(SwiftTUIEnvironmentVariable.json.rawValue)]"
  )
  public var json: Bool = false

  @Option(
    name: .customLong("companion"),
    help:
      "Browser accessibility companion: auto (interactive TTY), on, off. [env: \(SwiftTUIEnvironmentVariable.companion.rawValue)]"
  )
  public var companion: AccessibilityChoice?

  @Option(
    name: .customLong("companion-port"),
    help:
      "Loopback companion port. 0 = available port. [env: \(SwiftTUIEnvironmentVariable.companionPort.rawValue)]",
    transform: { value in
      guard let port = Int(value), (0...65535).contains(port) else {
        throw ValidationError("--companion-port must be between 0 and 65535")
      }
      return port
    })
  public var companionPort: Int?

  @Flag(
    name: .customLong("companion-url"),
    help: "Print browser URLs for this app's running instances without starting another session.")
  public var companionURL = false

  // ─── Web host ───────────────────────────────────────────────────

  @Flag(
    name: .customLong("web"),
    help:
      "Serve the app over HTTP instead of a local terminal. [env: \(SwiftTUIEnvironmentVariable.web.rawValue)]"
  )
  public var web: Bool = false

  @Option(
    name: .customLong("port"),
    help: "Port for --web. 0 = auto-assign. [env: \(SwiftTUIEnvironmentVariable.port.rawValue)]",
    transform: { argument in
      guard let port = Int(argument), (0...65_535).contains(port) else {
        throw ValidationError("--port must be between 0 and 65535")
      }
      return port
    }
  )
  var parsedPort: Int?

  public var port: Int {
    get { parsedPort ?? 0 }
    set { parsedPort = newValue }
  }

  @Option(
    name: .customLong("bind"),
    help: "Bind address for --web. [env: \(SwiftTUIEnvironmentVariable.bind.rawValue)]"
  )
  var parsedBind: String?

  public var bind: String {
    get { parsedBind ?? "127.0.0.1" }
    set { parsedBind = newValue }
  }

  @Flag(
    name: .customLong("open"), inversion: .prefixedNo,
    help:
      "Open the browser when serving with --web. [env: \(SwiftTUIEnvironmentVariable.open.rawValue)]"
  )
  var parsedOpen: Bool?

  public var open: Bool {
    get { parsedOpen ?? false }
    set { parsedOpen = newValue }
  }

  @Option(
    name: .customLong("scene"),
    help:
      "Scene identifier to launch when serving with --web. [env: \(SwiftTUIEnvironmentVariable.webScene.rawValue)]"
  )
  public var scene: String?

  // ─── Diagnostics ───────────────────────────────────────────────

  @Flag(
    name: .customLong("debug"),
    help:
      "Debug instrumentation: collects a debug bundle (diagnostics TSV, frame trace, manifest) under \(SwiftTUIEnvironmentVariable.debugDir.rawValue) or a temp directory. [env: \(SwiftTUIEnvironmentVariable.debug.rawValue)]"
  )
  public var debug: Bool = false

  public init() {}
}
