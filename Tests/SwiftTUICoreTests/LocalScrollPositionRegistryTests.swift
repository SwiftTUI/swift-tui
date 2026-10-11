import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@MainActor
@Suite
struct LocalScrollPositionRegistryTests {
  @Test("scroll route initializers preserve explicit content offsets")
  func scrollRouteInitializersPreserveExplicitContentOffsets() {
    let identity = testIdentity("Scroll")
    let viewportRect = CellRect(origin: .zero, size: .init(width: 10, height: 4))
    let contentBounds = CellRect(origin: .zero, size: .init(width: 10, height: 12))
    let contentOffset = CellPoint(x: 2, y: 5)

    let publicRoute = ScrollRoute(
      identity: identity,
      viewportRect: viewportRect,
      contentBounds: contentBounds,
      contentOffset: contentOffset
    )

    let packageRoute = ScrollRoute(
      identity: identity,
      viewNodeID: ViewNodeID(rawValue: 1),
      viewportRect: viewportRect,
      contentBounds: contentBounds,
      contentOffset: contentOffset
    )

    #expect(publicRoute.contentOffset == contentOffset)
    #expect(packageRoute.contentOffset == contentOffset)
  }

  @Test(
    "collection resize focus recovery yields to a newer logical scroll anchor",
    arguments: [false, true]
  )
  func collectionResizeFocusRecoveryHonorsScrollAnchor(hasNewerAnchor: Bool) {
    let registry = LocalScrollPositionRegistry()
    let scrollIdentity = testIdentity("ResizeCollection")
    let focusedIdentity = testIdentity("ResizeCollection", "Row", "8")
    let graph = ViewGraph()
    graph.beginFrame()
    let ownerNode = graph.beginEvaluation(identity: scrollIdentity, invalidator: nil)
    var logicalAnchor: CollectionScrollAnchor? = .row(3)
    var offset = ScrollOffset(x: 0, y: 9)
    var revealCalls = 0
    var offsetWrites = 0

    ViewNodeContext.withValue(ownerNode) {
      registry.register(
        identity: scrollIdentity,
        currentOffset: { offset },
        applyOffset: {
          offsetWrites += 1
          offset = $0
        },
        currentCollectionAnchor: { logicalAnchor },
        revealTarget: { query, anchor in
          revealCalls += 1
          #expect(query == ScrollTargetQuery(identity: focusedIdentity))
          #expect(anchor == nil)
          logicalAnchor = .row(7)
          offset = ScrollOffset(x: 0, y: 21)
          return true
        }
      )
    }

    let focusedRegion = FocusRegion(
      identity: focusedIdentity,
      rect: CellRect(origin: CellPoint(x: 0, y: 5), size: CellSize(width: 5, height: 1)),
      modalFocusScopePath: nil,
      ownerNodeID: ownerNode.viewNodeID,
      ownerIdentity: scrollIdentity
    )
    var previousRoute = ScrollRoute(
      identity: scrollIdentity,
      viewNodeID: ownerNode.viewNodeID,
      viewportRect: CellRect(origin: .zero, size: CellSize(width: 32, height: 8)),
      contentBounds: CellRect(origin: CellPoint(x: 0, y: -3), size: CellSize(width: 32, height: 12))
    )
    previousRoute.collectionScrollLayout = CollectionScrollLayout(
      geometry: CollectionScrollGeometry(rowCount: 12, rowSpan: 1, chromeInset: 0),
      visibleLines: 3..<11,
      anchor: .row(3)
    )
    var resizedRoute = ScrollRoute(
      identity: scrollIdentity,
      viewNodeID: ownerNode.viewNodeID,
      viewportRect: CellRect(origin: .zero, size: CellSize(width: 10, height: 8)),
      contentBounds: CellRect(origin: CellPoint(x: 0, y: -9), size: CellSize(width: 10, height: 36))
    )
    resizedRoute.collectionScrollLayout = CollectionScrollLayout(
      geometry: CollectionScrollGeometry(
        rowCount: 12, rowSpan: 1, chromeInset: 0,
        rowHeights: Dictionary(uniqueKeysWithValues: (0..<12).map { ($0, 3) })),
      visibleLines: 9..<17,
      anchor: .row(3)
    )

    // A command arriving after measurement must retain priority over resize recovery.
    if hasNewerAnchor {
      logicalAnchor = .end
      offset = ScrollOffset(x: 0, y: 28)
    }
    let changed = registry.revealCollectionFocusAfterResize(
      focusedRegion,
      previousRoutes: [previousRoute],
      scrollRoutes: [resizedRoute],
      scrollTargets: []
    )

    #expect(changed == !hasNewerAnchor)
    #expect(revealCalls == (hasNewerAnchor ? 0 : 1))
    #expect(offsetWrites == 0)
    #expect(offset == ScrollOffset(x: 0, y: hasNewerAnchor ? 28 : 21))
    #expect(logicalAnchor == (hasNewerAnchor ? .end : .row(7)))
  }

