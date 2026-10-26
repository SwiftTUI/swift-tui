import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// F1 pass 3 (STUI-1282), area 1: integer extremes in public layout arguments.
///
/// Every layout argument is a cell count of type `Int`. SwiftUI never
/// terminates for an extreme frame, padding or offset magnitude, and wave 2's
/// FW-E repair (STUI-741 class) states that caller-supplied numeric values must
/// not trap. Each case renders once through `DefaultRenderer` inside an exit
/// test, so a trap is observed as an abnormal exit of the child process.
@MainActor
@Suite(.serialized)
struct AdversarialSetCLayoutBoundsTests {
  @Test func setC201UniformIntMaxPaddingRenders() async {
    await #expect(processExitsWith: .success) {
      await MainActor.run { _ = setCBoundsLines(Text("a").padding(Int.max), "201") }
    }
  }

  @Test func setC202SingleEdgeIntMaxPaddingRenders() async {
    await #expect(processExitsWith: .success) {
      await MainActor.run { _ = setCBoundsLines(Text("a").padding(.leading, Int.max), "202") }
    }
  }

  @Test func setC203IntMinPaddingRenders() async {
    await #expect(processExitsWith: .success) {
      await MainActor.run { _ = setCBoundsLines(Text("a").padding(Int.min), "203") }
    }
  }

  @Test func setC204TopIntMaxPaddingRenders() async {
    await #expect(processExitsWith: .success) {
      await MainActor.run { _ = setCBoundsLines(Text("a").padding(.top, Int.max), "204") }
    }
  }

  @Test func setC205IntMaxStackSpacingRenders() async {
    await #expect(processExitsWith: .success) {
      await MainActor.run {
        _ = setCBoundsLines(
          HStack(spacing: Int.max) {
            Text("a")
            Text("b")
            Text("c")
          }, "205")
      }
    }
  }

  @Test func setC206IntMinStackSpacingRenders() async {
    await #expect(processExitsWith: .success) {
      await MainActor.run {
        _ = setCBoundsLines(
          VStack(spacing: Int.min) {
            Text("a")
            Text("b")
            Text("c")
          }, "206")
      }
    }
  }

  @Test func setC207IntMaxFrameWidthInStackRenders() async {
    await #expect(processExitsWith: .success) {
      await MainActor.run {
        _ = setCBoundsLines(
          HStack {
            Text("a").frame(width: Int.max)
            Text("b")
          }, "207")
      }
    }
  }

  @Test func setC208IntMaxSpacerMinimumRenders() async {
    await #expect(processExitsWith: .success) {
      await MainActor.run {
        _ = setCBoundsLines(
          VStack {
            Spacer(minLength: Int.max)
            Text("a")
          }, "208")
      }
    }
  }

  @Test func setC209IntMaxIntrinsicMinimumRenders() async {
    await #expect(processExitsWith: .success) {
      await MainActor.run {
        _ = setCBoundsLines(
          HStack {
            Text("a").minimumIntrinsicSize(width: Int.max)
            Text("b")
          }, "209")
      }
    }
  }

  @Test func setC210IntMinOffsetRenders() async {
    await #expect(processExitsWith: .success) {
      await MainActor.run { _ = setCBoundsLines(Text("a").offset(x: Int.min), "210") }
    }
  }

  @Test func setC211IntMaxOffsetRenders() async {
    await #expect(processExitsWith: .success) {
      await MainActor.run {
        _ = setCBoundsLines(Text("a").offset(x: Int.max, y: Int.max), "211")
      }
    }
  }

  @Test func setC212IntMaxPositionRenders() async {
    await #expect(processExitsWith: .success) {
      await MainActor.run { _ = setCBoundsLines(Text("a").position(x: Int.max, y: 0), "212") }
    }
  }

  @Test func setC213IntMaxSafeAreaPaddingRenders() async {
    await #expect(processExitsWith: .success) {
      await MainActor.run { _ = setCBoundsLines(Text("a").safeAreaPadding(Int.max), "213") }
    }
  }

  @Test func setC214IntMaxSafeAreaInsetSpacingRenders() async {
    await #expect(processExitsWith: .success) {
      await MainActor.run {
        _ = setCBoundsLines(
          Text("a").safeAreaInset(edge: .bottom, spacing: Int.max) { Text("b") }, "214")
      }
    }
  }

  @Test func setC215IntMaxTableColumnWidthRenders() async {
    await #expect(processExitsWith: .success) {
      await MainActor.run {
        _ = setCBoundsLines(
          Table(
            [SetCBoundsRow(id: 1), SetCBoundsRow(id: 2)],
            columns: [TableColumn("A", width: Int.max), TableColumn("B", width: 3)]
          ) { row in
            Text("a\(row.id)")
            Text("b\(row.id)")
          }, "215")
      }
    }
  }

  // Pin: the documented clamp of a non-positive line limit holds at Int.min.
  @Test func setC216IntMinLineLimitClampsToOneLine() {
    let lines = setCBoundsLines(Text("a b c").lineLimit(Int.min).frame(width: 1), "216")
    let painted = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    #expect(painted.count == 1, "\(lines)")
  }

  // MARK: - Wave 4 FW-I regressions (STUI-1303, STUI-777, STUI-780, STUI-796)

  /// STUI-777: an extreme offset or position inside a parent at a non-zero
  /// origin lays out, extracts semantics and rasterizes. The far child paints
  /// nothing, exactly as a merely distant one does, and keeps its focus region.
  @Test(arguments: SetCExtremePlacement.allCases)
  func extremePlacementInsideOriginParentMatchesDistantPlacement(
    _ placement: SetCExtremePlacement
  ) throws {
    let extreme = try setCOriginParentFrame(placement, extreme: true)
    let distant = try setCOriginParentFrame(placement, extreme: false)
    #expect(extreme.frame == distant.frame)
    let rows = extreme.frame.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(rows.count == 6)
    #expect(rows[1].hasPrefix(" top"))
    let extremeRegion = try #require(extreme.semantics.focusRegions.first)
    let distantRegion = try #require(distant.semantics.focusRegions.first)
    #expect(extreme.semantics.focusRegions.count == 1)
    if placement.isPositive {
      #expect(extremeRegion.rect.origin.x >= distantRegion.rect.origin.x)
    } else {
      #expect(extremeRegion.rect.origin.x <= distantRegion.rect.origin.x)
    }
  }

  /// STUI-1303: the extreme layout arguments render beside siblings in a parent
  /// at a non-zero origin; the parent's first row is unchanged.
  @Test(arguments: 0..<11)
  func extremeLayoutArgumentInsideOriginParentRenders(_ index: Int) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("setCBoundsParent", "\(index)"),
      size: .init(width: 20, height: 6)
    ) { setCOriginParent(setCExtremeLayoutArgument(index)) }
    defer { harness.shutdown() }
    let rows = harness.frame.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(rows.count == 6)
    #expect(rows[1].hasPrefix(" top"), "\(rows)")
  }

  /// STUI-1303: saturated sums are the measured extents, not a trap.
  @Test func extremePaddingMeasuresSaturated() {
    let maximum = DefaultRenderer().render(
      Text("a").padding(Int.max), context: .init(identity: testIdentity("setCSat", "max")),
      proposal: .init(width: 20, height: 4))
    #expect(maximum.measuredTree.measuredSize == CellSize(width: .max, height: .max))
    let spacing = DefaultRenderer().render(
      HStack(spacing: Int.max) {
        Text("a")
        Text("b")
      }, context: .init(identity: testIdentity("setCSat", "spacing")),
      proposal: .init(width: 20, height: 4))
    #expect(spacing.measuredTree.measuredSize.width == .max)
    // A one-shot render keeps the stack's natural extent, held at the cap.
    #expect(
      spacing.rasterSurface.size == CellSize(width: Rasterizer.maximumSurfaceExtent, height: 4))
  }

  /// STUI-780: a stack's share rounding stays exact for proposals above
  /// `Int.max / 2`, in the per-child surplus branch (a rigid 3 x 1 child
  /// before flexible ones) and the per-child deficit branch (bounded children
  /// whose ideals exceed the proposal).
  @Test(arguments: [Int.max, Int.max / 2 + 1], [true, false])
  func stackSharesUnderHugeProposals(main: Int, horizontal: Bool) throws {
    let proposal =
      horizontal
      ? ProposedSize(width: .finite(main), height: .finite(1))
      : ProposedSize(width: .finite(1), height: .finite(main))
    let ids = (0..<3).map { testIdentity("setCShare", "\($0)") }
    func mainLength(_ node: PlacedNode) -> Int {
      horizontal ? node.bounds.size.width : node.bounds.size.height
    }

    let surplusRoot = SetCShareStack(horizontal: horizontal) {
      Rectangle().fill(Color.green).frame(width: 3, height: 1).id(ids[0])
      Rectangle().fill(Color.red).id(ids[1])
      Rectangle().fill(Color.blue).id(ids[2])
    }
    let surplus = DefaultRenderer().render(
      surplusRoot, context: .init(identity: testIdentity("setCShare", "surplus")),
      proposal: proposal)
    let surplusLengths = try ids.map { try #require(setCFind($0, in: surplus.placedTree)) }
      .map(mainLength)
    #expect(surplusLengths[0] == (horizontal ? 3 : 1))
    #expect(surplusLengths.reduce(0) { $0 &+ $1 } == main)
    #expect(abs(surplusLengths[1] - surplusLengths[2]) <= 1)

    let ideal = ProposedDimension.finite(Int.max / 2 + 1)
    func bounded(_ color: Color) -> some View {
      Rectangle().fill(color).frame(
        idealWidth: horizontal ? ideal : nil, maxWidth: horizontal ? ideal : nil,
        idealHeight: horizontal ? nil : ideal, maxHeight: horizontal ? nil : ideal)
    }
    let deficitRoot = SetCShareStack(horizontal: horizontal) {
      bounded(.red).id(ids[0])
      bounded(.blue).id(ids[1])
    }
    let deficit = DefaultRenderer().render(
      deficitRoot, context: .init(identity: testIdentity("setCShare", "deficit")),
      proposal: proposal)
    let deficitLengths = try ids.prefix(2).map {
      try #require(setCFind($0, in: deficit.placedTree))
    }
    .map(mainLength)
    #expect(deficitLengths.reduce(0) { $0 &+ $1 } == main)
    #expect(abs(deficitLengths[0] - deficitLengths[1]) <= 1)
  }

  /// STUI-796: an interactive surface never exceeds the host's proposal;
  /// content beyond it clips. A one-shot render keeps its natural extent (the
  /// set B layout pins rely on it), held at the surface cap.
  @Test func interactiveSurfaceNeverExceedsTheHostProposal() throws {
    func rows() -> some View {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<100, id: \.self) { Text("row \($0)") }
      }
    }
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("setCSurface", "interactive"),
      size: .init(width: 20, height: 4)
    ) { rows() }
    defer { harness.shutdown() }
    let presented = harness.frame.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(presented.count == 4)
    #expect(presented.first?.hasPrefix("row 0") == true)
    let snapshot = DefaultRenderer().render(
      rows(), context: .init(identity: testIdentity("setCSurface", "rows")),
      proposal: .init(width: 20, height: 4)
    ).rasterSurface
    #expect(snapshot.size == CellSize(width: 20, height: 100))
    let wide = DefaultRenderer().render(
      Text("a").padding(.leading, Int.max),
      context: .init(identity: testIdentity("setCSurface", "wide")),
      proposal: .init(width: 20, height: 4)
    ).rasterSurface
    #expect(wide.size == CellSize(width: Rasterizer.maximumSurfaceExtent, height: 4))
  }

  /// STUI-796: an unproposed dimension keeps its natural extent below the
  /// documented bound and never allocates beyond it.
  @Test func unproposedRasterSurfaceKeepsNaturalExtentUpToTheBound() {
    let natural = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<100, id: \.self) { Text("row \($0)") }
      }, context: .init(identity: testIdentity("setCSurface", "natural"))
    ).rasterSurface
    #expect(natural.size == CellSize(width: 6, height: 100))
    let tall = DefaultRenderer().render(
      Rectangle().fill(Color.red).frame(width: 1, height: Int.max),
      context: .init(identity: testIdentity("setCSurface", "tall"))
    ).rasterSurface
    #expect(tall.size == CellSize(width: 1, height: Rasterizer.maximumSurfaceExtent))
    let far = DefaultRenderer().render(
      Text("a").padding(.top, Int.max),
      context: .init(identity: testIdentity("setCSurface", "far"))
    ).rasterSurface
    #expect(far.size == CellSize(width: 1, height: Rasterizer.maximumSurfaceExtent))
    // A child offset past the cap cannot be shown, so it does not size the
    // surface; the offset view keeps its own one cell.
    let offscreen = DefaultRenderer().render(
      Text("a").offset(x: Int.max),
      context: .init(identity: testIdentity("setCSurface", "offscreen"))
    ).rasterSurface
    #expect(offscreen.size == CellSize(width: 1, height: 1))
    // The sizing rule, without allocating the largest surfaces it allows.
    #expect(
      Rasterizer.boundedSurfaceSize(.init(width: .max, height: .max), maximum: nil)
        == CellSize(width: Rasterizer.maximumSurfaceExtent, height: 16))
    #expect(
      Rasterizer.boundedSurfaceSize(.init(width: 120, height: 50_000), maximum: nil)
        == CellSize(width: 120, height: Rasterizer.maximumSurfaceCellCount / 120))
    #expect(
      Rasterizer.boundedSurfaceSize(
        .init(width: 40, height: 10_002), maximum: .init(width: 40, height: 16))
        == CellSize(width: 40, height: 16))
    #expect(
      Rasterizer.boundedSurfaceSize(.init(width: 80, height: 24), maximum: nil)
        == CellSize(width: 80, height: 24))
  }

  /// STUI-796's acceptance: a menu far taller than the terminal presents a
  /// 40×16 surface at 40×16. Before the bound, 100 items presented 102 rows.
  /// The 10,000-item form of the acceptance passes too but takes minutes in a
  /// debug build, so the committed case uses 300 items (wave-4 FW-I evidence).
  @Test func tallMenuPresentsTheTerminalSize() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("setCSurface", "menu"),
      size: .init(width: 40, height: 16)
    ) {
      Menu("Commands") {
        ForEach(0..<300, id: \.self) { Text("Item \($0)") }
      }
    }
    defer { harness.shutdown() }
    let frame = try harness.clickText("Commands")
    #expect(frame.contains("Item 0"))
    let rows = frame.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(rows.count == 16)
  }
}

