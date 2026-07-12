import SwiftTUICore

private enum OutlineStyleKey: EnvironmentKey {
  static let defaultValue = AnyOutlineStyle.automatic
}

extension EnvironmentValues {
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

extension List where SelectionValue: Hashable & Sendable {
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
      VStack(alignment: .leading, spacing: 0) {
        ForEach(entries) { entry in
          OutlineRow(
            prefix: outlinePrefix(
              ancestry: ancestry,
              isLast: entry.isLast,
              style: outlineStyle
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

private struct OutlineRow<Content: View>: View {
  let prefix: String
  let content: Content
  let authoringScope: AuthoringContext?

  @ViewBuilder
  var body: some View {
    if prefix.isEmpty {
      ScopedOutlineRowContent(
        authoringScope: authoringScope,
        content: content
      )
    } else {
      HStack(alignment: .firstTextBaseline, spacing: 0) {
        Text(prefix)
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
}

private struct ScopedOutlineRowContent<Content: View>: PrimitiveView, ResolvableView {
  let authoringScope: AuthoringContext?
  let content: Content

  func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
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
    let resolved = withAuthoringContext(authoringScope) {
      resolveView(content, in: context)
    }
    if resolved.identity == context.identity,
      resolved.kind == .view("EmptyView")
    {
      // A dropped value still minted a stored node that lives in no children
      // array; anchor it to the resolving host so an enclosing teardown can
      // reclaim it (mirrors `appendDeclaredChildNodes`' EmptyView arm).
      context.viewGraph?.recordDetachedHostedSubtree(
        resolved,
        hostedBy: ViewNodeContext.current
      )
      return []
    }
    if resolved.identity == context.identity,
      resolved.kind == .view("Group")
    {
      // Splicing lifts the row content's children into the enclosing outline
      // container, so the group's own minted node — this row's `@State` owner
      // — lives in no children slot. Anchor it before splicing so teardown
      // reaches it (mirrors `ForEach`'s element-Group arm).
      context.viewGraph?.recordDetachedHostedSubtree(
        resolved,
        hostedBy: ViewNodeContext.current
      )
      return resolved.children
    }
    return [resolved]
  }
}

private func outlinePrefix(
  ancestry: [Bool],
  isLast: Bool,
  style: AnyOutlineStyle
) -> String {
  guard !ancestry.isEmpty else {
    return ""
  }

  let resolvedStyle = style.presentation
  let ancestorPrefix = ancestry.map { showsContinuation in
    outlineIndenter(
      showsContinuation: showsContinuation,
      style: resolvedStyle
    )
  }
  .joined()
  return ancestorPrefix + outlineConnector(isLast: isLast, style: resolvedStyle)
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
