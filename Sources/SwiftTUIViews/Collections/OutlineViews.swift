import SwiftTUICore

private enum OutlineStyleKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue = AnyOutlineStyle.automatic
}

extension EnvironmentValues {
  /// The outline style every ``OutlineGroup`` in this subtree resolves against.
  ///
  /// This is the environment slot `outlineStyle(_:)` writes, and the nearest
  /// write wins. It defaults to ``AnyOutlineStyle/automatic``, a fixed alias of
  /// ``AnyOutlineStyle/rounded``. Reading it is rarely necessary: an outline
  /// resolves its own style, and a custom style receives what it needs through
  /// ``OutlineStyleConfiguration``.
  ///
  /// This accessor is public while the other style families keep their slots
  /// package-visible, a difference recorded for the next minor release rather
  /// than a deliberate asymmetry.
  public var outlineStyle: AnyOutlineStyle {
    get { self[OutlineStyleKey.self] }
    set { self[OutlineStyleKey.self] = newValue }
  }
}

/// Presents hierarchical collection data as an outline.
public struct OutlineGroup<Data, ID, RowContent>: View
where Data: RandomAccessCollection, ID: Hashable & Sendable, RowContent: View {
  private let elements: [Data.Element]
  private let id: (Data.Element) -> ID
  private let children: (Data.Element) -> [Data.Element]
  private let rowContent: (Data.Element) -> RowContent
  private let authoringScope: AuthoringContext?

  public init(
    _ data: Data,
    id: KeyPath<Data.Element, ID>,
    children: KeyPath<Data.Element, [Data.Element]?>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  ) {
    elements = Array(data)
    self.id = { $0[keyPath: id] }
    self.children = { $0[keyPath: children] ?? [] }
    self.rowContent = rowContent
    authoringScope = currentAuthoringContext()
  }

  public init(
    _ data: Data,
    id: KeyPath<Data.Element, ID>,
    children: KeyPath<Data.Element, [Data.Element]>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  ) {
    elements = Array(data)
    self.id = { $0[keyPath: id] }
    self.children = { $0[keyPath: children] }
    self.rowContent = rowContent
    authoringScope = currentAuthoringContext()
  }

  public var body: some View {
    OutlineTree(
      elements: elements,
      id: id,
      children: children,
      rowContent: rowContent,
      authoringScope: authoringScope
    )
  }
}

extension List {
  public init<Data, RowContent: View>(
    _ data: Data,
    id: KeyPath<Data.Element, SelectionValue>,
    selection: Binding<SelectionValue>,
    children: KeyPath<Data.Element, [Data.Element]?>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  )
  where
    Data: RandomAccessCollection,
    Content == OutlineGroup<
      Data,
      SelectionValue,
      ModifiedContent<RowContent, TagValueModifier<SelectionValue>>
    >
  {
    self.init(
      selection: selection
    ) {
      OutlineGroup(data, id: id, children: children) { element in
        rowContent(element).modifier(
          TagValueModifier(
            tag: element[keyPath: id],
            includeOptional: true
          )
        )
      }
    }
  }

  public init<Data, RowContent: View>(
    _ data: Data,
    id: KeyPath<Data.Element, SelectionValue>,
    selection: Binding<SelectionValue>,
    children: KeyPath<Data.Element, [Data.Element]>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  )
  where
    Data: RandomAccessCollection,
    Content == OutlineGroup<
      Data,
      SelectionValue,
      ModifiedContent<RowContent, TagValueModifier<SelectionValue>>
    >
  {
    self.init(
      selection: selection
    ) {
      OutlineGroup(data, id: id, children: children) { element in
        rowContent(element).modifier(
          TagValueModifier(
            tag: element[keyPath: id],
            includeOptional: true
          )
        )
      }
    }
  }

  public init<Data, ID, RowContent: View>(
    _ data: Data,
    id: KeyPath<Data.Element, ID>,
    selection: Binding<ID?>,
    children: KeyPath<Data.Element, [Data.Element]?>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  )
  where
    Data: RandomAccessCollection, ID: Hashable & Sendable, SelectionValue == ID?,
    Content == OutlineGroup<
      Data,
      ID,
      ModifiedContent<RowContent, TagValueModifier<ID>>
    >
  {
    self.init(
      selection: selection
    ) {
      OutlineGroup(data, id: id, children: children) { element in
        rowContent(element).modifier(
          TagValueModifier(
            tag: element[keyPath: id],
            includeOptional: true
          )
        )
      }
    }
  }

