import SwiftTUICore
import Synchronization
import Testing

@testable import SwiftTUIViews

/// Engine-level owning tests for the custom `Layout` container contract
/// (plan 2026-08-31-001): `layoutProperties`, `spacing(subviews:cache:)`,
/// and the two `explicitAlignment` hooks, carried through `AnyLayout` and
/// the core handle into stack spacing negotiation and parent alignment.
///
/// Fixtures are `ResolvedNode` trees built directly, so each assertion reads
/// one engine seam. The rendered-view counterparts live in
/// `SwiftTUITests/CustomLayoutContainerContractRenderTests.swift`.
@MainActor
@Suite("Custom layout container contract (plan 2026-08-31-001)")
struct CustomLayoutContainerContractTests {
  // MARK: layoutProperties

  @Test("built-in stack layouts declare their axis; the default declares none")
  func builtinStackLayoutsDeclareOrientation() {
    #expect(HStackLayout.layoutProperties.stackOrientation == .horizontal)
    #expect(VStackLayout.layoutProperties.stackOrientation == .vertical)
    #expect(ZStackLayout.layoutProperties.stackOrientation == nil)
    #expect(DefaultContractLayout.layoutProperties == LayoutProperties())
    #expect(HorizontalContractLayout.layoutProperties.stackOrientation == .horizontal)
  }

