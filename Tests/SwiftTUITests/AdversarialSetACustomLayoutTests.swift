@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized, FailOnSoundnessViolationGrowth(), .timeLimit(.minutes(1)))
struct AdversarialSetACustomLayoutTests {
  @Test func setA426LayoutValueKeysWithTheSameValueTypeStayIndependent() {
    // Hypothesis: layout metadata indexes values by payload type instead of the key's concrete type.
    let probe = SetALayoutProbe()
    let layout = SetAProbeLayout(measure: { _, children, _ in
      probe.record([children[0][SetALayoutFirstKey.self], children[0][SetALayoutSecondKey.self]])
      return .init(width: 4, height: 1)
    })
    _ = render(layout) {
      Text("key").layoutValue(key: SetALayoutFirstKey.self, value: 3)
        .layoutValue(key: SetALayoutSecondKey.self, value: 11)
    }
    expectRecords(probe, equal: [3, 11])
  }

  @Test func setA427OptionalLayoutKeyDistinguishesMissingFromAuthoredNil() {
    // Hypothesis: an absent value casts as an authored optional nil and bypasses the key's default 17.
    let probe = SetALayoutProbe()
    let layout = SetAProbeLayout(measure: { _, children, _ in
      probe.record(children.map { $0[SetAOptionalLayoutKey.self] ?? -1 })
      return .init(width: 4, height: 2)
    })
    _ = render(layout) {
      Text("nil").layoutValue(key: SetAOptionalLayoutKey.self, value: nil)
      Text("default")
    }
    let records = probe.records
    #expect(!records.isEmpty)
    #expect(records.allSatisfy { $0[0] == -1 }, "Authored nil must remain nil: \(records)")
    withKnownIssue("STUI-982: absent optional layout values bypass their default") {
      #expect(records.allSatisfy { $0[1] == 17 }, "Missing key must use default 17: \(records)")
    }
  }

  @Test func setA428OuterLayoutValueOverridesAnInnerValueThroughPadding() {
    // Hypothesis: transparent modifier propagation overwrites the parent's nearest authored layout value.
    let probe = SetALayoutProbe()
    let layout = SetAProbeLayout(measure: { _, children, _ in
      probe.record([children[0][SetALayoutFirstKey.self]])
      return .init(width: 6, height: 3)
    })
    _ = render(layout) {
      Text("value").layoutValue(key: SetALayoutFirstKey.self, value: 2)
        .padding(1).layoutValue(key: SetALayoutFirstKey.self, value: 9)
    }
    expectRecords(probe, equal: [9])
  }

  @Test func setA429LayoutValuesDoNotBleedIntoAnUnannotatedSibling() {
    // Hypothesis: reusable subview handles carry the preceding child's value instead of the key default.
    let probe = SetALayoutProbe()
    let layout = SetAProbeLayout(measure: { _, children, _ in
      probe.record(children.map { $0[SetALayoutFirstKey.self] })
      return .init(width: 10, height: 1)
    })
    _ = render(layout) {
      Text("A").layoutValue(key: SetALayoutFirstKey.self, value: 13)
      Text("B")
      Text("C").layoutValue(key: SetALayoutFirstKey.self, value: 5)
    }
    expectRecords(probe, equal: [13, -3, 5])
  }

  @Test func setA430LayoutSubviewReportsIndependentFixedAxesAndPriority() {
    // Hypothesis: subview metadata conflates the fixed-size axes or drops an independent negative priority.
    let probe = SetALayoutProbe()
    let layout = SetAProbeLayout(measure: { _, children, _ in
      let child = children[0]
      probe.record([
        Int(child.layoutPriority), child.fixedSizeHorizontal ? 1 : 0,
        child.fixedSizeVertical ? 1 : 0,
      ])
      return .init(width: 12, height: 3)
    })
    _ = render(layout) {
      Text("rigid").padding(1).fixedSize(horizontal: false, vertical: true).layoutPriority(-7)
    }
    expectRecords(probe, equal: [-7, 0, 1])
  }

