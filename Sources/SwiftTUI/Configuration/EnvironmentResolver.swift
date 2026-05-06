extension RuntimeConfiguration {
  /// Builds a `RuntimeConfiguration` from environment variables and TTY status.
  ///
  /// Delegates to `TerminalCapabilityProfile.detect(environment:isTTY:)` for vars
  /// it already reads (`NO_COLOR`, `TERM`, `COLORTERM`, `LANG`/`LC_*`). Owns the
  /// new vars: `SWIFTTUI_*`, `FORCE_COLOR`, `CLICOLOR`, `CLICOLOR_FORCE`, `CI`.
  ///
  /// Precedence within env-var resolution:
  /// 1. `NO_COLOR` always wins over `FORCE_COLOR`
  /// 2. `CLICOLOR=0` disables color; `CLICOLOR_FORCE` forces it
  /// 3. `SWIFTTUI_JSON=1` wins over `SWIFTTUI_ACCESSIBLE=1`
  /// 4. Accessible output implies ASCII, reduced motion, no progress, and linear output
  /// 5. `SWIFTTUI_CURSOR_FOLLOWS_FOCUS=1` enables terminal cursor focus-following
  /// 6. `SWIFTTUI_PLAIN=1` implies `--no-color --ascii --reduce-motion`
  /// 7. CLI flags (in `SwiftTUIArguments`) layer on top of this result
  public static func detect(
    environment: [String: String],
    isStdoutTTY: Bool
  ) -> RuntimeConfiguration {
    let profile = TerminalCapabilityProfile.detect(environment: environment, isTTY: isStdoutTTY)

    // Color resolution. NO_COLOR > CLICOLOR=0 > FORCE_COLOR/CLICOLOR_FORCE > TTY auto.
    let color: ColorMode = {
      if let noColor = environment["NO_COLOR"], !noColor.isEmpty { return .never }
      if environment["CLICOLOR"] == "0" { return .never }
      if let force = environment["FORCE_COLOR"], !force.isEmpty, force != "0" { return .always }
      if let force = environment["CLICOLOR_FORCE"], !force.isEmpty, force != "0" { return .always }
      // Honor TerminalCapabilityProfile's TTY-derived decision:
      return profile.colorLevel == .none ? .never : .auto
    }()

    // Glyphs: directly mirror TerminalCapabilityProfile.detect.
    let glyphs: GlyphMode = profile.glyphLevel == .ascii ? .ascii : .unicode

    // Motion / no-progress: non-TTY or CI implies reduced motion + no progress.
    let isCI = environment["CI"].map { !$0.isEmpty && $0 != "false" && $0 != "0" } ?? false
    var motion: MotionMode = (isCI || !isStdoutTTY) ? .reduced : .normal
    var noProgress: Bool = isCI

    // Output mode.
    var output: OutputMode = .tui
    var glyphsResolved = glyphs

    // SWIFTTUI_* family — overlay on top of the above.
    if let v = environment["SWIFTTUI_ACCESSIBLE"], !v.isEmpty, v != "0" {
      output = .accessible
    }
    if let v = environment["SWIFTTUI_ASCII"], !v.isEmpty, v != "0" {
      glyphsResolved = .ascii
    }
    if let v = environment["SWIFTTUI_REDUCE_MOTION"], !v.isEmpty {
      motion = (v != "0") ? .reduced : .normal
    }
    if let v = environment["SWIFTTUI_NO_PROGRESS"], !v.isEmpty {
      noProgress = (v != "0")
    }
    var linear = false
    if let v = environment["SWIFTTUI_LINEAR"], !v.isEmpty, v != "0" {
      linear = true
    }
    var cursorFollowsFocus = false
    if let v = environment["SWIFTTUI_CURSOR_FOLLOWS_FOCUS"], !v.isEmpty, v != "0" {
      cursorFollowsFocus = true
    }
    if let v = environment["SWIFTTUI_JSON"], !v.isEmpty, v != "0" {
      output = .json
    }

    var colorResolved = color
    if let v = environment["SWIFTTUI_PLAIN"], !v.isEmpty, v != "0" {
      colorResolved = .never
      glyphsResolved = .ascii
      motion = .reduced
    }

    if output == .accessible {
      glyphsResolved = .ascii
      motion = .reduced
      noProgress = true
      linear = true
    }

    // Web config.
    let web: WebConfig? = {
      guard let v = environment["SWIFTTUI_WEB"], !v.isEmpty, v != "0" else { return nil }
      let port = environment["SWIFTTUI_PORT"].flatMap(Int.init) ?? 0
      let bind = environment["SWIFTTUI_BIND"] ?? "127.0.0.1"
      let isNoOpen = environment["SWIFTTUI_NO_OPEN"].map { !$0.isEmpty && $0 != "0" } ?? false
      let openBrowser = !isNoOpen
      return WebConfig(port: port, bind: bind, openBrowser: openBrowser)
    }()

    // Verbosity.
    let verbosity: Verbosity = {
      if let v = environment["SWIFTTUI_QUIET"], !v.isEmpty, v != "0" { return .quiet }
      if let v = environment["SWIFTTUI_VERBOSE"], let level = Int(v), level > 0 {
        return .verbose(level: level)
      }
      return .normal
    }()

    let debug = (environment["SWIFTTUI_DEBUG"].map { !$0.isEmpty && $0 != "0" }) ?? false
    let startIn = environment["SWIFTTUI_START_IN"].flatMap { $0.isEmpty ? nil : $0 }

    return RuntimeConfiguration(
      color: colorResolved,
      glyphs: glyphsResolved,
      motion: motion,
      output: output,
      verbosity: verbosity,
      web: web,
      startIn: startIn,
      debug: debug,
      noProgress: noProgress,
      linear: linear,
      cursorFollowsFocus: cursorFollowsFocus
    )
  }
}