  @Test("focused rect below viewport scrolls by the minimum reveal delta")
  func focusedRectBelowViewportScrollsByMinimumRevealDelta() {
    let registry = LocalScrollPositionRegistry()
    let scrollIdentity = testIdentity("Scroll")
    let focusedIdentity = testIdentity("Scroll", "Content", "Button")
    var offset = ScrollOffset.zero

    registry.register(
      identity: scrollIdentity,
      currentOffset: { offset },
      applyOffset: { offset = $0 }
    )

    let changed = registry.sync(
      focusedIdentity: focusedIdentity,
      focusRegions: [
        FocusRegion(
          identity: focusedIdentity,
          rect: .init(origin: .init(x: 0, y: 6), size: .init(width: 4, height: 1))
        )
      ],
      scrollRoutes: [
        ScrollRoute(
          identity: scrollIdentity,
          viewportRect: .init(origin: .zero, size: .init(width: 10, height: 4)),
          contentBounds: .init(origin: .zero, size: .init(width: 10, height: 12))
        )
      ]
    )

    #expect(changed)
    #expect(offset == .init(x: 0, y: 3))
  }

  @Test("focused rect above viewport scrolls by the minimum reveal delta")
  func focusedRectAboveViewportScrollsByMinimumRevealDelta() {
    let registry = LocalScrollPositionRegistry()
    let scrollIdentity = testIdentity("Scroll")
    let focusedIdentity = testIdentity("Scroll", "Content", "Button")
    var offset = ScrollOffset(x: 0, y: 5)

    registry.register(
      identity: scrollIdentity,
      currentOffset: { offset },
      applyOffset: { offset = $0 }
    )

    let changed = registry.sync(
      focusedIdentity: focusedIdentity,
      focusRegions: [
        FocusRegion(
          identity: focusedIdentity,
          rect: .init(origin: .init(x: 0, y: -2), size: .init(width: 4, height: 1))
        )
      ],
      scrollRoutes: [
        ScrollRoute(
          identity: scrollIdentity,
          viewportRect: .init(origin: .zero, size: .init(width: 10, height: 4)),
          contentBounds: .init(origin: .init(x: 0, y: -5), size: .init(width: 10, height: 12))
        )
      ]
    )

    #expect(changed)
    #expect(offset == .init(x: 0, y: 3))
  }

  @Test("visible focused rect does not scroll")
  func visibleFocusedRectDoesNotScroll() {
    let registry = LocalScrollPositionRegistry()
    let scrollIdentity = testIdentity("Scroll")
    let focusedIdentity = testIdentity("Scroll", "Content", "Button")
    var offset = ScrollOffset(x: 0, y: 2)

    registry.register(
      identity: scrollIdentity,
      currentOffset: { offset },
      applyOffset: { offset = $0 }
    )

    let changed = registry.sync(
      focusedIdentity: focusedIdentity,
      focusRegions: [
        FocusRegion(
          identity: focusedIdentity,
          rect: .init(origin: .init(x: 0, y: 1), size: .init(width: 4, height: 1))
        )
      ],
      scrollRoutes: [
        ScrollRoute(
          identity: scrollIdentity,
          viewportRect: .init(origin: .zero, size: .init(width: 10, height: 4)),
          contentBounds: .init(origin: .init(x: 0, y: -2), size: .init(width: 10, height: 12))
        )
      ]
    )

    #expect(!changed)
    #expect(offset == .init(x: 0, y: 2))
  }

