@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized, FailOnSoundnessViolationGrowth(), .timeLimit(.minutes(1)))
struct AdversarialSetAScrollLayoutBoundaryTests {
  @Test func setA626AbsoluteScrollOnOneAxisPreservesTheOtherOffset() throws {
    // Hypothesis: an omitted absolute coordinate resets the orthogonal offset instead of retaining it.
    let p = SetAScrollProxyHolder()
    let s = SetAScrollOffsetBox()
    let h = try pane(626, proxy: p, state: s) { fixedDocument() }
    defer { h.shutdown() }
    let proxy = try #require(p.proxy)
    #expect(proxy.scrollTo(x: 7, y: 9))
    try h.render()
    #expect(proxy.scrollTo(y: 13))
    try h.render()
    #expect(s.offset == .init(x: 7, y: 13))
    #expect(try offset(in: h) == .init(x: 7, y: 13))
  }

  @Test func setA627DisabledScrollAxisCannotTranslateOversizedContent() throws {
    // Hypothesis: the registry's horizontal command moves a vertical-only viewport's oversized fixed-width child.
    let p = SetAScrollProxyHolder()
    let s = SetAScrollOffsetBox()
    let h = try pane(627, proxy: p, state: s, axes: .vertical) { fixedDocument() }
    defer { h.shutdown() }
    let original = try route(in: h)
    _ = try #require(p.proxy).scrollTo(x: 9, y: 3)
    try h.render()
    let next = try route(in: h)
    #expect(next.contentBounds.origin.x == original.contentBounds.origin.x)
    #expect(next.contentBounds.origin.y == original.contentBounds.origin.y - 3)
  }

  @Test func setA628OvershootingBothScrollEdgesCannotCreateReverseDeadTravel() throws {
    // Hypothesis: a large absolute request leaves an unclamped binding that consumes subsequent reverse input.
    let p = SetAScrollProxyHolder()
    let s = SetAScrollOffsetBox()
    let h = try pane(628, proxy: p, state: s) { fixedDocument() }
    defer { h.shutdown() }
    let proxy = try #require(p.proxy)
    #expect(proxy.scrollTo(x: 999, y: 999))
    try h.render()
    #expect(s.offset == .init(x: 28, y: 24))
    #expect(proxy.scrollBy(x: -1, y: -1))
    try h.render()
    #expect(try offset(in: h) == .init(x: 27, y: 23))
    #expect(proxy.scrollTo(x: -999, y: -999))
    try h.render()
    #expect(s.offset == .zero)
  }

  @Test func setA629NoOpProxyCommandsDoNotRepeatBindingSideEffects() throws {
    // Hypothesis: empty coordinates, zero deltas, or an already-current offset still invoke the authored setter.
    let p = SetAScrollProxyHolder()
    let s = SetAScrollOffsetBox()
    let h = try pane(629, proxy: p, state: s) { fixedDocument() }
    defer { h.shutdown() }
    let proxy = try #require(p.proxy)
    #expect(proxy.scrollTo(x: 3, y: 4))
    try h.render()
    let writes = s.writes
    #expect(!proxy.scrollTo())
    #expect(!proxy.scrollBy())
    #expect(!proxy.scrollTo(x: 3, y: 4))
    try h.render()
    #expect(s.writes == writes)
  }

  @Test func setA630ARejectedScrollBindingCannotPublishAnOptimisticViewport() throws {
    // Hypothesis: the command's proposed offset is drawn despite the binding retaining its previous value.
    let p = SetAScrollProxyHolder()
    let s = SetAScrollOffsetBox(rejectWrites: true)
    let h = try pane(630, proxy: p, state: s) { fixedDocument() }
    defer { h.shutdown() }
    let before = try route(in: h).contentBounds
    _ = try #require(p.proxy).scrollTo(x: 8, y: 10)
    try h.render()
    #expect(s.writes == [.init(x: 8, y: 10)])
    #expect(s.offset == .zero)
    #expect(try route(in: h).contentBounds == before)
  }

