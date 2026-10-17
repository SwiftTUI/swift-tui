// Adversarial set B, pass 3: layout containers and modifiers (231–240).
//
// The register ratifies the stack engine's surplus and deficit rules and
// records two ZStack residues as Provisional; SwiftUI fixes the rest: a
// min-only frame does not fill, a lone alignment guide never resizes its
// container, invalid frame dimensions are ignored, spacers never reserve
// negative space, and `.position` is maximally flexible. These probes measure
// each rule at the root, on a stack's cross axis, and inside a ZStack, where
// the stack allocation that normally hides the difference is absent.
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: layout containers")
struct AdversarialSetBContainerTests {
  private func render<V: View>(_ view: V, _ name: String, width: Int, height: Int) -> RenderSnapshot
  {
    DefaultRenderer().render(
      view, context: .init(identity: testIdentity("SetBContainer", name)),
      proposal: .init(width: width, height: height))
  }

  // A min-only frame takes max(min, min(proposal, content)); an ideal-only
  // frame without `fixedSize` is inert. Neither fills a finite proposal, at
  // the root or on a stack's cross axis.
  @Test func setB231MinOnlyAndIdealOnlyFramesDoNotFill() {
    let minOnly = render(Text("ab").frame(minWidth: 3), "minOnly", width: 10, height: 1)
    let idealOnly = render(Text("ab").frame(idealWidth: 20), "idealOnly", width: 10, height: 1)
    let cross = render(
      VStack(spacing: 0) {
        Text("ab").frame(minWidth: 3)
        Text("c")
      }, "cross", width: 10, height: 2)
    withKnownIssue(
      "a flexible frame resolves a finite proposal to the proposal itself, ignoring the content size"
    ) {
      #expect(
        minOnly.measuredTree.measuredSize == CellSize(width: 3, height: 1),
        "\(minOnly.measuredTree.measuredSize)")
      #expect(
        idealOnly.measuredTree.measuredSize == CellSize(width: 2, height: 1),
        "\(idealOnly.measuredTree.measuredSize)")
      #expect(cross.measuredTree.measuredSize.width == 3, "\(cross.measuredTree.measuredSize)")
    }
    // Inside an HStack the main-axis allocation caps the frame at its ideal.
    let inStack = render(
      HStack(spacing: 0) {
        Text("ab").frame(minWidth: 3)
        Text("c")
      }, "inStack", width: 10, height: 1)
    #expect(
      inStack.placedTree.children.first?.bounds.size.width == 3,
      "\(inStack.placedTree.children.map(\.bounds))")
  }

  // A lone alignment guide never resizes or shifts its container: the stack
  // cross size is max(guide) + max(extent − guide), which for one child is
  // the child's own extent.
  @Test func setB232LoneAlignmentGuideDoesNotInflateItsContainer() {
    let far = render(
      ZStack { Text("ab").alignmentGuide(.leading) { _ in 100 } }, "far", width: 120, height: 1)
    let negative = render(
      VStack(alignment: .leading) { Text("ab").alignmentGuide(.leading) { _ in -3 } }, "negative",
      width: 10, height: 1)
    let tall = render(
      VStack(spacing: 0) {
        HStack(alignment: .top) { Text("A").alignmentGuide(.top) { _ in 5 } }
        Text("B")
      }, "tall", width: 10, height: 8)
    withKnownIssue(
      "each cross-axis term is clamped at zero, so a lone guide outside the child inflates the container"
    ) {
      #expect(
        far.measuredTree.measuredSize == CellSize(width: 2, height: 1),
        "\(far.measuredTree.measuredSize)")
      #expect(
        far.placedTree.children.first?.bounds.origin.x == 0,
        "\(far.placedTree.children.map(\.bounds))")
      #expect(
        negative.measuredTree.measuredSize == CellSize(width: 2, height: 1),
        "\(negative.measuredTree.measuredSize)")
      #expect(
        Array(tall.rasterSurface.lines.prefix(2)) == ["A", "B"], "\(tall.rasterSurface.lines)")
    }
    // A frame around the guided child still honours the guide.
    let framed = render(
      Text("ab").alignmentGuide(.leading) { _ in 100 }.frame(width: 10, alignment: .leading),
      "framed",
      width: 10, height: 1)
    #expect(
      framed.placedTree.children.first?.bounds.origin.x == -100,
      "\(framed.placedTree.children.map(\.bounds))")
  }

  // A negative frame dimension is invalid and ignored; it never becomes a
  // negative extent.
  @Test func setB233NegativeFrameDimensionsAreIgnored() async {
    await #expect(processExitsWith: .success) {
      await MainActor.run {
        let negativeWidth = DefaultRenderer().render(
          Text("ab").frame(width: -3),
          context: .init(identity: testIdentity("SetBContainer", "negW")),
          proposal: .init(width: 10, height: 1))
        let negativeHeight = DefaultRenderer().render(
          Text("ab").frame(height: -1),
          context: .init(identity: testIdentity("SetBContainer", "negH")),
          proposal: .init(width: 10, height: 1))
        withKnownIssue("frame(width:) and frame(height:) are stored unclamped and measure negative")
        {
          #expect(
            negativeWidth.measuredTree.measuredSize == CellSize(width: 2, height: 1),
            "\(negativeWidth.measuredTree.measuredSize)")
          #expect(
            negativeWidth.rasterSurface.lines == ["ab"], "\(negativeWidth.rasterSurface.lines)")
          #expect(
            negativeHeight.measuredTree.measuredSize == CellSize(width: 2, height: 1),
            "\(negativeHeight.measuredTree.measuredSize)")
        }
        let zero = DefaultRenderer().render(
          Text("ab").frame(width: 0),
          context: .init(identity: testIdentity("SetBContainer", "zeroW")),
          proposal: .init(width: 10, height: 1))
        #expect(
          zero.measuredTree.measuredSize == CellSize(width: 0, height: 1),
          "\(zero.measuredTree.measuredSize)")
      }
    }
  }

  // A spacer never reserves negative space: a negative minimum reads as zero
  // on both the allocated and the ideal paths.
  @Test func setB234NegativeSpacerMinimumReadsAsZero() {
    let ideal = render(
      HStack(spacing: 0) {
        Text("L")
        Spacer(minLength: -3)
        Text("R")
      }.fixedSize(), "ideal", width: 10, height: 1)
    withKnownIssue(
      "the raw negative minimum is summed into the ideal and advances placement backwards"
    ) {
      #expect(
        ideal.measuredTree.measuredSize == CellSize(width: 2, height: 1),
        "\(ideal.measuredTree.measuredSize)")
      #expect(
        ideal.placedTree.children.first?.children.map(\.bounds.origin.x) == [0, 1, 1],
        "\(ideal.placedTree)")
      #expect(ideal.rasterSurface.lines == ["LR"], "\(ideal.rasterSurface.lines)")
    }
    let allocated = render(
      HStack(spacing: 0) {
        Text("L")
        Spacer(minLength: -3)
        Text("R")
      }, "allocated", width: 10, height: 1)
    #expect(allocated.rasterSurface.lines == ["L        R"], "\(allocated.rasterSurface.lines)")
  }

  // A spacer-only ZStack fills its proposal and a spacer beside siblings is
  // layout-neutral, minimum included (the register's Provisional residues).
  @Test func setB235ZStackSpacersFollowSwiftUISizing() {
    let spacerOnly = render(ZStack { Spacer() }, "spacerOnly", width: 6, height: 3)
    let withMinimum = render(
      ZStack {
        Text("ab")
        Spacer(minLength: 5)
      }, "withMinimum", width: 10, height: 3)
    withKnownIssue(
      "the register's Provisional residue: a spacer-only ZStack has no size and a minimum is reserved on both axes"
    ) {
      #expect(
        spacerOnly.measuredTree.measuredSize == CellSize(width: 6, height: 3),
        "\(spacerOnly.measuredTree.measuredSize)")
      #expect(
        withMinimum.measuredTree.measuredSize == CellSize(width: 2, height: 1),
        "\(withMinimum.measuredTree.measuredSize)")
    }
    let neutral = render(
      ZStack {
        Text("ab")
        Spacer()
      }, "neutral", width: 10, height: 3)
    #expect(
      neutral.measuredTree.measuredSize == CellSize(width: 2, height: 1),
      "\(neutral.measuredTree.measuredSize)")
    let corner = render(
      ZStack(alignment: .bottomTrailing) {
        Text("abcd")
        Text("x")
      }, "corner", width: 10, height: 3)
    #expect(
      corner.measuredTree.measuredSize == CellSize(width: 4, height: 1),
      "\(corner.measuredTree.measuredSize)")
    #expect(corner.rasterSurface.lines.first == "abcx", "\(corner.rasterSurface.lines)")
  }

  // A divider outside a stack draws horizontally, whatever the proposal's
  // aspect (the register's second Provisional residue).
  @Test func setB236DividerInAZStackDrawsHorizontally() {
    let tall = render(ZStack { Divider() }, "tall", width: 3, height: 5)
    withKnownIssue(
      "the register's Provisional residue: a divider with no stack axis follows the longer side"
    ) {
      #expect(
        tall.measuredTree.measuredSize == CellSize(width: 3, height: 1),
        "\(tall.measuredTree.measuredSize)")
      #expect(tall.rasterSurface.lines.first == "───", "\(tall.rasterSurface.lines)")
    }
    let square = render(ZStack { Divider() }, "square", width: 5, height: 5)
    #expect(
      square.measuredTree.measuredSize == CellSize(width: 5, height: 1),
      "\(square.measuredTree.measuredSize)")
    let inVStack = render(VStack { Divider() }, "inVStack", width: 3, height: 5)
    #expect(inVStack.rasterSurface.lines.first == "───", "\(inVStack.rasterSurface.lines)")
    let inHStack = render(HStack { Divider() }, "inHStack", width: 5, height: 3)
    #expect(
      inHStack.measuredTree.measuredSize == CellSize(width: 1, height: 3),
      "\(inHStack.measuredTree.measuredSize)")
  }

  // Ideal dimensions apply under `fixedSize`, min and max clamp, and a
  // max-only frame fills up to its maximum.
  @Test func setB237IdealDimensionsApplyUnderFixedSize() {
    let ideal = render(
      Text("ab").frame(idealWidth: 20, idealHeight: 3).fixedSize(), "ideal", width: 10, height: 1)
    #expect(
      ideal.measuredTree.measuredSize == CellSize(width: 20, height: 3),
      "\(ideal.measuredTree.measuredSize)")
    #expect(
      ideal.placedTree.children.first?.bounds.origin == CellPoint(x: 9, y: 1),
      "\(ideal.placedTree.children.map(\.bounds))")
    let pinned = render(Text("ab").frame(minWidth: 3, maxWidth: 3), "pinned", width: 10, height: 1)
    #expect(pinned.measuredTree.measuredSize.width == 3, "\(pinned.measuredTree.measuredSize)")
    let capped = render(Text("ab").frame(maxWidth: 20), "capped", width: 10, height: 1)
    #expect(capped.measuredTree.measuredSize.width == 10, "\(capped.measuredTree.measuredSize)")
    let cappedBelow = render(Text("ab").frame(maxWidth: 5), "cappedBelow", width: 10, height: 1)
    #expect(
      cappedBelow.measuredTree.measuredSize.width == 5, "\(cappedBelow.measuredTree.measuredSize)")
  }

  // `.position` takes the full proposed space inside a stack, as its own
  // documentation says, so the sibling after it is pushed to the end.
  @Test func setB238PositionTakesTheFullProposedSpaceInAStack() {
    let row = render(
      HStack(spacing: 0) {
        Text("ab").position(x: 5, y: 0)
        Text("cd")
      }, "row", width: 10, height: 1)
    let widths = row.placedTree.children.map { $0.bounds.size.width }
    withKnownIssue(
      "the stack caps the position wrapper at its child's ideal width instead of the proposal"
    ) {
      #expect(widths == [8, 2], "\(widths)")
      #expect(
        row.placedTree.children.last?.bounds.origin.x == 8,
        "\(row.placedTree.children.map(\.bounds))")
      #expect(row.measuredTree.measuredSize.width == 10, "\(row.measuredTree.measuredSize)")
    }
    let alone = render(Text("ab").position(x: 5, y: 0), "alone", width: 10, height: 1)
    #expect(alone.measuredTree.measuredSize.width == 10, "\(alone.measuredTree.measuredSize)")
    #expect(
      alone.placedTree.children.first?.bounds.origin.x == 4,
      "\(alone.placedTree.children.map(\.bounds))")
  }

  // Negative spacing and negative padding overlap siblings by the overlap.
  @Test func setB239NegativeSpacingAndPaddingOverlapSiblings() {
    let spacing = render(
      HStack(spacing: -1) {
        Text("ab")
        Text("cd")
      }, "spacing", width: 10, height: 1)
    #expect(spacing.measuredTree.measuredSize.width == 3, "\(spacing.measuredTree.measuredSize)")
    #expect(
      spacing.placedTree.children.last?.bounds.origin.x == 1,
      "\(spacing.placedTree.children.map(\.bounds))")
    #expect(spacing.rasterSurface.lines == ["acd"], "\(spacing.rasterSurface.lines)")
    let padding = render(
      HStack(spacing: 0) {
        Text("ab").padding(.trailing, -1)
        Text("cd")
      }, "padding", width: 10, height: 1)
    #expect(padding.measuredTree.measuredSize.width == 3, "\(padding.measuredTree.measuredSize)")
    #expect(
      padding.placedTree.children.first?.bounds.size.width == 1,
      "\(padding.placedTree.children.map(\.bounds))")
    #expect(
      padding.placedTree.children.first?.children.first?.bounds.size.width == 2,
      "\(padding.placedTree)")
    #expect(padding.rasterSurface.lines == ["acd"], "\(padding.rasterSurface.lines)")
  }

  // Under a deficit the higher-priority flexible sibling wins and a lower
  // priority text can be squeezed to its ratified zero minimum.
  @Test func setB240LayoutPriorityDeficitSqueezesLowerTextToZero() {
    let framed = render(
      HStack(spacing: 0) {
        Text("aaaa").frame(maxWidth: .infinity).layoutPriority(1)
        Text("bbbb").frame(maxWidth: .infinity)
      }, "framed", width: 5, height: 1)
    #expect(
      framed.placedTree.children.map { $0.bounds.size.width } == [5, 0],
      "\(framed.placedTree.children.map(\.bounds))")
    #expect(framed.rasterSurface.lines == ["aaaa"], "\(framed.rasterSurface.lines)")
    let plain = render(
      HStack(spacing: 0) {
        Text("aaaa").layoutPriority(1)
        Text("bbbb")
      }, "plain", width: 5, height: 1)
    #expect(
      plain.placedTree.children.map { $0.bounds.size.width } == [4, 1],
      "\(plain.placedTree.children.map(\.bounds))")
    let equal = render(
      HStack(spacing: 0) {
        Text("aaaa")
        Text("bbbb")
      }, "equal", width: 6, height: 1)
    #expect(
      equal.placedTree.children.map { $0.bounds.size.width } == [3, 3],
      "\(equal.placedTree.children.map(\.bounds))")
  }
}
