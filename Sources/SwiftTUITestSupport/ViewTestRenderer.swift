public import SwiftTUIRuntime

/// Explicit inputs for a snapshot test, without exposing graph or phase state.
@_spi(Testing) public struct ViewTestContext {
  public var identity: Identity
  public var environmentValues: EnvironmentValues
  public var invalidatedIdentities: Set<Identity>

  public init(
    identity: Identity = Identity(components: ["ViewTest"]),
    environmentValues: EnvironmentValues = .init(),
    invalidatedIdentities: Set<Identity> = []
  ) {
    self.identity = identity
    self.environmentValues = environmentValues
    self.invalidatedIdentities = invalidatedIdentities
  }
}

/// Snapshot facade for external view-library tests. It renders synchronously on
/// the main actor; it does not start application tasks or dispatch user input.
@MainActor
@_spi(Testing) public final class ViewTestRenderer {
  private var renderer = DefaultRenderer()

  public init() {}

  /// Drops retained rendering state. Previously returned values remain owned by
  /// their caller and are valid after another render, reset, or renderer teardown.
  public func reset() { renderer = DefaultRenderer() }

  public func render<Content: View>(
    _ content: Content,
    context: ViewTestContext = .init(),
    proposal: ProposedSize = .unspecified,
    frameInstant: MonotonicInstant = .now()
  ) -> RenderSnapshot {
    let frame = renderer.render(
      content,
      context: .init(
        identity: context.identity,
        environmentValues: context.environmentValues,
        invalidatedIdentities: context.invalidatedIdentities
      ),
      proposal: proposal,
      frameInstant: frameInstant
    )
    // The public initializer deliberately does not retain the private phase trees.
    return RenderSnapshot(
      rasterSurface: frame.rasterSurface,
      semanticSnapshot: frame.semanticSnapshot,
      presentationDamage: frame.presentationDamage,
      diagnostics: frame.diagnostics
    )
  }
}