  @Test("visible focused rect preserves the producer's usable-viewport offset")
  func visibleFocusedRectPreservesProducerOffset() {
    let registry = LocalScrollPositionRegistry()
    let scrollIdentity = testIdentity("Scroll")
    let focusedIdentity = testIdentity("Scroll", "Content", "Button")
    // Two indicator lines leave six usable rows in an eight-line viewport.
    // The collection's final six-row window starts at row six, not row four.
    var offset = ScrollOffset(x: 0, y: 6)

    registry.register(
      identity: scrollIdentity,
      currentOffset: { offset },
      applyOffset: { offset = $0 },
      // Collections register a resolver for targets outside their placed window.
      revealTarget: { _, _ in nil }
    )

    let changed = registry.sync(
      focusedIdentity: focusedIdentity,
      focusRegions: [
        FocusRegion(
          identity: focusedIdentity,
          rect: CellRect(origin: CellPoint(x: 0, y: 2), size: CellSize(width: 4, height: 1))
        )
      ],
      scrollRoutes: [
        ScrollRoute(
          identity: scrollIdentity,
          viewportRect: CellRect(origin: .zero, size: CellSize(width: 10, height: 8)),
          contentBounds: CellRect(
            origin: CellPoint(x: 0, y: -6), size: CellSize(width: 10, height: 12))
        )
      ]
    )

    #expect(!changed)
    #expect(offset == ScrollOffset(x: 0, y: 6))
  }

  @Test(
    "focus reveal preserves the producer's offset on the axis that needs no movement",
    arguments: [
      (
        currentOffset: ScrollOffset(x: 2, y: 6), targetOrigin: CellPoint(x: -1, y: 2),
        expectedOffset: ScrollOffset(x: 1, y: 6)
      ),
      (
        currentOffset: ScrollOffset(x: 2, y: 6), targetOrigin: CellPoint(x: 8, y: 2),
        expectedOffset: ScrollOffset(x: 3, y: 6)
      ),
      (
        currentOffset: ScrollOffset(x: 6, y: 2), targetOrigin: CellPoint(x: 2, y: -1),
        expectedOffset: ScrollOffset(x: 6, y: 1)
      ),
      (
        currentOffset: ScrollOffset(x: 6, y: 2), targetOrigin: CellPoint(x: 2, y: 8),
        expectedOffset: ScrollOffset(x: 6, y: 3)
      ),
      (
        currentOffset: ScrollOffset(x: 0, y: 6), targetOrigin: CellPoint(x: -1, y: 2),
        expectedOffset: ScrollOffset(x: 0, y: 6)
      ),
      (
        currentOffset: ScrollOffset(x: 4, y: 6), targetOrigin: CellPoint(x: 8, y: 2),
        expectedOffset: ScrollOffset(x: 4, y: 6)
      ),
    ])
  func focusRevealPreservesOffsetOnUnmovedAxis(
    currentOffset: ScrollOffset, targetOrigin: CellPoint, expectedOffset: ScrollOffset
  ) {
    let registry = LocalScrollPositionRegistry()
    let scrollIdentity = testIdentity("Scroll")
    let focusedIdentity = testIdentity("Scroll", "Content", "Button")
    var offset = currentOffset

    registry.register(
      identity: scrollIdentity,
      currentOffset: { offset },
      applyOffset: { offset = $0 },
      // Collections register a resolver for targets outside their placed window.
      revealTarget: { _, _ in nil }
    )

    let changed = registry.sync(
      focusedIdentity: focusedIdentity,
      focusRegions: [
        FocusRegion(
          identity: focusedIdentity,
          rect: CellRect(origin: targetOrigin, size: CellSize(width: 1, height: 1))
        )
      ],
      scrollRoutes: [
        ScrollRoute(
          identity: scrollIdentity,
          viewportRect: CellRect(origin: .zero, size: CellSize(width: 8, height: 8)),
          contentBounds: CellRect(
            origin: CellPoint(x: -currentOffset.x, y: -currentOffset.y),
            size: CellSize(width: 12, height: 12))
        )
      ]
    )

    #expect(changed == (expectedOffset != currentOffset))
    #expect(offset == expectedOffset)
  }

