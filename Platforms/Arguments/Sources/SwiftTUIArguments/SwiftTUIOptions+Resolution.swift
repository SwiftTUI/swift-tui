import SwiftTUI
public import Foundation

extension SwiftTUIOptions {
  /// Resolves parsed flags + env vars into a `RuntimeConfiguration`.
  ///
  /// Precedence: explicit CLI flag > env var > TTY auto-detect > framework default.
  /// `--no-color` always wins over `--force-color`. `--plain` implies
  /// `--no-color --ascii --reduce-motion` but does not override explicit
  /// per-flag settings (so `--plain --force-color` ends up `--no-color` because
  /// `--no-color` from `--plain` wins over `--force-color`).
  public func runtimeConfiguration(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    isStdoutTTY: Bool = isatty(STDOUT_FILENO) != 0
  ) -> RuntimeConfiguration {
    // Step 1: Establish env-var-derived baseline.
    let baseline = RuntimeConfiguration.detect(environment: environment, isStdoutTTY: isStdoutTTY)

    // Step 2: Apply CLI flags on top of baseline. CLI flags shadow env vars
    //         only when they are non-default; default values pass through to baseline.
    var color = baseline.color
    var glyphs = baseline.glyphs
    var motion = baseline.motion
    var output = baseline.output
    var noProgress = baseline.noProgress
    var linear = baseline.linear

    // --plain expands to --no-color --ascii --reduce-motion. The "effective"
    // values are the union of the explicit flag and --plain's implication, so
    // a per-flag override (e.g. --force-color in combination with --plain)
    // still produces the documented result via the precedence rules below.
    let effectiveNoColor = noColor || plain
    let effectiveAscii = ascii || plain
    let effectiveReduceMotion = reduceMotion || plain

    // Color: --no-color (or --plain) > --force-color, both override baseline.
    if effectiveNoColor {
      color = .never
    } else if forceColor {
      color = .always
    }

    // Glyphs: --ascii (or --plain) overrides baseline.
    if effectiveAscii {
      glyphs = .ascii
    }

    // Motion: --reduce-motion (or --plain) overrides baseline.
    if effectiveReduceMotion {
      motion = .reduced
    }

    // No-progress: --no-progress overrides baseline.
    if self.noProgress {
      noProgress = true
    }

    // Linear: --linear overrides baseline.
    if self.linear {
      linear = true
    }

    // Output: --accessible > --json > baseline.
    if accessible {
      output = .accessible
    } else if json {
      output = .json
    }

    // Web: present iff --web or env var set; CLI values override env var values.
    let web: RuntimeConfiguration.WebConfig? = {
      if self.web {
        return RuntimeConfiguration.WebConfig(
          port: port,
          bind: bind,
          openBrowser: !noOpen
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

    // Start-in: CLI value overrides env-var value.
    let startInResolved = startIn ?? baseline.startIn

    return RuntimeConfiguration(
      color: color,
      glyphs: glyphs,
      motion: motion,
      output: output,
      verbosity: verbosity,
      web: web,
      startIn: startInResolved,
      debug: debug,
      noProgress: noProgress,
      linear: linear
    )
  }
}
