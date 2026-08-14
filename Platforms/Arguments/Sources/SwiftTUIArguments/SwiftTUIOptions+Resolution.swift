public import Foundation
public import SwiftTUIRuntime

extension SwiftTUIOptions {
  /// Resolves parsed flags + env vars into a `RuntimeConfiguration`.
  ///
  /// Precedence: explicit CLI flag > env var > TTY auto-detect > framework default.
  /// `--no-color` always wins over `--force-color`. `--accessible` implies
  /// `--reduce-motion --cursor-follows-focus`.
  public func runtimeConfiguration(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    isStdoutTTY: Bool = isatty(STDOUT_FILENO) != 0
  ) -> RuntimeConfiguration {
    // Step 1: Establish the env-var-derived baseline.
    let baseline = RuntimeConfiguration.detect(
      environment: environment, isStdoutTTY: isStdoutTTY)

    // Step 2: Apply CLI flags on top of baseline. CLI flags shadow env vars
    //         only when they are non-default; default values pass through to baseline.
    var color = baseline.color
    var glyphs = baseline.glyphs
    var motion = baseline.motion
    var stableOutput = baseline.stableOutput
    var output = baseline.output
    var cursorFollowsFocus = baseline.cursorFollowsFocus

    // --accessible expands to --reduce-motion --cursor-follows-focus.
    let effectiveReduceMotion = reduceMotion || accessible
    let effectiveCursorFollowsFocus = self.cursorFollowsFocus || accessible

    // Color: --no-color > --force-color, both override baseline.
    if noColor {
      color = .never
    } else if forceColor {
      color = .always
    }

    // Glyphs: --ascii overrides baseline.
    if ascii {
      glyphs = .ascii
    }

    // Motion: --reduce-motion (or --accessible) overrides baseline.
    if effectiveReduceMotion {
      motion = .reduced
    }
    if self.stableOutput {
      stableOutput = true
    }

    // Cursor focus-following: opt-in for TUI output.
    if effectiveCursorFollowsFocus {
      cursorFollowsFocus = true
    }

    // Output: --json overrides the baseline output mode.
    if json {
      output = .json
    }

    // Web: present iff --web or env var set; CLI values override env var values.
    let web: RuntimeConfiguration.WebConfig? = {
      if self.web {
        return RuntimeConfiguration.WebConfig(
          port: port,
          bind: bind,
          openBrowser: open,
          sceneID: scene.map { WindowIdentifier($0) }
        )
      }
      return baseline.web
    }()

    // Verbosity: --quiet > --verbose level > baseline.
    let verbosity: RuntimeConfiguration.Verbosity = {
      if quiet { return .quiet }
      if verbose > 0 { return .verbose(level: verbose) }
      return baseline.verbosity
    }()

    // Debug: --debug overrides baseline.
    let debug = self.debug || baseline.debug

    return RuntimeConfiguration(
      color: color,
      glyphs: glyphs,
      motion: motion,
      stableOutput: stableOutput,
      output: output,
      verbosity: verbosity,
      web: web,
      debug: debug,
      cursorFollowsFocus: cursorFollowsFocus
    )
  }
}