  @Test func setA431SameAlignmentIDOnDifferentAxesKeepsSeparateAnswers() {
    // Hypothesis: memoized custom alignment answers collide when both axes use the same AlignmentID type.
    let horizontal = HorizontalAlignment(SetASharedAlignmentID.self)
    let vertical = VerticalAlignment(SetASharedAlignmentID.self)
    let child = SetAProbeLayout(
      measure: { _, _, _ in .init(width: 4, height: 2) },
      horizontalGuide: { guide, _, _, _, _ in guide == horizontal ? 3 : nil },
      verticalGuide: { guide, _, _, _, _ in guide == vertical ? 7 : nil })
    let parent = SetAProbeLayout(place: { bounds, _, children, _ in
      children[0].place(
        at: .init(x: bounds.origin.x + 10, y: bounds.origin.y + 10),
        anchor: .init(horizontal: horizontal, vertical: vertical), proposal: .unspecified)
    })
    let result = render(parent) { child { Text("X") } }
    #expect(result.placedTree.children[0].bounds.origin == .init(x: 7, y: 3))
  }

  @Test func setA432SubviewDimensionsUseTheSameProposalAsSizeThatFits() {
    // Hypothesis: dimensions(in:) reuses the previous sizeThatFits proposal rather than its own argument.
    let probe = SetALayoutProbe()
    let child = SetAProbeLayout(measure: { proposal, _, _ in
      .init(
        width: setAFiniteDimension(proposal.width, fallback: 19),
        height: setAFiniteDimension(proposal.height, fallback: 3))
    })
    let parent = SetAProbeLayout(measure: { _, children, _ in
      _ = children[0].sizeThatFits(.init(width: 2, height: 8))
      let dimensions = children[0].dimensions(in: .init(width: 7, height: 4))
      let size = children[0].sizeThatFits(.init(width: 7, height: 4))
      probe.record([dimensions.width, dimensions.height, size.width, size.height])
      return .init(width: 10, height: 5)
    })
    _ = render(parent) { child { Text("X") } }
    expectRecords(probe, equal: [7, 4, 7, 4])
  }