  @Test("AnyLayout carries the erased layout's traits per instance")
  func anyLayoutCarriesErasedTraits() {
    #expect(AnyLayout(HStackLayout()).resolvedLayoutProperties.stackOrientation == .horizontal)
    #expect(AnyLayout(VStackLayout()).resolvedLayoutProperties.stackOrientation == .vertical)
    #expect(
      AnyLayout(HorizontalContractLayout()).resolvedLayoutProperties.stackOrientation
        == .horizontal
    )
    #expect(
      AnyLayout(AnyLayout(HorizontalContractLayout())).resolvedLayoutProperties.stackOrientation
        == .horizontal
    )
    // The static requirement stays the default: traits are only known per
    // erased instance.
    #expect(AnyLayout.layoutProperties == LayoutProperties())
  }

  // MARK: ViewSpacing

  @Test("ViewSpacing.union takes the larger request per axis and tolerates nil")
  func viewSpacingUnion() {
    let declared = ViewSpacing(horizontal: 2, vertical: nil)
    let other = ViewSpacing(horizontal: 1, vertical: 3)
    #expect(declared.union(other) == ViewSpacing(horizontal: 2, vertical: 3))
    #expect(ViewSpacing().union(other) == other)
    #expect(other.union(ViewSpacing()) == other)
    #expect(ViewSpacing.zero == ViewSpacing(horizontal: 0, vertical: 0))
    var accumulated = ViewSpacing()
    accumulated.formUnion(declared)
    accumulated.formUnion(other)
    #expect(accumulated == ViewSpacing(horizontal: 2, vertical: 3))
  }

  // MARK: spacing(subviews:cache:)

  @Test("a declared vertical spacing widens the parent VStack's gap")
  func declaredVerticalSpacingReachesParentStack() {
    let engine = LayoutEngine()
    let declaring = stack(
      "declaring",
      axis: .vertical,
      children: [
        leaf("declaring-text", width: 4, height: 1),
        container("declaring-box", layout: SpacingContractLayout(vertical: 2)),
      ]
    )
    let silent = stack(
      "silent",
      axis: .vertical,
      children: [
        leaf("silent-text", width: 4, height: 1),
        container("silent-box", layout: DefaultContractLayout()),
      ]
    )

    let declaringMeasured = engine.measure(declaring, proposal: .unspecified)
    let silentMeasured = engine.measure(silent, proposal: .unspecified)

    // The box measures 4x1; the default vertical gap is 0 and the declared
    // gap is max(0, 2) = 2.
    #expect(silentMeasured.measuredSize.height == 2)
    #expect(declaringMeasured.measuredSize.height == 4)

    let placed = engine.place(declaring, measured: declaringMeasured)
    #expect(placed.children.map(\.bounds.origin.y) == [0, 3])
  }

  @Test("a declared horizontal spacing widens the parent HStack's gap")
  func declaredHorizontalSpacingReachesParentStack() {
    let engine = LayoutEngine()
    let row = stack(
      "row",
      axis: .horizontal,
      children: [
        leaf("row-text", width: 4, height: 1),
        container("row-box", layout: SpacingContractLayout(horizontal: 3)),
      ]
    )
    let measured = engine.measure(row, proposal: .unspecified)
    // 4 + max(1, 3) + 4.
    #expect(measured.measuredSize.width == 11)
    let placed = engine.place(row, measured: measured)
    #expect(placed.children.map(\.bounds.origin.x) == [0, 7])
  }

  @Test("an explicit stack spacing still overrides the container's declaration")
  func stackSpacingOverrideWins() {
    let engine = LayoutEngine()
    let row = stack(
      "row",
      axis: .horizontal,
      spacing: 1,
      children: [
        leaf("row-text", width: 4, height: 1),
        container("row-box", layout: SpacingContractLayout(horizontal: 3)),
      ]
    )
    #expect(engine.measure(row, proposal: .unspecified).measuredSize.width == 9)
  }

  @Test("the default spacing is the union of the subviews, so nested declarations flow up")
  func defaultSpacingUnionsNestedDeclarations() {
    let engine = LayoutEngine()
    let column = stack(
      "column",
      axis: .vertical,
      children: [
        leaf("column-text", width: 4, height: 1),
        ResolvedNode(
          identity: testIdentity("outer"),
          kind: .view("Outer"),
          children: [
            container("inner", layout: SpacingContractLayout(vertical: 2))
          ],
          layoutBehavior: AnyLayout(DefaultContractLayout()).resolvedBehavior
        ),
      ]
    )
    let measured = engine.measure(column, proposal: .unspecified)
    // text (1) + gap max(0, 2) + outer (4x1 box) = 4.
    #expect(measured.measuredSize.height == 4)
  }

  @Test("LayoutSubview.spacing reports a custom child's declaration")
  func layoutSubviewSpacingReportsDeclaration() {
    let engine = LayoutEngine()
    let declared = LayoutSubview(
      child: container("box", layout: SpacingContractLayout(horizontal: 3, vertical: 2)),
      engine: engine
    )
    let plain = LayoutSubview(child: leaf("text", width: 4, height: 1), engine: engine)
    #expect(declared.spacing == ViewSpacing(horizontal: 3, vertical: 2))
    #expect(plain.spacing == ViewSpacing())
  }

  @Test("the spacing hook runs once per pass with a pass context")
  func spacingHookIsMemoizedPerPass() {
    let probe = HookProbe()
    let engine = LayoutEngine()
    let column = stack(
      "column",
      axis: .vertical,
      children: [
        leaf("column-text", width: 4, height: 1),
        container("column-box", layout: ProbedContractLayout(probe: probe)),
      ]
    )
    let passContext = LayoutPassContext()
    let measured = engine.measure(
      column, proposal: .init(width: 20, height: 10), passContext: passContext)
    _ = engine.place(
      column,
      measured: measured,
      in: .init(origin: .zero, size: measured.measuredSize),
      passContext: passContext
    )
    #expect(probe.spacingCalls == 1)
  }

  @Test("the spacing hook never writes the persistent cache store")
  func spacingHookDoesNotWriteStore() {
    let store = CustomLayoutCacheStore()
    let engine = LayoutEngine()
    let column = stack(
      "column",
      axis: .vertical,
      children: [
        leaf("column-text", width: 4, height: 1),
        container("column-box", layout: SpacingContractLayout(vertical: 2)),
      ]
    )
    let passContext = LayoutPassContext(customLayoutCacheStore: store)
    let measured = engine.measure(
      column, proposal: .init(width: 20, height: 10), passContext: passContext)
    _ = engine.place(
      column,
      measured: measured,
      in: .init(origin: .zero, size: measured.measuredSize),
      passContext: passContext
    )
    // Exactly the container's placement records an update; nothing else.
    #expect(passContext.workerCustomLayoutCacheUpdates.count == 1)
    #expect(store.isEmpty)
  }

  // MARK: explicitAlignment

  @Test("a horizontal guide answer aggregates into a VStack(alignment:)")
  func horizontalGuideAggregatesIntoVStack() {
    let engine = LayoutEngine()
    let column = stack(
      "column",
      axis: .vertical,
      horizontalAlignment: .leading,
      children: [
        leaf("column-text", width: 6, height: 1),
        container("column-box", layout: AlignmentContractLayout(leading: 3)),
      ]
    )
    let measured = engine.measure(column, proposal: .unspecified)
    // leading = max(0, 3) = 3; trailing = max(6 - 0, 4 - 3) = 6.
    #expect(measured.measuredSize.width == 9)
    let placed = engine.place(column, measured: measured)
    #expect(placed.children.map(\.bounds.origin.x) == [3, 0])
  }

  @Test("a vertical guide answer aggregates into an HStack(alignment:)")
  func verticalGuideAggregatesIntoHStack() {
    let engine = LayoutEngine()
    let row = stack(
      "row",
      axis: .horizontal,
      verticalAlignment: .top,
      children: [
        leaf("row-text", width: 4, height: 1),
        container("row-box", layout: AlignmentContractLayout(top: 2, height: 3)),
      ]
    )
    let measured = engine.measure(row, proposal: .unspecified)
    // leading = max(0, 2) = 2; trailing = max(1 - 0, 3 - 2) = 1.
    #expect(measured.measuredSize.height == 3)
    let placed = engine.place(row, measured: measured)
    #expect(placed.children.map(\.bounds.origin.y) == [2, 0])
  }

  @Test("an alignmentGuide modifier on the container beats the layout's answer")
  func modifierGuideBeatsLayoutAnswer() {
    let engine = LayoutEngine()
    var box = container("column-box", layout: AlignmentContractLayout(leading: 3))
    box.layoutMetadata = box.layoutMetadata.settingHorizontalAlignmentGuide(
      .leading,
      debugName: "leading"
    ) { _ in 1 }
    let column = stack(
      "column",
      axis: .vertical,
      horizontalAlignment: .leading,
      children: [leaf("column-text", width: 6, height: 1), box]
    )
    let measured = engine.measure(column, proposal: .unspecified)
    let placed = engine.place(column, measured: measured)
    #expect(placed.children.map(\.bounds.origin.x) == [1, 0])
  }

  @Test("a frame(alignment:) honours the layout's guide answer (fast-path guard)")
  func frameAlignmentHonoursLayoutAnswer() {
    let engine = LayoutEngine()
    let answering = frame(
      "answering",
      width: 10,
      alignment: .init(horizontal: .leading, vertical: .top),
      child: container("answering-box", layout: AlignmentContractLayout(leading: 3))
    )
    let silent = frame(
      "silent",
      width: 10,
      alignment: .init(horizontal: .leading, vertical: .top),
      child: container("silent-box", layout: DefaultContractLayout())
    )
    let answeringPlaced = engine.place(answering, measured: engine.measure(answering))
    let silentPlaced = engine.place(silent, measured: engine.measure(silent))
    // The guide is pulled onto the frame's leading edge: the container
    // starts three cells left of it.
    #expect(answeringPlaced.children.map(\.bounds.origin.x) == [-3])
    #expect(silentPlaced.children.map(\.bounds.origin.x) == [0])
  }

  @Test("LayoutSubview.dimensions exposes a nested custom child's guide answer")
  func layoutSubviewDimensionsExposeAnswer() {
    let engine = LayoutEngine()
    let subview = LayoutSubview(
      child: container("box", layout: AlignmentContractLayout(leading: 3)),
      engine: engine
    )
    let dimensions = subview.dimensions(in: .unspecified)
    #expect(dimensions[.leading] == 3)
    #expect(dimensions[.trailing] == 4)
    #expect(dimensions[HorizontalAlignment.center] == 2)
  }

  @Test("double erasure forwards spacing and alignment answers")
  func doubleErasureForwardsAnswers() {
    let engine = LayoutEngine()
    let box = ResolvedNode(
      identity: testIdentity("box"),
      kind: .view("Box"),
      children: [leaf("box-a", width: 4, height: 1)],
      layoutBehavior: AnyLayout(AnyLayout(AlignmentContractLayout(leading: 3))).resolvedBehavior
    )
    #expect(engine.dimensions(of: box)[.leading] == 3)
    let spaced = ResolvedNode(
      identity: testIdentity("spaced"),
      kind: .view("Spaced"),
      children: [leaf("spaced-a", width: 4, height: 1)],
      layoutBehavior: AnyLayout(AnyLayout(SpacingContractLayout(horizontal: 3, vertical: 2)))
        .resolvedBehavior
    )
    #expect(
      engine.effectiveSpacing(for: spaced, passContext: nil)
        == Spacing(horizontal: 3, vertical: 2)
    )
  }

  @Test("the alignment hook runs once per guide and proposal within a pass")
  func alignmentHookIsMemoizedPerPass() {
    let probe = HookProbe()
    let engine = LayoutEngine()
    let box = container("column-box", layout: ProbedContractLayout(probe: probe))
    let column = stack(
      "column",
      axis: .vertical,
      horizontalAlignment: .leading,
      children: [leaf("column-text", width: 6, height: 1), box]
    )
    let passContext = LayoutPassContext()
    let measured = engine.measure(
      column, proposal: .init(width: 20, height: 10), passContext: passContext)
    _ = engine.place(
      column,
      measured: measured,
      in: .init(origin: .zero, size: measured.measuredSize),
      passContext: passContext
    )
    // The stack measures the box under distinct proposals (ideal, then
    // allocated) and reads its `.leading` guide for each; the answer may
    // depend on the proposal, so each distinct proposal is one question.
    let distinctProposals = Set(measured.childMeasurements.map(\.proposal)).count
    let callsAfterPass = probe.horizontalAlignmentCalls
    #expect(callsAfterPass >= 1)
    #expect(callsAfterPass <= max(2, distinctProposals))

    // Re-reading the same guide at an already-measured proposal within the
    // same pass is a memo hit, however many times it happens.
    let boxMeasurement = measured.childMeasurements[1]
    for _ in 0..<3 {
      let dimensions = engine.dimensions(
        of: box, proposal: boxMeasurement.proposal, passContext: passContext)
      #expect(dimensions[.leading] == 3)
    }
    #expect(probe.horizontalAlignmentCalls == callsAfterPass)

    // A different pass has its own memo: reading the guide asks once more.
    // (The providers are lazy — the guide must actually be read.)
    let freshDimensions = engine.dimensions(
      of: box, proposal: boxMeasurement.proposal, passContext: LayoutPassContext())
    #expect(freshDimensions[.leading] == 3)
    #expect(probe.horizontalAlignmentCalls == callsAfterPass + 1)
  }

  @Test("a guide answered from a persisted cache matches a fresh pass")
  func persistedCacheAnswersGuideConsistently() {
    let store = CustomLayoutCacheStore()
    let engine = LayoutEngine()
    let proposal = ProposedSize(width: 20, height: 10)
    let box = container("box", layout: PersistingAlignmentLayout(), childWidth: 4)

    let firstContext = LayoutPassContext(customLayoutCacheStore: store)
    let measured = engine.measure(box, proposal: proposal, passContext: firstContext)
    _ = engine.place(
      box,
      measured: measured,
      in: .init(origin: .zero, size: measured.measuredSize),
      passContext: firstContext
    )
    for update in firstContext.workerCustomLayoutCacheUpdates {
      update.apply()
    }
    #expect(!store.isEmpty)

    let secondContext = LayoutPassContext(customLayoutCacheStore: store)
    let dimensions = engine.dimensions(of: box, proposal: proposal, passContext: secondContext)
    #expect(dimensions[.leading] == 2)
    #expect(secondContext.runtimeIssues.isEmpty)
  }

  // MARK: Fixtures

  private func leaf(_ name: String, width: Int, height: Int) -> ResolvedNode {
    ResolvedNode(
      identity: testIdentity(name),
      kind: .view("Test"),
      intrinsicSize: .init(width: width, height: height)
    )
  }

  private func container(
    _ name: String,
    layout: some Layout,
    childWidth: Int = 4
  ) -> ResolvedNode {
    ResolvedNode(
      identity: testIdentity(name),
      kind: .view("ContractFixture"),
      children: [leaf("\(name)-a", width: childWidth, height: 1)],
      layoutBehavior: AnyLayout(layout).resolvedBehavior
    )
  }

  private func stack(
    _ name: String,
    axis: SwiftTUICore.Axis,
    spacing: Int? = nil,
    horizontalAlignment: HorizontalAlignment = .center,
    verticalAlignment: VerticalAlignment = .center,
    children: [ResolvedNode]
  ) -> ResolvedNode {
    ResolvedNode(
      identity: testIdentity(name),
      kind: .view(axis == .vertical ? "VStack" : "HStack"),
      children: children,
      layoutBehavior: .stack(
        axis: axis,
        spacing: spacing,
        horizontalAlignment: horizontalAlignment,
        verticalAlignment: verticalAlignment
      )
    )
  }

  private func frame(
    _ name: String,
    width: Int,
    alignment: Alignment,
    child: ResolvedNode
  ) -> ResolvedNode {
    ResolvedNode(
      identity: testIdentity(name),
      kind: .view("Frame"),
      children: [child],
      layoutBehavior: .frame(width: width, height: nil, alignment: alignment)
    )
  }
}