  public init<Data, ID, RowContent: View>(
    _ data: Data,
    id: KeyPath<Data.Element, ID>,
    selection: Binding<ID?>,
    children: KeyPath<Data.Element, [Data.Element]>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  )
  where
    Data: RandomAccessCollection, ID: Hashable & Sendable, SelectionValue == ID?,
    Content == OutlineGroup<
      Data,
      ID,
      ModifiedContent<RowContent, TagValueModifier<ID>>
    >
  {
    self.init(
      selection: selection
    ) {
      OutlineGroup(data, id: id, children: children) { element in
        rowContent(element).modifier(
          TagValueModifier(
            tag: element[keyPath: id],
            includeOptional: true
          )
        )
      }
    }
  }
}

extension List {
  public init<Data, RowContent: View>(
    _ data: Data,
    selection: Binding<SelectionValue>,
    children: KeyPath<Data.Element, [Data.Element]?>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  )
  where
    Data: RandomAccessCollection, Data.Element: Identifiable,
    Data.Element.ID: Sendable,
    SelectionValue == Data.Element.ID,
    Content == OutlineGroup<
      Data,
      Data.Element.ID,
      ModifiedContent<RowContent, TagValueModifier<Data.Element.ID>>
    >
  {
    self.init(
      data,
      id: \.id,
      selection: selection,
      children: children,
      rowContent: rowContent
    )
  }

  public init<Data, RowContent: View>(
    _ data: Data,
    selection: Binding<SelectionValue>,
    children: KeyPath<Data.Element, [Data.Element]>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  )
  where
    Data: RandomAccessCollection, Data.Element: Identifiable,
    Data.Element.ID: Sendable,
    SelectionValue == Data.Element.ID,
    Content == OutlineGroup<
      Data,
      Data.Element.ID,
      ModifiedContent<RowContent, TagValueModifier<Data.Element.ID>>
    >
  {
    self.init(
      data,
      id: \.id,
      selection: selection,
      children: children,
      rowContent: rowContent
    )
  }

  public init<Data, RowContent: View>(
    _ data: Data,
    selection: Binding<SelectionValue>,
    children: KeyPath<Data.Element, [Data.Element]?>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  )
  where
    Data: RandomAccessCollection, Data.Element: Identifiable,
    Data.Element.ID: Sendable,
    SelectionValue == Data.Element.ID?,
    Content == OutlineGroup<
      Data,
      Data.Element.ID,
      ModifiedContent<RowContent, TagValueModifier<Data.Element.ID>>
    >
  {
    self.init(
      data,
      id: \.id,
      selection: selection,
      children: children,
      rowContent: rowContent
    )
  }

  public init<Data, RowContent: View>(
    _ data: Data,
    selection: Binding<SelectionValue>,
    children: KeyPath<Data.Element, [Data.Element]>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  )
  where
    Data: RandomAccessCollection, Data.Element: Identifiable,
    Data.Element.ID: Sendable,
    SelectionValue == Data.Element.ID?,
    Content == OutlineGroup<
      Data,
      Data.Element.ID,
      ModifiedContent<RowContent, TagValueModifier<Data.Element.ID>>
    >
  {
    self.init(
      data,
      id: \.id,
      selection: selection,
      children: children,
      rowContent: rowContent
    )
  }
}

extension OutlineGroup
where Data.Element: Identifiable, Data.Element.ID: Sendable, ID == Data.Element.ID {
  public init(
    _ data: Data,
    children: KeyPath<Data.Element, [Data.Element]?>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  ) {
    self.init(
      data,
      id: \.id,
      children: children,
      rowContent: rowContent
    )
  }

  public init(
    _ data: Data,
    children: KeyPath<Data.Element, [Data.Element]>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  ) {
    self.init(
      data,
      id: \.id,
      children: children,
      rowContent: rowContent
    )
  }
}

package struct OutlineTree<Element, ID, RowContent>: View
where ID: Hashable & Sendable, RowContent: View {
  package var elements: [Element]
  package var id: (Element) -> ID
  package var children: (Element) -> [Element]
  package var rowContent: (Element) -> RowContent
  package var authoringScope: AuthoringContext?
  package var ancestry: [Bool] = []

  public var body: some View {
    EnvironmentReader(\.outlineStyle) { outlineStyle in
      EnvironmentReader(\.styleEnvironmentSnapshot) { styleEnvironment in
        outlineLevelBody(
          presentation: outlineStyle.presentation(
            for: OutlineStyleConfiguration(styleEnvironment: styleEnvironment)
          )
        )
      }
    }
  }

  @ViewBuilder @MainActor
  private func outlineLevelBody(
    presentation: OutlineStylePresentation
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(entries) { entry in
        OutlineRow(
          prefix: outlinePrefix(
            ancestry: ancestry,
            isLast: entry.isLast,
            style: presentation
          ),
          content: rowView(for: entry.element),
          authoringScope: authoringScope
        )

        if !entry.children.isEmpty {
          OutlineTree(
            elements: entry.children,
            id: id,
            children: children,
            rowContent: rowContent,
            authoringScope: authoringScope,
            ancestry: ancestry + [!entry.isLast]
          )
        }
      }
    }
  }

  private func rowView(for element: Element) -> RowContent {
    withAuthoringContext(authoringScope) {
      rowContent(element)
    }
  }

  private var entries: [OutlineEntry<Element, ID>] {
    elements.enumerated().map { offset, element in
      OutlineEntry(
        id: id(element),
        element: element,
        children: children(element),
        isLast: offset == elements.count - 1
      )
    }
  }
}

