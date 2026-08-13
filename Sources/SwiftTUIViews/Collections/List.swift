@_spi(Testing) import SwiftTUICore

// `Section` — the header/content/footer grouping view — lives in
// `Section.swift`.

/// Presents selectable rows in a vertically scrollable list.
public struct List<SelectionValue: Hashable & Sendable, Content: View>: PrimitiveView,
  ResolvableView
{
  private var selectionPolicy: CollectionSelectionPolicy<SelectionValue>
  private var onActivate: (@MainActor (SelectionValue) -> Void)?
  private var content: Content
  package var usesIndexedDataSource = false

  @_disfavoredOverload
  public init(
    selection: Binding<SelectionValue>,
    onActivate: (@MainActor (SelectionValue) -> Void)? = nil,
    @ViewBuilder content: () -> Content
  ) {
    selectionPolicy = .requiredSingle(selection)
    self.onActivate = onActivate
    self.content = content()
  }

  public init(
    selection: Binding<SelectionValue?>,
    onActivate: (@MainActor (SelectionValue) -> Void)? = nil,
    @ViewBuilder content: () -> Content
  ) {
    selectionPolicy = .optionalSingle(selection)
    self.onActivate = onActivate
    self.content = content()
  }

  public init(
    selection: Binding<Set<SelectionValue>>,
    onActivate: (@MainActor (SelectionValue) -> Void)? = nil,
    @ViewBuilder content: () -> Content
  ) {
    selectionPolicy = .multiple(selection)
    self.onActivate = onActivate
    self.content = content()
  }

  public init(
    @ViewBuilder content: () -> Content
  ) where SelectionValue == Never {
    selectionPolicy = .none
    onActivate = nil
    self.content = content()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [resolvedNode(in: context)]
  }
}

extension List {
  private typealias RowSelection = HostedCollectionRowSelection

  private struct ResolvedItems {
    var items: [ListItemPayload] = []
    var rows: [RowSelection] = []
    var children: [ResolvedNode] = []
    var runtimeIssues: [RuntimeIssue] = []
    var indexedSource: (any IndexedChildSource)?
  }

  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused = context.environmentValues.focusedIdentity == context.identity
    let isEnabled = context.environmentValues.isEnabled
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let listStyle = context.environmentValues.listStyle.presentation(
      for: ListStyleConfiguration(
        isSelectable: selectionPolicy.isSelectable,
        isEnabled: isEnabled,
        isFocused: isFocused,
        showsFocusEffect: showsFocusEffect,
        styleEnvironment: styleEnvironment
      )
    )
    let showsIndicators =
      context.environmentValues.scrollIndicatorVisibility.allowsVisibleIndicators
    let itemContext = context.child(component: .named("ListItems"))
    var resolvedContent: ResolvedItems
    if usesIndexedDataSource,
      let source = makeIndexedChildSource(
        from: content,
        in: itemContext.settingEnvironment(\.isResolvingHostedCollectionContent, to: true)
      )
    {
      resolvedContent = resolvedIndexedItems(from: source, in: context)
    } else {
      resolvedContent = resolvedItems(in: itemContext)
      // D22: `usesIndexedDataSource` is set only by the direct-data
      // initializers, so `List { ForEach(data) }` silently takes the eager
      // path even though the recognition machinery would have succeeded on it.
      // Flipping that spelling to windowed is its own characterization
      // program; making the fork visible is not.
      if let issue = eagerCollectionRuntimeIssue(
        rowCount: resolvedContent.rows.count,
        identity: context.identity,
        source: "List"
      ) {
        resolvedContent.runtimeIssues.append(issue)
      }
    }
    let rows = resolvedContent.rows
    // Locate the selected row through the source's id index when there is
    // one: scanning every row and asking the policy about each tag is
    // O(dataset) on the resolve path of every frame (register item D18).
    // The eager path keeps the scan — it has already materialized every row.
    let selectedIndex: Int? =
      if let source = resolvedContent.indexedSource {
        selectionPolicy.selectionTag().flatMap(source.elementIndex(forSelectionTag:))
      } else {
        rows.indices.first { index in
          rows[index].tag.map(selectionPolicy.contains) == true
        }
      }
    // Likewise for focus: the focused identity already encodes its row index,
    // so parsing it beats minting an identity per row until one matches.
    let focusedRowIndex = context.environmentValues.focusedIdentity.flatMap { focused in
      listRowIndex(parsedFrom: focused, container: context.identity)
    }.flatMap { rowIndex in
      rows.indices.contains(rowIndex) ? rowIndex : nil
    }
    let isListOrRowFocused = isFocused || focusedRowIndex != nil
    let activeRowIndex = focusedRowIndex ?? selectedIndex
    // Focus is signalled at the row layer (caret + selected-row chrome);
    // the list container itself stays neutral so the row signal stays visible.
    let chrome = styleEnvironment.controlChrome(
      isEnabled: isEnabled,
      isFocused: false
    )
    let rowChrome = styleEnvironment.rowChrome(
      isEnabled: isEnabled,
      isFocused: isListOrRowFocused && showsFocusEffect,
      isSelected: true
    )

