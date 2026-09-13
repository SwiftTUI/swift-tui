#if DEBUG && (os(macOS) || os(Linux))
  public import SwiftTUIViews

  /// The retained root payload returned by an application's debug reload export.
  ///
  /// Use this only in `swifttui_hot_reload_root`, a C-callable application
  /// function driven by `swifttui-dev`. The loader consumes the retain after
  /// checking the image's scalar ABI and toolchain entries. Release builds and
  /// non-native hosts do not expose this development API.
  @MainActor
  public enum HotReloadExport {
    /// Creates the payload for one independently compiled root factory.
    ///
    /// Return the pointer directly from the C export. Do not release or retain
    /// it yourself; ownership transfers to the debug loader exactly once.
    public static func retainedRoot<Content: View>(
      @ViewBuilder _ content: @escaping @MainActor () -> Content
    ) -> UnsafeMutableRawPointer {
      unsafe Unmanaged.passRetained(HotReloadGeneration(content: content)).toOpaque()
    }
  }

#endif

package enum HotReloadABI {
  // Available to a release-built driver, whose child is always a debug build.
  // Update whenever the private payload/runtime contract changes. The driver
  // emits a literal scalar export, never a call into the host framework.
  package static let version: UInt64 = 0x5354_5549_524C_0001
  package static let maximumImages = 100
}
