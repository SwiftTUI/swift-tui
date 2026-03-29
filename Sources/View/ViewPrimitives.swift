import Core

/// A view with no rendered content.
public struct EmptyView: View, ResolvableView {
  public init() {}

  package func resolveElements(in _: ResolveContext) -> [ResolvedNode] {
    []
  }
}

/// Displays a string of terminal text.
public struct Text: View, ResolvableView {
  public var content: String
  public var drawMetadata: DrawMetadata
  public var semanticMetadata: SemanticMetadata

  public init(
    _ content: String,
    drawMetadata: DrawMetadata = .init(),
    semanticMetadata: SemanticMetadata = .init()
  ) {
    self.content = content
    self.drawMetadata = drawMetadata
    self.semanticMetadata = semanticMetadata
  }

  @inline(never)
  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let node = ResolvedNode(
      identity: context.identity,
      kind: .view("Text"),
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      layoutMetadata: .init(),
      drawMetadata: drawMetadata,
      semanticMetadata: semanticMetadata,
      drawPayload: .text(content)
    )
    return [
      node
    ]
  }
}

extension Text {
  /// Alias for the supported text truncation modes.
  public typealias TruncationMode = TextTruncationMode
  /// Alias for the supported text wrapping strategies.
  public typealias WrappingStrategy = TextWrappingStrategy
}

/// A flexible empty region that expands to absorb extra space.
public struct Spacer: View, ResolvableView {
  public var minLength: Int

  public init(minLength: Int = 0) {
    self.minLength = minLength
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [
      parallelResolveLeaf(
        kindName: "Spacer",
        intrinsicSize: .init(width: minLength, height: minLength),
        in: context
      )
    ]
  }
}

/// A one-cell rule that adapts to its surrounding layout direction.
public struct Divider: View, ResolvableView {
  public var drawMetadata: DrawMetadata

  public init(drawMetadata: DrawMetadata = .init()) {
    self.drawMetadata = drawMetadata
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [
      parallelResolveLeaf(
        kindName: "Divider",
        intrinsicSize: .init(width: 1, height: 1),
        drawMetadata: drawMetadata,
        drawPayload: .rule(nil),
        in: context
      )
    ]
  }
}

private func idealTextSize(for content: String) -> Size {
  parallelTextLayout(for: content, width: Optional<Int>.none).size
}
func parallelResolveLeaf(
  kindName: String,
  intrinsicSize: Size? = nil,
  layoutBehavior: LayoutBehavior = .intrinsic,
  layoutMetadata: LayoutMetadata = .init(),
  drawMetadata: DrawMetadata = .init(),
  semanticMetadata: SemanticMetadata = .init(),
  drawPayload: DrawPayload = .none,
  in context: ResolveContext
) -> ResolvedNode {
  if let reused = context.reusedResolvedSubtreeIfAvailable() {
    return reused
  }
  context.recordResolvedComputation()
  return ResolvedNode(
    identity: context.identity,
    kind: .view(kindName),
    environmentSnapshot: context.environment,
    transactionSnapshot: context.transaction,
    layoutBehavior: layoutBehavior,
    layoutMetadata: layoutMetadata,
    drawMetadata: drawMetadata,
    semanticMetadata: semanticMetadata,
    drawPayload: drawPayload,
    intrinsicSize: intrinsicSize
  )
}