/// The far placements STUI-777 names, each beside a distant twin that paints
/// the same (nothing) without saturating.
enum SetCExtremePlacement: CaseIterable, Sendable, CustomTestStringConvertible {
  case offsetMinX, offsetMax, offsetMin, positionMax, positionMin

  var testDescription: String { "\(self)" }

  var isPositive: Bool { self == .offsetMax || self == .positionMax }

  @MainActor
  func view(extreme: Bool) -> AnyView {
    let far = 10_000
    let button = Button("a") {}
    switch self {
    case .offsetMinX:
      return AnyView(button.offset(x: extreme ? .min : -far))
    case .offsetMax:
      return AnyView(button.offset(x: extreme ? .max : far, y: extreme ? .max : far))
    case .offsetMin:
      return AnyView(button.offset(x: extreme ? .min : -far, y: extreme ? .min : -far))
    case .positionMax:
      return AnyView(button.position(x: extreme ? .max : far, y: extreme ? .max : far))
    case .positionMin:
      return AnyView(button.position(x: extreme ? .min : -far, y: extreme ? .min : -far))
    }
  }
}

@MainActor
private func setCOriginParent<V: View>(_ content: V) -> some View {
  VStack(alignment: .leading, spacing: 0) {
    Text("top")
    HStack(spacing: 1) {
      Text("L")
      content
      Text("R")
    }
    Text("bottom")
  }
  .padding(1)
}

