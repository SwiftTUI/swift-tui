import TerminalUI

/// Source-of-truth list of every layout in the Layouts example app.
///
/// The app picker iterates this to render the list; the parameterised
/// smoke test iterates it to prove every entry resolves. Adding a
/// layout is one struct literal in ``all`` — do not introduce any
/// other registration seam.
public enum LayoutCatalog {
  /// All 56 layouts, in picker display order.
  ///
  /// Entries are appended as their underlying layout file lands;
  /// the list is deliberately sparse during the mid-implementation
  /// phase of the plan. `LayoutCatalog` is complete once 56 entries
  /// are listed and `CatalogIntegrityTests.entries_coverAllCategories`
  /// passes.
  public static let all: [LayoutEntry] = [
    // AnyView policy: `makeView` is the single documented AnyView seam
    // for the heterogeneous catalog. Every concrete layout below is a
    // strongly-typed `View`; erasure happens only in the closure.
    LayoutEntry(
      id: "stacks.hstack-alignment-triad",
      category: .stacks,
      title: "HStack alignment triad",
      blurb: ".top vs .center vs .bottom with mixed-height children",
      marker: "HStack alignment triad",
      tier: .behaviour,
      makeView: { AnyView(HStackAlignmentTriad()) }
    ),
    LayoutEntry(
      id: "stacks.vstack-spacing-vs-padding",
      category: .stacks,
      title: "VStack spacing vs padding",
      blurb: "spacing lives between siblings; padding wraps each",
      marker: "VStack spacing vs padding",
      tier: .smoke,
      makeView: { AnyView(VStackSpacingVsPadding()) }
    ),
    LayoutEntry(
      id: "stacks.zstack-alignment-grid",
      category: .stacks,
      title: "ZStack alignment grid",
      blurb: "9 cells: every alignment with a marker child",
      marker: "ZStack alignment grid",
      tier: .behaviour,
      makeView: { AnyView(ZStackAlignmentGrid()) }
    ),
    LayoutEntry(
      id: "stacks.hstack-priority-tug",
      category: .stacks,
      title: "HStack priority tug",
      blurb: "priorities 0/1/0 under squeeze",
      marker: "HStack priority tug",
      tier: .behaviour,
      makeView: { AnyView(HStackPriorityTug()) }
    ),
    LayoutEntry(
      id: "stacks.vstack-leading-guide-shift",
      category: .stacks,
      title: "VStack leading guide shift",
      blurb: "one row shifted via .alignmentGuide(.leading) { _ in 4 }",
      marker: "VStack leading guide shift",
      tier: .behaviour,
      makeView: { AnyView(VStackLeadingGuideShift()) }
    ),
    LayoutEntry(
      id: "frames.frame-fixed-inside-unbounded",
      category: .frames,
      title: "Frame fixed inside unbounded",
      blurb: "fixed frame in infinite vs tight parent",
      marker: "Frame fixed inside unbounded",
      tier: .smoke,
      makeView: { AnyView(FrameFixedInsideUnbounded()) }
    ),
    LayoutEntry(
      id: "frames.flexible-frame-alignment-grid",
      category: .frames,
      title: "Flexible frame alignment grid",
      blurb: "9 cells exercising every alignment",
      marker: "Flexible frame alignment grid",
      tier: .behaviour,
      makeView: { AnyView(FlexibleFrameAlignmentGrid()) }
    ),
    LayoutEntry(
      id: "frames.fixed-size-text",
      category: .frames,
      title: "FixedSize text",
      blurb: "narrow parent + .fixedSize() → content escapes",
      marker: "FixedSize text",
      tier: .behaviour,
      makeView: { AnyView(FixedSizeText()) }
    ),
    LayoutEntry(
      id: "frames.fixed-size-one-axis",
      category: .frames,
      title: "FixedSize one axis",
      blurb: "wrap horizontally, don't stretch vertically",
      marker: "FixedSize one axis",
      tier: .behaviour,
      makeView: { AnyView(FixedSizeOneAxis()) }
    ),
    LayoutEntry(
      id: "frames.min-ideal-max-frame-clamp",
      category: .frames,
      title: "Min ideal max frame clamp",
      blurb: "clamp points under 3 proposals",
      marker: "Min ideal max frame clamp",
      tier: .behaviour,
      makeView: { AnyView(MinIdealMaxFrameClamp()) }
    ),
    LayoutEntry(
      id: "frames.layout-priority-cascade",
      category: .frames,
      title: "Layout priority cascade",
      blurb: "priorities 0/1/0/2 drop order",
      marker: "Layout priority cascade",
      tier: .behaviour,
      makeView: { AnyView(LayoutPriorityCascade()) }
    ),
    LayoutEntry(
      id: "frames.proposal-tightening",
      category: .frames,
      title: "Proposal tightening",
      blurb: ".frame(width:30) caps inner GeometryReader proxy",
      marker: "Proposal tightening",
      tier: .behaviour,
      makeView: { AnyView(ProposalTightening()) }
    ),
    LayoutEntry(
      id: "frames.intrinsic-text-under-zero-proposal",
      category: .frames,
      title: "Intrinsic text under zero proposal",
      blurb: "Text at 0×0 proposal",
      marker: "Intrinsic text under zero proposal",
      tier: .behaviour,
      makeView: { AnyView(IntrinsicTextUnderZeroProposal()) }
    ),
    LayoutEntry(
      id: "padding.asymmetric-padding-insets",
      category: .padding,
      title: "Asymmetric padding insets",
      blurb: "EdgeInsets with asymmetric top/leading/bottom/trailing",
      marker: "Asymmetric padding insets",
      tier: .smoke,
      makeView: { AnyView(AsymmetricPaddingInsets()) }
    ),
    LayoutEntry(
      id: "padding.border-ordering",
      category: .padding,
      title: "Padding border ordering",
      blurb: ".padding.border vs .border.padding give different widths",
      marker: "Padding border ordering",
      tier: .behaviour,
      makeView: { AnyView(PaddingBorderOrdering()) }
    ),
    LayoutEntry(
      id: "padding.safe-area-inset-bottom-bar",
      category: .padding,
      title: "Safe area inset bottom bar",
      blurb: "bar pinned bottom; inner proposal reduced",
      marker: "Safe area inset bottom bar",
      tier: .behaviour,
      makeView: { AnyView(SafeAreaInsetBottomBar()) }
    ),
    LayoutEntry(
      id: "padding.ignores-safe-area-bleed",
      category: .padding,
      title: "Ignores safe area bleed",
      blurb: "content paints through the safe area bar zone",
      marker: "Ignores safe area bleed",
      tier: .behaviour,
      makeView: { AnyView(IgnoresSafeAreaBleed()) }
    ),
    LayoutEntry(
      id: "borders.background-vs-overlay-paint-order",
      category: .bordersOverlays,
      title: "Background vs overlay paint order",
      blurb: "overlay wins at cell collisions; background loses",
      marker: "Background vs overlay paint order",
      tier: .behaviour,
      makeView: { AnyView(BackgroundVsOverlayPaintOrder()) }
    ),
    LayoutEntry(
      id: "borders.nested-border-ordering",
      category: .bordersOverlays,
      title: "Nested border ordering",
      blurb: "two concentric rings; inner hugs content, outer hugs padding",
      marker: "Nested border ordering",
      tier: .behaviour,
      makeView: { AnyView(NestedBorderOrdering()) }
    ),
    LayoutEntry(
      id: "borders.per-side-border-colors",
      category: .bordersOverlays,
      title: "Per-side border colors",
      blurb: "BorderEdgeStyle 4-color",
      marker: "Per-side border colors",
      tier: .behaviour,
      makeView: { AnyView(PerSideBorderColors()) }
    ),
    LayoutEntry(
      id: "borders.border-blend-static-phase",
      category: .bordersOverlays,
      title: "Border blend static phase",
      blurb: "phase 0 vs 0.5; no RunLoop",
      marker: "Border blend static phase",
      tier: .behaviour,
      makeView: { AnyView(BorderBlendStaticPhase()) }
    ),
    LayoutEntry(
      id: "borders.background-shapestyle-vs-content-overloads",
      category: .bordersOverlays,
      title: "Background ShapeStyle vs Content overloads",
      blurb: ".background(.tint) vs .background { Rectangle }",
      marker: "Background ShapeStyle vs Content overloads",
      tier: .smoke,
      makeView: { AnyView(BackgroundShapeStyleVsContentOverloads()) }
    ),
    LayoutEntry(
      id: "borders.overlay-alignment-badge",
      category: .bordersOverlays,
      title: "Overlay alignment badge",
      blurb: "overlay(alignment: .bottomTrailing) anchors at corner",
      marker: "Overlay alignment badge",
      tier: .behaviour,
      makeView: { AnyView(OverlayAlignmentBadge()) }
    ),
    LayoutEntry(
      id: "offset.preserves-measured-size",
      category: .offsetPosition,
      title: "Offset preserves measured size",
      blurb: "offset shifts paint only, not layout",
      marker: "Offset preserves measured size",
      tier: .behaviour,
      makeView: { AnyView(OffsetPreservesMeasuredSize()) }
    ),
    LayoutEntry(
      id: "offset.position-ignores-layout",
      category: .offsetPosition,
      title: "Position ignores layout",
      blurb: ".position(x:y:) anchors child at an absolute point",
      marker: "Position ignores layout",
      tier: .behaviour,
      makeView: { AnyView(PositionIgnoresLayout()) }
    ),
    LayoutEntry(
      id: "offset.clipped-overflow-crop",
      category: .offsetPosition,
      title: "Clipped overflow crop",
      blurb: ".clipped() drops content past its frame",
      marker: "Clipped overflow crop",
      tier: .behaviour,
      makeView: { AnyView(ClippedOverflowCrop()) }
    ),
    LayoutEntry(
      id: "offset.negative-escape",
      category: .offsetPosition,
      title: "Negative offset escape",
      blurb: ".offset(x: -2) paints outside parent frame",
      marker: "Negative offset escape",
      tier: .behaviour,
      makeView: { AnyView(NegativeOffsetEscape()) }
    ),
    LayoutEntry(
      id: "zstack.paint-order-overlap",
      category: .zStack,
      title: "ZStack paint order overlap",
      blurb: "later paints over earlier at shared cells",
      marker: "ZStack paint order overlap",
      tier: .behaviour,
      makeView: { AnyView(ZStackPaintOrderOverlap()) }
    ),
    LayoutEntry(
      id: "zstack.sized-by-largest",
      category: .zStack,
      title: "ZStack sized by largest",
      blurb: "stack size equals the largest child's size",
      marker: "ZStack sized by largest",
      tier: .behaviour,
      makeView: { AnyView(ZStackSizedByLargest()) }
    ),
    LayoutEntry(
      id: "zstack.spacer-noop",
      category: .zStack,
      title: "ZStack spacer noop",
      blurb: "Spacer is a no-op for sizing in ZStack",
      marker: "ZStack spacer noop",
      tier: .behaviour,
      makeView: { AnyView(ZStackSpacerNoop()) }
    ),
  ]

  public static func entry(id: String) -> LayoutEntry? {
    all.first { $0.id == id }
  }
}
