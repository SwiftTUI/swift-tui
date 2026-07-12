import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI layout proposal stress behavior", .serialized)
struct FrameworkStressLayoutProposalTests {}

@MainActor
private func expectLayoutProposalFrameMatchesFresh<V: View>(
  _ root: V,
  renderer: DefaultRenderer,
  identity: Identity,
  generation: Int,
  proposal: ProposedSize = .unspecified
) {
  let retained = renderer.render(
    root,
    context: .init(
      identity: identity,
      invalidatedIdentities: generation == 0 ? [] : [identity]
    ),
    proposal: proposal
  )
  let fresh = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache())).render(
    root,
    context: .init(identity: identity),
    proposal: proposal
  )

  #expect(retained.rasterSurface == fresh.rasterSurface)
  #expect(retained.measuredTree.measuredSize == fresh.measuredTree.measuredSize)
}

// MARK: - Attempt 001: horizontal fixed-size replacement

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 001 horizontal fixed size follows every replacement")
  func layoutProposal001HorizontalFixedSizeFollowsEveryReplacement() {
    // Hypothesis: a stable text node can retain its original horizontal compression resistance
    // after only fixedSize(horizontal:) changes inside a width-constrained stack.
    struct Root: View {
      let fixed: Bool

      var body: some View {
        HStack(spacing: 1) {
          Text("alpha beta gamma")
            .fixedSize(horizontal: fixed, vertical: false)
          Text("tail")
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal001")

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(fixed: generation.isMultiple(of: 2)),
        renderer: renderer,
        identity: identity,
        generation: generation,
        proposal: .init(width: 11, height: 3)
      )
    }
  }
}

// MARK: - Attempt 002: vertical fixed-size replacement

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 002 vertical fixed size refreshes wrapped allocation")
  func layoutProposal002VerticalFixedSizeRefreshesWrappedAllocation() {
    // Hypothesis: vertical fixed-size metadata can leave a wrapped child's old minimum height in
    // the stack allocator after compression resistance is removed and restored.
    struct Root: View {
      let fixed: Bool

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Text("one two three four")
            .frame(width: 5, alignment: .leading)
            .fixedSize(horizontal: false, vertical: fixed)
          Text("footer")
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal002")

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(fixed: generation.isMultiple(of: 2)),
        renderer: renderer,
        identity: identity,
        generation: generation,
        proposal: .init(width: 8, height: 4)
      )
    }
  }
}

// MARK: - Attempt 003: flexible-frame minimum replacement

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 003 flexible minimum width replaces retained clamp")
  func layoutProposal003FlexibleMinimumWidthReplacesRetainedClamp() {
    // Hypothesis: flexible-frame measurement reuse can preserve an earlier minimum-width clamp
    // when the child and outer proposal are otherwise unchanged.
    struct Root: View {
      let minimum: Int

      var body: some View {
        Text("M")
          .frame(
            minWidth: .finite(minimum),
            maxWidth: .infinity,
            alignment: .trailing
          )
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal003")
    let minimums = [1, 7, 3, 11, 2, 9]

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(minimum: minimums[generation % minimums.count]),
        renderer: renderer,
        identity: identity,
        generation: generation,
        proposal: .init(width: 12, height: 2)
      )
    }
  }
}