    let ownerNode = ViewNodeContext.current ?? context.viewGraph?.nodeForIdentity(context.identity)
    var scrollCurrency: CollectionScrollCurrency?
    if isEnabled, !rows.isEmpty {
      let showsIndicatorLines = showsIndicators
      let rowCount = rows.count
      scrollCurrency = CollectionScrollCurrency(
        identity: context.identity,
        geometry: CollectionScrollGeometry(
          rowCount: rowCount,
          rowSpan: listStyle.listRowDisplaySpan,
          chromeInset: listStyle.listChromeLineInset
        ),
        ownerNode: ownerNode,
        registry: context.scrollCommandRegistry,
        windowMetrics: { viewportLineCount in
          let window = listStyle.viewportBackedListWindow(
            itemCount: rowCount,
            selectedRowIndex: activeRowIndex,
            anchorRowIndex: nil,
            showsIndicators: showsIndicatorLines,
            viewportLineCount: viewportLineCount
          )
          return (window.offset, window.visibleLineCount)
        }
      )
    }

    if isEnabled {
      let policy = selectionPolicy
      let intake = HandlerDescriptorIntake(
        context: context,
        fallbackAuthoringScope: nil
      )
      let activate: @MainActor (SelectionTag) -> Bool = { tag in
        guard let value = policy.value(from: tag) else {
          return false
        }
        if !policy.isMultiple {
          _ = policy.select(tag)
        }
        onActivate?(value)
        return true
      }

      if let scrollCurrency {
        // Registration is unconditional for an enabled non-empty collection:
        // scrolling is not a selection feature, and this registration is what
        // lets `ScrollViewProxy` reach the collection at all.
        let indexedSource = resolvedContent.indexedSource
        intake.registerScrollPosition(
          identity: context.identity,
          currentOffset: { scrollCurrency.currentOffset() },
          applyOffset: { scrollCurrency.applyOffset($0) },
          revealTarget: { query, anchor in
            scrollCurrency.revealTarget(for: query, anchor: anchor) { query in
              indexedSource?.elementIndex(matching: query)
            }
          }
        )

        let rootRouteID = runtimePrimaryRouteID(for: context.identity)
        intake.registerPointerHandler(routeID: rootRouteID) { event in
          guard case .scrolled(let deltaX, let deltaY) = event.kind,
            let delta = pointerSelectionDelta(deltaX: deltaX, deltaY: deltaY)
          else {
            return .ignored
          }
          // Behavioural flip (scroll-currency S1): the wheel moves the window
          // and leaves the selection alone. Arrow keys keep selection
          // semantics. Previously the wheel drove `policy.step`, so a
          // non-selectable collection could not scroll at all and a selectable
          // one could not be looked through without changing what was selected.
          return scrollCurrency.scroll(byRows: delta) ? .claimed : .ignored
        }
      }

      intake.registerKeyHandler(identity: context.identity) { event in
        if let scrollCurrency, applyCollectionScrollKey(event, to: scrollCurrency) {
          return true
        }
        guard policy.isSelectable else {
          return false
        }

        let delta: Int?
        switch event {
        case .arrowUp:
          delta = -1
        case .arrowDown:
          delta = 1
        case .return:
          guard let activeRowIndex, rows.indices.contains(activeRowIndex) else {
            return false
          }
          guard let tag = rows[activeRowIndex].tag else {
            return false
          }
          return activate(tag)
        case .space:
          guard let activeRowIndex, rows.indices.contains(activeRowIndex),
            let tag = rows[activeRowIndex].tag
          else {
            return false
          }
          return policy.isMultiple ? policy.toggle(tag) : activate(tag)
        default:
          delta = nil
        }

        guard let delta, !rows.isEmpty else {
          return false
        }

        guard policy.step(orderedTags: rows.compactMap(\.tag), delta: delta) else {
          return false
        }
        if let scrollCurrency {
          scrollCurrency.pinCurrentAnchor()
          if let selectedRow = rows.firstIndex(where: { row in
            row.tag.map(policy.contains) == true
          }) {
            scrollCurrency.reveal(row: selectedRow)
          }
        }
        return true
      }

      if policy.isSelectable {
        let interactionIndices: any Sequence<Int> =
          if resolvedContent.indexedSource == nil {
            rows.indices
          } else {
            collectionInteractionBand(
              count: rows.count,
              scrollAnchorRow: scrollCurrency?.effectiveAnchorRow,
              selectionAnchor: activeRowIndex,
              visibleRowCount: scrollCurrency.map { currency in
                currency.visibleLineCount / currency.geometry.rowSpan
              }
            )
          }
        for rowIndex in interactionIndices {
          let row = rows[rowIndex]
          guard let tag = row.tag else {
            continue
          }
          let rowIdentity = listRowIdentity(
            for: context.identity,
            rowIndex: rowIndex
          )
          intake.registerAction(identity: rowIdentity) {
            policy.isMultiple ? policy.toggle(tag) : activate(tag)
          }
          intake.registerKeyHandler(identity: rowIdentity) { event in
            let delta: Int?
            switch event {
            case .arrowUp:
              delta = -1
            case .arrowDown:
              delta = 1
            default:
              delta = nil
            }

            guard let delta, !rows.isEmpty else {
              return false
            }

            let targetIndex = min(
              max(rowIndex + delta, rows.startIndex),
              rows.index(before: rows.endIndex)
            )
            guard let targetTag = rows[targetIndex].tag else {
              return false
            }
            if !policy.isMultiple {
              _ = policy.select(targetTag)
            }
            if let scrollCurrency {
              // This handler owns the common case: with focus on a row, the
              // row's own handler sees the arrow and the container's never
              // does. Pin before revealing — while nothing is stored the
              // window IS the selection, so a minimal reveal would just be
              // re-centred by the fallback underneath it.
              scrollCurrency.pinCurrentAnchor()
              scrollCurrency.reveal(row: targetIndex)
            }
            return false
          }
        }
      }
    }

