import Testing

@testable import SwiftTUICore

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
