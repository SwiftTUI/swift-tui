@_spi(Testing) import SwiftTUITestSupport
// Adversarial set B, pass 3: plain ScrollView geometry and commands
// (211–220).
//
// A plain `ScrollView` binds a raw cell offset, exposes keyboard scrolling on
// its own focus region, and resolves proxy commands against its routes. The
// register fixes the shape of those APIs; the module's DocC fixes the key
// semantics (Home returns to the start, End jumps to the far edge, every
// movement clamps). These probes put a two-axis view under Home, write a
// binding past the extent, shrink content under a scrolled offset, send
// proxy commands along a non-scrollable axis, reveal a target wider than the
// viewport, ignore a wheel notch from the view's own handler, and pin the
// page keys, one-row horizontal views, and no-op proxy commands.
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: scroll views", .serialized)
struct AdversarialSetBScrollViewTests {
  @MainActor
  private struct Engine {
    let keys = LocalKeyHandlerRegistry()
    let actions = LocalActionRegistry()
    let scrolls = LocalScrollPositionRegistry()
    let renderer = DefaultRenderer()
    let root: Identity
    var focused: Identity?

    init(_ name: String, focused: Identity? = nil) {
      root = testIdentity("SetBScrollView", name)
      self.focused = focused
    }

    func render<V: View>(_ view: V, width: Int, height: Int) -> RenderSnapshot {
      var environment = EnvironmentValues()
      environment.focusedIdentity = focused
      var context = ResolveContext(
        identity: root, environmentValues: environment, localActionRegistry: actions,
        localKeyHandlerRegistry: keys, applyEnvironmentValues: true)
      context.localScrollPositionRegistry = scrolls
      return renderer.render(view, context: context, proposal: .init(width: width, height: height))
    }
  }

