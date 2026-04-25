import Testing

@testable import Core

@MainActor
@Suite
struct LocalScrollPositionRegistryTests {
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
}
