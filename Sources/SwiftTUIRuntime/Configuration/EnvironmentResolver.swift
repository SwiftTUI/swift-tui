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

    // SWIFTTUI_* family — overlay on top of the above.
    if let v = environment["SWIFTTUI_ASCII"], !v.isEmpty, v != "0" {
      glyphsResolved = .ascii
    }
    if let v = environment["SWIFTTUI_REDUCE_MOTION"], !v.isEmpty {
      motion = ["0", "false", "no", "off"].contains(v.lowercased()) ? .normal : .reduced
    }
    var cursorFollowsFocus = false
    if let v = environment["SWIFTTUI_CURSOR_FOLLOWS_FOCUS"], !v.isEmpty, v != "0" {
      cursorFollowsFocus = true
    }
    // SWIFTTUI_ACCESSIBLE is a convenience alias for reduced motion plus
    // cursor-follows-focus. It wins over explicit `0` values on either.
    if let v = environment["SWIFTTUI_ACCESSIBLE"], !v.isEmpty, v != "0" {
      motion = .reduced
      cursorFollowsFocus = true
    }
    if let v = environment["SWIFTTUI_JSON"], !v.isEmpty, v != "0" {
      output = .json
    }

    // Web config.
    func port(_ key: String) -> Int {
      guard let value = environment[key].flatMap(Int.init), (0...65535).contains(value) else {
        return 0
      }
      return value
    }
    let web: WebConfig? = {
      guard let v = environment["SWIFTTUI_WEB"], !v.isEmpty, v != "0" else { return nil }
      let port = port("SWIFTTUI_PORT")
      let bind = environment["SWIFTTUI_BIND"] ?? "127.0.0.1"
      let requestedOpen = environment["SWIFTTUI_OPEN"].map { !$0.isEmpty && $0 != "0" } ?? false
      let disabledOpen = environment["SWIFTTUI_NO_OPEN"].map { !$0.isEmpty && $0 != "0" } ?? false
      let openBrowser = requestedOpen && !disabledOpen
      let sceneID = environment["SWIFTTUI_WEB_SCENE"].flatMap { value in
        value.isEmpty ? nil : WindowIdentifier(value)
      }
      return WebConfig(port: port, bind: bind, openBrowser: openBrowser, sceneID: sceneID)
    }()

    // Hosted viewers are interactive even when the server has no terminal.
    if web != nil { stableOutput = false }
    if let v = environment["SWIFTTUI_STABLE_OUTPUT"], !v.isEmpty {
      stableOutput = v != "0"
    }

    let debug = (environment["SWIFTTUI_DEBUG"].map { !$0.isEmpty && $0 != "0" }) ?? false

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
    func preference(_ key: String) -> Bool? {
      guard let value = environment[key]?.lowercased() else { return nil }
      switch value {
      case "1", "true", "yes", "on": return true
      case "0", "false", "no", "off": return false
      default: return nil
      }
    }
    configuration.accessibilityPreferences = .init(
      reduceMotion: preference("SWIFTTUI_REDUCE_MOTION"),
      contrast: preference("SWIFTTUI_INCREASE_CONTRAST").map { $0 ? .increased : .standard },
      differentiateWithoutColor: preference("SWIFTTUI_DIFFERENTIATE_WITHOUT_COLOR"),
      reduceTransparency: preference("SWIFTTUI_REDUCE_TRANSPARENCY"),
      colorProfile: environment["SWIFTTUI_COLOR_PROFILE"].flatMap(
        AccessibilityColorProfile.init(rawValue:)))
    configuration.companion =
      environment["SWIFTTUI_COMPANION"].flatMap(CompanionMode.init(rawValue:)) ?? .auto
    configuration.companionPort = port("SWIFTTUI_COMPANION_PORT")
    configuration.terminalReader = preference("SWIFTTUI_READER") == true
    return configuration
  }
}