    var payload = ListPayload(
      items: resolvedContent.items,
      selectedRowIndex: activeRowIndex,
      style: listStyle,
      foregroundStyle: chrome.foregroundStyle,
      backgroundStyle: chrome.backgroundStyle,
      borderStyle: chrome.borderStyle,
      selectedRowForegroundStyle: isListOrRowFocused && showsFocusEffect
        ? rowChrome.foregroundStyle : nil,
      selectedRowBackgroundStyle: isListOrRowFocused && showsFocusEffect
        ? rowChrome.backgroundStyle : nil,
      selectedRowMarkerStyle: isListOrRowFocused && showsFocusEffect ? rowChrome.borderStyle : nil,
      // The gutter is structural: reserve it for any non-empty list whose
      // focus effects are enabled, regardless of whether focus is currently
      // inside the list. Toggling the gutter on focus arrival would shift
      // every row's content sideways at the moment of highlighting.
      showsSelectionMarker: showsFocusEffect && !rows.isEmpty,
      showsIndicators: showsIndicators,
      opacity: chrome.opacity
    )
    payload.isViewportBacked = resolvedContent.indexedSource != nil
    if resolvedContent.indexedSource != nil {
      // The rows are committed child nodes; the payload's copies were N
      // identical empty stubs carrying only their count (register item D18).
      // Carry the count instead of the array.
      payload.virtualRowCount = rows.count
    }
    payload.scrollAnchorRowIndex = scrollCurrency?.storedAnchorRow

