import SwiftTUICore

extension RuntimeConfiguration {
  /// Builds a `RuntimeConfiguration` from environment variables and TTY status.
  ///
  /// Delegates to `TerminalCapabilityProfile.detect(environment:isTTY:)` for vars
  /// it already reads (`NO_COLOR`, `TERM`, `COLORTERM`, `LANG`/`LC_*`).
  /// This resolver owns `SWIFTTUI_*`, `FORCE_COLOR`, `CLICOLOR`, `CLICOLOR_FORCE`, and `CI`.
  ///
  /// Precedence within env-var resolution:
  /// 1. Nonempty `NO_COLOR` always wins over `FORCE_COLOR`; an empty value is ignored
  /// 2. Enabled force variables override `CLICOLOR=0`; otherwise it disables color.
  /// 3. `SWIFTTUI_ACCESSIBLE=1` is shorthand for `SWIFTTUI_REDUCE_MOTION=1`
  ///    plus `SWIFTTUI_CURSOR_FOLLOWS_FOCUS=1`, and wins over explicit `0`
  ///    values on those two variables
  /// 4. CLI flags (in `SwiftTUIArguments`) layer on top of this result
  public static func detect(
    environment: [String: String],
    isStdoutTTY: Bool
  ) -> RuntimeConfiguration {
    let profile = TerminalCapabilityProfile.detect(environment: environment, isTTY: isStdoutTTY)

    // Color resolution. NO_COLOR > FORCE_COLOR/CLICOLOR_FORCE > CLICOLOR=0 > TTY auto.
    let color: ColorMode = {
      if let noColor = environment["NO_COLOR"], !noColor.isEmpty { return .never }
      let forcesColor = [environment["FORCE_COLOR"], environment["CLICOLOR_FORCE"]]
        .compactMap { $0?.lowercased() }
        .contains { !$0.isEmpty && $0 != "0" && $0 != "false" }
      if forcesColor { return .always }
      if environment["CLICOLOR"] == "0" { return .never }
      // Honor TerminalCapabilityProfile's TTY-derived decision:
      return profile.colorLevel == .none ? .never : .auto
    }()

    // Glyphs: directly mirror TerminalCapabilityProfile.detect.
    let glyphs: GlyphMode = profile.glyphLevel == .ascii ? .ascii : .unicode

    // Stable output: non-TTY or CI suppresses built-in motion for deterministic
    // capture, but it is not exposed to app code as an accessibility preference.
    let isCI = environment["CI"].map { !$0.isEmpty && $0 != "false" && $0 != "0" } ?? false
    var stableOutput = isCI || !isStdoutTTY
    var motion: MotionMode = .normal

    // Output mode.
    var output: OutputMode = .tui
    var glyphsResolved = glyphs

    func preference(_ key: SwiftTUIEnvironmentVariable) -> Bool? {
      // A blank optional preference leaves the choice with the host.
      guard let value = environment[key], !value.trimmedUnicodeWhitespace().isEmpty else {
        return nil
      }
      return FeatureFlags.booleanValue(value)
    }

    // SWIFTTUI_* family — overlay on top of the above.
    if preference(.ascii) == true {
      glyphsResolved = .ascii
    }
    if preference(.reduceMotion) == true { motion = .reduced }
    var cursorFollowsFocus = preference(.cursorFollowsFocus) ?? false
    // SWIFTTUI_ACCESSIBLE is a convenience alias for reduced motion plus
    // cursor-follows-focus. It wins over explicit `0` values on either.
    if preference(.accessible) == true {
      motion = .reduced
      cursorFollowsFocus = true
    }
    if preference(.json) == true {
      output = .json
    }

    // Web config.
    func port(_ key: SwiftTUIEnvironmentVariable) -> Int {
      guard let value = environment[key].flatMap(Int.init), (0...65535).contains(value) else {
        return 0
      }
      return value
    }
    let web: WebConfig? = {
      guard preference(.web) == true else { return nil }
      let port = port(.port)
      let bind = environment[.bind] ?? "127.0.0.1"
      let requestedOpen = preference(.open) ?? false
      let disabledOpen = preference(.noOpen) ?? false
      let openBrowser = requestedOpen && !disabledOpen
      let sceneID = environment[.webScene].flatMap { value in
        value.isEmpty ? nil : WindowIdentifier(value)
      }
      return WebConfig(port: port, bind: bind, openBrowser: openBrowser, sceneID: sceneID)
    }()

    // Hosted viewers are interactive even when the server has no terminal.
    if web != nil { stableOutput = false }
    stableOutput = preference(.stableOutput) ?? stableOutput

    let debug = preference(.debug) ?? false

    var configuration = RuntimeConfiguration(
      color: color,
      glyphs: glyphsResolved,
      motion: motion,
      stableOutput: stableOutput,
      // A hosted session presents surface frames; JSON is a terminal output mode.
      output: web == nil ? output : .tui,
      web: web,
      debug: debug,
      cursorFollowsFocus: cursorFollowsFocus
    )
    configuration.accessibilityPreferences = .init(
      reduceMotion: preference(.reduceMotion),
      contrast: preference(.increaseContrast).map { $0 ? .increased : .standard },
      differentiateWithoutColor: preference(.differentiateWithoutColor),
      reduceTransparency: preference(.reduceTransparency),
      colorProfile: environment[.colorProfile].flatMap(
        AccessibilityColorProfile.init(rawValue:)))
    configuration.companion =
      environment[.companion].flatMap(CompanionMode.init(rawValue:)) ?? .auto
    configuration.companionPort = port(.companionPort)
    configuration.terminalReader = preference(.reader) == true
    return configuration
  }
}
