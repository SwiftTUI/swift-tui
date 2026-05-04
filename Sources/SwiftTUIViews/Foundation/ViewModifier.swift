public import SwiftTUICore

@MainActor
public protocol ViewModifier {
  associatedtype Body: View = Never
  typealias Content = ViewModifierContent<Self>

  @ViewBuilder
  func body(content: Content) -> Body
}

extension ViewModifier where Body == Never {
  public func body(content _: Content) -> Never {
    fatalError("\(Self.self) is a primitive modifier and does not expose a composed body.")
  }
}

@MainActor
package struct ModifierContentInputs<Base: View> {
  package let base: Base
  package let authoringContext: AuthoringContext?

  private func applyAuthoringContext<Result>(
    _ body: () -> Result
  ) -> Result {
    withAuthoringContext(authoringContext) {
      body()
    }
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    applyAuthoringContext {
      let erased: Any = base
      if let resolvable = erased as? any ResolvableView {
        return resolvable.resolveElements(in: context)
      }
      return resolveViewElements(base, in: context)
    }
  }

  package func resolve(in context: ResolveContext) -> ResolvedNode {
    applyAuthoringContext {
      resolveView(base, in: context)
    }
  }
}

@MainActor
package protocol PrimitiveViewModifier: ViewModifier where Body == Never {
  func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode]
}

public struct ViewModifierContent<Modifier: ViewModifier>: View, ResolvableView {
  private let resolveElementsClosure: @MainActor (ResolveContext) -> [ResolvedNode]

  package init<Base: View>(
    base: Base,
    authoringContext: AuthoringContext?
  ) {
    let inputs = ModifierContentInputs(
      base: base,
      authoringContext: authoringContext
    )
    resolveElementsClosure = { context in
      inputs.resolveElements(in: context)
    }
  }

  public var body: Never {
    fatalError("ViewModifier.Content is an opaque modifier-content carrier.")
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    resolveElementsClosure(context)
  }
}

public struct ModifiedContent<Content, Modifier> {
  public var content: Content
  public var modifier: Modifier
  package var authoringContext: AuthoringContext?

  @MainActor
  public init(content: Content, modifier: Modifier) {
    self.content = content
    self.modifier = modifier
    authoringContext = makeDeferredAuthoringContext()
  }
}

extension ModifiedContent: View where Content: View, Modifier: ViewModifier {
  public var body: some View {
    modifier.body(
      content: ViewModifierContent(
        base: content,
        authoringContext: authoringContext
      )
    )
  }
}

extension ModifiedContent: ViewModifier where Content: ViewModifier, Modifier: ViewModifier {
  public func body(content: ViewModifierContent<Self>) -> some View {
    content
      .modifier(self.content)
      .modifier(modifier)
  }
}

extension ModifiedContent: ResolvableView where Content: View, Modifier: PrimitiveViewModifier {
  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let authoringContext = dynamicPropertyAuthoringContext(for: context)
    let inputs = ModifierContentInputs(
      base: content,
      authoringContext: self.authoringContext
    )
    return withAuthoringContext(authoringContext) {
      modifier.resolve(content: inputs, in: context)
    }
  }
}

extension ModifiedContent: Sendable where Content: Sendable, Modifier: Sendable {}

extension ModifiedContent: Identifiable where Content: Identifiable {
  public typealias ID = Content.ID

  public var id: Content.ID {
    content.id
  }
}

extension ModifiedContent: ActionScope where Content: ActionScope {}

extension ModifiedContent: Equatable where Content: Equatable, Modifier: Equatable {
  public static func == (
    lhs: ModifiedContent<Content, Modifier>,
    rhs: ModifiedContent<Content, Modifier>
  ) -> Bool {
    lhs.content == rhs.content
      && lhs.modifier == rhs.modifier
  }
}

extension ModifiedContent: Animatable where Content: Animatable, Modifier: Animatable {
  public typealias AnimatableData = AnimatablePair<Content.AnimatableData, Modifier.AnimatableData>

  public var animatableData: AnimatableData {
    get {
      .init(content.animatableData, modifier.animatableData)
    }
    set {
      content.animatableData = newValue.first
      modifier.animatableData = newValue.second
    }
  }
}

extension View {
  public func modifier<M: ViewModifier>(
    _ modifier: M
  ) -> ModifiedContent<Self, M> {
    ModifiedContent(
      content: self,
      modifier: modifier
    )
  }
}

extension ViewModifier {
  public func concat<M: ViewModifier>(
    _ modifier: M
  ) -> ModifiedContent<Self, M> {
    ModifiedContent(
      content: self,
      modifier: modifier
    )
  }
}
