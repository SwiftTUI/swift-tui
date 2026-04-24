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
    LayoutEntry(
      id: "spacers.three-sharing",
      category: .spacers,
      title: "Three spacer sharing",
      blurb: "HStack with 3 Spacers splits residual equally",
      marker: "Three spacer sharing",
      tier: .behaviour,
      makeView: { AnyView(ThreeSpacerSharing()) }
    ),
    LayoutEntry(
      id: "spacers.min-length-respected",
      category: .spacers,
      title: "Spacer min length respected",
      blurb: "Spacer(minLength: 10) honored under tight proposal",
      marker: "Spacer min length respected",
      tier: .behaviour,
      makeView: { AnyView(SpacerMinLengthRespected()) }
    ),
    LayoutEntry(
      id: "spacers.divider-orientation-flip",
      category: .spacers,
      title: "Divider orientation flip",
      blurb: "Divider is a horizontal rule in VStack, vertical rule in HStack",
      marker: "Divider orientation flip",
      tier: .behaviour,
      makeView: { AnyView(DividerOrientationFlip()) }
    ),
    LayoutEntry(
      id: "scrolling.vertical-measures-content",
      category: .scrolling,
      title: "Vertical scroll measures content",
      blurb: "raster height = proposal; content taller than viewport",
      marker: "Vertical scroll measures content",
      tier: .behaviour,
      makeView: { AnyView(VerticalScrollMeasuresContent()) }
    ),
    LayoutEntry(
      id: "scrolling.horizontal-infinite-child",
      category: .scrolling,
      title: "Horizontal scroll with infinite child",
      blurb: ".frame(maxWidth:.infinity) inside horizontal ScrollView",
      marker: "Horizontal scroll with infinite child",
      tier: .behaviour,
      makeView: { AnyView(HorizontalScrollWithInfiniteChild()) }
    ),
    LayoutEntry(
      id: "scrolling.safe-area-inset",
      category: .scrolling,
      title: "Scroll view with safe area inset",
      blurb: "first content row below top inset",
      marker: "Scroll view with safe area inset",
      tier: .behaviour,
      makeView: { AnyView(ScrollViewWithSafeAreaInset()) }
    ),
    LayoutEntry(
      id: "geometry.takes-proposal",
      category: .geometry,
      title: "Geometry reader takes proposal",
      blurb: "proxy.size reflects frame proposal",
      marker: "Geometry reader takes proposal",
      tier: .behaviour,
      makeView: { AnyView(GeometryReaderTakesProposal()) }
    ),
    LayoutEntry(
      id: "geometry.in-hstack-hogs",
      category: .geometry,
      title: "Geometry reader in HStack hogs",
      blurb: "Classic 'eats everything' gotcha",
      marker: "Geometry reader in HStack hogs",
      tier: .behaviour,
      makeView: { AnyView(GeometryReaderInHStackHogs()) }
    ),
    LayoutEntry(
      id: "geometry.anchor-corner",
      category: .geometry,
      title: "Geometry reader anchor corner",
      blurb: ".position using proxy.size locates corner",
      marker: "Geometry reader anchor corner",
      tier: .behaviour,
      makeView: { AnyView(GeometryReaderAnchorCorner()) }
    ),
    LayoutEntry(
      id: "view-that-fits.axis-choice",
      category: .viewThatFits,
      title: "View that fits axis choice",
      blurb: "3 variants at 3 widths; pick widest that fits",
      marker: "View that fits axis choice",
      tier: .behaviour,
      makeView: { AnyView(ViewThatFitsAxisChoice()) }
    ),
    LayoutEntry(
      id: "view-that-fits.vertical-only",
      category: .viewThatFits,
      title: "View that fits vertical only",
      blurb: "axis: .vertical; height-driven swap",
      marker: "View that fits vertical only",
      tier: .behaviour,
      makeView: { AnyView(ViewThatFitsVerticalOnly()) }
    ),
    LayoutEntry(
      id: "view-that-fits.boundary-inclusive",
      category: .viewThatFits,
      title: "View that fits boundary inclusive",
      blurb: "pin inclusive-vs-exclusive at exact threshold",
      marker: "View that fits boundary inclusive",
      tier: .behaviour,
      makeView: { AnyView(ViewThatFitsBoundaryInclusive()) }
    ),
    LayoutEntry(
      id: "custom-layout.flow-wrap",
      category: .customLayout,
      title: "Flow layout wrap",
      blurb: "custom Layout: wrap children into rows when they don't fit",
      marker: "Flow layout wrap",
      tier: .behaviour,
      makeView: { AnyView(FlowLayoutWrap()) }
    ),
    LayoutEntry(
      id: "custom-layout.any-layout-hv-swap",
      category: .customLayout,
      title: "Any layout HV swap",
      blurb: "AnyLayout(VStackLayout vs HStackLayout) at runtime",
      marker: "Any layout HV swap",
      tier: .behaviour,
      makeView: { AnyView(AnyLayoutHVSwap()) }
    ),
    LayoutEntry(
      id: "custom-layout.radial",
      category: .customLayout,
      title: "Radial layout",
      blurb: "custom Layout placing children in a ring",
      marker: "Radial layout",
      tier: .behaviour,
      makeView: { AnyView(RadialLayout()) }
    ),
    LayoutEntry(
      id: "alignment.colon-aligned-form",
      category: .alignmentGuides,
      title: "Colon aligned form",
      blurb: "custom HorizontalAlignment at colon",
      marker: "Colon aligned form",
      tier: .behaviour,
      makeView: { AnyView(ColonAlignedForm()) }
    ),
    LayoutEntry(
      id: "alignment.dimension-dependent-guide",
      category: .alignmentGuides,
      title: "Alignment guide dimension dependent",
      blurb: "bottoms align via { d in d.height }",
      marker: "Alignment guide dimension dependent",
      tier: .behaviour,
      makeView: { AnyView(AlignmentGuideDimensionDependent()) }
    ),
    LayoutEntry(
      id: "collections.list-in-short-frame",
      category: .collections,
      title: "List in short frame",
      blurb: "20-row List in 5-row frame",
      marker: "List in short frame",
      tier: .behaviour,
      makeView: { AnyView(ListInShortFrame()) }
    ),
    LayoutEntry(
      id: "collections.for-each-identity-reorder",
      category: .collections,
      title: "For each identity reorder",
      blurb: "reorder preserves identity",
      marker: "For each identity reorder",
      tier: .behaviour,
      makeView: { AnyView(ForEachIdentityReorder()) }
    ),
    LayoutEntry(
      id: "collections.table-column-prioritization",
      category: .collections,
      title: "Table column prioritization",
      blurb: "Table column compression order",
      marker: "Table column prioritization",
      tier: .behaviour,
      makeView: { AnyView(TableColumnPrioritization()) }
    ),
    LayoutEntry(
      id: "shapes.circle-in-non-square-frame",
      category: .shapesCanvas,
      title: "Circle in non square frame",
      blurb: "circle in 12×5 leaves empty corners",
      marker: "Circle in non square frame",
      tier: .behaviour,
      makeView: { AnyView(CircleInNonSquareFrame()) }
    ),
    LayoutEntry(
      id: "shapes.capsule-axis-flip",
      category: .shapesCanvas,
      title: "Capsule axis flip",
      blurb: "wide vs tall capsule rounds different ends",
      marker: "Capsule axis flip",
      tier: .behaviour,
      makeView: { AnyView(CapsuleAxisFlip()) }
    ),
  ]

  public static func entry(id: String) -> LayoutEntry? {
    all.first { $0.id == id }
  }
}
