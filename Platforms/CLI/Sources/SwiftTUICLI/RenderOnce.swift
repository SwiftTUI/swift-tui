public import Foundation
public import SwiftTUIArguments
import SwiftTUIRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#endif

/// One-shot rendering of a SwiftTUI view tree to stdout (or to a string).
///
/// Unlike the interactive runtime, `RenderOnce` does not grab the alternate
/// screen, install signal handlers, or enter a runloop. It resolves, measures,
/// places, draws, and rasterizes the view tree once, then emits the resulting
/// cell buffer as ANSI-decorated text and returns. Output streams naturally
/// to stdout and survives piping to `less`, `tee`, or files.
///
/// Width defaults to the live terminal width (`TIOCGWINSZ`), then `$COLUMNS`,
/// then 80. Color and glyph policy honors `SwiftTUIOptions` plus the standard
/// env-var precedence (`NO_COLOR`, `CLICOLOR`, `FORCE_COLOR`, `CLICOLOR_FORCE`,
/// `TERM=dumb`, `LANG`/`LC_*` for Unicode).
public enum RenderOnce {
  /// Resolves / measures / places / draws / rasters the view tree once at the
  /// requested width, then emits the resulting cell buffer as ANSI-decorated
  /// text to stdout.
  ///
  /// - Parameters:
  ///   - view: The root view to render.
  ///   - width: Output width in cells. Defaults to the live terminal width,
  ///     then `$COLUMNS`, then 80.
  ///   - options: Parsed `SwiftTUIOptions` providing color/glyph/motion policy.
  ///     Defaults to a fresh options instance (auto-detected behavior).
  ///   - environment: Process environment. Defaults to the current process.
  ///   - isStdoutTTY: Whether stdout is a TTY. Defaults to live detection.
  @MainActor
  public static func print<V: View>(
    _ view: V,
    width: Int? = nil,
    options: SwiftTUIOptions? = nil,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    isStdoutTTY: Bool = standardOutputIsTTY()
  ) {
    let output = render(
      view,
      width: width,
      options: options,
      environment: environment,
      isStdoutTTY: isStdoutTTY
    )
    Swift.print(output)
  }

  /// Same as `print` but returns the rendered string instead of writing to
  /// stdout. Useful for tests and pipelines that consume the rendered output
  /// programmatically.
  @MainActor
  public static func render<V: View>(
    _ view: V,
    width: Int? = nil,
    options: SwiftTUIOptions? = nil,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    isStdoutTTY: Bool = standardOutputIsTTY()
  ) -> String {
    let resolvedWidth = width ?? resolveTerminalWidth(environment: environment)
    // ArgumentParser-managed properties (e.g. `@Flag verbose: Int`) aren't
    // initialized by the synthesized `init()`, so the blessed way to get a
    // defaults-only instance is `parse([])`. Fall through if even that fails.
    let resolvedOptions = options ?? (try? SwiftTUIOptions.parse([])) ?? SwiftTUIOptions()
    let configuration = resolvedOptions.runtimeConfiguration(
      environment: environment,
      isStdoutTTY: isStdoutTTY
    )
    let baseProfile = TerminalCapabilityProfile.detect(
      environment: environment,
      isTTY: isStdoutTTY
    )
    let profile = baseProfile.applying(configuration)

    let renderer = DefaultRenderer()
    let frame = renderer.render(
      view,
      proposal: .init(width: resolvedWidth, height: nil)
    )

    let surfaceRenderer = TerminalSurfaceRenderer(capabilityProfile: profile)
    let raw = surfaceRenderer.render(frame.rasterSurface)
    // TerminalSurfaceRenderer emits \r\n row separators for the interactive
    // path; non-interactive emission normalizes to \n so piping to files /
    // `less` / `tee` produces a single newline per row.
    return raw.replacingOccurrences(of: "\r\n", with: "\n")
  }

  // MARK: - Width detection

  /// Resolves the effective terminal width using TIOCGWINSZ, then `$COLUMNS`,
  /// then 80.
  public static func resolveTerminalWidth(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Int {
    if let width = ioctlTerminalWidth(), width > 0 {
      return width
    }
    if let columns = environment["COLUMNS"], let parsed = Int(columns), parsed > 0 {
      return parsed
    }
    return 80
  }

  // MARK: - TTY detection

  /// Whether stdout is connected to a terminal.
  public static func standardOutputIsTTY() -> Bool {
    #if canImport(WASILibc)
      return false
    #else
      return isatty(STDOUT_FILENO) != 0
    #endif
  }

  // MARK: - Private POSIX helpers

  private static func ioctlTerminalWidth() -> Int? {
    #if canImport(Darwin) || canImport(Glibc) || canImport(Android)
      var size = winsize()
      let result = unsafe withUnsafeMutablePointer(to: &size) { pointer in
        unsafe ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), pointer)
      }
      guard result == 0, size.ws_col > 0 else { return nil }
      return Int(size.ws_col)
    #else
      return nil
    #endif
  }
}