    var metadata = focusableControlMetadata(
      // A selectable list signals focus at the row layer, so the container
      // stays neutral. A non-selectable *viewport-backed* list has no row
      // focus at all, so the container itself must be focusable or its
      // PageUp/PageDown/Home/End handlers are unreachable — the same bargain
      // `ScrollView` makes. Builder-spelled (eager) lists keep today's
      // behaviour; they take the unwindowed path anyway.
      isFocusable: rows.isEmpty
        ? nil
        : (selectionPolicy.isSelectable || resolvedContent.indexedSource == nil ? false : true),
      focusInteractions: .edit,
      scrollRole: .list,
      accessibilityRole: .list
    )
    metadata.hostedCollectionContainer = .init(kind: .list)
    var node = ResolvedNode(
      identity: context.identity,
      kind: .view("List"),
      children: resolvedContent.children,
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: metadata,
      drawPayload: .list(payload),
      indexedChildSource: resolvedContent.indexedSource
    )
    node.drawMetadata.clipsToBounds = true
    var preferences = node.preferenceValues
    var runtimeIssues = preferences[RuntimeIssuePreferenceKey.self]
    for issue in resolvedContent.runtimeIssues where !runtimeIssues.contains(issue) {
      runtimeIssues.append(issue)
    }
    preferences[RuntimeIssuePreferenceKey.self] = runtimeIssues
    node.preferenceValues = preferences
    return node
  }

  private func resolvedItems(
    in context: ResolveContext
  ) -> ResolvedItems {
    let nodes = resolveDeclaredChildren(
      content,
      in: context.settingEnvironment(\.isResolvingHostedCollectionContent, to: true),
      kindName: "ListContent"
    )
    var result = ResolvedItems()
    var hasEmittedSection = false
    var previousSectionBottomVisibility: Visibility?
    collectTopLevelItems(
      from: nodes,
      into: &result,
      hasEmittedSection: &hasEmittedSection,
      previousSectionBottomVisibility: &previousSectionBottomVisibility
    )
    return result
  }

  private func resolvedIndexedItems(
    from source: any IndexedChildSource,
    in context: ResolveContext
  ) -> ResolvedItems {
    var result = ResolvedItems()
    // No `items` array: every entry would be the same empty stub, so the
    // payload carries `virtualRowCount` instead (register item D18). `rows`
    // still materializes — the key handlers index it by row and hand its tags
    // to the selection policy, which takes an ordered array — but the
    // snapshot is served from the source's retained identity artifacts when
    // nothing that determines it changed (R4-A): the artifacts already
    // re-mint on any ids change, and the key carries the only other inputs
    // the build reads (selectability + the selection value type the tags
    // must cast to). Rebuilding it per resolve was an O(dataset) term on the
    // per-notch scroll path.
    let selectionPolicy = self.selectionPolicy
    let buildRows: () -> [RowSelection] = {
      var rows: [RowSelection] = []
      rows.reserveCapacity(source.count)
      for index in 0..<source.count {
        let candidateTag = source.elementSelectionTag(at: index)
        let compatibleTag = candidateTag.flatMap { tag in
          selectionPolicy.isSelectable && selectionPolicy.value(from: tag) != nil ? tag : nil
        }
        rows.append(
          .init(
            tag: compatibleTag,
            identity: source.elementIdentity(at: index)
          )
        )
      }
      return rows
    }
    if let cachingSource = source as? any RowSelectionCachingIndexedChildSource {
      result.rows = cachingSource.retainedRowSelections(
        key: HostedRowSelectionCacheKey(
          isSelectable: selectionPolicy.isSelectable,
          selectionValueType: ObjectIdentifier(SelectionValue.self)
        ),
        build: buildRows
      )
    } else {
      result.rows = buildRows()
    }

    let policy = selectionPolicy
    result.indexedSource = HostedCollectionIndexedChildSource(base: source) { rawNode, index in
      var node = rawNode
      let row = resolvedHostedListRow(from: node)
      let compatibleTag = row.tag.flatMap { tag in
        policy.isSelectable && policy.value(from: tag) != nil ? tag : nil
      }
      node = applyingHostedRowForegroundStyle(
        row.drawMetadata.listStyle?.rowForegroundStyle,
        to: node
      )
      node.semanticMetadata.hostedCollectionItem = .init(
        role: .listRow(rowIndex: index),
        isSelectable: compatibleTag != nil
      )
      return node
    }
    return result
  }

  private func collectTopLevelItems(
    from nodes: [ResolvedNode],
    into result: inout ResolvedItems,
    hasEmittedSection: inout Bool,
    previousSectionBottomVisibility: inout Visibility?
  ) {
    for var node in nodes {
      if node.semanticMetadata.sectionRole == .section {
        if hasEmittedSection, !result.items.isEmpty {
          result.items.append(
            .init(
              kind: .sectionBreak,
              text: "",
              sectionSeparators: .init(
                top: node.drawMetadata.listStyle?.sectionSeparatorTopVisibility,
                bottom: previousSectionBottomVisibility
              )
            )
          )
          var breakMetadata = SemanticMetadata(isFocusable: false)
          breakMetadata.hostedCollectionItem = .init(role: .listSectionBreak)
          result.children.append(
            ResolvedNode(
              identity: node.identity.child(.named("ListSectionBreak")),
              kind: .view("ListSectionBreak"),
              environmentSnapshot: node.environmentSnapshot,
              transactionSnapshot: node.transactionSnapshot,
              semanticMetadata: breakMetadata,
              intrinsicSize: .init(width: 1, height: 1)
            )
          )
        }
        collectSection(node, into: &result)
        previousSectionBottomVisibility =
          node.drawMetadata.listStyle?.sectionSeparatorBottomVisibility
        hasEmittedSection = true
      } else if containsHostedCollectionRowBoundary(node) {
        collectItems(from: [node], into: &result)
      } else {
        appendRow(node: &node, to: &result)
      }
    }
  }

  private func collectSection(
    _ node: ResolvedNode,
    into result: inout ResolvedItems
  ) {
    for var child in node.children {
      switch child.semanticMetadata.sectionRole {
      case .header:
        let label = resolvedNodeLabelText(from: child)
        if !label.isEmpty {
          result.items.append(
            sectionChromeItem(kind: .header, text: label, node: child, into: &result)
          )
          child.semanticMetadata.hostedCollectionItem = .init(role: .listHeader)
          result.children.append(child)
        }
      case .footer:
        let label = resolvedNodeLabelText(from: child)
        if !label.isEmpty {
          result.items.append(
            sectionChromeItem(kind: .footer, text: label, node: child, into: &result)
          )
          child.semanticMetadata.hostedCollectionItem = .init(role: .listFooter)
          result.children.append(child)
        }
      default:
        collectItems(from: child.children, into: &result)
      }
    }
  }

  /// Builds a header/footer item, carrying the authored text attributes off
  /// the flattened subtree. Section chrome lines are always drawn from the
  /// flattened payload (even in hosted lists) at a single line, so an
  /// authored limit above 1 cannot be honored: it clamps to 1 and reports a
  /// runtime issue — the framework's fail-loud preference over silent
  /// truncation.
  private func sectionChromeItem(
    kind: ListItemPayload.Kind,
    text: String,
    node: ResolvedNode,
    into result: inout ResolvedItems
  ) -> ListItemPayload {
    let textAttributes = flattenedTextLayoutAttributes(from: node)
    var lineLimit = textAttributes.lineLimit
    if let authored = lineLimit, authored > 1 {
      lineLimit = 1
      result.runtimeIssues.append(
        RuntimeIssue(
          severity: .warning,
          code: "collection.unsupportedSectionChromeLineLimit",
          message:
            "A list \(kind == .header ? "header" : "footer") asked for lineLimit \(authored), "
            + "but section chrome renders single-line; clamping to 1.",
          identity: node.identity,
          source: "List"
        )
      )
    }
    return .init(
      kind: kind,
      text: text,
      style: listItemTextStyle(from: node.drawMetadata),
      lineLimit: lineLimit,
      truncationMode: textAttributes.truncationMode
    )
  }

  private func collectItems(
    from nodes: [ResolvedNode],
    into result: inout ResolvedItems
  ) {
    for var node in nodes {
      if node.semanticMetadata.isHostedCollectionRowBoundary {
        appendRow(node: &node, to: &result)
        continue
      }
      if containsHostedCollectionRowBoundary(node) {
        collectItems(from: node.children, into: &result)
        continue
      }
      let row = resolvedHostedListRow(from: node)
      if row.tagCount > 0 || node.children.isEmpty {
        appendRow(node: &node, row: row, to: &result)
      } else {
        collectItems(from: node.children, into: &result)
      }
    }
  }

  private func containsHostedCollectionRowBoundary(_ node: ResolvedNode) -> Bool {
    node.semanticMetadata.isHostedCollectionRowBoundary
      || node.children.contains(where: containsHostedCollectionRowBoundary)
  }

  private func appendRow(
    node: inout ResolvedNode,
    to result: inout ResolvedItems
  ) {
    appendRow(node: &node, row: resolvedHostedListRow(from: node), to: &result)
  }

  private func appendRow(
    node: inout ResolvedNode,
    row: ResolvedListRow,
    to result: inout ResolvedItems
  ) {
    let rowIndex = result.rows.count
    let compatibleTag = row.tag.flatMap { tag in
      selectionPolicy.value(from: tag) == nil ? nil : tag
    }
    result.items.append(listItemPayload(from: row))
    result.rows.append(.init(tag: compatibleTag, identity: node.identity))
    node = applyingHostedRowForegroundStyle(
      row.drawMetadata.listStyle?.rowForegroundStyle,
      to: node
    )
    node.semanticMetadata.hostedCollectionItem = .init(
      role: .listRow(rowIndex: rowIndex),
      isSelectable: compatibleTag != nil
    )
    result.children.append(node)

    let issue: RuntimeIssue?
    if !selectionPolicy.isSelectable {
      issue = nil
    } else if row.tagCount == 0 {
      issue = RuntimeIssue(
        severity: .warning,
        code: "collection.missingSelectionTag",
        message:
          "Selectable List row has no selection tag; the row remains visible but is not selectable.",
        identity: node.identity,
        source: "List"
      )
    } else if row.tagCount > 1 {
      issue = RuntimeIssue(
        severity: .error,
        code: "collection.ambiguousSelectionTag",
        message:
          "Selectable List row has \(row.tagCount) selection tags; the row remains visible but is not selectable.",
        identity: node.identity,
        source: "List"
      )
    } else if compatibleTag == nil {
      issue = RuntimeIssue(
        severity: .warning,
        code: "collection.incompatibleSelectionTag",
        message:
          "Selectable List row has a tag incompatible with the selection value type; the row remains visible but is not selectable.",
        identity: node.identity,
        source: "List"
      )
    } else {
      issue = nil
    }
    if let issue, !result.runtimeIssues.contains(issue) {
      result.runtimeIssues.append(issue)
    }
  }
}