  @Test(
    "ordinary focus reveal uses the clamped offset after viewport growth",
    arguments: [false, true], [18, 11]
  )
  func focusRevealAfterViewportGrowth(horizontal: Bool, targetCoordinate: Int) {
    let registry = LocalScrollPositionRegistry()
    let scrollIdentity = testIdentity("ResizedScroll")
    let focusedIdentity = testIdentity("ResizedScroll", "Content", "Target")
    // A twenty-cell document scrolled to the end of a four-cell viewport
    // stores 16. Growing the viewport to eight cells places it at 12 while
    // the binding still holds 16. Reveal must use that actual placement.
    var offset = horizontal ? ScrollOffset(x: 16) : ScrollOffset(y: 16)
    registry.register(
      identity: scrollIdentity,
      currentOffset: { offset },
      applyOffset: { offset = $0 }
    )
    let route = ScrollRoute(
      identity: scrollIdentity,
      viewportRect: CellRect(origin: .zero, size: CellSize(width: 8, height: 8)),
      contentBounds: CellRect(
        origin: horizontal ? CellPoint(x: -12, y: 0) : CellPoint(x: 0, y: -12),
        size: horizontal ? CellSize(width: 20, height: 8) : CellSize(width: 8, height: 20))
    )
    let target = CellRect(
      origin: horizontal
        ? CellPoint(x: targetCoordinate - 12, y: 0)
        : CellPoint(x: 0, y: targetCoordinate - 12),
      size: CellSize(width: 1, height: 1)
    )

    let changed = registry.sync(
      focusedIdentity: focusedIdentity,
      focusRegions: [FocusRegion(identity: focusedIdentity, rect: target)],
      scrollRoutes: [route]
    )

    // Row/column 18 is already visible; 11 is immediately before the viewport.
    let expected = targetCoordinate == 18 ? 12 : 11
    #expect(changed)
    #expect(offset == (horizontal ? ScrollOffset(x: expected) : ScrollOffset(y: expected)))
  }

  /// Regression for "wheel scroll stalls partway down, must click to continue":
  /// once a control is focused, focus-reveal must NOT re-assert itself every
  /// frame and drag the offset back when the user scrolls that control out of
  /// view. It is a one-shot response to a focus/cursor change.
  @Test("focus-reveal does not fight a user scroll that moves the focused control out of view")
  func focusRevealDoesNotFightUserScroll() {
    let registry = LocalScrollPositionRegistry()
    let scrollIdentity = testIdentity("Scroll")
    let focusedIdentity = testIdentity("Scroll", "Content", "Button")
    var offset = ScrollOffset.zero
    registry.register(
      identity: scrollIdentity,
      currentOffset: { offset },
      applyOffset: { offset = $0 }
    )

    let viewport = CellRect(origin: .zero, size: .init(width: 10, height: 4))
    // The focused control lives at content row 1. Its on-screen rect is
    // `contentRow - offset.y`; the route's content origin shifts by `-offset.y`.
    func syncFocused(contentRow: Int) -> Bool {
      registry.sync(
        focusedIdentity: focusedIdentity,
        focusRegions: [
          FocusRegion(
            identity: focusedIdentity,
            rect: .init(
              origin: .init(x: 0, y: contentRow - offset.y),
              size: .init(width: 4, height: 1))
          )
        ],
        scrollRoutes: [
          ScrollRoute(
            identity: scrollIdentity,
            viewportRect: viewport,
            contentBounds: .init(
              origin: .init(x: 0, y: -offset.y), size: .init(width: 10, height: 20)))
        ]
      )
    }

    // First sync: the focused control (content row 1) is already visible at
    // offset 0, so no scroll — but the reveal anchor is now recorded.
    #expect(!syncFocused(contentRow: 1))
    #expect(offset == .zero)

    // The user wheels down past the focused control (offset jumps to 5; the
    // control is now four rows above the viewport top).
    offset = ScrollOffset(x: 0, y: 5)
    let changed = syncFocused(contentRow: 1)

    // The fix: reveal must leave the user's offset alone instead of yanking the
    // focused control back into view.
    #expect(!changed)
    #expect(offset == ScrollOffset(x: 0, y: 5))
  }