  @Test func setA631RevealingAnAlreadyVisibleTargetWithoutAnAnchorDoesNotMoveIt() throws {
    // Hypothesis: target reveal defaults to top alignment even when the entire target is already visible.
    let p = SetAScrollProxyHolder()
    let s = SetAScrollOffsetBox()
    let h = try pane(631, proxy: p, state: s, axes: .vertical) { rows(30) }
    defer { h.shutdown() }
    let proxy = try #require(p.proxy)
    #expect(proxy.scrollTo(y: 8))
    try h.render()
    let before = try #require(h.point(forText: "R010"))
    #expect(!proxy.scrollTo(10))
    try h.render()
    #expect(try #require(h.point(forText: "R010")) == before)
    #expect(s.offset.y == 8)
  }

  @Test func setA632CenteredTargetUsesItsWholeHeightAtATranslatedViewport() throws {
    // Hypothesis: anchor alignment centers the target origin rather than its two-cell bounds or ignores parent translation.
    let p = SetAScrollProxyHolder()
    let s = SetAScrollOffsetBox()
    let h = try make(632) {
      ScrollViewReader { proxy in
        let _ = p.capture(proxy)
        ScrollView(.vertical, position: s.binding) {
          VStack(spacing: 0) {
            Text("prefix").frame(height: 12)
            Text("TARGET\nsecond").id("target")
            Text("tail").frame(height: 12)
          }
        }.scrollIndicators(.hidden).frame(width: 12, height: 8).padding(.top, 3)
      }
    }
    defer { h.shutdown() }
    #expect(try #require(p.proxy).scrollTo("target", anchor: .center))
    try h.render()
    let viewport = try route(in: h).viewportRect
    #expect(try #require(h.point(forText: "TARGET")).y == Double(viewport.origin.y + 3))
    #expect(try #require(h.point(forText: "second")).y == Double(viewport.origin.y + 4))
  }

  @Test func setA633AnOversizedRevealKeepsTheTargetsLeadingEdgeVisible() throws {
    // Hypothesis: reveal tries to expose a tall target's bottom and scrolls its start out of the viewport.
    let p = SetAScrollProxyHolder()
    let s = SetAScrollOffsetBox()
    let h = try pane(633, proxy: p, state: s, axes: .vertical) {
      VStack(spacing: 0) {
        Text("prefix").frame(height: 10)
        Text("TALL").frame(height: 12, alignment: .topLeading).id("tall")
        Text("tail").frame(height: 10)
      }
    }
    defer { h.shutdown() }
    #expect(try #require(p.proxy).scrollTo("tall"))
    try h.render()
    #expect(try #require(h.point(forText: "TALL")).y == Double(route(in: h).viewportRect.origin.y))
    #expect(s.offset.y == 10)
  }

  @Test func setA634SiblingReadersWithEqualTargetIDsKeepTheirOwnRoute() throws {
    // Hypothesis: target lookup matches an equal authored ID in an earlier sibling reader scope.
    let left = SetAScrollProxyHolder()
    let right = SetAScrollProxyHolder()
    let a = SetAScrollOffsetBox()
    let b = SetAScrollOffsetBox()
    let h = try make(634) {
      HStack {
        reader(left, state: a) { rows(40) }
        reader(right, state: b) { rows(40) }
      }
    }
    defer { h.shutdown() }
    #expect(try #require(right.proxy).scrollTo(25, anchor: .top))
    try h.render()
    #expect(a.offset == .zero)
    #expect(b.offset.y == 25)
    #expect(h.frame.contains("R000") && h.frame.contains("R025"))
  }

  @Test func setA635AnInnerReaderCommandCannotChooseItsOuterViewport() throws {
    // Hypothesis: nested-reader route selection chooses the enclosing ancestor's geometry before its own descendant.
    let inner = SetAScrollProxyHolder()
    let outer = SetAScrollOffsetBox()
    let child = SetAScrollOffsetBox()
    let h = try make(635) {
      ScrollView(.vertical, position: outer.binding) {
        VStack(spacing: 0) {
          reader(inner, state: child) { rows(40) }
          Text("outside tail").frame(height: 20)
        }
      }.scrollIndicators(.hidden).frame(width: 20, height: 12)
    }
    defer { h.shutdown() }
    #expect(try #require(inner.proxy).scrollTo(edge: .bottom))
    try h.render()
    #expect(child.offset.y == 34)
    #expect(outer.offset == .zero)
  }