// MARK: - Attempt 004: flexible-frame ideal revisit

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 004 ideal width revisits use the current preference")
  func layoutProposal004IdealWidthRevisitsUseCurrentPreference() {
    // Hypothesis: revisiting an ideal width can reuse a measurement produced before intervening
    // ideal-width values changed the same flexible frame's intrinsic contract.
    struct Root: View {
      let ideal: Int

      var body: some View {
        Text("ideal")
          .frame(
            minWidth: 1,
            idealWidth: .finite(ideal),
            maxWidth: .infinity,
            alignment: .leading
          )
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal004")
    let ideals = [5, 12, 7, 16, 5, 9, 16, 7]

    for generation in 0..<32 {
      expectLayoutProposalFrameMatchesFresh(
        Root(ideal: ideals[generation % ideals.count]),
        renderer: renderer,
        identity: identity,
        generation: generation
      )
    }
  }
}

// MARK: - Attempt 005: finite and infinite maximum replacement

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 005 maximum width crosses finite and infinite bounds")
  func layoutProposal005MaximumWidthCrossesFiniteAndInfiniteBounds() {
    // Hypothesis: a flexible frame can retain finite maximum-width geometry after maxWidth
    // becomes unbounded, or retain expansion after the finite clamp returns.
    struct Root: View {
      let unbounded: Bool

      var body: some View {
        Text("maximum width payload")
          .frame(
            maxWidth: unbounded ? ProposedDimension.infinity : .finite(8),
            alignment: .leading
          )
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal005")

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(unbounded: generation.isMultiple(of: 2)),
        renderer: renderer,
        identity: identity,
        generation: generation,
        proposal: .init(width: 18, height: 3)
      )
    }
  }
}

// MARK: - Attempt 006: flexible height interval replacement

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 006 flexible height interval remeasures wrapped content")
  func layoutProposal006FlexibleHeightIntervalRemeasuresWrappedContent() {
    // Hypothesis: changing both ends of a flexible height interval can leave the wrapped child's
    // old measured height attached to the stable frame node.
    struct Root: View {
      let compact: Bool

      var body: some View {
        Text("a b c d e f g")
          .frame(width: 3, alignment: .leading)
          .frame(
            minHeight: .finite(compact ? 1 : 4),
            maxHeight: .finite(compact ? 2 : 6),
            alignment: compact ? .bottomLeading : .topLeading
          )
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal006")

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(compact: generation.isMultiple(of: 2)),
        renderer: renderer,
        identity: identity,
        generation: generation,
        proposal: .init(width: 6, height: 6)
      )
    }
  }
}

// MARK: - Attempt 007: spacer minimum replacement

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 007 spacer minimum replaces its allocation floor")
  func layoutProposal007SpacerMinimumReplacesItsAllocationFloor() {
    // Hypothesis: stack allocation can cache a Spacer's first minimum and continue distributing
    // width from that floor after minLength changes in place.
    struct Root: View {
      let minimum: Int

      var body: some View {
        HStack(spacing: 0) {
          Text("L")
          Spacer(minLength: minimum)
          Text("R")
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal007")
    let minimums = [0, 7, 2, 11, 1, 5]

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(minimum: minimums[generation % minimums.count]),
        renderer: renderer,
        identity: identity,
        generation: generation,
        proposal: .init(width: 14, height: 1)
      )
    }
  }
}

// MARK: - Attempt 008: unequal spacer floors exchange positions

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 008 unequal spacer floors exchange without stale shares")
  func layoutProposal008UnequalSpacerFloorsExchangeWithoutStaleShares() {
    // Hypothesis: the stack's equal-share correction can remain indexed to the previous Spacer
    // order when two stable slots exchange unequal minimum lengths.
    struct Root: View {
      let reversed: Bool

      var body: some View {
        HStack(spacing: 0) {
          Text("A")
          Spacer(minLength: reversed ? 7 : 1)
          Text("B")
          Spacer(minLength: reversed ? 1 : 7)
          Text("C")
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal008")

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(reversed: generation.isMultiple(of: 2)),
        renderer: renderer,
        identity: identity,
        generation: generation,
        proposal: .init(width: 17, height: 1)
      )
    }
  }
}