  /// The other half of the contract: reveal must still fire when focus moves to
  /// a *different* control that is off-screen.
  @Test("focus-reveal still fires when focus changes to a new off-screen control")
  func focusRevealStillFiresOnFocusChange() {
    let registry = LocalScrollPositionRegistry()
    let scrollIdentity = testIdentity("Scroll")
    let firstButton = testIdentity("Scroll", "Content", "ButtonA")
    let secondButton = testIdentity("Scroll", "Content", "ButtonB")
    var offset = ScrollOffset(x: 0, y: 5)
    registry.register(
      identity: scrollIdentity,
      currentOffset: { offset },
      applyOffset: { offset = $0 }
    )
    let viewport = CellRect(origin: .zero, size: .init(width: 10, height: 4))
    let route = ScrollRoute(
      identity: scrollIdentity,
      viewportRect: viewport,
      contentBounds: .init(origin: .init(x: 0, y: -5), size: .init(width: 10, height: 20)))

    // Focus ButtonA (visible) — records its anchor, no scroll.
    _ = registry.sync(
      focusedIdentity: firstButton,
      focusRegions: [
        FocusRegion(
          identity: firstButton,
          rect: .init(origin: .init(x: 0, y: 1), size: .init(width: 4, height: 1)))
      ],
      scrollRoutes: [route]
    )
    #expect(offset == ScrollOffset(x: 0, y: 5))

    // Focus moves to ButtonB, which sits two rows above the viewport top.
    let changed = registry.sync(
      focusedIdentity: secondButton,
      focusRegions: [
        FocusRegion(
          identity: secondButton,
          rect: .init(origin: .init(x: 0, y: -2), size: .init(width: 4, height: 1)))
      ],
      scrollRoutes: [route]
    )
    #expect(changed)
    #expect(offset == ScrollOffset(x: 0, y: 3))
  }

  @Test("scrollTo target below viewport uses the minimum reveal delta")
  func scrollToTargetBelowViewportUsesMinimumRevealDelta() {
    let registry = LocalScrollPositionRegistry()
    let scrollIdentity = testIdentity("Scroll")
    let targetIdentity = testIdentity("Scroll", "Content", "Target")
    var offset = ScrollOffset.zero

    registry.register(
      identity: scrollIdentity,
      currentOffset: { offset },
      applyOffset: { offset = $0 }
    )
    registry.updateGeometry(
      scrollRoutes: [
        ScrollRoute(
          identity: scrollIdentity,
          viewportRect: .init(origin: .zero, size: .init(width: 10, height: 4)),
          contentBounds: .init(origin: .zero, size: .init(width: 10, height: 12))
        )
      ],
      scrollTargets: [
        ScrollTarget(
          identity: targetIdentity,
          scrollIdentity: scrollIdentity,
          rect: .init(origin: .init(x: 0, y: 6), size: .init(width: 4, height: 1))
        )
      ]
    )

    let changed = registry.scrollToTarget(
      .init(identity: targetIdentity),
      anchor: nil,
      scopeIdentity: nil
    )

    #expect(changed)
    #expect(offset == .init(x: 0, y: 3))
  }

