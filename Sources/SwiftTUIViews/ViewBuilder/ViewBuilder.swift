@resultBuilder
/// Builds strongly typed trees of terminal views.
///
/// `ViewBuilder` mirrors SwiftUI's builder shape closely so authored APIs can
/// stay body-driven and declarative.
@MainActor
public enum ViewBuilder {
  public static func buildBlock() -> EmptyView {
    EmptyView()
  }

  public static func buildExpression<V: View>(_ expression: V) -> V {
    expression
  }

  public static func buildExpression(_ expression: ()) -> EmptyView {
    EmptyView()
  }

  public static func buildBlock<V: View>(_ view: V) -> V {
    view
  }

  public static func buildBlock<each V: View>(
    _ views: repeat each V
  ) -> TupleView<repeat each V> {
    TupleView((repeat each views))
  }

  public static func buildOptional<Content: View>(
    _ component: Content?
  ) -> ConditionalContent<Content, EmptyView> {
    if let component {
      return ConditionalContent(
        storage: .trueContent(component),
        collapsesImplicitEmptyFalseBranch: true
      )
    }
    return ConditionalContent(
      storage: .falseContent(EmptyView()),
      collapsesImplicitEmptyFalseBranch: true
    )
  }

  public static func buildEither<TrueContent: View, FalseContent: View>(
    first component: TrueContent
  ) -> ConditionalContent<TrueContent, FalseContent> {
    ConditionalContent(
      storage: .trueContent(component),
      collapsesImplicitEmptyFalseBranch: false
    )
  }

  public static func buildEither<TrueContent: View, FalseContent: View>(
    second component: FalseContent
  ) -> ConditionalContent<TrueContent, FalseContent> {
    ConditionalContent(
      storage: .falseContent(component),
      collapsesImplicitEmptyFalseBranch: false
    )
  }

  public static func buildArray<Content: View>(
    _ components: [Content]
  ) -> VariadicView<Content> {
    VariadicView(components)
  }

  public static func buildLimitedAvailability<Content: View>(
    _ component: Content
  ) -> AnyView {
    scopedAnyView {
      component
    }
  }
}
