@_spi(Testing) public import SwiftTUICore

/// Displays a string of terminal text.
public struct Text: PrimitiveView, ResolvableView {
  package enum Storage: Equatable, Sendable {
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
  /// True after an explicit `.underline(false)` on this text value. A `nil`
  /// `underlineStyle` alone cannot distinguish "never styled" (inherit the
  /// ambient underline) from "explicitly cleared" (suppress it) — and the
  /// explicit clear must win over the environment, matching SwiftUI.
  package var underlineExplicitlyCleared = false
  /// The strikethrough counterpart of ``underlineExplicitlyCleared``.
  package var strikethroughExplicitlyCleared = false

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

  /// Creates text that displays the supplied string literally.
  ///
  /// SwiftTUI does not reinterpret this initializer as a localization-key
  /// lookup. Any future localization API will use an explicit additive
  /// spelling.
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

  /// Creates text that displays the given string with no localization.
  ///
  /// This is an explicit alias of
  /// ``init(_:semanticMetadata:)-(String,_)``; both initializers permanently
  /// display their string argument literally.
  public init(verbatim content: String) {
    self.init(content)
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
    // Ambient decorations stamp only where this text's own value styling is
    // unset — node-over-environment precedence, with an explicit
    // `.underline(false)`/`.strikethrough(false)` clear winning over the
    // inherited style.
    var stampedDrawMetadata = drawMetadata
    let decorations = ambientTextDecorations(in: context)
    if stampedDrawMetadata.underlineStyle == nil, !underlineExplicitlyCleared {
      stampedDrawMetadata.underlineStyle = decorations.underline
    }
    if stampedDrawMetadata.strikethroughStyle == nil, !strikethroughExplicitlyCleared {
      stampedDrawMetadata.strikethroughStyle = decorations.strikethrough
    }
    // A plain string with a non-identity content transition records it on
    // the node: the animation controller reads the stamp to start a roll,
    // and the frame tail cannot read the environment. Rich content keeps
    // its per-run styling and cuts.
    if case .plain = storage, let contentTransition = ambientContentTransition(in: context) {
      stampedDrawMetadata.contentTransition = contentTransition
    }
    let node = ResolvedNode(
      identity: context.identity,
      kind: .view("Text"),
      typeDiscriminator: ObjectIdentifier(Text.self),
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      layoutMetadata: ambientTextLayoutMetadata(in: context),
      drawMetadata: stampedDrawMetadata,
      semanticMetadata: semanticMetadata,
      drawPayload: drawPayload
    )
    return [
      node
    ]
  }
}

// `Hashable` is deliberately omitted: it would require hashing the full
// draw/semantic metadata payloads, which are `Equatable`-only today.
extension Text: Equatable, Sendable {}

extension Text {
  /// Alias for the supported text truncation modes.
  public typealias TruncationMode = TextTruncationMode
  /// Alias for the supported text wrapping strategies.
  public typealias WrappingStrategy = TextWrappingStrategy

  public struct RichContent: ExpressibleByStringInterpolation, ExpressibleByStringLiteral,
    Equatable, Sendable
  {
    package indirect enum Fragment: Equatable, Sendable {
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
public struct Spacer: PrimitiveView, ResolvableView {
  public var minLength: Int

  public init(minLength: Int = 0) {
    self.minLength = minLength
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let intrinsicSize =
      switch context.environmentValues.stackAxis {
      case .horizontal:
        CellSize(width: minLength, height: 0)
      case .vertical:
        CellSize(width: 0, height: minLength)
      case nil:
        CellSize(width: minLength, height: minLength)
      }
    // Record the enclosing stack's axis for the same reason `Divider` does: a
    // Spacer absorbs unbounded space only along its *own* stack's axis. Without
    // this the maximum-size traversal reports the subtree as unbounded on both
    // axes, so an `HStack { Text; Spacer() }` status bar competes with its
    // siblings for the VStack's height.
    var resolvedDrawMetadata = DrawMetadata()
    resolvedDrawMetadata.leafStackAxis = context.environmentValues.stackAxis
    return [
      resolveLeafNode(
        kindName: "Spacer",
        intrinsicSize: intrinsicSize,
        drawMetadata: resolvedDrawMetadata,
        in: context
      )
    ]
  }
}

/// A one-cell single-line rule that adapts to its surrounding layout direction.
public struct Divider: PrimitiveView, ResolvableView {
  public var strokeStyle: StrokeStyle

  public init(strokeStyle: StrokeStyle = .single) {
    self.strokeStyle = strokeStyle
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var resolvedDrawMetadata = DrawMetadata()
    resolvedDrawMetadata.leafStackAxis = context.environmentValues.stackAxis
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
