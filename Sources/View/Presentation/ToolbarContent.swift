/// A declarative description of the items attached to a toolbar host.
///
/// `ToolbarContent` mirrors SwiftUI's protocol of the same name so
/// authored `.toolbar { … }` literals can stay body-driven and
/// declarative. Unlike SwiftUI, the framework deliberately does not
/// ship a `CustomizableToolbarContent` split — there is no user-facing
/// customization surface yet. See
/// ``docs/proposals/COMMAND_AND_CHROME_APIS.md`` §4.3 for the rationale.
@MainActor
public protocol ToolbarContent {
  associatedtype Body: ToolbarContent
  @ToolbarContentBuilder @MainActor
  var body: Body { get }
}

extension Never: ToolbarContent {
  // The `typealias Body = Never` that `View` already declares on
  // `Never` satisfies the `ToolbarContent.Body` associated type, so
  // no explicit typealias is needed here.
}

/// Builds strongly typed trees of toolbar content.
///
/// `ToolbarContentBuilder` mirrors SwiftUI's builder shape so authored
/// literals support a single item, variadic blocks, `if` / `else`
/// branches, and limited-availability wrappers.
@resultBuilder
@MainActor
public enum ToolbarContentBuilder {
  public static func buildBlock() -> EmptyToolbarContent {
    EmptyToolbarContent()
  }

  public static func buildBlock<C: ToolbarContent>(_ component: C) -> C {
    component
  }

  public static func buildBlock<each C: ToolbarContent>(
    _ components: repeat each C
  ) -> TupleToolbarContent<repeat each C> {
    TupleToolbarContent((repeat each components))
  }

  public static func buildExpression<C: ToolbarContent>(_ expression: C) -> C {
    expression
  }

  public static func buildExpression(_ expression: ()) -> EmptyToolbarContent {
    EmptyToolbarContent()
  }

  public static func buildIf<C: ToolbarContent>(
    _ component: C?
  ) -> OptionalToolbarContent<C> {
    OptionalToolbarContent(component)
  }

  public static func buildOptional<C: ToolbarContent>(
    _ component: C?
  ) -> OptionalToolbarContent<C> {
    OptionalToolbarContent(component)
  }

  public static func buildEither<T: ToolbarContent, F: ToolbarContent>(
    first: T
  ) -> ConditionalToolbarContent<T, F> {
    ConditionalToolbarContent(storage: .trueContent(first))
  }

  public static func buildEither<T: ToolbarContent, F: ToolbarContent>(
    second: F
  ) -> ConditionalToolbarContent<T, F> {
    ConditionalToolbarContent(storage: .falseContent(second))
  }

  public static func buildLimitedAvailability<C: ToolbarContent>(
    _ component: C
  ) -> C {
    component
  }
}

// MARK: - Primitive ToolbarContent shapes

/// The empty toolbar content, produced by a ``ToolbarContentBuilder``
/// literal with no items.
public struct EmptyToolbarContent: ToolbarContent {
  public typealias Body = Never

  public init() {}

  public var body: Never {
    fatalError("EmptyToolbarContent is a primitive builder artifact.")
  }
}

/// The builder artifact produced when a ``ToolbarContentBuilder``
/// contains multiple child expressions in sequence.
public struct TupleToolbarContent<each Contents: ToolbarContent>: ToolbarContent {
  public typealias Body = Never

  package let value: (repeat each Contents)

  package init(
    _ value: (repeat each Contents)
  ) {
    self.value = value
  }

  public var body: Never {
    fatalError("TupleToolbarContent is a primitive builder artifact.")
  }
}

/// The builder artifact produced by an `if` branch inside a
/// ``ToolbarContentBuilder`` without a matching `else`.
public struct OptionalToolbarContent<Wrapped: ToolbarContent>: ToolbarContent {
  public typealias Body = Never

  package let value: Wrapped?

  package init(_ value: Wrapped?) {
    self.value = value
  }

  public var body: Never {
    fatalError("OptionalToolbarContent is a primitive builder artifact.")
  }
}

/// The builder artifact produced by an `if` / `else` branch inside a
/// ``ToolbarContentBuilder``.
public struct ConditionalToolbarContent<
  TrueContent: ToolbarContent,
  FalseContent: ToolbarContent
>: ToolbarContent {
  public typealias Body = Never

  /// The currently active conditional branch.
  package enum Storage {
    case trueContent(TrueContent)
    case falseContent(FalseContent)
  }

  package let storage: Storage

  package init(storage: Storage) {
    self.storage = storage
  }

  public var body: Never {
    fatalError("ConditionalToolbarContent is a primitive builder artifact.")
  }
}