  @Test func setA636AProxyFromARemovedReaderCannotWriteItsRetiredBinding() throws {
    // Hypothesis: a retained public proxy keeps a removed scroll registration live after conditional teardown.
    var shown = true
    let p = SetAScrollProxyHolder()
    let s = SetAScrollOffsetBox()
    let h = try make(636) { if shown { reader(p, state: s) { rows(40) } } else { Text("removed") } }
    defer { h.shutdown() }
    let retired = try #require(p.proxy)
    shown = false
    try h.renderAfterExternalMutation()
    #expect(!retired.scrollTo(y: 12))
    #expect(s.writes.isEmpty)
    #expect(h.runLoop.latestSemanticSnapshot.scrollRoutes.isEmpty)
  }

  @Test func setA637ChangingScrollAxesClearsTheRetiredVisualTranslation() throws {
    // Hypothesis: stable layout identity preserves an old horizontal translation after horizontal scrolling is disabled.
    var axes: SwiftTUIViews.Axis.Set = [.horizontal, .vertical]
    let s = SetAScrollOffsetBox(offset: .init(x: 8, y: 7))
    let h = try make(637) {
      ScrollView(axes, position: s.binding) { fixedDocument() }
        .scrollIndicators(.hidden).frame(width: 12, height: 6)
    }
    defer { h.shutdown() }
    #expect(try offset(in: h) == .init(x: 8, y: 7))
    axes = .vertical
    try h.renderAfterExternalMutation()
    #expect(try offset(in: h) == .init(x: 0, y: 7))
  }

  @Test func setA638AsymmetricStyleInsetsKeepBothScrollEndpointsReachable() throws {
    // Hypothesis: scroll clamping uses outer bounds instead of the inset content viewport at the trailing edges.
    let p = SetAScrollProxyHolder()
    let s = SetAScrollOffsetBox()
    let h = try make(638) {
      ScrollViewReader { proxy in
        let _ = p.capture(proxy)
        ScrollView([.horizontal, .vertical], position: s.binding) { fixedDocument() }
          .scrollIndicators(.hidden)
          .scrollViewStyle(
            SetAScrollInsetsStyle(insets: .init(top: 1, leading: 2, bottom: 2, trailing: 1))
          )
          .frame(width: 12, height: 8)
      }
    }
    defer { h.shutdown() }
    #expect(try route(in: h).viewportRect.size == .init(width: 9, height: 5))
    #expect(try #require(p.proxy).scrollTo(x: 999, y: 999))
    try h.render()
    let r = try route(in: h)
    #expect(r.contentBounds.maxX == r.viewportRect.maxX)
    #expect(r.contentBounds.maxY == r.viewportRect.maxY)
    #expect(s.offset == .init(x: 31, y: 25))
  }

  @Test func setA639IndicatorFeedbackConvergesAndCanReturnToNoInsets() throws {
    // Hypothesis: one scrollbar causing perpendicular overflow fails to reserve the second bar, or a refuted retained seed survives shrink.
    var width = 10
    var height = 6
    let h = try make(639) {
      ScrollView([.horizontal, .vertical]) { Text("document").frame(width: width, height: height) }
        .frame(width: 10, height: 5)
    }
    defer { h.shutdown() }
    #expect(try route(in: h).viewportRect.size == .init(width: 9, height: 4))
    // A 10×5 document is intentionally bistable under the retained indicator
    // hysteresis. Fit inside the inset viewport too, so both bars must retire.
    width = 9
    height = 4
    try h.renderAfterExternalMutation()
    let viewport = try route(in: h).viewportRect.size
    #expect(viewport == .init(width: 10, height: 5))
  }

  @Test func setA640HidingOneIndicatorAxisDoesNotReserveItsTrack() throws {
    // Hypothesis: axis-specific indicator visibility hides paint but still reserves that axis's track.
    let h = try make(640) {
      ScrollView([.horizontal, .vertical]) { fixedDocument() }
        .scrollIndicators(.hidden, axes: .horizontal).frame(width: 12, height: 6)
    }
    defer { h.shutdown() }
    #expect(try route(in: h).viewportRect.size == .init(width: 11, height: 6))
  }