  @Test("unanchored scrollTo a visible target preserves the producer's offset")
  func unanchoredScrollToVisibleTargetPreservesProducerOffset() {
    let registry = LocalScrollPositionRegistry()
    let scrollIdentity = testIdentity("Scroll")
    let targetIdentity = testIdentity("Scroll", "Content", "Target")
    var offset = ScrollOffset(x: 0, y: 6)

    registry.register(
      identity: scrollIdentity,
      currentOffset: { offset },
      applyOffset: { offset = $0 },
      // Collections register a resolver for targets outside their placed window.
      revealTarget: { _, _ in nil }
    )
    registry.updateGeometry(
      scrollRoutes: [
        ScrollRoute(
          identity: scrollIdentity,
          viewportRect: CellRect(origin: .zero, size: CellSize(width: 10, height: 8)),
          contentBounds: CellRect(
            origin: CellPoint(x: 0, y: -6), size: CellSize(width: 10, height: 12))
        )
      ],
      scrollTargets: [
        ScrollTarget(
          identity: targetIdentity,
          scrollIdentity: scrollIdentity,
          rect: CellRect(origin: CellPoint(x: 0, y: 2), size: CellSize(width: 4, height: 1))
        )
      ]
    )

    let changed = registry.scrollToTarget(
      ScrollTargetQuery(identity: targetIdentity),
      anchor: nil,
      scopeIdentity: nil
    )

    #expect(!changed)
    #expect(offset == ScrollOffset(x: 0, y: 6))
  }

  @Test("scrollTo target with bottom anchor aligns to the viewport bottom")
  func scrollToTargetBottomAnchorAlignsToViewportBottom() {
    let registry = LocalScrollPositionRegistry()
    let scrollIdentity = testIdentity("Scroll")
    let targetIdentity = testIdentity("Scroll", "Content", "Target")
    var offset = ScrollOffset.zero

    registry.register(
      identity: scrollIdentity,
      currentOffset: { offset },
      applyOffset: { offset = $0 }
    )
    registry.updateGeometry(
      scrollRoutes: [
        ScrollRoute(
          identity: scrollIdentity,
          viewportRect: .init(origin: .zero, size: .init(width: 10, height: 4)),
          contentBounds: .init(origin: .zero, size: .init(width: 10, height: 12))
        )
      ],
      scrollTargets: [
        ScrollTarget(
          identity: targetIdentity,
          scrollIdentity: scrollIdentity,
          rect: .init(origin: .init(x: 0, y: 8), size: .init(width: 4, height: 1))
        )
      ]
    )

    let changed = registry.scrollToTarget(
      .init(identity: targetIdentity),
      anchor: .bottom,
      scopeIdentity: nil
    )

    #expect(changed)
    #expect(offset == .init(x: 0, y: 5))
  }

  @Test("scrollTo target clamps anchored offsets at content edges")
  func scrollToTargetClampsAnchoredOffsetsAtContentEdges() {
    let registry = LocalScrollPositionRegistry()
    let scrollIdentity = testIdentity("Scroll")
    let targetIdentity = testIdentity("Scroll", "Content", "Target")
    var offset = ScrollOffset.zero

    registry.register(
      identity: scrollIdentity,
      currentOffset: { offset },
      applyOffset: { offset = $0 }
    )
    registry.updateGeometry(
      scrollRoutes: [
        ScrollRoute(
          identity: scrollIdentity,
          viewportRect: .init(origin: .zero, size: .init(width: 10, height: 4)),
          contentBounds: .init(origin: .zero, size: .init(width: 10, height: 8))
        )
      ],
      scrollTargets: [
        ScrollTarget(
          identity: targetIdentity,
          scrollIdentity: scrollIdentity,
          rect: .init(origin: .init(x: 0, y: 12), size: .init(width: 4, height: 1))
        )
      ]
    )

    let changed = registry.scrollToTarget(
      .init(identity: targetIdentity),
      anchor: .bottom,
      scopeIdentity: nil
    )

    #expect(changed)
    #expect(offset == .init(x: 0, y: 4))
  }

