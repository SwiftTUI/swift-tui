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
  /// This existing accessor remains public for source compatibility. Other
  /// families keep their storage slots package-visible; applications select
  /// all styles through their public view modifiers.
  public var outlineStyle: AnyOutlineStyle {
    get { self[OutlineStyleKey.self] }
    set { self[OutlineStyleKey.self] = newValue }
  }
}

/// Presents hierarchical collection data as an outline.
public struct OutlineGroup<Data, ID, RowContent>: View
where Data: RandomAccessCollection, ID: Hashable & Sendable, RowContent: View {
  @State private var collapsed: Set<[ID]> = []
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
    LazyVStack(alignment: .leading, spacing: 0) {
      rows(
        outlineEntries(elements, id: id, children: children, collapsed: collapsed),
        collapsed: $collapsed)
    }.accessibilityRole(.list)
  }

  private func rows(_ entries: [OutlineEntry<Data.Element, ID>], collapsed: Binding<Set<[ID]>>)
    -> some View & IndexedChildSourceView
  {
    return ForEach(entries, id: \.path) { entry in
      EnvironmentReader(\.outlineStyle) { style in
        EnvironmentReader(\.styleEnvironmentSnapshot) { environment in
          let presentation = style.presentation(for: .init(styleEnvironment: environment))
          OutlineRow(
            prefix: outlinePrefix(
              ancestry: entry.ancestry, isLast: entry.isLast, style: presentation),
            content: withAuthoringContext(authoringScope) { rowContent(entry.element) },
            authoringScope: authoringScope,
            expanded: entry.hasChildren
              ? Binding(
                get: { !collapsed.wrappedValue.contains(entry.path) },
                set: { expanded in
                  var next = collapsed.wrappedValue
                  if expanded { next.remove(entry.path) } else { next.insert(entry.path) }
                  // Removed data must not leave a growing history of disclosure state.
                  let livePaths = Set(
                    outlineEntries(elements, id: id, children: children, collapsed: []).map(\.path))
                  collapsed.wrappedValue = next.intersection(livePaths)
                }) : nil,
            level: entry.ancestry.count + 1, position: entry.position, count: entry.count
          )
          .tag(entry.identifier)
          .accessibilityRole(.custom("listitem"))
          .accessibilityProperties(
            .init(
              level: entry.ancestry.count + 1,
              positionInSet: entry.position, setSize: entry.count))
        }
      }
    }
  }
}

/// A direct OutlineGroup in List has a logical source without evaluating rows.
@MainActor
package protocol IndexedOutlineSourceView: IndexedChildSourceView {}

extension OutlineGroup: IndexedOutlineSourceView {
  package func indexedChildSource(in context: ResolveContext) -> (any IndexedChildSource)? {
    withDynamicPropertyUpdateScope(self, for: context) {
      let entries = outlineEntries(elements, id: id, children: children, collapsed: collapsed)
      guard let source = rows(entries, collapsed: $collapsed).indexedChildSource(in: context) else {
        return nil
      }
      return OutlineIndexedSource(
        base: source,
        tags: entries.map { SelectionTag(value: $0.identifier, includeOptional: true) })
    }
  }
}

private struct OutlineIndexedSource: IndexedChildSource {
  let base: any IndexedChildSource
  let tags: [SelectionTag]
  var count: Int { base.count }
  var identityRoot: Identity { base.identityRoot }
  var measurementSignature: IndexedChildMeasurementSignature { base.measurementSignature }
  func child(at index: Int) -> ResolvedNode { base.child(at: index) }
  func elementIdentity(at index: Int) -> Identity { base.elementIdentity(at: index) }
  func elementSelectionTag(at index: Int) -> SelectionTag? { tags[index] }
}

private struct OutlineEntry<Element, ID: Hashable & Sendable> {
  let path: [ID]
  let identifier: ID
  let element: Element
  let hasChildren: Bool
  let ancestry: [Bool]
  let position: Int
  let count: Int
  let isLast: Bool
}

