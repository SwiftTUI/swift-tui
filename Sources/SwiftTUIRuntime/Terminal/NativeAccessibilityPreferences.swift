import SwiftTUICore

#if os(macOS) && canImport(AppKit)
  import AppKit
#endif

/// Local terminal sessions can use the desktop user's display preferences.
/// Remote terminals inherit their client's choices through explicit options;
/// the server's desktop preferences do not describe that client.
@MainActor
package func nativeAccessibilityPreferences(
  for surface: any PresentationSurfaceMetricsProvider
) -> AccessibilityPreferences {
  #if os(macOS) && canImport(AppKit)
    guard isLocalTerminalPreferenceSource(surface) else { return .init() }
    let workspace = NSWorkspace.shared
    return .init(
      reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
      contrast: workspace.accessibilityDisplayShouldIncreaseContrast ? .increased : .standard,
      differentiateWithoutColor: workspace.accessibilityDisplayShouldDifferentiateWithoutColor,
      reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency)
  #else
    return .init()
  #endif
}

@MainActor
package func isLocalTerminalPreferenceSource(
  _ surface: any PresentationSurfaceMetricsProvider
) -> Bool {
  #if !canImport(WASILibc)
    guard let terminal = surface as? TerminalHost, terminal.usesNativeAccessibilityPreferences
    else { return false }
    return terminal.controller.isATTY(terminal.outputFileDescriptor)
      && terminal.environment["SSH_CONNECTION"] == nil
      && terminal.environment["SSH_CLIENT"] == nil
      && terminal.environment["REMOTEHOST"] == nil
  #else
    return false
  #endif
}

/// The runtime owns observation, so an idle terminal refreshes when preferences
/// change and releases the observer with its session. No app plumbing is needed.
@MainActor
package final class NativeAccessibilityPreferenceObserver {
  #if os(macOS) && canImport(AppKit)
    private var token: (any NSObjectProtocol)?
    private let center: NotificationCenter

    init?(
      surface: any PresentationSurfaceMetricsProvider,
      notificationCenter: NotificationCenter? = nil,
      changed: @escaping @MainActor @Sendable () -> Void
    ) {
      guard isLocalTerminalPreferenceSource(surface) else { return nil }
      center = notificationCenter ?? NSWorkspace.shared.notificationCenter
      token = center.addObserver(
        forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
        object: nil, queue: .main
      ) { _ in
        Task { @MainActor in changed() }
      }
    }

    isolated deinit {
      if let token { center.removeObserver(token) }
    }
  #else
    init?(
      surface: any PresentationSurfaceMetricsProvider,
      changed: @escaping @MainActor @Sendable () -> Void
    ) { return nil }
  #endif
}