  @Test("scrollTo missing target is a no-op")
  func scrollToMissingTargetIsNoOp() {
    let registry = LocalScrollPositionRegistry()
    let scrollIdentity = testIdentity("Scroll")
    var offset = ScrollOffset(x: 1, y: 2)

    registry.register(
      identity: scrollIdentity,
      currentOffset: { offset },
      applyOffset: { offset = $0 }
    )
    registry.updateGeometry(
      scrollRoutes: [
        ScrollRoute(
          identity: scrollIdentity,
          viewportRect: .init(origin: .zero, size: .init(width: 10, height: 4)),
          contentBounds: .init(origin: .zero, size: .init(width: 10, height: 12))
        )
      ],
      scrollTargets: []
    )

    let changed = registry.scrollToTarget(
      .init(identity: testIdentity("Missing")),
      anchor: nil,
      scopeIdentity: nil
    )

    #expect(!changed)
    #expect(offset == .init(x: 1, y: 2))
  }

  @Test("focused text input cursor anchor can reveal a descendant scroll route")
  func focusedTextInputCursorAnchorRevealsDescendantScrollRoute() {
    let registry = LocalScrollPositionRegistry()
    let focusedIdentity = testIdentity("TextEditor")
    let scrollIdentity = testIdentity("TextEditor", "ScrollView")
    var offset = ScrollOffset.zero

    registry.register(
      identity: scrollIdentity,
      currentOffset: { offset },
      applyOffset: { offset = $0 }
    )

    let changed = registry.sync(
      focusedIdentity: focusedIdentity,
      focusRegions: [
        FocusRegion(
          identity: focusedIdentity,
          rect: .init(origin: .zero, size: .init(width: 12, height: 5)),
          focusInteractions: .edit
        )
      ],
      scrollRoutes: [
        ScrollRoute(
          identity: scrollIdentity,
          viewportRect: .init(origin: .zero, size: .init(width: 12, height: 4)),
          contentBounds: .init(origin: .zero, size: .init(width: 12, height: 12))
        )
      ],
      accessibilityNodes: [
        AccessibilityNode(
          identity: focusedIdentity,
          rect: .init(origin: .zero, size: .init(width: 12, height: 5)),
          role: .textEditor,
          cursorAnchor: CellPoint(x: 1, y: 8)
        )
      ]
    )

    #expect(changed)
    #expect(offset == .init(x: 0, y: 5))
  }

  @Test("routesWithCurrentOffsets fills the live offset and leaves unregistered routes at zero")
  func routesWithCurrentOffsetsFillsLiveOffset() {
    let registry = LocalScrollPositionRegistry()
    let registered = testIdentity("Scroll")
    let unregistered = testIdentity("Other")
    var offset = ScrollOffset(x: 1, y: 4)

    registry.register(
      identity: registered,
      currentOffset: { offset },
      applyOffset: { offset = $0 }
    )

    let routes = [
      ScrollRoute(
        identity: registered,
        viewportRect: .init(origin: .zero, size: .init(width: 4, height: 3)),
        contentBounds: .init(origin: .zero, size: .init(width: 4, height: 10))
      ),
      ScrollRoute(
        identity: unregistered,
        viewportRect: .init(origin: .zero, size: .init(width: 4, height: 3)),
        contentBounds: .init(origin: .zero, size: .init(width: 4, height: 10))
      ),
    ]

    let enriched = registry.routesWithCurrentOffsets(routes)
    #expect(enriched.count == 2)
    #expect(enriched[0].contentOffset == .init(x: 1, y: 4))
    #expect(enriched[1].contentOffset == .zero)
  }
}
