public import Core

private enum OutlineStyleKey: EnvironmentKey {
  static let defaultValue = OutlineStyle.automatic
}

extension EnvironmentValues {
  public var outlineStyle: OutlineStyle {
    get { self[OutlineStyleKey.self] }
    set { self[OutlineStyleKey.self] = newValue }
  }
}

/// Presents hierarchical collection data as an outline.
public struct OutlineGroup<Data, ID, RowContent>: View
where Data: RandomAccessCollection, ID: Hashable, RowContent: View {
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
    Data: RandomAccessCollection, ID: Hashable, SelectionValue == ID?,
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
    Data: RandomAccessCollection, ID: Hashable, SelectionValue == ID?,
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

extension List where SelectionValue: Hashable {
  public init<Data, RowContent: View>(
    _ data: Data,
    selection: Binding<SelectionValue>,
    children: KeyPath<Data.Element, [Data.Element]?>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  )
  where
    Data: RandomAccessCollection, Data.Element: Identifiable,
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

extension OutlineGroup where Data.Element: Identifiable, ID == Data.Element.ID {
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
where ID: Hashable, RowContent: View {
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

private struct OutlineEntry<Element, ID: Hashable>: Identifiable {
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

private struct ScopedOutlineRowContent<Content: View>: View, ResolvableView {
  let authoringScope: AuthoringContext?
  let content: Content

  func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    withAuthoringContext(authoringScope) {
      content.resolveElements(in: context)
    }
  }
}

private func outlinePrefix(
  ancestry: [Bool],
  isLast: Bool,
  style: OutlineStyle
) -> String {
  guard !ancestry.isEmpty else {
    return ""
  }

  let resolvedStyle = resolvedOutlineStyle(style)
  let ancestorPrefix = ancestry.map { showsContinuation in
    outlineIndenter(
      showsContinuation: showsContinuation,
      style: resolvedStyle
    )
  }
  .joined()
  return ancestorPrefix + outlineConnector(isLast: isLast, style: resolvedStyle)
}

private func resolvedOutlineStyle(
  _ style: OutlineStyle
) -> OutlineStyle {
  style == .automatic ? .rounded : style
}

private func outlineConnector(
  isLast: Bool,
  style: OutlineStyle
) -> String {
  switch style {
  case .plain:
    return isLast ? "└─ " : "├─ "
  case .ascii:
    return isLast ? "`- " : "|- "
  default:
    return isLast ? "╰─ " : "├─ "
  }
}

private func outlineIndenter(
  showsContinuation: Bool,
  style: OutlineStyle
) -> String {
  switch style {
  case .ascii:
    return showsContinuation ? "| " : "  "
  default:
    return showsContinuation ? "│ " : "  "
  }
}