// MARK: - Attempt 009: spacer cardinality replacement

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 009 conditional spacer releases its allocation share")
  func layoutProposal009ConditionalSpacerReleasesItsAllocationShare() {
    // Hypothesis: removing a Spacer from between stable siblings can leave its expansion share in
    // the retained stack allocation vector and keep the surviving trailing child displaced.
    struct Root: View {
      let includesMiddleSpacer: Bool

      var body: some View {
        HStack(spacing: 0) {
          Text("left")
          Spacer(minLength: 1)
          Text("middle")
          if includesMiddleSpacer {
            Spacer(minLength: 4)
          }
          Text("right")
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal009")

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(includesMiddleSpacer: generation.isMultiple(of: 2)),
        renderer: renderer,
        identity: identity,
        generation: generation,
        proposal: .init(width: 25, height: 1)
      )
    }
  }
}

// MARK: - Attempt 010: ZStack alignment replacement

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 010 ZStack alignment replaces overlay metrics")
  func layoutProposal010ZStackAlignmentReplacesOverlayMetrics() {
    // Hypothesis: ZStack can reuse the prior overlay alignment metrics when heterogeneous child
    // sizes stay constant and only the container alignment changes.
    struct Root: View {
      let alignment: Alignment

      var body: some View {
        ZStack(alignment: alignment) {
          Text("base")
            .frame(width: 13, height: 5, alignment: .topLeading)
          Text("X")
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal010")
    let alignments: [Alignment] = [.topLeading, .bottomTrailing, .center, .topTrailing]

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(alignment: alignments[generation % alignments.count]),
        renderer: renderer,
        identity: identity,
        generation: generation
      )
    }
  }
}

private enum LayoutProposal011AlignmentID: AlignmentID {
  static func defaultValue(in context: ViewDimensions) -> Int {
    context[HorizontalAlignment.center]
  }
}

// MARK: - Attempt 011: ZStack custom-guide replacement

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 011 ZStack reads each current custom guide")
  func layoutProposal011ZStackReadsEachCurrentCustomGuide() {
    // Hypothesis: overlay alignment metrics can retain an explicit guide value from the first
    // closure capture when the aligned child keeps identical intrinsic dimensions.
    struct Root: View {
      let shifted: Bool

      var body: some View {
        let guide = HorizontalAlignment(LayoutProposal011AlignmentID.self)
        ZStack(alignment: .init(horizontal: guide, vertical: .top)) {
          Text("anchor")
            .frame(width: 12, height: 3, alignment: .topLeading)
          Text("G")
            .alignmentGuide(guide) { dimensions in
              shifted ? dimensions[.trailing] : dimensions[.leading]
            }
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal011")

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(shifted: generation.isMultiple(of: 2)),
        renderer: renderer,
        identity: identity,
        generation: generation
      )
    }
  }
}

private struct LayoutProposal012AnchorLayout: Layout {
  let trailing: Bool

  var measurementReuseSignature: String? { "LayoutProposal012.measure" }
  var placementReuseSignature: String? { "LayoutProposal012.place.\(trailing)" }

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews _: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    .init(width: 14, height: 3)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    guard let child = subviews.first else { return }
    child.place(
      at: .init(
        x: trailing ? bounds.origin.x + bounds.size.width : bounds.origin.x,
        y: bounds.origin.y
      ),
      anchor: trailing ? .topTrailing : .topLeading,
      proposal: .unspecified
    )
  }
}

// MARK: - Attempt 012: custom placement-anchor replacement

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 012 custom placement anchor follows current algorithm")
  func layoutProposal012CustomPlacementAnchorFollowsCurrentAlgorithm() {
    // Hypothesis: a reusable custom layout can update its placement signature while retained
    // placement still applies the prior anchor to the current position.
    struct Root: View {
      let trailing: Bool

      var body: some View {
        LayoutProposal012AnchorLayout(trailing: trailing) {
          Text("anchor")
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal012")

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(trailing: generation.isMultiple(of: 2)),
        renderer: renderer,
        identity: identity,
        generation: generation
      )
    }
  }
}

private struct LayoutProposal013ChildProposalLayout: Layout {
  let constrained: Bool

  var measurementReuseSignature: String? { "LayoutProposal013.measure.\(constrained)" }
  var placementReuseSignature: String? { "LayoutProposal013.place.\(constrained)" }