  private func rows(_ count: Int, width: Int? = nil) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(0..<count, id: \.self) { row in
        Text("row \(row)")
      }
    }
  }

  // Home returns a two-axis view to its origin on both axes, even when the
  // vertical offset is already zero.
  @Test func setB211HomeReturnsBothAxesToTheOrigin() {
    let scrollID = testIdentity("SetBScrollView", "twoAxis")
    let box = SetBOffsetBox(ScrollCellOffset(x: 3, y: 0))
    let engine = Engine("Home", focused: scrollID)
    func view() -> some View {
      ScrollView([.horizontal, .vertical], position: box.binding()) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<8, id: \.self) { row in Text("r\(row)-0123456789") }
        }
      }
      .id(scrollID).scrollIndicators(.hidden).frame(width: 5, height: 3)
    }
    _ = engine.render(view(), width: 5, height: 3)
    let fromTop = engine.keys.dispatch(identity: scrollID, keyPress: KeyPress(.home))
    let afterTop = box.value
    box.value = ScrollCellOffset(x: 3, y: 4)
    _ = engine.render(view(), width: 5, height: 3)
    let fromMiddle = engine.keys.dispatch(identity: scrollID, keyPress: KeyPress(.home))
    let afterMiddle = box.value
    withKnownIssue("the vertical Home case shadows the horizontal one, so x is never reset") {
      #expect(fromTop, "Home with y == 0 is still consumed")
      #expect(afterTop == ScrollCellOffset(x: 0, y: 0), "\(afterTop)")
      #expect(afterMiddle == ScrollCellOffset(x: 0, y: 0), "\(afterMiddle)")
    }
    #expect(fromMiddle, "Home with y > 0 is consumed")
    #expect(afterMiddle.y == 0, "\(afterMiddle)")
  }

  // A binding written past the extent publishes the clamped offset, and the
  // first reverse arrow moves the view by one row.
  @Test func setB212BindingPastTheExtentPublishesTheClampedOffset() throws {
    let scrollID = testIdentity("SetBScrollView", "past")
    let box = SetBOffsetBox(.zero)
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBScrollView", "PastExtent"), size: .init(width: 20, height: 8)
    ) {
      ScrollView(.vertical, position: box.binding()) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<20, id: \.self) { row in Text("row \(row)") }
        }
      }
      .id(scrollID).scrollIndicators(.hidden).frame(width: 10, height: 5)
    }
    defer { h.shutdown() }
    box.value.y = 50
    _ = try h.renderAfterExternalMutation()
    #expect(h.frame.contains("row 15") && h.frame.contains("row 19"), "\(h.frame)")
    let registry = h.runLoop.localScrollPositionRegistry
    let published = registry.routesWithCurrentOffsets(h.runLoop.latestSemanticSnapshot.scrollRoutes)
      .first?.contentOffset.y
    _ = try h.focus(scrollID)
    _ = try h.pressKey(KeyPress(.arrowUp))
    let afterFirstUp = h.frame
    withKnownIssue(
      "the raw binding is published and the first key only brings it back inside the extent (adjacent to STUI-999)"
    ) {
      #expect(published == 15, "\(String(describing: published))")
      #expect(afterFirstUp.contains("row 14"), "\(afterFirstUp)")
    }
    _ = try h.pressKey(KeyPress(.arrowUp))
    #expect(h.frame.contains("row 13") || h.frame.contains("row 14"), "\(h.frame)")
  }

  // Shrinking the content below the current offset re-clamps the binding
  // for a plain stack as it does for a lazy one.
  @Test func setB213ContentShrinkReclampsTheBinding() throws {
    for lazy in [false, true] {
      let box = SetBOffsetBox(.zero)
      let scrollID = testIdentity("SetBScrollView", "shrink-\(lazy)")
      let h = try StressRuntimeHarness(
        rootIdentity: testIdentity("SetBScrollView", "Shrink-\(lazy)"),
        size: .init(width: 20, height: 8)
      ) {
        SetBShrinkingList(lazy: lazy, box: box, scrollID: scrollID)
      }
      defer { h.shutdown() }
      _ = try h.focus(scrollID)
      _ = try h.pressKey(KeyPress(.end))
      try #require(box.value.y == 15, "lazy=\(lazy): \(box.value)")
      _ = try h.pressKey(KeyPress(.character("h"), modifiers: .ctrl))
      try #require(
        h.frame.contains("row 7") && !h.frame.contains("row 8"), "lazy=\(lazy): \(h.frame)")
      let afterShrink = box.value.y
      _ = try h.focus(scrollID)
      _ = try h.pressKey(KeyPress(.arrowUp))
      let frame = h.frame
      withKnownIssue(
        "neither stack writes the clamp back: the binding keeps the stale offset and the first arrow is absorbed by it (adjacent to STUI-999)"
      ) {
        #expect(afterShrink == 3, "lazy=\(lazy): \(afterShrink)")
        #expect(frame.contains("row 2"), "lazy=\(lazy): \(frame)")
      }
    }
  }

  // Proxy commands never move the axis a single-axis view cannot scroll.
  @Test func setB214ProxyCommandsIgnoreTheNonScrollableAxis() {
    let scrollID = testIdentity("SetBScrollView", "vertical")
    let trailingID = testIdentity("SetBScrollView", "trailing")
    let xID = testIdentity("SetBScrollView", "x3")
    let box = SetBOffsetBox(.zero)
    let result = SetBResultBox()
    let engine = Engine("Proxy")
    func view() -> some View {
      ScrollViewReader { proxy in
        VStack(alignment: .leading) {
          ScrollView(.vertical, position: box.binding()) {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<10, id: \.self) { row in Text("row \(row)") }
            }
            .frame(width: 20)
          }
          .scrollIndicators(.hidden).frame(width: 6, height: 3).id(scrollID)
          Button("Trailing") { result.value = proxy.scrollTo(edge: .trailing) }.id(trailingID)
          Button("X3") { result.value = proxy.scrollTo(x: 3) }.id(xID)
        }
      }
    }
    let before = engine.render(view(), width: 20, height: 6).rasterSurface.lines
    _ = engine.actions.dispatch(identity: trailingID)
    let trailingResult = result.value
    let afterTrailing = engine.render(view(), width: 20, height: 6).rasterSurface.lines
    let xAfterTrailing = box.value.x
    _ = engine.actions.dispatch(identity: xID)
    let xResult = result.value
    withKnownIssue(
      "edge and offset commands clamp against the content bounds without consulting the view's axes"
    ) {
      #expect(
        trailingResult == false,
        "scrollTo(edge: .trailing) reported \(String(describing: trailingResult))")
      #expect(xAfterTrailing == 0, "\(xAfterTrailing)")
      #expect(xResult == false, "scrollTo(x: 3) reported \(String(describing: xResult))")
      #expect(box.value.x == 0, "\(box.value)")
    }
    #expect(afterTrailing == before, "the pixels never move on the vertical-only view")
  }

  // Revealing a target wider than the viewport keeps its start visible; a
  // minimal movement never scrolls past the target's leading edge.
  @Test func setB215RevealingAWideTargetKeepsItsStartVisible() {
    let box = SetBOffsetBox(.zero)
    let jumpID = testIdentity("SetBScrollView", "jump")
    let engine = Engine("Reveal")
    func view() -> some View {
      ScrollViewReader { proxy in
        VStack(alignment: .leading) {
          ScrollView([.horizontal, .vertical], position: box.binding()) {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<8, id: \.self) { row in Text("r\(row)-0123456789").id("row\(row)") }
            }
          }
          .scrollIndicators(.hidden).frame(width: 6, height: 3)
          Button("Jump") { _ = proxy.scrollTo("row5") }.id(jumpID)
        }
      }
    }
    _ = engine.render(view(), width: 20, height: 6)
    _ = engine.actions.dispatch(identity: jumpID)
    let after = engine.render(view(), width: 20, height: 6).rasterSurface.lines
    withKnownIssue("the horizontal reveal has no width guard and aligns the target's trailing end")
    {
      #expect(box.value == ScrollCellOffset(x: 0, y: 3), "\(box.value)")
      #expect(after.first?.hasPrefix("r5-012") == true, "\(after)")
    }
    #expect(box.value.y == 3, "\(box.value)")
  }

  // An `onScrollWheel` handler on the scroll view itself that returns
  // `.ignored` lets the view scroll.
  @Test func setB216IgnoredWheelHandlerOnTheScrollViewLetsItScroll() throws {
    let box = SetBOffsetBox(.zero)
    let events = SetBResultBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBScrollView", "Wheel"), size: .init(width: 20, height: 6)
    ) {
      ScrollView(.vertical, position: box.binding()) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<8, id: \.self) { row in Text("row \(row)") }
        }
      }
      .onScrollWheel { event in
        events.count += 1
        return .ignored
      }
      .scrollIndicators(.hidden).frame(width: 20, height: 3)
    }
    defer { h.shutdown() }
    let point = try #require(h.point(forText: "row 1"))
    _ = try h.scrollPointer(at: point, deltaY: 1)
    withKnownIssue(
      "the modifier occupies the scroll body's pointer route, so an ignored notch reaches no scroller"
    ) {
      #expect(events.count == 1, "\(events.count)")
      #expect(box.value.y == 1, "\(box.value)")
      #expect(h.frame.contains("row 3"), "\(h.frame)")
    }
  }

  // A one-row horizontal scroll view shows its content; the indicator track
  // never consumes the only row.
  @Test func setB217OneRowHorizontalScrollViewShowsContent() {
    let engine = Engine("OneRow")
    let snapshot = engine.render(
      ScrollView(.horizontal) { Text("0123456789") }.frame(width: 5, height: 1), width: 5, height: 1
    )
    let line = snapshot.rasterSurface.lines.first ?? ""
    withKnownIssue(
      "the horizontal indicator reserves the bottom row, leaving a zero-height content viewport"
    ) {
      #expect(line.contains("01234"), "\(snapshot.rasterSurface.lines)")
    }
    let hidden = engine.render(
      ScrollView(.horizontal) { Text("0123456789") }.scrollIndicators(.hidden).frame(
        width: 5, height: 1),
      width: 5, height: 1)
    #expect(
      hidden.rasterSurface.lines.first?.contains("01234") == true, "\(hidden.rasterSurface.lines)")
  }

  // Page Down and Page Up page a focused scroll view by one viewport less a
  // row, as the assistive paging already does.
  @Test func setB218PageKeysPageAFocusedScrollView() {
    let scrollID = testIdentity("SetBScrollView", "paging")
    let box = SetBOffsetBox(.zero)
    let engine = Engine("Paging", focused: scrollID)
    func view() -> some View {
      ScrollView(.vertical, position: box.binding()) { rows(12) }
        .id(scrollID).scrollIndicators(.hidden).frame(width: 8, height: 4)
    }
    _ = engine.render(view(), width: 8, height: 4)
    let down = engine.keys.dispatch(identity: scrollID, keyPress: KeyPress(.pageDown))
    let afterDown = box.value.y
    box.value.y = 8
    _ = engine.render(view(), width: 8, height: 4)
    let up = engine.keys.dispatch(identity: scrollID, keyPress: KeyPress(.pageUp))
    let afterUp = box.value.y
    withKnownIssue("the key handler has no page cases; Page keys bubble unconsumed") {
      #expect(down, "PageDown consumed")
      #expect(afterDown == 3, "\(afterDown)")
      #expect(up, "PageUp consumed")
      #expect(afterUp == 5, "\(afterUp)")
    }
    #expect(
      engine.keys.dispatch(identity: scrollID, keyPress: KeyPress(.arrowUp)),
      "an arrow from the end is consumed")
    #expect(box.value.y == 7, "\(box.value)")
  }

  // Unresolved and no-op proxy commands report false and leave the offset.
  @Test func setB219UnresolvedProxyCommandsReportFalse() {
    let box = SetBOffsetBox(.zero)
    let result = SetBResultBox()
    let missingID = testIdentity("SetBScrollView", "missing")
    let bottomID = testIdentity("SetBScrollView", "bottom")
    let anchoredID = testIdentity("SetBScrollView", "anchored")
    let engine = Engine("NoOps")
    func view() -> some View {
      ScrollViewReader { proxy in
        VStack(alignment: .leading) {
          ScrollView(.vertical, position: box.binding()) {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<3, id: \.self) { row in Text("row \(row)").id("row\(row)") }
            }
          }
          .scrollIndicators(.hidden).frame(width: 10, height: 5)
          Button("Missing") { result.value = proxy.scrollTo("missing") }.id(missingID)
          Button("Bottom") { result.value = proxy.scrollTo(edge: .bottom) }.id(bottomID)
          Button("Anchored") { result.value = proxy.scrollTo("row2", anchor: .bottom) }.id(
            anchoredID)
        }
      }
    }
    _ = engine.render(view(), width: 20, height: 8)
    for identity in [missingID, bottomID, anchoredID] {
      result.value = nil
      _ = engine.actions.dispatch(identity: identity)
      #expect(result.value == false, "\(identity): \(String(describing: result.value))")
      #expect(box.value == .zero, "\(identity): \(box.value)")
    }
  }

  // Content exactly the viewport height neither scrolls nor reserves an
  // indicator track, and a wheel notch bubbles to an enclosing handler.
  @Test func setB220ContentExactlyTheViewportHeightDoesNotScroll() throws {
    let scrollID = testIdentity("SetBScrollView", "exact")
    let engine = Engine("Exact", focused: scrollID)
    for visibility in [ScrollIndicatorVisibility.automatic, .visible] {
      let snapshot = engine.render(
        ScrollView(.vertical) { rows(5) }.id(scrollID).scrollIndicators(visibility).frame(
          width: 10, height: 5),
        width: 10, height: 5)
      let route = try #require(snapshot.semanticSnapshot.scrollRoutes.first, "\(visibility)")
      #expect(route.viewportRect.size.width == 10, "\(visibility): \(route.viewportRect)")
      #expect(
        snapshot.rasterSurface.lines.allSatisfy { !$0.contains("▂") && !$0.contains("█") },
        "\(visibility): \(snapshot.rasterSurface.lines)")
    }
    #expect(!engine.keys.dispatch(identity: scrollID, keyPress: KeyPress(.arrowDown)))

    let outer = SetBResultBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBScrollView", "ExactWheel"), size: .init(width: 20, height: 6)
    ) {
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<5, id: \.self) { row in Text("row \(row)") }
        }
      }
      .frame(width: 10, height: 5)
      .onScrollWheel { _ in
        outer.count += 1
        return .handled
      }
    }
    defer { h.shutdown() }
    let point = try #require(h.point(forText: "row 1"))
    _ = try h.scrollPointer(at: point, deltaY: 1)
    #expect(outer.count == 1, "\(outer.count)")
  }
}

@MainActor
private final class SetBOffsetBox {
  var value: ScrollCellOffset

  init(_ value: ScrollCellOffset) {
    self.value = value
  }

  func binding() -> Binding<ScrollCellOffset> {
    Binding(get: { self.value }, set: { self.value = $0 })
  }
}

@MainActor
private final class SetBResultBox {
  var value: Bool?
  var count = 0
}

@MainActor
private struct SetBShrinkingList: View {
  let lazy: Bool
  let box: SetBOffsetBox
  let scrollID: Identity
  @State private var count = 20

  var body: some View {
    ScrollView(.vertical, position: box.binding()) {
      if lazy {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<count, id: \.self) { row in Text("row \(row)") }
        }
      } else {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<count, id: \.self) { row in Text("row \(row)") }
        }
      }
    }
    .id(scrollID).scrollIndicators(.hidden).frame(width: 10, height: 5)
    .onKeyPress(.character("h"), modifiers: .ctrl) { _ in
      count = 8
      return .handled
    }
  }
}
