import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// A `Spacer` absorbs unbounded space only along its own stack's axis.
///
/// `derivedMaximumMainSize` used to report every `Spacer` subtree as unbounded
/// on *both* axes, so an `HStack { Text; Spacer() }` header or status bar
/// claimed unbounded vertical appetite inside a `VStack` and competed with the
/// intended flexible child. The visible symptom was a surface that never filled
/// its proposal: the terminal-workspace example's tab strip and status strip
/// left the bottom of the terminal blank at every window height.
///
/// `Divider` has always had the axis check (via `drawMetadata.leafStackAxis`);
/// these pin the same rule for `Spacer`, plus the two directions it must *not*
/// break — a spacer still has to stretch along its own axis.
@MainActor
struct SpacerCrossAxisFlexibilityTests {
  private struct VerticalSkeleton: View {
    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 1) {
          Text("[dev]")
          Spacer(minLength: 1)
          Text("workspace")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Divider()
        Text("panes")
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        Divider()
        HStack(spacing: 2) {
          Text("shell")
          Spacer(minLength: 1)
          Text("^K commands")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private struct HorizontalSkeleton: View {
    var body: some View {
      HStack(spacing: 0) {
        VStack(spacing: 1) {
          Text("A")
          Spacer(minLength: 1)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        Divider()
        Text("body")
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        Divider()
        VStack(spacing: 1) {
          Text("Z")
          Spacer(minLength: 1)
        }
        .frame(maxHeight: .infinity, alignment: .top)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private func lines(_ view: some View, width: Int, height: Int, id: String) -> [String] {
    DefaultRenderer()
      .render(
        view,
        context: .init(identity: testIdentity(id)),
        proposal: ProposedSize(width: width, height: height)
      )
      .rasterSurface.lines
  }

  @Test("a Spacer-bearing bar does not steal its VStack sibling's height")
  func horizontalBarsDoNotConsumeVerticalSpace() {
    let rendered = lines(VerticalSkeleton(), width: 40, height: 12, id: "SpacerCrossAxisV")

    #expect(rendered.count == 12)
    // The status strip is the last child, so it must land on the last row: any
    // vertical greed in the two Spacer-bearing bars pulls it upwards and leaves
    // blank rows beneath.
    #expect(rendered.last?.contains("^K commands") == true)
    #expect(rendered.first?.contains("[dev]") == true)
  }

  @Test("a Spacer-bearing column does not steal its HStack sibling's width")
  func verticalBarsDoNotConsumeHorizontalSpace() {
    let rendered = lines(HorizontalSkeleton(), width: 40, height: 6, id: "SpacerCrossAxisH")

    // The trailing column must reach the last cell of the row.
    let first = rendered.first ?? ""
    #expect(first.count == 40)
    #expect(first.hasSuffix("Z"))
  }

  @Test("a Spacer still expands along its own axis")
  func spacerStillExpandsAlongItsOwnAxis() {
    let rendered = lines(
      HStack(spacing: 0) {
        Text("a")
        Spacer(minLength: 0)
        Text("b")
      }
      .frame(maxWidth: .infinity, alignment: .leading),
      width: 20,
      height: 1,
      id: "SpacerOwnAxisH"
    )

    #expect(rendered.first?.hasPrefix("a") == true)
    #expect(rendered.first?.hasSuffix("b") == true)
    #expect(rendered.first?.count == 20)
  }

  @Test("a Spacer in a VStack still expands vertically")
  func spacerStillExpandsVertically() {
    let rendered = lines(
      VStack(spacing: 0) {
        Text("top")
        Spacer(minLength: 0)
        Text("bottom")
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading),
      width: 10,
      height: 6,
      id: "SpacerOwnAxisV"
    )

    #expect(rendered.count == 6)
    #expect(rendered.first?.contains("top") == true)
    #expect(rendered.last?.contains("bottom") == true)
  }
}