  private var childProposal: ProposedViewSize {
    constrained ? .init(width: 5, height: .unspecified) : .unspecified
  }

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    subviews.first?.sizeThatFits(childProposal) ?? .zero
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: childProposal)
  }
}

// MARK: - Attempt 013: custom child-proposal replacement

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 013 custom layout replaces child proposal mode")
  func layoutProposal013CustomLayoutReplacesChildProposalMode() {
    // Hypothesis: a custom layout's stable child can keep an unspecified measurement when the
    // algorithm switches to a finite child proposal, or keep wrapping after returning to nil.
    struct Root: View {
      let constrained: Bool

      var body: some View {
        LayoutProposal013ChildProposalLayout(constrained: constrained) {
          Text("proposal sensitive payload")
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal013")

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(constrained: generation.isMultiple(of: 2)),
        renderer: renderer,
        identity: identity,
        generation: generation
      )
    }
  }
}

private struct LayoutProposal014MeasurementSignatureLayout: Layout {
  let width: Int

  var measurementReuseSignature: String? { "LayoutProposal014.measure.\(width)" }
  var placementReuseSignature: String? { "LayoutProposal014.place" }

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews _: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    .init(width: width, height: 1)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    subviews.first?.place(
      at: bounds.origin,
      anchor: .topLeading,
      proposal: .init(width: width, height: 1)
    )
  }
}

// MARK: - Attempt 014: measurement-signature replacement

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 014 measurement signature isolates changing size")
  func layoutProposal014MeasurementSignatureIsolatesChangingSize() {
    // Hypothesis: changing only a custom layout's declared measurement signature can still reuse
    // an older measured size when placement advertises one stable signature.
    struct Root: View {
      let width: Int

      var body: some View {
        LayoutProposal014MeasurementSignatureLayout(width: width) {
          Text("signature")
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal014")
    let widths = [4, 12, 7, 15, 4, 9]

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(width: widths[generation % widths.count]),
        renderer: renderer,
        identity: identity,
        generation: generation
      )
    }
  }
}

private struct LayoutProposal015PlacementSignatureLayout: Layout {
  let trailing: Bool

  var measurementReuseSignature: String? { "LayoutProposal015.measure" }
  var placementReuseSignature: String? { "LayoutProposal015.place.\(trailing)" }

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews _: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    .init(width: 16, height: 1)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    subviews.first?.place(
      at: .init(
        x: trailing ? bounds.origin.x + bounds.size.width - 1 : bounds.origin.x,
        y: bounds.origin.y
      ),
      anchor: .topLeading,
      proposal: .init(width: 1, height: 1)
    )
  }
}

// MARK: - Attempt 015: placement-signature replacement

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 015 placement signature isolates current origin")
  func layoutProposal015PlacementSignatureIsolatesCurrentOrigin() {
    // Hypothesis: placement-only signature changes can be overlooked when measurement is safely
    // reusable and the stable child keeps the same proposed size.
    struct Root: View {
      let trailing: Bool

      var body: some View {
        LayoutProposal015PlacementSignatureLayout(trailing: trailing) {
          Text("P")
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal015")

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(trailing: generation.isMultiple(of: 2)),
        renderer: renderer,
        identity: identity,
        generation: generation
      )
    }
  }
}

private struct LayoutProposal016MetadataLayout: Layout {
  var measurementReuseSignature: String? { "LayoutProposal016.measure" }
  var placementReuseSignature: String? { "LayoutProposal016.place" }

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    subviews.first?.sizeThatFits(.init(width: 5, height: 4)) ?? .zero
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    subviews.first?.place(
      at: bounds.origin,
      anchor: .topLeading,
      proposal: .init(width: 5, height: 4)
    )
  }
}