  @Test func setA433PlacementProposalOverridesTheContainerMeasurementOffer() {
    // Hypothesis: placement reuses premeasured child geometry despite the custom layout's narrower proposal.
    let layout = SetAProbeLayout(
      measure: { _, children, _ in
        _ = children[0].sizeThatFits(.init(width: 12, height: 2))
        return .init(width: 12, height: 2)
      },
      place: { bounds, _, children, _ in
        children[0].place(at: bounds.origin, proposal: .init(width: 4, height: 2))
      })
    let result = render(layout) {
      Rectangle().fill(Color.white).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #expect(result.placedTree.bounds.size == .init(width: 12, height: 2))
    #expect(result.placedTree.children[0].bounds.size == .init(width: 4, height: 2))
  }

  @Test func setA434ASecondPlacementReplacesTheFirstForOneSubview() {
    // Hypothesis: placement recording keeps the first call or emits a duplicate child when a layout revises it.
    let layout = SetAProbeLayout(place: { bounds, _, children, _ in
      children[0].place(at: bounds.origin, proposal: .init(width: 1, height: 1))
      children[0].place(
        at: .init(x: bounds.origin.x + 6, y: bounds.origin.y + 2),
        proposal: .init(width: 3, height: 1))
    })
    let result = render(layout) {
      Rectangle().fill(Color.white).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #expect(result.placedTree.children.count == 1)
    #expect(
      result.placedTree.children[0].bounds
        == .init(origin: .init(x: 6, y: 2), size: .init(width: 3, height: 1)))
  }

  @Test func setA435UnplacedSubviewUsesItsOwnCenteredDefaultPlacement() {
    // Hypothesis: an omitted subview borrows another child's placement instead of the documented center fallback.
    let layout = SetAProbeLayout(
      measure: { _, _, _ in .init(width: 11, height: 7) },
      place: { bounds, _, children, _ in
        children[0].place(at: bounds.origin, proposal: .unspecified)
      })
    let result = render(layout) {
      Text("A")
      Text("BBB").frame(width: 3, height: 2)
    }
    #expect(result.placedTree.children[0].bounds.origin == .zero)
    #expect(result.placedTree.children[1].bounds.origin == .init(x: 4, y: 2))
  }

  @Test func setA436PlacementCallOrderDoesNotReverseSubviewPaintOrder() {
    // Hypothesis: the placement recorder's insertion order becomes paint order when a layout places in reverse.
    let layout = SetAProbeLayout(
      measure: { _, _, _ in .init(width: 1, height: 1) },
      place: { bounds, _, children, _ in
        for child in children.reversed() { child.place(at: bounds.origin, proposal: .unspecified) }
      })
    let result = render(layout) {
      Text("A")
      Text("B")
    }
    #expect(result.rasterSurface.lines == ["B"])
    #expect(result.placedTree.children.count == 2)
  }

  @Test func setA437PlacementReceivesTheCacheWrittenByMeasurement() {
    // Hypothesis: erasure reconstructs Cache between measuring and placing, dropping author-produced data.
    let layout = SetAProbeLayout(
      measure: { _, _, cache in
        cache.value = 7
        return .init(width: 12, height: 1)
      },
      place: { bounds, _, children, cache in
        children[0].place(
          at: .init(x: bounds.origin.x + cache.value, y: bounds.origin.y), proposal: .unspecified)
      })
    let result = render(layout) { Text("X") }
    #expect(result.placedTree.children[0].bounds.origin.x == 7)
  }

  @Test func setA438SpacingHookCannotOverwriteTheMeasurePlaceCache() {
    // Hypothesis: spacing's disposable cache shares writable storage with the cache prepared for placement.
    let probe = SetALayoutProbe()
    let layout = SetAProbeLayout(
      measure: { _, _, cache in
        cache.value = 6
        return .init(width: 10, height: 1)
      },
      place: { bounds, _, children, cache in
        children[0].place(
          at: .init(x: bounds.origin.x + cache.value, y: bounds.origin.y), proposal: .unspecified)
      },
      spacingHook: { _, cache in
        probe.record([cache.value])
        cache.value = 99
        return .init(horizontal: 4)
      })
    let node = resolve(layout) { Text("X") }
    let engine = LayoutEngine()
    let context = LayoutPassContext()
    let measured = engine.measure(node, passContext: context)
    #expect(engine.effectiveSpacing(for: node, passContext: context).horizontal == 4)
    let placed = engine.place(node, measured: measured, origin: .zero, passContext: context)
    #expect(placed.children[0].bounds.origin.x == 6)
    expectRecords(probe, equal: [0])
  }

  @Test func setA439AlignmentHookMutationsAreDiscardedBeforePlacement() {
    // Hypothesis: asking an explicit guide mutates the shared author cache and changes later placement.
    let layout = SetAProbeLayout(
      measure: { _, _, cache in
        cache.value = 5
        return .init(width: 10, height: 2)
      },
      place: { bounds, _, children, cache in
        children[0].place(
          at: .init(x: bounds.origin.x + cache.value, y: bounds.origin.y), proposal: .unspecified)
      },
      horizontalGuide: { guide, _, _, _, cache in
        guard guide == .leading else { return nil }
        cache.value = 88
        return 2
      })
    let node = resolve(layout) { Text("X") }
    let engine = LayoutEngine()
    let context = LayoutPassContext()
    let measured = engine.measure(node, passContext: context)
    #expect(
      engine.viewDimensions(for: node, measured: measured, passContext: context)[.leading] == 2)
    let placed = engine.place(node, measured: measured, origin: .zero, passContext: context)
    #expect(placed.children[0].bounds.origin.x == 5)
  }

  @Test func setA440ProposalSpecificCachesDoNotBorrowTheLastProbeValue() {
    // Hypothesis: multiple custom-layout probes share one cache slot, so width 9 overwrites width 5's placement data.
    let child = SetAProbeLayout(
      measure: { proposal, _, cache in
        cache.value = setAFiniteDimension(proposal.width, fallback: 1)
        return .init(width: cache.value, height: 1)
      },
      place: { bounds, _, children, cache in
        children[0].place(
          at: .init(x: bounds.origin.x + cache.value - 1, y: bounds.origin.y),
          proposal: .unspecified)
      })
    let parent = SetAProbeLayout(
      measure: { _, children, _ in
        _ = children[0].sizeThatFits(.init(width: 5, height: 1))
        _ = children[0].sizeThatFits(.init(width: 9, height: 1))
        return .init(width: 12, height: 1)
      },
      place: { bounds, _, children, _ in
        children[0].place(at: bounds.origin, proposal: .init(width: 5, height: 1))
      })
    let result = render(parent) { child { Text("X") } }
    #expect(result.placedTree.children[0].bounds.size.width == 5)
    #expect(result.placedTree.children[0].children[0].bounds.origin.x == 4)
  }

