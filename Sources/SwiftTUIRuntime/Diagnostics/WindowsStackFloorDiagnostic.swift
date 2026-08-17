import SwiftTUICore

/// The Windows main-thread stack-floor diagnostic (Windows plan, Stage 6
/// item 9).
///
/// Windows executables reserve 1 MiB of main-thread stack from the PE header
/// unless the link sets `/STACK`; POSIX main threads get 8 MiB. The resolve
/// descent is budgeted against the POSIX floor, so a default-link Windows
/// debug build dies at launch with `STATUS_STACK_OVERFLOW` (`0xC00000FD`)
/// unless the engine degrades. `stackLeanResolveProfile` arms automatically
/// when the measured reserve is below ``fullEngineStackReserveFloor``; this
/// type owns the loud debug-build warning that names the remedy, so the
/// degradation is never silent for the developers it protects.
package enum WindowsStackFloorDiagnostic {
  /// Non-nil when a below-floor Windows main-thread stack reserve degraded
  /// this debug session to the stack-lean engine profile. Release builds and
  /// explicit `SWIFTTUI_STACK_LEAN_PROFILE` choices stay silent.
  @MainActor
  package static func sessionIssue() -> RuntimeIssue? {
    #if DEBUG && os(Windows)
      guard stackLeanArmedByWindowsStackFloor else { return nil }
      return RuntimeIssue(
        severity: .warning,
        code: "windows.stack-floor-lean-profile",
        message: message(
          reserveBytes: windowsMainThreadStackReserve(),
          floorBytes: fullEngineStackReserveFloor
        )
      )
    #else
      return nil
    #endif
  }

  /// The warning text, split out so its wording — especially the remedy —
  /// is pinned by tests on every platform.
  package static func message(reserveBytes: Int, floorBytes: Int) -> String {
    "the main-thread stack reserve (\(reserveBytes >> 20) MiB) is below the "
      + "\(floorBytes >> 20) MiB full-engine floor, so this debug session runs "
      + "the degraded stack-lean engine profile. Link a larger reserve to run "
      + "the full engine: swift build -Xlinker /STACK:16777216 — or add "
      + "linkerSettings: [.unsafeFlags([\"-Xlinker\", \"/STACK:16777216\"], "
      + ".when(platforms: [.windows]))] to the app's root-package executable "
      + "target."
  }
}