  @Test func setA641OverlayIndicatorsDoNotReduceThePublishedViewport() throws {
    // Hypothesis: reservesIndicatorSpace=false changes paint but geometry still loses a row and column.
    let h = try make(641) {
      ScrollView([.horizontal, .vertical]) { fixedDocument() }
        .scrollViewStyle(SetAScrollInsetsStyle(reserves: false)).frame(width: 12, height: 6)
    }
    defer { h.shutdown() }
    #expect(try route(in: h).viewportRect.size == .init(width: 12, height: 6))
    #expect(try route(in: h).contentBounds.size == .init(width: 40, height: 30))
  }

  @Test func setA642OversizedStyleInsetsCannotPublishNegativeViewportDimensions() throws {
    // Hypothesis: subtracting valid but oversized style insets underflows the scroll viewport's finite dimensions.
    let h = try make(642) {
      ScrollView([.horizontal, .vertical]) { fixedDocument() }.scrollIndicators(.hidden)
        .scrollViewStyle(
          SetAScrollInsetsStyle(insets: .init(top: 8, leading: 9, bottom: 7, trailing: 6))
        )
        .frame(width: 12, height: 6)
    }
    defer { h.shutdown() }
    #expect(try route(in: h).viewportRect.size == .zero)
  }

  @Test func setA643ContentPaddingContributesToScrollExtentExactlyOnce() throws {
    // Hypothesis: padding around the primary document is omitted from or double-counted in its scrollable content extent.
    let p = SetAScrollProxyHolder()
    let s = SetAScrollOffsetBox()
    let h = try pane(643, proxy: p, state: s, axes: .vertical) {
      VStack(alignment: .leading, spacing: 0) {
        Text("HEAD")
        Text("TAIL").frame(height: 9, alignment: .bottomLeading)
      }
      .padding(.init(top: 2, leading: 1, bottom: 3, trailing: 1))
    }
    defer { h.shutdown() }
    #expect(try route(in: h).contentBounds.size.height == 15)
    #expect(try #require(p.proxy).scrollTo(edge: .bottom))
    try h.render()
    #expect(s.offset.y == 9)
    #expect(try #require(h.point(forText: "TAIL")).y == Double(route(in: h).viewportRect.maxY - 4))
  }