/// Only logical data and IDs are enumerated. Row producers run in the viewport.
@MainActor
private func outlineEntries<Element, ID: Hashable & Sendable>(
  _ elements: [Element], id: (Element) -> ID, children: (Element) -> [Element], collapsed: Set<[ID]>
) -> [OutlineEntry<Element, ID>] {
  var result: [OutlineEntry<Element, ID>] = []
  var stack: [(elements: [Element], offset: Int, ancestry: [Bool], path: [ID])] = [
    (elements, 0, [], [])
  ]
  while let frame = stack.popLast() {
    guard frame.offset < frame.elements.count else { continue }
    let element = frame.elements[frame.offset]
    let identifier = id(element)
    let path = frame.path + [identifier]
    let descendants = children(element)
    let isLast = frame.offset == frame.elements.count - 1
    result.append(
      .init(
        path: path, identifier: identifier, element: element,
        hasChildren: !descendants.isEmpty, ancestry: frame.ancestry, position: frame.offset + 1,
        count: frame.elements.count, isLast: isLast))
    stack.append((frame.elements, frame.offset + 1, frame.ancestry, frame.path))
    if !collapsed.contains(path), !descendants.isEmpty {
      stack.append((descendants, 0, frame.ancestry + [!isLast], path))
    }
  }
  return result
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

private struct OutlineRow<Content: View>: PrimitiveView, IterativeResolvableView {
  let prefix: String
  let content: Content
  let authoringScope: AuthoringContext?
  let expanded: Binding<Bool>?
  let level: Int
  let position: Int
  let count: Int

  @ViewBuilder
  private func rowBody(
    prefix renderedPrefix: String,
    spacing: Int
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: spacing) {
      if !renderedPrefix.isEmpty {
        Text(renderedPrefix)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
          .foregroundStyle(.terminalBorder(.neutral))
          .accessibilityHidden(true)
      }
      if let expanded {
        Button(expanded.wrappedValue ? "▾" : "▸") { expanded.wrappedValue.toggle() }
          .buttonStyle(.plain)
          .accessibilityLabel(
            "\(expanded.wrappedValue ? "Collapse" : "Expand") item \(position) at level \(level)"
          )
          .accessibilityProperties(.init(expanded: expanded.wrappedValue))
      }
      ScopedOutlineRowContent(authoringScope: authoringScope, content: content)
    }
  }

  func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    let isHosted = context.environmentValues.isResolvingHostedCollectionContent
    return resolveDeclaredChildrenWork(
      rowBody(prefix: prefix, spacing: isHosted ? 1 : 0),
      in: context.child(component: .named("Content")),
      kindName: "OutlineRow"
    ).map { children in
      var metadata = SemanticMetadata(isHostedCollectionRowBoundary: true)
      metadata.accessibilityProperties = .init(
        description: "Level \(level), item \(position) of \(count)")
      return [
        ResolvedNode(
          identity: context.identity,
          kind: .view("OutlineRow"),
          children: children,
          environmentSnapshot: context.environment,
          transactionSnapshot: context.transaction,
          semanticMetadata: metadata
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
    // identity carried down by the outline source's `ForEach`. The generic
    // `content.resolveElements(in:)` path this replaced never called
    // `beginEvaluation`/`makeAuthoringContext`, so it re-used the single
    // `authoringScope` owner captured once at `OutlineGroup.init` for every
    // row, collapsing all rows' row-local state onto one shared slot.
    //
    // Captures of the ENCLOSING view's `@State` stay correct independently of
    // this per-row owner: control handlers dispatch under their
    // construction-time scope (`HandlerDescriptorIntake.preferringAuthoringScope`),
    // and the row content is still built under `authoringScope` in
    // `OutlineGroup`'s row producer, so a row button that mutates enclosing state
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