// MARK: - Attempt 016: child metadata under reusable custom layout

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 016 reusable layout observes child fixed-size metadata")
  func layoutProposal016ReusableLayoutObservesChildFixedSizeMetadata() {
    // Hypothesis: reusable custom-layout signatures can mask a child's current fixedSize metadata
    // and preserve the child measurement from before compression resistance changed.
    struct Root: View {
      let fixed: Bool

      var body: some View {
        LayoutProposal016MetadataLayout {
          Text("custom child metadata")
            .fixedSize(horizontal: fixed, vertical: false)
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal016")

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(fixed: generation.isMultiple(of: 2)),
        renderer: renderer,
        identity: identity,
        generation: generation
      )
    }
  }
}

private struct LayoutProposal017Cache: Sendable {
  var widths: [Int]
}

private struct LayoutProposal017CachedWidthsLayout: Layout {
  var measurementReuseSignature: String? { "LayoutProposal017.measure" }
  var placementReuseSignature: String? { "LayoutProposal017.place" }

  func makeCache(subviews: LayoutSubviews) -> LayoutProposal017Cache {
    .init(widths: subviews.map { $0.sizeThatFits(.unspecified).width })
  }

  func updateCache(
    _ cache: inout LayoutProposal017Cache,
    subviews: LayoutSubviews
  ) {
    cache.widths = subviews.map { $0.sizeThatFits(.unspecified).width }
  }

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews _: LayoutSubviews,
    cache: inout LayoutProposal017Cache
  ) -> LayoutSize {
    .init(width: cache.widths.reduce(0, +), height: 1)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout LayoutProposal017Cache
  ) {
    var x = bounds.origin.x
    for index in subviews.indices {
      let width = cache.widths[index]
      subviews[index].place(
        at: .init(x: x, y: bounds.origin.y),
        anchor: .topLeading,
        proposal: .init(width: width, height: 1)
      )
      x += width
    }
  }
}

// MARK: - Attempt 017: same-count custom cache reorder

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 017 custom cache refreshes same-count width reorder")
  func layoutProposal017CustomCacheRefreshesSameCountWidthReorder() {
    // Hypothesis: updateCache can retain size entries by structural ordinal when same-count,
    // stable-ID children reorder and bring different intrinsic widths to those ordinals.
    struct Row: Identifiable {
      let id: Int
      let label: String
    }

    struct Root: View {
      let alternate: Bool

      var rows: [Row] {
        let values = [
          Row(id: 1, label: "A"),
          Row(id: 2, label: "BBBB"),
          Row(id: 3, label: "CC"),
        ]
        return alternate ? [values[2], values[0], values[1]] : values
      }

      var body: some View {
        LayoutProposal017CachedWidthsLayout {
          ForEach(rows) { row in
            Text(row.label)
          }
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal017")

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(alternate: generation.isMultiple(of: 2)),
        renderer: renderer,
        identity: identity,
        generation: generation
      )
    }
  }
}

private struct LayoutProposal018MultiProbeLayout: Layout {
  let preferWide: Bool

  var measurementReuseSignature: String? { "LayoutProposal018.measure.\(preferWide)" }
  var placementReuseSignature: String? { "LayoutProposal018.place.\(preferWide)" }

  private func measuredSizes(of child: LayoutSubview) -> (narrow: LayoutSize, wide: LayoutSize) {
    if preferWide {
      let narrow = child.sizeThatFits(.init(width: 4, height: .unspecified))
      let wide = child.sizeThatFits(.init(width: 9, height: .unspecified))
      return (narrow, wide)
    }
    let wide = child.sizeThatFits(.init(width: 9, height: .unspecified))
    let narrow = child.sizeThatFits(.init(width: 4, height: .unspecified))
    return (narrow, wide)
  }

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    guard let child = subviews.first else { return .zero }
    let sizes = measuredSizes(of: child)
    return preferWide ? sizes.wide : sizes.narrow
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    guard let child = subviews.first else { return }
    let width = preferWide ? 9 : 4
    child.place(
      at: bounds.origin,
      anchor: .topLeading,
      proposal: .init(width: .finite(width), height: .unspecified)
    )
  }
}

