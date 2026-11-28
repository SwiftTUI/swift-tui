import Observation
@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@testable import SwiftTUIViews

@MainActor
@Suite
struct ObservableAnimationTransactionTests {
  @Test("An animated observable write reaches the body and animates the rendered offset")
  func animatedModelOffset() throws {
    let model = MovingModel()
    let recorder = MovingModelRecorder()
    let harness = try RunLoopTestHarness(size: .init(width: 20, height: 3)) {
      MovingModelScene(model: model, recorder: recorder)
    }
    defer { harness.shutdown() }

    func column() throws -> Int {
      let line = try #require(harness.lines.first { $0.contains("X") })
      let x = try #require(line.firstIndex(of: "X"))
      return line.distance(from: line.startIndex, to: x)
    }
    let initial = try column()
    recorder.curves.withLock { $0.removeAll() }
    try harness.press(.init(.character("x")))
    #expect(recorder.curves.withLock { $0.contains(MovingModelScene.curve) })
    #expect(recorder.completions == 0)
    try harness.advance(by: .milliseconds(400))
    let middle = try column()
    #expect(middle > initial && middle < initial + 8)
    try harness.advance(by: .milliseconds(600))
    #expect(try column() == initial + 8)
    #expect(recorder.completions == 1)
  }
}

@MainActor @Observable
private final class MovingModel {
  var moved = false
}

@MainActor
private final class MovingModelRecorder {
  nonisolated let curves = Mutex<[Animation?]>([])
  var completions = 0
}

private struct MovingModelScene: View {
  static let curve = Animation.linear(duration: .milliseconds(800))
  let model: MovingModel
  let recorder: MovingModelRecorder

  var body: some View {
    Text("X")
      .offset(x: model.moved ? 8 : 0)
      .transaction { [recorder] tx in recorder.curves.withLock { $0.append(tx.animation) } }
      .frame(maxWidth: .infinity, alignment: .leading)
      .focusable()
      .onKeyPress(.character("x")) { _ in
        withAnimation(Self.curve) {
          model.moved = true
        } completion: {
          recorder.completions += 1
        }
        return .handled
      }
  }
}
