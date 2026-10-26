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
    await setCKnownAsync(setCNEW1) {
      await #expect(processExitsWith: .success) {
        await MainActor.run { _ = setCBoundsLines(Text("a").padding(Int.max), "201") }
      }
    }
  }

  @Test func setC202SingleEdgeIntMaxPaddingRenders() async {
    await setCKnownAsync(setCNEW2) {
      await #expect(processExitsWith: .success) {
        await MainActor.run { _ = setCBoundsLines(Text("a").padding(.leading, Int.max), "202") }
      }
    }
  }

  @Test func setC203IntMinPaddingRenders() async {
    await setCKnownAsync(setCNEW1) {
      await #expect(processExitsWith: .success) {
        await MainActor.run { _ = setCBoundsLines(Text("a").padding(Int.min), "203") }
      }
    }
  }

  @Test func setC204TopIntMaxPaddingRenders() async {
    await setCKnownAsync(setCNEW2) {
      await #expect(processExitsWith: .success) {
        await MainActor.run { _ = setCBoundsLines(Text("a").padding(.top, Int.max), "204") }
      }
    }
  }

  @Test func setC205IntMaxStackSpacingRenders() async {
    await setCKnownAsync(setCNEW3) {
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
  }

  @Test func setC206IntMinStackSpacingRenders() async {
    await setCKnownAsync(setCNEW3) {
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
  }

  @Test func setC207IntMaxFrameWidthInStackRenders() async {
    await setCKnownAsync(setCNEW3) {
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
  }

  @Test func setC208IntMaxSpacerMinimumRenders() async {
    await setCKnownAsync(setCNEW3) {
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
    await setCKnownAsync(setCNEW4) {
      await #expect(processExitsWith: .success) {
        await MainActor.run { _ = setCBoundsLines(Text("a").offset(x: Int.min), "210") }
      }
    }
  }

  @Test func setC211IntMaxOffsetRenders() async {
    await setCKnownAsync(setCNEW4) {
      await #expect(processExitsWith: .success) {
        await MainActor.run {
          _ = setCBoundsLines(Text("a").offset(x: Int.max, y: Int.max), "211")
        }
      }
    }
  }

  @Test func setC212IntMaxPositionRenders() async {
    await setCKnownAsync(setCNEW4) {
      await #expect(processExitsWith: .success) {
        await MainActor.run { _ = setCBoundsLines(Text("a").position(x: Int.max, y: 0), "212") }
      }
    }
  }

  @Test func setC213IntMaxSafeAreaPaddingRenders() async {
    await setCKnownAsync(setCNEW1) {
      await #expect(processExitsWith: .success) {
        await MainActor.run { _ = setCBoundsLines(Text("a").safeAreaPadding(Int.max), "213") }
      }
    }
  }

  @Test func setC214IntMaxSafeAreaInsetSpacingRenders() async {
    await setCKnownAsync(setCNEW5) {
      await #expect(processExitsWith: .success) {
        await MainActor.run {
          _ = setCBoundsLines(
            Text("a").safeAreaInset(edge: .bottom, spacing: Int.max) { Text("b") }, "214")
        }
      }
    }
  }

  @Test func setC215IntMaxTableColumnWidthRenders() async {
    await setCKnownAsync(setCNEW6) {
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
  }

  // Pin: the documented clamp of a non-positive line limit holds at Int.min.
  @Test func setC216IntMinLineLimitClampsToOneLine() {
    let lines = setCBoundsLines(Text("a b c").lineLimit(Int.min).frame(width: 1), "216")
    let painted = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    #expect(painted.count == 1, "\(lines)")
  }
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

private let setCNEW1 = Comment(
  rawValue:
    "NEW-1: an Int.max or Int.min padding (or safe-area padding) amount "
    + "terminates the process with an arithmetic-overflow trap; "
    + "EdgeInsets.horizontal/vertical add the edges unchecked "
    + "(GeometryTypes.swift:80-86); contract: SwiftUI padding never traps, FW-E "
    + "caller-value contract (fw-e/report-section.md:5); adjacent STUI-741")
private let setCNEW2 = Comment(
  rawValue:
    "NEW-2: a single-edge Int.max padding sizes the root raster surface to "
    + "Int.max cells and crashes allocating it (SIGABRT/SIGBUS); "
    + "Rasterizer.rasterizeFreshCollectingVisibleIdentities allocates the "
    + "measured root extent unbounded (Rasterizer.swift:257-258); contract: "
    + "SwiftUI layout of extreme frames never terminates, FW-E caller-value "
    + "contract; adjacent STUI-741")
private let setCNEW3 = Comment(
  rawValue:
    "NEW-3: Int.max/Int.min stack spacing, an Int.max frame or an Int.max "
    + "Spacer minimum in a stack traps with arithmetic overflow; stack "
    + "measurement sums spacings and child extents unchecked "
    + "(LayoutEngine+StackMeasurementScheduling.swift "
    + "scheduleStackAfterIdealMeasurements, "
    + "LayoutEngine+StackSpaceAllocation.swift:169,180); contract: SwiftUI, "
    + "FW-E caller-value contract; adjacent STUI-741")
private let setCNEW4 = Comment(
  rawValue:
    "NEW-4: offset(x: Int.min), offset(x: Int.max, y: Int.max) or position(x: "
    + "Int.max) traps with arithmetic overflow; LayoutEngine.union forms rect "
    + "far edges unchecked (LayoutEngine+Placement.swift:191-196); contract: "
    + "SwiftUI offset/position never trap, FW-E caller-value contract; adjacent "
    + "STUI-741")
private let setCNEW5 = Comment(
  rawValue:
    "NEW-5: safeAreaInset(spacing: Int.max) traps with arithmetic overflow; "
    + "safeAreaInsetConsumedAmount adds the spacing unchecked "
    + "(LayoutEngine+Insets.swift:95); contract: SwiftUI, FW-E caller-value "
    + "contract; adjacent STUI-741")
private let setCNEW6 = Comment(
  rawValue:
    "NEW-6: a TableColumn width of Int.max beside another column traps with "
    + "arithmetic overflow; borderedTableLineWidth sums column widths unchecked "
    + "(TableSupport.swift:119); contract: FW-E caller-value contract; adjacent "
    + "STUI-741")