// MARK: - Attempt 018: multiple child proposals in one pass

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 018 child measurement probes stay proposal-specific")
  func layoutProposal018ChildMeasurementProbesStayProposalSpecific() {
    // Hypothesis: measuring one child under two proposals in opposite orders can return the most
    // recent cached size for both queries and corrupt the custom layout's chosen geometry.
    struct Root: View {
      let preferWide: Bool

      var body: some View {
        LayoutProposal018MultiProbeLayout(preferWide: preferWide) {
          Text("multiple proposal probes")
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal018")

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(preferWide: generation.isMultiple(of: 2)),
        renderer: renderer,
        identity: identity,
        generation: generation
      )
    }
  }
}

private enum LayoutProposal019AlignmentID: AlignmentID {
  static func defaultValue(in _: ViewDimensions) -> Int { 0 }
}

private struct LayoutProposal019DimensionsLayout: Layout {
  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews _: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    .init(width: 12, height: 2)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    guard let child = subviews.first else { return }
    let guide = HorizontalAlignment(LayoutProposal019AlignmentID.self)
    let dimensions = child.dimensions(in: .unspecified)
    child.place(
      at: .init(x: bounds.origin.x + dimensions[guide], y: bounds.origin.y),
      anchor: .topLeading,
      proposal: .unspecified
    )
  }
}

// MARK: - Attempt 019: custom dimensions guide replacement

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 019 custom dimensions publish current explicit guide")
  func layoutProposal019CustomDimensionsPublishCurrentExplicitGuide() {
    // Hypothesis: LayoutSubview.dimensions can retain an explicit alignment guide from an earlier
    // closure capture even when the custom layout opts out of placement reuse.
    struct Root: View {
      let shifted: Bool

      var body: some View {
        let guide = HorizontalAlignment(LayoutProposal019AlignmentID.self)
        LayoutProposal019DimensionsLayout {
          Text("D")
            .alignmentGuide(guide) { _ in shifted ? 8 : 1 }
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal019")

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(shifted: generation.isMultiple(of: 2)),
        renderer: renderer,
        identity: identity,
        generation: generation
      )
    }
  }
}

// MARK: - Attempt 020: vertical ViewThatFits selection

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 020 vertical ViewThatFits refreshes candidate selection")
  func layoutProposal020VerticalViewThatFitsRefreshesCandidateSelection() {
    // Hypothesis: the vertical-only fit probe can preserve the prior selected child when the first
    // candidate crosses only the proposed-height boundary.
    struct Root: View {
      let tall: Bool

      var body: some View {
        ViewThatFits(in: .vertical) {
          Text("primary")
            .frame(width: 8, height: tall ? 7 : 2, alignment: .topLeading)
          Text("fallback")
            .frame(width: 8, height: 2, alignment: .topLeading)
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal020")

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(tall: generation.isMultiple(of: 2)),
        renderer: renderer,
        identity: identity,
        generation: generation,
        proposal: .init(width: 10, height: 4)
      )
    }
  }
}