// MARK: - Fixture layouts

/// Sizes to its single child's width by one row; declares nothing.
private struct DefaultContractLayout: Layout {
  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    .init(width: subviews.first?.sizeThatFits(.unspecified).width ?? 0, height: 1)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    for subview in subviews {
      subview.place(
        at: bounds.origin,
        proposal: .init(width: bounds.size.width, height: bounds.size.height)
      )
    }
  }
}

private struct HorizontalContractLayout: Layout {
  static var layoutProperties: LayoutProperties {
    LayoutProperties(stackOrientation: .horizontal)
  }

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Void
  ) -> LayoutSize {
    DefaultContractLayout().sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Void
  ) {
    DefaultContractLayout().placeSubviews(
      in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
  }
}

private struct SpacingContractLayout: Layout {
  var horizontal: Int?
  var vertical: Int?

  init(horizontal: Int? = nil, vertical: Int? = nil) {
    self.horizontal = horizontal
    self.vertical = vertical
  }

  func spacing(subviews _: LayoutSubviews, cache _: inout Void) -> ViewSpacing {
    ViewSpacing(horizontal: horizontal, vertical: vertical)
  }

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Void
  ) -> LayoutSize {
    DefaultContractLayout().sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Void
  ) {
    DefaultContractLayout().placeSubviews(
      in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
  }
}

