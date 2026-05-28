package import SwiftTUIRuntime

/// Scene wrapper that activates profiling when the runtime traverses its
/// `body` during scene setup — which happens before the first session is
/// built, satisfying the activation-ordering requirement. Activation is
/// idempotent, so repeated `body` access is safe.
@MainActor
package struct ProfilingScene<Wrapped: Scene>: Scene {
  package typealias Body = Wrapped

  private let wrapped: Wrapped
  private let config: ProfileConfig?

  init(wrapped: Wrapped, config: ProfileConfig?) {
    self.wrapped = wrapped
    self.config = config
  }

  package var body: Wrapped {
    ProfileActivation.shared.activateIfNeeded(config: config)
    return wrapped
  }
}

extension Scene {
  /// Enables env-gated profiling for this scene tree.
  ///
  /// With no argument it reads `SWIFTTUI_PROFILE`; if unset it is a complete
  /// no-op (no sinks, no timers, the runtime registry stays empty). Pass an
  /// explicit ``ProfileConfig`` to activate regardless of the environment.
  package func profiling(_ config: ProfileConfig? = nil) -> ProfilingScene<Self> {
    ProfilingScene(wrapped: self, config: config)
  }
}