// MARK: - Attempt 021: two-axis ViewThatFits selection

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 021 two-axis ViewThatFits rejects either overflow")
  func layoutProposal021TwoAxisViewThatFitsRejectsEitherOverflow() {
    // Hypothesis: two-axis fitting can reuse a selection proven on one axis after the primary
    // candidate alternates between horizontal overflow and vertical overflow.
    struct Root: View {
      let mode: Int

      var body: some View {
        ViewThatFits(in: [.horizontal, .vertical]) {
          Text("primary")
            .frame(
              width: mode == 0 ? 6 : 14,
              height: mode == 2 ? 6 : 2,
              alignment: .topLeading
            )
          Text("fallback")
            .frame(width: 6, height: 2, alignment: .topLeading)
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal021")

    for generation in 0..<30 {
      expectLayoutProposalFrameMatchesFresh(
        Root(mode: generation % 3),
        renderer: renderer,
        identity: identity,
        generation: generation,
        proposal: .init(width: 9, height: 4)
      )
    }
  }
}

// MARK: - Attempt 022: ViewThatFits candidate topology replacement

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 022 ViewThatFits drops removed leading candidate")
  func layoutProposal022ViewThatFitsDropsRemovedLeadingCandidate() {
    // Hypothesis: removing a leading non-fitting candidate can leave the selected child index
    // offset, causing the retained container to choose a different surviving candidate.
    struct Root: View {
      let includesOversizedPrefix: Bool

      var body: some View {
        ViewThatFits(in: .horizontal) {
          if includesOversizedPrefix {
            Text("oversized").frame(width: 20)
          }
          Text("middle").frame(width: 7)
          Text("last").frame(width: 4)
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal022")

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(includesOversizedPrefix: generation.isMultiple(of: 2)),
        renderer: renderer,
        identity: identity,
        generation: generation,
        proposal: .init(width: 8, height: 2)
      )
    }
  }
}

// MARK: - Attempt 023: lazy vertical spacing replacement

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 023 LazyVStack spacing repositions stable rows")
  func layoutProposal023LazyVStackSpacingRepositionsStableRows() {
    // Hypothesis: lazy row-offset reuse can preserve the first spacing vector when row identities
    // and intrinsic sizes remain stable across spacing-only updates.
    struct Root: View {
      let spacing: Int

      var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
          LazyVStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<4) { row in
              Text("V\(row)")
            }
          }
        }
        .frame(width: 8, height: 8, alignment: .topLeading)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal023")
    let spacings = [0, 2, 1, 3]

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(spacing: spacings[generation % spacings.count]),
        renderer: renderer,
        identity: identity,
        generation: generation,
        proposal: .init(width: 8, height: 8)
      )
    }
  }
}

// MARK: - Attempt 024: lazy horizontal spacing replacement

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 024 LazyHStack spacing repositions stable columns")
  func layoutProposal024LazyHStackSpacingRepositionsStableColumns() {
    // Hypothesis: horizontal lazy placement can retain column origins produced under an earlier
    // spacing value when every indexed child remains otherwise unchanged.
    struct Root: View {
      let spacing: Int

      var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(alignment: .top, spacing: spacing) {
            ForEach(0..<5) { column in
              Text("H\(column)")
            }
          }
        }
        .frame(width: 14, height: 2, alignment: .topLeading)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal024")
    let spacings = [0, 3, 1, 2]

    for generation in 0..<24 {
      expectLayoutProposalFrameMatchesFresh(
        Root(spacing: spacings[generation % spacings.count]),
        renderer: renderer,
        identity: identity,
        generation: generation,
        proposal: .init(width: 14, height: 2)
      )
    }
  }
}

// MARK: - Attempt 025: nested clipping intersection replacement

extension FrameworkStressLayoutProposalTests {
  @Test("stress layout proposal 025 nested clips recompute moving intersections")
  func layoutProposal025NestedClipsRecomputeMovingIntersections() {
    // Hypothesis: nested clip commands can combine one generation's inner frame with another
    // generation's outer frame after both bounds and the oversized child's offset change.
    struct Root: View {
      let generation: Int

      var body: some View {
        Text("ABCDEFGHIJKLMNOPQRST")
          .fixedSize()
          .offset(x: -(generation % 5), y: 0)
          .frame(width: 9 + generation % 3, height: 1, alignment: .leading)
          .clipped()
          .offset(x: generation % 4, y: 0)
          .frame(width: 7 + generation % 2, height: 1, alignment: .leading)
          .clipped()
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("LayoutProposal025")

    for generation in 0..<30 {
      expectLayoutProposalFrameMatchesFresh(
        Root(generation: generation),
        renderer: renderer,
        identity: identity,
        generation: generation
      )
    }
  }
}