private struct AlignmentContractLayout: Layout {
  var leading: Int?
  var top: Int?
  var height: Int

  init(leading: Int? = nil, top: Int? = nil, height: Int = 1) {
    self.leading = leading
    self.top = top
    self.height = height
  }

  func explicitAlignment(
    of guide: HorizontalAlignment,
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews _: LayoutSubviews,
    cache _: inout Void
  ) -> Int? {
    // The bounds are the container's own, zero-origin.
    precondition(bounds.origin == .zero)
    return guide == .leading ? leading : nil
  }

  func explicitAlignment(
    of guide: VerticalAlignment,
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews _: LayoutSubviews,
    cache _: inout Void
  ) -> Int? {
    precondition(bounds.origin == .zero)
    return guide == .top ? top : nil
  }

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    .init(width: subviews.first?.sizeThatFits(.unspecified).width ?? 0, height: height)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Void
  ) {
    DefaultContractLayout().placeSubviews(
      in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
  }
}

/// Counts hook invocations.
private final class HookProbe: Sendable {
  private struct Counts: Sendable {
    var spacing = 0
    var horizontalAlignment = 0
  }

  private let counts = Mutex(Counts())

  var spacingCalls: Int {
    counts.withLock { $0.spacing }
  }

  var horizontalAlignmentCalls: Int {
    counts.withLock { $0.horizontalAlignment }
  }