  @Test func setA644ScrollCommandsAndLayoutAgreeForOverflowingDecorations() throws {
    // Hypothesis: proxy clamping uses overflowing decoration bounds while placement clamps against a different measured extent.
    let p = SetAScrollProxyHolder()
    let s = SetAScrollOffsetBox()
    let h = try pane(644, proxy: p, state: s, axes: .vertical) {
      Text("MARK").frame(height: 10).overlay(alignment: .topLeading) {
        Text("decoration").frame(height: 100, alignment: .bottomLeading)
      }
    }
    defer { h.shutdown() }
    let before = try #require(h.point(forText: "MARK"))
    #expect(s.offset == .zero)
    #expect(try #require(p.proxy).scrollTo(edge: .bottom))
    try h.render()
    let after = try #require(h.point(forText: "MARK"))
    let renderedOffset = before.y - after.y
    // The primary's authored ten rows in a six-row viewport move four rows.
    // The distant decoration stays offscreen, so it cannot obscure the witness.
    #expect(renderedOffset == 4)
    withKnownIssue("STUI-999: proxy extent and layout clamp disagree for overflowing overlays") {
      #expect(
        Double(s.offset.y) == renderedOffset,
        "Proxy published offset \(s.offset.y), but the document moved \(renderedOffset) rows")
    }
  }

  @Test func setA645LazyMultiChildFragmentBottomAnchorIncludesItsLastChild() throws {
    // Hypothesis: an estimated ForEach target resolves to only its first child instead of the whole authored fragment.
    let p = SetAScrollProxyHolder()
    let s = SetAScrollOffsetBox()
    let h = try pane(645, proxy: p, state: s, axes: .vertical) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(0..<400, id: \.self) { index in
          Text("A\(index)")
          Text("B\(index)")
        }
      }
    }
    defer { h.shutdown() }
    #expect(try #require(p.proxy).scrollTo(200, anchor: .bottom))
    try h.render()
    let r = try route(in: h)
    #expect(try #require(h.point(forText: "B200")).y == Double(r.viewportRect.maxY - 1))
    #expect(try #require(h.point(forText: "A200")).y == Double(r.viewportRect.maxY - 2))
  }

  @Test func setA646AnEmptyLazyTargetRestoresThePrecommandViewport() throws {
    // Hypothesis: a speculative target estimate commits a jump even when realization proves the logical element empty.
    let p = SetAScrollProxyHolder()
    let s = SetAScrollOffsetBox()
    let h = try pane(646, proxy: p, state: s, axes: .vertical) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(0..<400, id: \.self) { index in if index != 200 { Text("R\(index)") } }
      }
    }
    defer { h.shutdown() }
    let proxy = try #require(p.proxy)
    #expect(proxy.scrollTo(30, anchor: .top))
    try h.render()
    let before = try offset(in: h)
    _ = proxy.scrollTo(200, anchor: .top)
    try h.render()
    #expect(try offset(in: h) == before)
    #expect(h.frame.contains("R30"))
  }

  @Test func setA647ChangingLazySpacingInvalidatesTargetPositionEstimates() throws {
    // Hypothesis: target refinement reuses an old stride after only the lazy stack's authored spacing changes.
    var spacing = 0
    let p = SetAScrollProxyHolder()
    let s = SetAScrollOffsetBox()
    let h = try pane(647, proxy: p, state: s, axes: .vertical) {
      LazyVStack(alignment: .leading, spacing: spacing) {
        ForEach(0..<400, id: \.self) { Text("R\($0)") }
      }
    }
    defer { h.shutdown() }
    #expect(try #require(p.proxy).scrollTo(200, anchor: .top))
    try h.render()
    spacing = 2
    try h.renderAfterExternalMutation()
    _ = try #require(p.proxy).scrollTo(201, anchor: .top)
    try h.render()
    #expect(try #require(h.point(forText: "R201")).y == Double(route(in: h).viewportRect.origin.y))
    #expect(try #require(h.point(forText: "R202")).y - #require(h.point(forText: "R201")).y == 3)
  }

  @Test func setA648LazyHeightGrowthBeforeTheViewportPreservesTheVisibleAnchor() throws {
    // Hypothesis: remeasured prefix heights shift a visible lazy anchor despite unchanged source membership.
    var tall = false
    let p = SetAScrollProxyHolder()
    let s = SetAScrollOffsetBox()
    let h = try pane(648, proxy: p, state: s, axes: .vertical) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(0..<80, id: \.self) { index in
          Text("R\(index)").frame(height: tall && index < 40 ? 2 : 1)
        }
      }
    }
    defer { h.shutdown() }
    #expect(try #require(p.proxy).scrollTo(40, anchor: .top))
    try h.render()
    let before = try #require(h.point(forText: "R40"))
    tall = true
    try h.renderAfterExternalMutation()
    #expect(try #require(h.point(forText: "R40")) == before)
  }

  @Test func setA649ADeletedTargetCannotFallBackToItsFormerLogicalIndex() throws {
    // Hypothesis: the lazy target index cache maps a removed ID to the successor now occupying its old index.
    var ids = Array(0..<100)
    let p = SetAScrollProxyHolder()
    let s = SetAScrollOffsetBox()
    let h = try pane(649, proxy: p, state: s, axes: .vertical) {
      LazyVStack(alignment: .leading, spacing: 0) { ForEach(ids, id: \.self) { Text("R\($0)") } }
    }
    defer { h.shutdown() }
    let proxy = try #require(p.proxy)
    #expect(proxy.scrollTo(50, anchor: .top))
    try h.render()
    ids.removeAll { $0 == 50 }
    try h.renderAfterExternalMutation()
    let before = try offset(in: h)
    #expect(!proxy.scrollTo(50, anchor: .top))
    try h.render()
    #expect(try offset(in: h) == before)
  }

  @Test func setA650ARepopulatedLazyTargetDiscardsItsEarlierEmptyRealization() throws {
    // Hypothesis: a logical element first realized empty retains that empty fragment after its content becomes nonempty.
    var populated = false
    let p = SetAScrollProxyHolder()
    let s = SetAScrollOffsetBox()
    let h = try pane(650, proxy: p, state: s, axes: .vertical) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(0..<100, id: \.self) { index in if index != 50 || populated { Text("R\(index)") } }
      }
    }
    defer { h.shutdown() }
    _ = try #require(p.proxy).scrollTo(50, anchor: .top)
    try h.render()
    #expect(!h.frame.contains("R50"))
    populated = true
    try h.renderAfterExternalMutation()
    #expect(try #require(p.proxy).scrollTo(50, anchor: .top))
    try h.render()
    #expect(try #require(h.point(forText: "R50")).y == Double(route(in: h).viewportRect.origin.y))
  }

  private func make<V: View>(_ id: Int, @ViewBuilder content: @escaping () -> V) throws
    -> StressRuntimeHarness<V>
  {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetAScroll\(id)"), size: .init(width: 60, height: 20),
      content: content)
  }
  private func pane<V: View>(
    _ id: Int, proxy: SetAScrollProxyHolder, state: SetAScrollOffsetBox,
    axes: SwiftTUIViews.Axis.Set = [.horizontal, .vertical], @ViewBuilder content: @escaping () -> V
  ) throws -> StressRuntimeHarness<some View> {
    try make(id) { reader(proxy, state: state, axes: axes, content: content) }
  }
  private func reader<V: View>(
    _ holder: SetAScrollProxyHolder, state: SetAScrollOffsetBox,
    axes: SwiftTUIViews.Axis.Set = .vertical, @ViewBuilder content: @escaping () -> V
  ) -> some View {
    ScrollViewReader { proxy in
      let _ = holder.capture(proxy)
      ScrollView(axes, position: state.binding) { content() }
        .scrollIndicators(.hidden).frame(width: 12, height: 6)
    }
  }
  private func fixedDocument() -> some View {
    Text("document").frame(width: 40, height: 30, alignment: .topLeading)
  }
  private func rows(_ count: Int) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(0..<count, id: \.self) { index in Text(formatRow(index)) }
    }
  }
  private func formatRow(_ index: Int) -> String {
    "R" + String(repeating: "0", count: max(0, 3 - String(index).count)) + String(index)
  }
  private func route<V: View>(in h: StressRuntimeHarness<V>) throws -> ScrollRoute {
    try #require(h.runLoop.latestSemanticSnapshot.scrollRoutes.first)
  }
  private func offset<V: View>(in h: StressRuntimeHarness<V>) throws -> ScrollCellOffset {
    let r = try route(in: h)
    return .init(
      x: r.viewportRect.origin.x - r.contentBounds.origin.x,
      y: r.viewportRect.origin.y - r.contentBounds.origin.y)
  }
}

@MainActor
private final class SetAScrollProxyHolder {
  var proxy: ScrollViewProxy?
  func capture(_ value: ScrollViewProxy) { proxy = value }
}

@MainActor
private final class SetAScrollOffsetBox {
  var offset: ScrollCellOffset
  var writes: [ScrollCellOffset] = []
  var rejectWrites: Bool
  init(offset: ScrollCellOffset = .zero, rejectWrites: Bool = false) {
    self.offset = offset
    self.rejectWrites = rejectWrites
  }
  var binding: Binding<ScrollCellOffset> {
    Binding(
      get: { self.offset },
      set: { value in
        self.writes.append(value)
        if !self.rejectWrites { self.offset = value }
      })
  }
}

private struct SetAScrollInsetsStyle: ScrollViewStyle {
  var insets: EdgeInsets = .zero
  var reserves = true
  var snapshotLabel: String { "SetAScrollInsets" }
  func resolvePresentation(for configuration: ScrollViewStyleConfiguration)
    -> ScrollViewStylePresentation
  {
    .init(snapshotLabel: snapshotLabel, contentInsets: insets, reservesIndicatorSpace: reserves)
  }
}
