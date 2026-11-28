@_spi(Testing) import SwiftTUITestSupport
import SwiftTUIViews
import Testing

@MainActor
@Suite struct RealizedRowAnimationTests {
  enum Mode: CaseIterable, Sendable {
    case withAnimation, transaction, valueGate, outerOpacity
  }

  private final class Realizations {
    var indices: Set<Int> = []
  }

  private struct Scene: View {
    let list: Bool
    let mode: Mode
    let realized: Realizations
    @State private var changed = false
    nonisolated var curve: Animation { .linear(duration: .seconds(1)) }

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("animate").focusable().onKeyPress(.character("a")) { _ in
          switch mode {
          case .withAnimation, .outerOpacity: withAnimation(curve) { changed.toggle() }
          case .transaction, .valueGate: changed.toggle()
          }
          return .handled
        }
        if list {
          ScrollView { List(0..<1_000, id: \.self) { row($0) } }.frame(height: 6)
        } else {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
              ForEach(0..<1_000, id: \.self) { row($0) }
            }
          }
        }
      }
    }

    @ViewBuilder private func row(_ index: Int) -> some View {
      let _ = realized.indices.insert(index)
      let text = Text("X\(index)").foregroundStyle(Color.white)
      switch mode {
      case .withAnimation: text.offset(x: changed ? 8 : 0)
      case .transaction:
        text.offset(x: changed ? 8 : 0).transaction { $0.animation = curve }
      case .valueGate:
        text.offset(x: changed ? 8 : 0).animation(curve, value: changed)
      case .outerOpacity:
        text.transaction { $0.disablesAnimations = true }.opacity(changed ? 0.9 : 0.1)
      }
    }
  }

  @Test(
    "visible lazy rows paint the midpoint and endpoint without visiting the dataset",
    arguments: [false, true], Mode.allCases)
  func rowPresentation(list: Bool, mode: Mode) throws {
    let realized = Realizations()
    let harness = try RunLoopTestHarness(size: .init(width: 32, height: 8)) {
      Scene(list: list, mode: mode, realized: realized)
    }
    defer { harness.shutdown() }

    func sample() throws -> (x: Int, brightness: Double) {
      for line in harness.frame.cells {
        if let x = line.firstIndex(where: { $0.character == "X" }) {
          return (x, line[x].style?.foregroundColor?.red ?? 1)
        }
      }
      throw IssueError.noVisibleRow
    }

    let start = try sample()
    try harness.press(KeyPress(.character("a")))
    try harness.advance(by: .milliseconds(500))
    let middle = try sample()
    try harness.advance(by: .milliseconds(600))
    let end = try sample()
    if mode == .outerOpacity {
      #expect(start.brightness < middle.brightness && middle.brightness < end.brightness)
    } else {
      #expect(middle.x > start.x && middle.x < end.x)
      #expect(end.x == start.x + 8)
    }
    #expect(realized.indices.count < 100)
  }

  private enum IssueError: Error { case noVisibleRow }
}
