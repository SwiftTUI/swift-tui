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
  ]

  public static func entry(id: String) -> LayoutEntry? {
    all.first { $0.id == id }
  }
}
