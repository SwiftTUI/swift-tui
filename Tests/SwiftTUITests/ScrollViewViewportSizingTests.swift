import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct ScrollViewViewportSizingTests {
  private func render(_ view: some View, width: Int = 20, height: Int = 10) -> RenderSnapshot {
    DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("ScrollViewportSizing")),
      proposal: .init(width: width, height: height)
    )
  }

  @Test(
    "STUI-489: finite scroll viewports fill independently of content", arguments: [0, 2, 10, 15])
  func finiteViewport(count: Int) throws {
    for lazy in [false, true] {
      for spacer in [false, true] {
        let snapshot = render(
          ScrollView { ViewportRows(count: count, lazy: lazy, spacer: spacer) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        let route = try #require(snapshot.semanticSnapshot.scrollRoutes.first)
        #expect(route.viewportRect.origin == .zero)
        #expect(route.viewportRect.size == .init(width: count > 10 ? 19 : 20, height: 10))
        #expect(route.contentBounds.origin == .zero)
        if count > 0 {
          #expect(snapshot.rasterSurface.lines[0].hasPrefix("Row 0"))
          #expect(snapshot.rasterSurface.lines[1].hasPrefix("Row 1"))
        }
        if count <= 10 {
          #expect(route.contentBounds.size.height == count)
        }
      }
    }
  }

  @Test("STUI-489: horizontal and bidirectional short content starts at the viewport origin")
  func otherAxes() throws {
    for axes: SwiftTUIViews.Axis.Set in [.horizontal, [.horizontal, .vertical]] {
      let snapshot = render(
        ScrollView(axes) { Text("AB") }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      )
      let route = try #require(snapshot.semanticSnapshot.scrollRoutes.first)
      #expect(route.viewportRect == .init(origin: .zero, size: .init(width: 20, height: 10)))
      #expect(route.contentBounds == .init(origin: .zero, size: .init(width: 2, height: 1)))
      #expect(snapshot.rasterSurface.lines[0] == "AB")
    }
  }

  @Test("STUI-489: an unframed scroll view absorbs the remaining stack height")
  func verticalSiblings() throws {
    let snapshot = render(
      VStack(spacing: 0) {
        Text("Header")
        ScrollView { ViewportRows(count: 2) }
        Text("Footer")
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    )
    let route = try #require(snapshot.semanticSnapshot.scrollRoutes.first)
    #expect(route.viewportRect.origin.y == 1)
    #expect(route.viewportRect.size.height == 8)
    #expect(snapshot.rasterSurface.lines[0].contains("Header"))
    #expect(snapshot.rasterSurface.lines[1].hasPrefix("Row 0"))
    #expect(snapshot.rasterSurface.lines[9].contains("Footer"))
  }

  @Test("STUI-489: an unframed horizontal scroll view absorbs the remaining stack width")
  func horizontalSiblings() throws {
    let snapshot = render(
      HStack(spacing: 0) {
        Text("L")
        ScrollView(.horizontal) { Text("AB") }
        Text("R")
      }.frame(maxWidth: .infinity, maxHeight: .infinity),
      height: 1
    )
    let route = try #require(snapshot.semanticSnapshot.scrollRoutes.first)
    #expect(route.viewportRect.origin.x == 1)
    #expect(route.viewportRect.size.width == 18)
    #expect(snapshot.rasterSurface.lines.contains { $0.hasPrefix("LAB") && $0.hasSuffix("R") })
  }

  @Test("STUI-489: recordings composition fills between toolbar and bottom inset")
  func recordingsComposition() throws {
    let snapshot = render(
      Panel(id: "Root") {
        NavigationStack {
          ScrollView { ViewportRows(count: 2, lazy: true, spacer: true) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) { Text("Search / REC") }
            .navigationTitle("Recordings")
        }.toolbar().toolbarStyle(.defaultTop)
      }
    )
    let route = try #require(snapshot.semanticSnapshot.scrollRoutes.first)
    #expect(route.viewportRect.origin.y == 1)
    #expect(route.viewportRect.size.height == 8)
    #expect(snapshot.rasterSurface.lines[0].contains("Recordings"))
    #expect(snapshot.rasterSurface.lines[1].hasPrefix("Row 0"))
    #expect(snapshot.rasterSurface.lines[9].contains("Search / REC"))
  }

  @Test("Explicit scroll sizing constraints still bound stack allocation", arguments: 0..<5)
  func constraints(kind: Int) throws {
    @ViewBuilder func content() -> some View {
      let scroll = ScrollView { ViewportRows(count: 2) }
      switch kind {
      case 0: scroll.frame(height: 3)
      case 1: scroll.fixedSize(horizontal: false, vertical: true)
      case 2: scroll.frame(minHeight: 3)
      case 3: scroll.frame(idealHeight: 4)
      default: scroll.frame(maxHeight: 5)
      }
    }
    let snapshot = render(
      VStack(spacing: 0) {
        content()
        Spacer(minLength: 0)
        Text("Footer")
      }
    )
    let route = try #require(snapshot.semanticSnapshot.scrollRoutes.first)
    #expect(route.viewportRect.size.height == [3, 2, 3, 4, 5][kind])
    #expect(snapshot.rasterSurface.lines[9].contains("Footer"))
  }

  @Test("Multiple scroll views share spare space and honor layout priority")
  func flexibleSiblings() throws {
    for priority in [0.0, 1.0] {
      let snapshot = render(
        VStack(spacing: 0) {
          ScrollView { Text("First") }.layoutPriority(priority)
          ScrollView { Text("Second") }
        }
      )
      let routes = snapshot.semanticSnapshot.scrollRoutes.sorted {
        $0.viewportRect.origin.y < $1.viewportRect.origin.y
      }
      #expect(routes.count == 2)
      #expect(routes.map(\.viewportRect.size.height) == (priority == 0 ? [5, 5] : [10, 0]))
    }
  }

  @Test("Scroll expansion participates in cross-axis reconciliation without overriding fixedSize")
  func crossAxisReconciliation() throws {
    for fixed in [false, true] {
      let snapshot = DefaultRenderer().render(
        HStack(spacing: 0) {
          ScrollView { Text("Row") }.fixedSize(horizontal: false, vertical: fixed)
          Text("Tall").frame(height: 6)
        },
        context: .init(identity: testIdentity("ViewportCrossAxis")),
        proposal: .init(width: .finite(20), height: .unspecified)
      )
      let route = try #require(snapshot.semanticSnapshot.scrollRoutes.first)
      #expect(route.viewportRect.size.height == (fixed ? 1 : 6))
    }
  }

  @Test("Ordinary custom layouts remain content-sized")
  func ordinaryCustomLayout() throws {
    let snapshot = render(
      VStack(spacing: 0) {
        ViewportPassthroughLayout { Text("Rigid") }
        Spacer(minLength: 0)
        Text("Footer")
      }
    )
    let custom = try #require(snapshot.measuredTree.childMeasurements.first)
    #expect(custom.measuredSize.height == 1)
    #expect(snapshot.rasterSurface.lines[9].contains("Footer"))
  }

  @Test("Inset and indicator reservations are subtracted once", arguments: [false, true])
  func insets(reservesSpace: Bool) throws {
    for count in [2, 15] {
      let snapshot = render(
        ScrollView([.horizontal, .vertical]) {
          ViewportRows(count: count).frame(width: 25)
        }.scrollViewStyle(ConsumerScrollViewStyle(reservesSpace: reservesSpace))
      )
      let route = try #require(snapshot.semanticSnapshot.scrollRoutes.first)
      #expect(snapshot.measuredTree.measuredSize == .init(width: 20, height: 10))
      #expect(route.viewportRect.origin == .init(x: 1, y: 1))
      #expect(route.viewportRect.size.width == (reservesSpace && count > 8 ? 17 : 18))
      #expect(route.viewportRect.size.height == (reservesSpace ? 7 : 8))
      #expect(snapshot.rasterSurface.lines[1].contains("Row 0"))
    }
  }

  @Test("Retained data changes, resizing, wheel input, and touch panning keep viewport geometry")
  func liveChanges() throws {
    for lazy in [false, true] {
      let harness = try StressRuntimeHarness(
        rootIdentity: testIdentity("ViewportChanges"), size: .init(width: 40, height: 14),
        pointerInputCapabilities: .init(supportsScrollPanning: true)
      ) { ViewportChanges(lazy: lazy) }
      defer { harness.shutdown() }
      func route() throws -> ScrollRoute {
        try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first)
      }
      #expect(try route().viewportRect.size.height == 10)
      _ = try harness.clickText("Short")
      #expect(try route().contentBounds.origin.y == route().viewportRect.origin.y)
      #expect(try route().viewportRect.size.height == 10)
      // Input in the blank remainder still belongs to the full scroll body.
      _ = try harness.scrollPointer(at: .init(x: 2, y: 9), deltaY: 100)
      #expect(try route().contentBounds.origin.y == route().viewportRect.origin.y)
      _ = try harness.clickText("Long")
      _ = try harness.scrollPointer(at: .init(x: 2, y: 9), deltaY: 100)
      #expect(try route().contentBounds.maxY == route().viewportRect.maxY)
      _ = try harness.clickText("Resize")
      #expect(try route().viewportRect.size.height == 12)
      #expect(try route().contentBounds.maxY == route().viewportRect.maxY)
      _ = try harness.clickText("Short")
      #expect(try route().contentBounds.origin.y == route().viewportRect.origin.y)
      #expect(try route().viewportRect.size.height == 12)
      _ = try harness.clickText("Empty")
      #expect(try route().viewportRect.size.height == 12)
      _ = try harness.clickText("Long")
      _ = try harness.scrollPointer(at: .init(x: 2, y: 9), deltaY: -100)
      #expect(try route().contentBounds.origin.y == route().viewportRect.origin.y)
      _ = try harness.sendMouse(.down(.primary), at: .init(x: 2, y: 9))
      _ = try harness.sendMouse(.dragged(.primary), at: .init(x: 2, y: 6))
      #expect(try route().contentBounds.origin.y == route().viewportRect.origin.y - 3)
      // Assert before release, which may schedule momentum.
      _ = try harness.sendMouse(.up(.primary), at: .init(x: 2, y: 6))
    }
  }
}

private struct ViewportPassthroughLayout: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void)
    -> LayoutSize
  {
    subviews[0].sizeThatFits(proposal)
  }

  func placeSubviews(
    in bounds: LayoutRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void
  ) {
    subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: proposal)
  }
}

@MainActor
private struct ViewportChanges: View {
  var lazy: Bool
  @State private var count = 0
  @State private var height = 10

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 1) {
        Button("Empty") { count = 0 }
        Button("Short") { count = 2 }
        Button("Long") { count = 15 }
        Button("Resize") { height = 12 }
      }.buttonStyle(.plain)
      ScrollView { ViewportRows(count: count, lazy: lazy) }
    }.frame(width: 40, height: height + 1)
  }
}

@MainActor
private struct ViewportRows: View {
  var count: Int
  var lazy = false
  var spacer = false

  @ViewBuilder private var rows: some View {
    ForEach(0..<count, id: \.self) { row in
      Text("Row \(row)").frame(maxWidth: .infinity, alignment: .leading)
    }
    if spacer { Spacer() }
  }

  var body: some View {
    if lazy {
      LazyVStack(spacing: 0) { rows }
    } else {
      VStack(spacing: 0) { rows }
    }
  }
}