  @Test func setA441StructuralGroupsFlattenIntoTheLayoutsDirectSubviews() {
    // Hypothesis: Group or ForEach wrappers become phantom layout children and alter author indexing.
    let probe = SetALayoutProbe()
    let layout = SetAProbeLayout(measure: { _, children, _ in
      probe.record(children.map { $0[SetALayoutFirstKey.self] })
      return .init(width: 12, height: 1)
    })
    _ = render(layout) {
      Group {
        Text("A").layoutValue(key: SetALayoutFirstKey.self, value: 1)
        Text("B").layoutValue(key: SetALayoutFirstKey.self, value: 2)
      }
      ForEach([3, 4], id: \.self) { value in
        Text("item").layoutValue(key: SetALayoutFirstKey.self, value: value)
      }
    }
    expectRecords(probe, equal: [1, 2, 3, 4])
  }

  @Test func setA442NestedCustomLayoutRemainsOneSubviewOfItsParent() {
    // Hypothesis: flattening that is valid for Group incorrectly exposes a nested layout's children to its parent.
    let outer = SetALayoutProbe()
    let inner = SetALayoutProbe()
    let parent = SetAProbeLayout(measure: { _, children, _ in
      outer.record([children.count])
      return .init(width: 15, height: 3)
    })
    let child = SetAProbeLayout(measure: { _, children, _ in
      inner.record([children.count])
      return .init(width: 5, height: 1)
    })
    _ = render(parent) {
      child {
        Text("A")
        Text("B")
      }
      Text("C")
    }
    expectRecords(outer, equal: [2])
    expectRecords(inner, equal: [2])
  }

  @Test func setA443GeometryReaderSeesTheCustomPlacementProposal() {
    // Hypothesis: deferred geometry content uses the earlier measure offer after custom placement narrows the child.
    let layout = SetAProbeLayout(
      measure: { _, children, _ in
        _ = children[0].sizeThatFits(.init(width: 12, height: 1))
        return .init(width: 12, height: 1)
      },
      place: { bounds, _, children, _ in
        children[0].place(at: bounds.origin, proposal: .init(width: 5, height: 1))
      })
    let result = render(layout) {
      GeometryReader { proxy in Text("w\(proxy.size.width)") }
    }
    #expect(result.placedTree.children[0].bounds.size.width == 5)
    #expect(result.rasterSurface.lines.joined().contains("w5"))
    #expect(!result.rasterSurface.lines.joined().contains("w12"))
  }

  @Test func setA444AnyLayoutSwitchesConcreteCacheTypesWithoutLosingChildState() throws {
    // Hypothesis: replacing an erased layout either reuses an incompatible cache or remounts unchanged content.
    let h = try harness(444) { SetAErasedLayoutSwitch() }
    defer { h.shutdown() }
    try h.clickText("Local 0")
    try #require(h.frame.contains("Local 1"))
    try h.clickText("Switch algorithm")
    #expect(h.frame.contains("Local 1"))
    let counter = try #require(h.point(forText: "Local 1"))
    let marker = try #require(h.point(forText: "Marker"))
    #expect(counter.y < marker.y)
    try h.clickText("Local 1")
    #expect(h.frame.contains("Local 2"))
  }

