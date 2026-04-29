@_spi(Testing) public import Core

/// Displays a string of terminal text.
public struct Text: View, ResolvableView {
  package enum Storage {
    case plain(String)
    case rich(RichContent)
  }

  package var storage: Storage
  package var drawMetadata: DrawMetadata {
    get { _boxedDrawMetadata.value }
    set { _boxedDrawMetadata.value = newValue }
  }
  package var _boxedDrawMetadata: Boxed<DrawMetadata>
  public var semanticMetadata: SemanticMetadata

  public var content: String {
    switch storage {
    case .plain(let content):
      content
    case .rich(let content):
      content.visibleText
    }
  }

  // Public surface deliberately omits `drawMetadata` — visual styling is
  // applied through view modifiers (`.foregroundStyle(_:)`, `.bold()`,
  // `.italic()`, `.underline()`, `.opacity(_:)`, etc.) so that styling
  // composes through the environment the way SwiftUI canonically does it,
  // rather than being passed as an opaque metadata bag at construction.
  // See `Sources/View/Primitives/TextStyles.swift` for the modifier set.

  @_disfavoredOverload
  public init(
    _ content: String,
    semanticMetadata: SemanticMetadata = SemanticMetadata()
  ) {
    self.init(
      content,
      drawMetadata: DrawMetadata(),
      semanticMetadata: semanticMetadata
    )
  }

  public init(
    _ content: RichContent,
    semanticMetadata: SemanticMetadata = SemanticMetadata()
  ) {
    self.init(
      content,
      drawMetadata: DrawMetadata(),
      semanticMetadata: semanticMetadata
    )
  }

  @_disfavoredOverload
  package init(
    _ content: String,
    drawMetadata: DrawMetadata = DrawMetadata(),
    semanticMetadata: SemanticMetadata = SemanticMetadata()
  ) {
    storage = .plain(content)
    self._boxedDrawMetadata = Boxed(drawMetadata)
    self.semanticMetadata = semanticMetadata
  }

  package init(
    _ content: RichContent,
    drawMetadata: DrawMetadata = DrawMetadata(),
    semanticMetadata: SemanticMetadata = SemanticMetadata()
  ) {
    if let plainText = content.plainText {
      storage = .plain(plainText)
    } else {
      storage = .rich(content)
    }
    self._boxedDrawMetadata = Boxed(drawMetadata)
    self.semanticMetadata = semanticMetadata
  }

  @inline(never)
  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let drawPayload: DrawPayload =
      switch storage {
      case .plain(let content):
        .text(content)
      case .rich:
        .richText(
          resolvedRichTextPayload(
            for: self,
            in: context
          )
        )
      }
    let node = ResolvedNode(
      identity: context.identity,
      kind: .view("Text"),
      typeDiscriminator: ObjectIdentifier(Text.self),
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      layoutMetadata: .init(),
      drawMetadata: drawMetadata,
      semanticMetadata: semanticMetadata,
      drawPayload: drawPayload
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

  public struct RichContent: ExpressibleByStringInterpolation, ExpressibleByStringLiteral {
    package indirect enum Fragment {
      case literal(String)
      case text(Text)
      case link(Link)
    }

    package var fragments: [Fragment]

    public init(
      stringLiteral value: String
    ) {
      fragments = [.literal(value)]
    }

    public init(
      stringInterpolation: StringInterpolation
    ) {
      fragments = stringInterpolation.finalizedFragments()
    }

    package var plainText: String? {
      guard fragments.count == 1 else {
        return nil
      }
      guard case .literal(let literal) = fragments[0] else {
        return nil
      }
      return literal
    }

    @MainActor
    package var visibleText: String {
      fragments.map {
        switch $0 {
        case .literal(let literal):
          literal
        case .text(let text):
          text.content
        case .link(let link):
          link.label.content
        }
      }.joined()
    }
  }

  public struct StringInterpolation: StringInterpolationProtocol {
    package var fragments: [RichContent.Fragment] = []
    package var bufferedLiteral = ""

    public init(
      literalCapacity _: Int,
      interpolationCount _: Int
    ) {}

    public mutating func appendLiteral(
      _ literal: String
    ) {
      bufferedLiteral += literal
    }

    public mutating func appendInterpolation(
      _ text: Text
    ) {
      flushBufferedLiteral()
      fragments.append(.text(text))
    }

    public mutating func appendInterpolation(
      _ link: Link
    ) {
      flushBufferedLiteral()
      fragments.append(.link(link))
    }

    public mutating func appendInterpolation(
      _ value: some StringProtocol
    ) {
      bufferedLiteral += String(value)
    }

    public mutating func appendInterpolation<T>(
      _ value: T
    ) where T: CustomStringConvertible {
      bufferedLiteral += value.description
    }

    public mutating func appendInterpolation<T>(
      _ value: T?
    ) where T: CustomStringConvertible {
      bufferedLiteral += value.map(\.description) ?? ""
    }

    package mutating func flushBufferedLiteral() {
      guard !bufferedLiteral.isEmpty else {
        return
      }
      fragments.append(.literal(bufferedLiteral))
      bufferedLiteral = ""
    }

    package func finalizedFragments() -> [RichContent.Fragment] {
      var copy = self
      copy.flushBufferedLiteral()
      return copy.fragments
    }
  }
}

/// A flexible empty region that expands to absorb extra space.
public struct Spacer: View, ResolvableView {
  public var minLength: Int

  public init(minLength: Int = 0) {
    self.minLength = minLength
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [
      resolveLeafNode(
        kindName: "Spacer",
        intrinsicSize: .init(width: minLength, height: minLength),
        in: context
      )
    ]
  }
}

/// A one-cell rule that adapts to its surrounding layout direction.
public struct Divider: View, ResolvableView {
  public var strokeStyle: StrokeStyle

  public init(strokeStyle: StrokeStyle = .init()) {
    self.strokeStyle = strokeStyle
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var resolvedDrawMetadata = DrawMetadata()
    resolvedDrawMetadata.ruleStackAxis = context.environmentValues.stackAxis
    return [
      resolveLeafNode(
        kindName: "Divider",
        intrinsicSize: .init(width: 1, height: 1),
        drawMetadata: resolvedDrawMetadata,
        drawPayload: .rule(strokeStyle),
        in: context
      )
    ]
  }
}

private func idealTextSize(for content: String) -> CellSize {
  layoutText(for: content, width: Optional<Int>.none).size
}
@MainActor
func resolveLeafNode(
  kindName: String,
  intrinsicSize: CellSize? = nil,
  layoutBehavior: LayoutBehavior = .intrinsic,
  layoutMetadata: LayoutMetadata = .init(),
  drawMetadata: DrawMetadata = DrawMetadata(),
  semanticMetadata: SemanticMetadata = SemanticMetadata(),
  drawPayload: DrawPayload = .none,
  in context: ResolveContext
) -> ResolvedNode {
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