@MainActor
private func setCOriginParentFrame(
  _ placement: SetCExtremePlacement,
  extreme: Bool
) throws -> (frame: String, semantics: SemanticSnapshot) {
  let harness = try StressRuntimeHarness(
    rootIdentity: testIdentity("setCOrigin", "\(placement)"),
    size: .init(width: 20, height: 6)
  ) { setCOriginParent(placement.view(extreme: extreme)) }
  defer { harness.shutdown() }
  return (harness.frame, harness.runLoop.latestSemanticSnapshot)
}

@MainActor
private func setCExtremeLayoutArgument(_ index: Int) -> AnyView {
  switch index {
  case 0: AnyView(Text("a").padding(Int.max))
  case 1: AnyView(Text("a").padding(Int.min))
  case 2: AnyView(Text("a").padding(.leading, Int.max).padding(.top, Int.max))
  case 3: AnyView(Text("a").padding(Int.max).padding(Int.max))
  case 4:
    AnyView(
      HStack(spacing: Int.max) {
        Text("a")
        Text("b")
      })
  case 5:
    AnyView(
      VStack(spacing: Int.min) {
        Text("a")
        Text("b")
      })
  case 6: AnyView(Text("a").frame(width: Int.max, height: Int.max))
  case 7:
    AnyView(
      VStack {
        Spacer(minLength: Int.max)
        Text("a")
      })
  case 8: AnyView(Text("a").safeAreaPadding(Int.max))
  case 9: AnyView(Text("a").safeAreaInset(edge: .leading, spacing: Int.max) { Text("b") })
  default:
    AnyView(
      Text("a").padding(.trailing, Int.max).border(style: .single, placement: .outset, sides: .all))
  }
}

private struct SetCShareStack<Content: View>: View {
  let horizontal: Bool
  @ViewBuilder let content: Content

  var body: some View {
    if horizontal {
      HStack(spacing: 0) { content }
    } else {
      VStack(spacing: 0) { content }
    }
  }
}

private func setCFind(_ identity: Identity, in node: PlacedNode) -> PlacedNode? {
  if node.identity == identity { return node }
  for child in node.children {
    if let found = setCFind(identity, in: child) { return found }
  }
  return nil
}

private struct SetCBoundsRow: Identifiable, Sendable {
  var id: Int
}

@MainActor
private func setCBoundsLines<V: View>(_ view: V, _ name: String) -> [String] {
  DefaultRenderer().render(
    view, context: .init(identity: testIdentity("setCBounds", name)),
    proposal: .init(width: 20, height: 4)
  ).rasterSurface.lines
}