private struct OutlineEntry<Element, ID: Hashable & Sendable>: Identifiable {
  let id: ID
  let element: Element
  let children: [Element]
  let isLast: Bool
}

private struct OutlineRow<Content: View>: PrimitiveView, IterativeResolvableView {
  let prefix: String
  let content: Content
  let authoringScope: AuthoringContext?

  @ViewBuilder
  private func rowBody(
    prefix renderedPrefix: String,
    spacing: Int
  ) -> some View {
    if renderedPrefix.isEmpty {
      ScopedOutlineRowContent(
        authoringScope: authoringScope,
        content: content
      )
    } else {
      HStack(alignment: .firstTextBaseline, spacing: spacing) {
        Text(renderedPrefix)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
          .foregroundStyle(.terminalBorder(.neutral))
        ScopedOutlineRowContent(
          authoringScope: authoringScope,
          content: content
        )
      }
    }
  }

  func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    let isHosted = context.environmentValues.isResolvingHostedCollectionContent
    let renderedPrefix =
      isHosted
      ? String(prefix.drop(while: \.isWhitespace))
      : prefix
    return resolveDeclaredChildrenWork(
      rowBody(prefix: renderedPrefix, spacing: isHosted ? 1 : 0),
      in: context.child(component: .named("Content")),
      kindName: "OutlineRow"
    ).map { children in
      return [
        ResolvedNode(
          identity: context.identity,
          kind: .view("OutlineRow"),
          children: children,
          environmentSnapshot: context.environment,
          transactionSnapshot: context.transaction,
          semanticMetadata: .init(isHostedCollectionRowBoundary: true)
        )
      ]
    }
  }
}

private struct ScopedOutlineRowContent<Content: View>: PrimitiveView, IterativeResolvableView {
  let authoringScope: AuthoringContext?
  let content: Content

  func makeResolveWork(
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    // Mint a per-row owner for the row content by routing through
    // `resolveView`, so each outline row's row-local `@State` binds to its own
    // node keyed on `context.identity` — already the per-row explicit-ID
    // identity carried down by `OutlineTree`'s `ForEach`. The generic
    // `content.resolveElements(in:)` path this replaced never called
    // `beginEvaluation`/`makeAuthoringContext`, so it re-used the single
    // `authoringScope` owner captured once at `OutlineGroup.init` for every
    // row, collapsing all rows' row-local state onto one shared slot.
    //
    // Captures of the ENCLOSING view's `@State` stay correct independently of
    // this per-row owner: control handlers dispatch under their
    // construction-time scope (`HandlerDescriptorIntake.preferringAuthoringScope`),
    // and the row content is still built under `authoringScope` in
    // `OutlineTree.rowView(for:)`, so a row button that mutates enclosing state
    // still routes to the enclosing owner.
    return withAuthoringContext(authoringScope) {
      resolveViewWork(content, in: context)
    }.map { resolved in
      // Splicing lifts the row content's children into the enclosing outline
      // container, so the group's own minted node — this row's `@State` owner —
      // lives in no children slot, and a dropped value's mint lives in none
      // either. Both are anchored at the nearest declaring host.
      return consumeDeclaredChild(
        resolved,
        resolvedUnder: context.identity,
        in: context.viewGraph,
        policy: .declaredBuilder
      )
    }
  }
}

private func outlinePrefix(
  ancestry: [Bool],
  isLast: Bool,
  style: OutlineStylePresentation
) -> String {
  guard !ancestry.isEmpty else {
    return ""
  }

  let ancestorPrefix = ancestry.map { showsContinuation in
    outlineIndenter(
      showsContinuation: showsContinuation,
      style: style
    )
  }
  .joined()
  return ancestorPrefix + outlineConnector(isLast: isLast, style: style)
}

private func outlineConnector(
  isLast: Bool,
  style: OutlineStylePresentation
) -> String {
  isLast ? style.leafConnector : style.branchConnector
}

private func outlineIndenter(
  showsContinuation: Bool,
  style: OutlineStylePresentation
) -> String {
  showsContinuation ? style.continuingIndenter : style.emptyIndenter
}