  @Test func setA445LayoutValuesWithEqualDescriptionsStillInvalidateGeometry() throws {
    // Hypothesis: metadata equality compares debug strings and hides a changed typed value with the same description.
    // This fixture reproduces a fatal shadow mismatch (retained x=0, fresh x=6). Suppress
    // only this synchronous fixture's shadow probe so ordinary geometry assertions report it.
    let suppression = SoundnessProbeSuppression()
    defer { suppression.restore() }
    let cold = render(SetAValuePositionLayout()) {
      Text("Mover").layoutValue(key: SetADescribedLayoutKey.self, value: .init(offset: 6))
    }
    #expect(cold.placedTree.children[0].bounds.origin.x == 6)
    let h = try harness(445) { SetADescribedLayoutValueFixture() }
    defer { h.shutdown() }
    let first = try #require(h.point(forText: "Mover"))
    try h.clickText("Change typed value")
    let second = try #require(h.point(forText: "Mover"))
    withKnownIssue("STUI-983: equal debug descriptions hide changed typed layout values") {
      #expect(second.x - first.x == 6, "Retained x=\(second.x), initial x=\(first.x), cold x=6")
    }
    try h.clickText("Change typed value")
    #expect(try #require(h.point(forText: "Mover")) == first)
  }

  @Test func setA446ChangedMeasurementSignatureRefreshesParentAllocation() throws {
    // Hypothesis: a custom layout's measurement signature changes but its parent retains the prior allocation.
    let h = try harness(446) { SetASignatureLayoutFixture(changesMeasurement: true) }
    defer { h.shutdown() }
    let first = try #require(h.point(forText: "Tail"))
    try h.clickText("Change layout field")
    let next = try #require(h.point(forText: "Tail"))
    #expect(next.x - first.x == 7)
    try h.clickText("Change layout field")
    #expect(try #require(h.point(forText: "Tail")) == first)
  }

  @Test func setA447PlacementSignatureCanChangeWithoutChangingMeasurement() throws {
    // Hypothesis: retained measurement reuse suppresses a changed custom placement signature.
    let h = try harness(447) { SetASignatureLayoutFixture(changesMeasurement: false) }
    defer { h.shutdown() }
    let first = try #require(h.point(forText: "Mover"))
    let tail = try #require(h.point(forText: "Tail"))
    try h.clickText("Change layout field")
    #expect(try #require(h.point(forText: "Mover")).x - first.x == 7)
    #expect(try #require(h.point(forText: "Tail")) == tail)
  }

  @Test func setA448ReusedErasedLayoutKeepsSeparateCachesForSiblingContainers() {
    // Hypothesis: two containers sharing the same AnyLayout box overwrite each other's per-identity cache.
    let layout = AnyLayout(
      SetAProbeLayout(
        measure: { _, children, cache in
          cache.value = children.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width }
          return .init(width: 20, height: 1)
        },
        place: { bounds, _, children, cache in
          for child in children {
            child.place(
              at: .init(x: bounds.origin.x + cache.value, y: bounds.origin.y),
              proposal: .unspecified)
          }
        }))
    let result = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        layout { Text("A") }
        layout { Text("BBBB") }
      })
    let children = result.placedTree.children
    #expect(children[0].children[0].bounds.origin.x == 1)
    #expect(children[1].children[0].bounds.origin.x == 4)
  }

  @Test func setA449ExplicitZeroPriorityReplacesAnEarlierNonzeroPriority() {
    // Hypothesis: zero is treated as absent metadata, so a later layoutPriority(0) cannot reset a child's priority.
    let probe = SetALayoutProbe()
    let layout = SetAProbeLayout(measure: { _, children, _ in
      probe.record([Int(children[0].layoutPriority)])
      return .init(width: 10, height: 1)
    })
    _ = render(layout) { Text("priority").layoutPriority(9).layoutPriority(0) }
    let records = probe.records
    #expect(!records.isEmpty)
    withKnownIssue("STUI-984: zero priority is mistaken for absent metadata") {
      #expect(records.allSatisfy { $0 == [0] }, "Expected [0], got \(records)")
    }
  }

  @Test func setA450EmptyCustomLayoutStillSuppliesItsAuthoredSize() {
    // Hypothesis: an empty-child fast path bypasses custom sizeThatFits and collapses a nonzero layout to zero.
    let probe = SetALayoutProbe()
    let layout = SetAProbeLayout(
      measure: { _, children, _ in
        probe.record([children.count])
        return .init(width: 7, height: 3)
      })
    let result = render(layout) { EmptyView() }
    #expect(result.placedTree.bounds.size == .init(width: 7, height: 3))
    #expect(result.placedTree.children.isEmpty)
    #expect(probe.records.contains([0]))
  }

  private func render<L: Layout, V: View>(_ layout: L, @ViewBuilder content: () -> V)
    -> RenderSnapshot
  {
    DefaultRenderer().render(
      layout { content() }, context: .init(identity: testIdentity("SetACustomLayout")))
  }

  private func resolve<L: Layout, V: View>(_ layout: L, @ViewBuilder content: () -> V)
    -> ResolvedNode
  {
    Resolver().resolve(layout { content() }, in: .init(identity: testIdentity("SetACustomLayout")))
  }

  private func expectRecords(_ probe: SetALayoutProbe, equal expected: [Int]) {
    let records = probe.records
    #expect(!records.isEmpty)
    #expect(records.allSatisfy { $0 == expected }, "Expected \(expected), got \(records)")
  }

  private func harness<V: View>(_ number: Int, @ViewBuilder content: @escaping () -> V) throws
    -> StressRuntimeHarness<V>
  {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetACustomLayout\(number)"), size: .init(width: 60, height: 16),
      content: content)
  }
}

