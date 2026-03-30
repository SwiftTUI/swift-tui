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
public struct OutlineGroup<Data, ID>: View
where Data: RandomAccessCollection, ID: Hashable {
  private let rootView: AnyView

  public init<RowContent: View>(
    _ data: Data,
    id: KeyPath<Data.Element, ID>,
    children: KeyPath<Data.Element, [Data.Element]?>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  ) {
    rootView = AnyView(
      OutlineTree(
        elements: Array(data),
        id: { $0[keyPath: id] },
        children: { $0[keyPath: children] ?? [] },
        rowContent: { element in
          AnyView(rowContent(element))
        }
      )
    )
  }

  public init<RowContent: View>(
    _ data: Data,
    id: KeyPath<Data.Element, ID>,
    children: KeyPath<Data.Element, [Data.Element]>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  ) {
    rootView = AnyView(
      OutlineTree(
        elements: Array(data),
        id: { $0[keyPath: id] },
        children: { $0[keyPath: children] },
        rowContent: { element in
          AnyView(rowContent(element))
        }
      )
    )
  }

  public var body: some View {
    rootView
  }
}

extension List {
  public init<Data, RowContent: View>(
    _ data: Data,
    id: KeyPath<Data.Element, SelectionValue>,
    selection: Binding<SelectionValue>,
    children: KeyPath<Data.Element, [Data.Element]?>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  ) where Data: RandomAccessCollection {
    self.init(
      selection: selection,
      contentViews: [
        AnyView(
          OutlineTree(
            elements: Array(data),
            id: { $0[keyPath: id] },
            children: { $0[keyPath: children] ?? [] },
            rowContent: { element in
              AnyView(rowContent(element).tag(element[keyPath: id]))
            }
          )
        )
      ]
    )
  }

  public init<Data, RowContent: View>(
    _ data: Data,
    id: KeyPath<Data.Element, SelectionValue>,
    selection: Binding<SelectionValue>,
    children: KeyPath<Data.Element, [Data.Element]>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  ) where Data: RandomAccessCollection {
    self.init(
      selection: selection,
      contentViews: [
        AnyView(
          OutlineTree(
            elements: Array(data),
            id: { $0[keyPath: id] },
            children: { $0[keyPath: children] },
            rowContent: { element in
              AnyView(rowContent(element).tag(element[keyPath: id]))
            }
          )
        )
      ]
    )
  }

  public init<Data, ID, RowContent: View>(
    _ data: Data,
    id: KeyPath<Data.Element, ID>,
    selection: Binding<ID?>,
    children: KeyPath<Data.Element, [Data.Element]?>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  ) where Data: RandomAccessCollection, ID: Hashable, SelectionValue == ID? {
    self.init(
      selection: selection,
      contentViews: [
        AnyView(
          OutlineTree(
            elements: Array(data),
            id: { $0[keyPath: id] },
            children: { $0[keyPath: children] ?? [] },
            rowContent: { element in
              AnyView(rowContent(element).tag(element[keyPath: id]))
            }
          )
        )
      ]
    )
  }

  public init<Data, ID, RowContent: View>(
    _ data: Data,
    id: KeyPath<Data.Element, ID>,
    selection: Binding<ID?>,
    children: KeyPath<Data.Element, [Data.Element]>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  ) where Data: RandomAccessCollection, ID: Hashable, SelectionValue == ID? {
    self.init(
      selection: selection,
      contentViews: [
        AnyView(
          OutlineTree(
            elements: Array(data),
            id: { $0[keyPath: id] },
            children: { $0[keyPath: children] },
            rowContent: { element in
              AnyView(rowContent(element).tag(element[keyPath: id]))
            }
          )
        )
      ]
    )
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
    SelectionValue == Data.Element.ID
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
    SelectionValue == Data.Element.ID
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
    SelectionValue == Data.Element.ID?
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
    SelectionValue == Data.Element.ID?
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
  public init<RowContent: View>(
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

  public init<RowContent: View>(
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

package struct OutlineTree<Element, ID>: View where ID: Hashable {
  package var elements: [Element]
  package var id: (Element) -> ID
  package var children: (Element) -> [Element]
  package var rowContent: (Element) -> AnyView
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
            content: rowContent(entry.element)
          )

          if !entry.children.isEmpty {
            OutlineTree(
              elements: entry.children,
              id: id,
              children: children,
              rowContent: rowContent,
              ancestry: ancestry + [!entry.isLast]
            )
          }
        }
      }
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

private struct OutlineRow: View {
  let prefix: String
  let content: AnyView

  var body: some View {
    if prefix.isEmpty {
      AnyView(content)
    } else {
      AnyView(
        HStack(alignment: .firstTextBaseline, spacing: 0) {
          Text(prefix)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(.terminalBorder(.neutral))
          content
        }
      )
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
