import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct MatchedGeometryBadgeMoveBehaviourTests {
  /// Renders two sibling variants of ``MatchedGeometryBadgeMove`` —
  /// one whose `@State Bool` is locked to `true` (left container) and
  /// one whose state is locked to `false` (right container) — and
  /// asserts that `[BADGE]`'s column is strictly LESS in the
  /// left-locked raster than in the right-locked raster.  That column
  /// inequality is the move-between-containers invariant: the badge
  /// inhabits the left slot when the boolean chooses left, the right
  /// slot otherwise.
  ///
  /// The two badges should land at roughly the same row (the middle
  /// of the 5-row container) — the assertion permits at most a 1-row
  /// drift between variants.
  ///
  /// VACUITY: see the variants below for the swap-the-conditional
  /// mutation that flips `leftCol < rightCol` and fails this test.
  @Test("badge moves between containers based on state")
  func badgeMovesBetweenContainers() {
    let leftRaster = render(
      _LeftVariant(),
      width: 40,
      height: 10,
      id: "matched-badge-move.left"
    ).rasterSurface
    let rightRaster = render(
      _RightVariant(),
      width: 40,
      height: 10,
      id: "matched-badge-move.right"
    ).rasterSurface

    let leftJoined = leftRaster.lines.joined(separator: "\n")
    let rightJoined = rightRaster.lines.joined(separator: "\n")

    guard let leftRow = leftRaster.firstRow(containing: "[BADGE]") else {
      Issue.record(
        """
        expected [BADGE] in left-variant raster but did not find it
        \(leftJoined)
        """
      )
      return
    }
    guard let rightRow = rightRaster.firstRow(containing: "[BADGE]") else {
      Issue.record(
        """
        expected [BADGE] in right-variant raster but did not find it
        \(rightJoined)
        """
      )
      return
    }
    guard let leftCol = column(of: "[BADGE]", in: leftRaster.row(at: leftRow)) else {
      Issue.record("could not measure [BADGE] column in left variant\n\(leftJoined)")
      return
    }
    guard let rightCol = column(of: "[BADGE]", in: rightRaster.row(at: rightRow)) else {
      Issue.record("could not measure [BADGE] column in right variant\n\(rightJoined)")
      return
    }

    #expect(
      leftCol < rightCol,
      """
      [BADGE] should occupy the LEFT container when isLeft=true and the \
      RIGHT container when isLeft=false. Got left col=\(leftCol), \
      right col=\(rightCol). The move-between-containers invariant is \
      violated.
      --- left ---
      \(leftJoined)
      --- right ---
      \(rightJoined)
      """
    )
    #expect(
      abs(leftRow - rightRow) <= 1,
      """
      [BADGE] should land on roughly the same row in both variants \
      (both containers are the same height). Got left row=\(leftRow), \
      right row=\(rightRow).
      --- left ---
      \(leftJoined)
      --- right ---
      \(rightJoined)
      """
    )
  }
}

/// Test-only sibling of ``MatchedGeometryBadgeMove`` whose `@State`
/// boolean is initialised to `true`, so the badge always lives in the
/// left container.
private struct _LeftVariant: View {
  @State private var isLeft: Bool = true
  @Namespace private var ns

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Matched geometry badge move").foregroundStyle(.muted)
      HStack(spacing: 4) {
        ZStack {
          Rectangle().fill(Color.gray).frame(width: 10, height: 5)
          // VACUITY: change `isLeft` to `!isLeft` here (and `!isLeft`
          // to `isLeft` in the right ZStack below) and the badge will
          // appear in the right container despite the boolean being
          // true. The test then fails because leftCol > rightCol.
          if isLeft {
            Text("[BADGE]").matchedGeometryEffect(id: "badge", in: ns)
          }
        }
        ZStack {
          Rectangle().fill(Color.gray).frame(width: 10, height: 5)
          if !isLeft {
            Text("[BADGE]").matchedGeometryEffect(id: "badge", in: ns)
          }
        }
      }
      .border(.separator)
    }
    .padding(1)
  }
}

/// Test-only sibling of ``MatchedGeometryBadgeMove`` whose `@State`
/// boolean is initialised to `false`, so the badge always lives in the
/// right container.
private struct _RightVariant: View {
  @State private var isLeft: Bool = false
  @Namespace private var ns

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Matched geometry badge move").foregroundStyle(.muted)
      HStack(spacing: 4) {
        ZStack {
          Rectangle().fill(Color.gray).frame(width: 10, height: 5)
          if isLeft {
            Text("[BADGE]").matchedGeometryEffect(id: "badge", in: ns)
          }
        }
        ZStack {
          Rectangle().fill(Color.gray).frame(width: 10, height: 5)
          if !isLeft {
            Text("[BADGE]").matchedGeometryEffect(id: "badge", in: ns)
          }
        }
      }
      .border(.separator)
    }
    .padding(1)
  }
}