private final class SetALayoutProbe: Sendable {
  private let storage = Mutex<[[Int]]>([])
  var records: [[Int]] { storage.withLock { $0 } }
  func record(_ values: [Int]) { storage.withLock { $0.append(values) } }
}

private func setAFiniteDimension(_ dimension: ProposedDimension, fallback: Int) -> Int {
  if case .finite(let value) = dimension { return value }
  return fallback
}

private struct SetAProbeLayout: Layout {
  struct Cache: Sendable { var value = 0 }
  var measure: @Sendable (ProposedViewSize, LayoutSubviews, inout Cache) -> LayoutSize = {
    _, _, _ in .init(width: 20, height: 12)
  }
  var place: @Sendable (LayoutRect, ProposedViewSize, LayoutSubviews, inout Cache) -> Void = {
    bounds, _, children, _ in
    for (index, child) in children.enumerated() {
      child.place(at: .init(x: bounds.origin.x, y: bounds.origin.y + index), proposal: .unspecified)
    }
  }
  var spacingHook: (@Sendable (LayoutSubviews, inout Cache) -> ViewSpacing)? = nil
  var horizontalGuide:
    (
      @Sendable (HorizontalAlignment, LayoutRect, ProposedViewSize, LayoutSubviews, inout Cache) ->
        Int?
    )? = nil
  var verticalGuide:
    (
      @Sendable (VerticalAlignment, LayoutRect, ProposedViewSize, LayoutSubviews, inout Cache) ->
        Int?
    )? = nil

  func makeCache(subviews: LayoutSubviews) -> Cache { Cache() }
  func updateCache(_ cache: inout Cache, subviews: LayoutSubviews) {}
  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Cache)
    -> LayoutSize
  {
    measure(proposal, subviews, &cache)
  }
  func placeSubviews(
    in bounds: LayoutRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Cache
  ) {
    place(bounds, proposal, subviews, &cache)
  }
  func spacing(subviews: LayoutSubviews, cache: inout Cache) -> ViewSpacing {
    spacingHook?(subviews, &cache)
      ?? subviews.reduce(into: ViewSpacing()) { $0.formUnion($1.spacing) }
  }
  func explicitAlignment(
    of guide: HorizontalAlignment, in bounds: LayoutRect, proposal: ProposedViewSize,
    subviews: LayoutSubviews, cache: inout Cache
  ) -> Int? {
    horizontalGuide?(guide, bounds, proposal, subviews, &cache)
  }
  func explicitAlignment(
    of guide: VerticalAlignment, in bounds: LayoutRect, proposal: ProposedViewSize,
    subviews: LayoutSubviews, cache: inout Cache
  ) -> Int? {
    verticalGuide?(guide, bounds, proposal, subviews, &cache)
  }
}

