import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct RealizedTextTransitionTests {
  private struct RuntimeRows: View {
    @State private var digit = "7"
    @State private var complete = false
    var body: some View {
      VStack {
        Button(complete ? "DONE" : "roll") {
          withAnimation(.linear(duration: .milliseconds(500))) {
            digit = "0"
          } completion: {
            complete = true
          }
        }
        List(0..<100, id: \.self) { row in
          Text("row \(row): \(digit)").contentTransition(.numericText())
        }
      }
    }
  }

  @Test("an indexed row driven by input rolls and releases its completion batch")
  func runtimeCompletion() async throws {
    let harness = try AnimatorRuntimeHarness(size: .init(width: 30, height: 9)) { RuntimeRows() }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController
    try withAnimationSinks(controller) { _ = try harness.clickText("roll") }
    try await harness.wait { harness.frame.contains("DONE") }
    let frames = harness.surfaces.map { $0.lines.joined(separator: "\n") }
    #expect(frames.contains { $0.contains("row 0: 8") || $0.contains("row 0: 9") })
    #expect(harness.frame.contains("row 0: 0"))
    #expect(controller.debugStateSnapshot().completionClosureBatchIDs.isEmpty)
    #expect(controller.activeAnimationCount == 0)
  }

  private struct Rows: View {
    var digit: String
    var indexed: Bool
    var firstRow: Int = 0
    var body: some View {
      if indexed {
        List(firstRow..<(firstRow + 100), id: \.self) { row in
          Text("row \(row): \(digit)").contentTransition(.numericText())
        }
      } else {
        List {
          ForEach(firstRow..<(firstRow + 100), id: \.self) { row in
            Text("row \(row): \(digit)").contentTransition(.numericText())
          }
        }
      }
    }
  }

  @Test("numeric text samples in both indexed and eager List rows", arguments: [true, false])
  func listRows(indexed: Bool) throws {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let root = testIdentity("realized-text")
    let start = MonotonicInstant(offset: .seconds(100))
    let proposal = ProposedSize(width: .finite(30), height: .finite(7))
    var animated = TransactionSnapshot()
    animated.animationRequest = .animate(Animation.linear(duration: .seconds(1)).animationBox)
    withAnimationSinks(controller) {
      _ = renderer.render(
        Rows(digit: "7", indexed: indexed), context: .init(identity: root),
        proposal: proposal, frameInstant: start)
      let changed = renderer.render(
        Rows(digit: "0", indexed: indexed),
        context: .init(identity: root, transaction: animated), proposal: proposal,
        frameInstant: start)
      #expect(controller.activeAnimationCount > 0)
      #expect(changed.rasterSurface.lines.joined(separator: "\n").contains("row 0: 7"))
      let midpoint = renderer.render(
        Rows(digit: "0", indexed: indexed),
        context: .init(identity: root), proposal: proposal,
        frameInstant: start.advanced(by: .milliseconds(500)))
      let midText = midpoint.rasterSurface.lines.joined(separator: "\n")
      #expect(midText.contains("row 0: 8") || midText.contains("row 0: 9"), "\(midText)")
      let settled = renderer.render(
        Rows(digit: "0", indexed: indexed),
        context: .init(identity: root), proposal: proposal,
        frameInstant: start.advanced(by: .milliseconds(1500)))
      #expect(settled.rasterSurface.lines.joined(separator: "\n").contains("row 0: 0"))
      #expect(controller.activeAnimationCount == 0)
      #expect(!controller.lastTickResult.hasPendingWork)
    }
  }

  @Test("replacing an indexed viewport releases its departed rolls")
  func viewportDeparture() {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let root = testIdentity("realized-text-departure")
    let start = MonotonicInstant(offset: .seconds(100))
    let proposal = ProposedSize(width: .finite(30), height: .finite(7))
    var animated = TransactionSnapshot()
    animated.animationRequest = .animate(Animation.linear(duration: .seconds(10)).animationBox)
    withAnimationSinks(controller) {
      _ = renderer.render(
        Rows(digit: "7", indexed: true), context: .init(identity: root),
        proposal: proposal, frameInstant: start)
      _ = renderer.render(
        Rows(digit: "0", indexed: true),
        context: .init(identity: root, transaction: animated), proposal: proposal,
        frameInstant: start)
      #expect(controller.activeAnimationCount > 0)
      _ = renderer.render(
        Rows(digit: "0", indexed: true, firstRow: 100),
        context: .init(identity: root), proposal: proposal,
        frameInstant: start.advanced(by: .milliseconds(100)))
      #expect(controller.activeAnimationCount == 0)
      #expect(!controller.lastTickResult.hasPendingWork)
    }
  }

  @Test(
    "indexed retargeting continues from the displayed digit or snaps when unanimated",
    arguments: [true, false])
  func retarget(animatedRetarget: Bool) {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let root = testIdentity("realized-retarget")
    let start = MonotonicInstant(offset: .seconds(100))
    let proposal = ProposedSize(width: .finite(30), height: .finite(7))
    var animated = TransactionSnapshot()
    animated.animationRequest = .animate(Animation.linear(duration: .seconds(1)).animationBox)
    withAnimationSinks(controller) {
      _ = renderer.render(
        Rows(digit: "7", indexed: true), context: .init(identity: root),
        proposal: proposal, frameInstant: start)
      _ = renderer.render(
        Rows(digit: "0", indexed: true),
        context: .init(identity: root, transaction: animated), proposal: proposal,
        frameInstant: start)
      let retargeted = renderer.render(
        Rows(digit: "5", indexed: true),
        context: .init(identity: root, transaction: animatedRetarget ? animated : .init()),
        proposal: proposal, frameInstant: start.advanced(by: .milliseconds(500)))
      let text = retargeted.rasterSurface.lines.joined(separator: "\n")
      #expect(text.contains(animatedRetarget ? "row 0: 9" : "row 0: 5"), "\(text)")
      #expect((controller.activeAnimationCount > 0) == animatedRetarget)
    }
  }
}