  func recordSpacing() {
    counts.withLock { $0.spacing += 1 }
  }

  func recordHorizontalAlignment() {
    counts.withLock { $0.horizontalAlignment += 1 }
  }
}

private struct ProbedContractLayout: Layout {
  let probe: HookProbe

  func spacing(subviews _: LayoutSubviews, cache _: inout Void) -> ViewSpacing {
    probe.recordSpacing()
    return ViewSpacing(vertical: 2)
  }

  func explicitAlignment(
    of guide: HorizontalAlignment,
    in _: LayoutRect,
    proposal _: ProposedViewSize,
    subviews _: LayoutSubviews,
    cache _: inout Void
  ) -> Int? {
    probe.recordHorizontalAlignment()
    return guide == .leading ? 3 : nil
  }

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Void
  ) -> LayoutSize {
    DefaultContractLayout().sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Void
  ) {
    DefaultContractLayout().placeSubviews(
      in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
  }
}

/// A persisting layout (incremental `updateCache`) whose guide answer is
/// derived from the cache, so a served cache and a fresh one must agree.
private struct PersistingAlignmentLayout: Layout {
  struct Cache: Sendable {
    var leading: Int
  }

  func makeCache(subviews: LayoutSubviews) -> Cache {
    Cache(leading: (subviews.first?.sizeThatFits(.unspecified).width ?? 0) / 2)
  }

  func updateCache(_: inout Cache, subviews _: LayoutSubviews) {}

  func explicitAlignment(
    of guide: HorizontalAlignment,
    in _: LayoutRect,
    proposal _: ProposedViewSize,
    subviews _: LayoutSubviews,
    cache: inout Cache
  ) -> Int? {
    guide == .leading ? cache.leading : nil
  }

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Cache
  ) -> LayoutSize {
    .init(width: subviews.first?.sizeThatFits(.unspecified).width ?? 0, height: 1)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Cache
  ) {
    for subview in subviews {
      subview.place(
        at: bounds.origin,
        proposal: .init(width: bounds.size.width, height: bounds.size.height)
      )
    }
  }
}
