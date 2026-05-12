import SwiftTUI

/// Helper that wraps `RenderOnce.print` with the gitviz options resolution.
///
/// Marked `@MainActor` to match the underlying renderer; every subcommand's
/// `run()` is also `@MainActor` so the SwiftUI ViewBuilder + render call
/// happens inline without main-actor hops.
enum GitVizRunOnce {
  @MainActor
  static func print<V: View>(
    _ view: V,
    opts: GitVizOptions
  ) {
    RenderOnce.print(
      view,
      width: opts.width,
      options: opts.swiftTUIOptions
    )
  }
}