private enum SetALayoutFirstKey: LayoutValueKey { static let defaultValue = -3 }
private enum SetALayoutSecondKey: LayoutValueKey { static let defaultValue = -8 }
private enum SetAOptionalLayoutKey: LayoutValueKey { static let defaultValue: Int? = 17 }
private enum SetASharedAlignmentID: AlignmentID {
  static func defaultValue(in context: ViewDimensions) -> Int { 0 }
}

private struct SetADescribedLayoutValue: Sendable, CustomStringConvertible {
  var offset: Int
  var description: String { "opaque-layout-value" }
}
private enum SetADescribedLayoutKey: LayoutValueKey {
  static let defaultValue = SetADescribedLayoutValue(offset: 0)
}

@MainActor
private struct SetADescribedLayoutValueFixture: View {
  @State private var shifted = false
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Change typed value") { shifted.toggle() }
      SetAValuePositionLayout {
        Text("Mover").layoutValue(
          key: SetADescribedLayoutKey.self, value: .init(offset: shifted ? 6 : 0))
      }
    }
  }
}

private struct SetAValuePositionLayout: Layout {
  var measurementReuseSignature: String? { "value-position-size" }
  var placementReuseSignature: String? { "value-position-placement" }
  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void)
    -> LayoutSize
  {
    .init(width: 20, height: 1)
  }
  func placeSubviews(
    in bounds: LayoutRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void
  ) {
    for child in subviews {
      child.place(
        at: .init(
          x: bounds.origin.x + child[SetADescribedLayoutKey.self].offset, y: bounds.origin.y),
        proposal: .unspecified)
    }
  }
}

@MainActor
private struct SetASignatureLayoutFixture: View {
  var changesMeasurement: Bool
  @State private var expanded = false
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Change layout field") { expanded.toggle() }
      HStack(alignment: .top, spacing: 0) {
        SetASignatureLayout(
          width: changesMeasurement && expanded ? 27 : 20,
          offset: !changesMeasurement && expanded ? 7 : 0
        ) { Text("Mover") }
        Text("Tail")
      }
    }
  }
}

private struct SetASignatureLayout: Layout {
  var width: Int
  var offset: Int
  var measurementReuseSignature: String? { "width=\(width)" }
  var placementReuseSignature: String? { "offset=\(offset)" }
  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void)
    -> LayoutSize
  {
    .init(width: width, height: 1)
  }
  func placeSubviews(
    in bounds: LayoutRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void
  ) {
    for child in subviews {
      child.place(
        at: .init(x: bounds.origin.x + offset, y: bounds.origin.y), proposal: .unspecified)
    }
  }
}

@MainActor
private struct SetAErasedLayoutSwitch: View {
  @State private var vertical = false
  var body: some View {
    let layout = vertical ? AnyLayout(SetAStringCacheColumn()) : AnyLayout(SetAIntCacheRow())
    VStack(alignment: .leading, spacing: 0) {
      Button("Switch algorithm") { vertical.toggle() }
      layout {
        SetALayoutCounter()
        Text("Marker")
      }
    }
  }
}

@MainActor
private struct SetALayoutCounter: View {
  @State private var count = 0
  var body: some View { Button("Local \(count)") { count += 1 } }
}

private struct SetAIntCacheRow: Layout {
  func makeCache(subviews: LayoutSubviews) -> Int { 9 }
  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Int)
    -> LayoutSize
  {
    .init(width: 30, height: 2)
  }
  func placeSubviews(
    in bounds: LayoutRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Int
  ) {
    for (index, child) in subviews.enumerated() {
      child.place(
        at: .init(x: bounds.origin.x + index * cache, y: bounds.origin.y), proposal: .unspecified)
    }
  }
}

private struct SetAStringCacheColumn: Layout {
  func makeCache(subviews: LayoutSubviews) -> String { "2" }
  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout String)
    -> LayoutSize
  {
    .init(width: 30, height: 5)
  }
  func placeSubviews(
    in bounds: LayoutRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout String
  ) {
    for (index, child) in subviews.enumerated() {
      child.place(
        at: .init(x: bounds.origin.x, y: bounds.origin.y + index * (Int(cache) ?? 9)),
        proposal: .unspecified)
    }
  }
}
