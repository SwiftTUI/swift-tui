package import Core

/// The builder artifact produced by conditional branches inside a
/// ``ViewBuilder``.
public struct ConditionalContent<TrueContent: View, FalseContent: View>: View,
  ResolvableView, DeclaredChildrenView
{
  /// The currently active conditional branch.
  public enum Storage {
    case trueContent(TrueContent)
    case falseContent(FalseContent)
  }

  package let storage: Storage
  package let collapsesImplicitEmptyFalseBranch: Bool

  package init(
    storage: Storage,
    collapsesImplicitEmptyFalseBranch: Bool
  ) {
    self.storage = storage
    self.collapsesImplicitEmptyFalseBranch = collapsesImplicitEmptyFalseBranch
  }

  public var body: Never {
    fatalError("ConditionalContent is a builder composition artifact.")
  }

  package func appendDeclaredChildren(
    in context: ResolveContext,
    kindName: String,
    nextIndex: inout Int,
    into resolved: inout [ResolvedNode]
  ) {
    switch storage {
    case .trueContent(let content):
      appendDeclaredChildNodes(
        content,
        in: context,
        kindName: kindName,
        nextIndex: &nextIndex,
        into: &resolved
      )
    case .falseContent(let content):
      if collapsesImplicitEmptyFalseBranch, content is EmptyView {
        return
      }
      appendDeclaredChildNodes(
        content,
        in: context,
        kindName: kindName,
        nextIndex: &nextIndex,
        into: &resolved
      )
    }
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    switch storage {
    case .trueContent(let content):
      return resolveViewElements(content, in: context)
    case .falseContent(let content):
      if collapsesImplicitEmptyFalseBranch, content is EmptyView {
        return []
      }
      return resolveViewElements(content, in: context)
    }
  }

  package func appendErasedDeclaredChildren(
    into children: inout [AnyView]
  ) {
    switch storage {
    case .trueContent(let content):
      appendErasedDeclaredBuilderChildren(
        from: content,
        into: &children
      )
    case .falseContent(let content):
      if collapsesImplicitEmptyFalseBranch, content is EmptyView {
        return
      }
      appendErasedDeclaredBuilderChildren(
        from: content,
        into: &children
      )
    }
  }
}
