import Foundation
import Testing

@testable import Core
@testable import View

@MainActor
@Suite
struct GestureProtocolTests {
  @Test("Gesture protocol compiles with Body == Never primitive")
  func primitiveCompiles() {
    struct Fake: Gesture {
      typealias Value = Int
      typealias Body = Never

      var body: Never { neverBody() }

      package func _makeRecognizer(context: GestureRecognizerBuildContext) -> AnyGestureRecognizer {
        AnyGestureRecognizer(NoopRecognizer())
      }
    }

    let fake = Fake()
    #expect(fake is (any Gesture))
  }

  @Test("Accessing Never body traps")
  func neverBodyTraps() {
    // Compile-time check that neverBody() exists.
    _ = { () -> Never in neverBody() }
  }
}

private final class NoopRecognizer: GestureRecognizer {
  typealias Value = Int
  var phase: GestureRecognizerPhase = .possible
  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition { .ignored }
  func handleDeadline(at instant: MonotonicInstant) -> Bool { false }
  func currentValue() -> Int? { nil }
  func tearDown() {}
}
