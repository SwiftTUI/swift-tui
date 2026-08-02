public import SwiftTUIRuntime

/// A scene wrapper that activates profiling when the runtime traverses its `body` during scene setup.
/// This traversal occurs before the runtime builds the first session.
/// Thus, it obeys the activation-order requirement. Activation is
/// idempotent, so repeated `body` access is safe.
@MainActor
public struct ProfilingScene<Wrapped: Scene>: Scene {
  public typealias Body = Wrapped

  private let wrapped: Wrapped
  private let config: ProfileConfig?

  init(wrapped: Wrapped, config: ProfileConfig?) {
    self.wrapped = wrapped
    self.config = config
  }

  public var body: Wrapped {
    ProfileActivation.shared.activateIfNeeded(config: config)
    return wrapped
  }
}

extension Scene {
  /// Enables env-gated profiling for this scene tree.
  ///
  /// With no argument, it reads `SWIFTTUI_PROFILE`.
  /// If the variable is not set, the modifier adds no sinks or timers, and the runtime registry stays empty.
  /// Pass an
  /// explicit ``ProfileConfig`` to activate regardless of the environment.
  public func profiling(_ config: ProfileConfig? = nil) -> ProfilingScene<Self> {
    ProfilingScene(wrapped: self, config: config)
  }
}
