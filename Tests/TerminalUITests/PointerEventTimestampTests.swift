import Foundation
import Testing

@testable import Core

@MainActor
@Suite
struct PointerEventTimestampTests {
  @Test("LocalPointerEvent carries a MonotonicInstant timestamp")
  func carriesTimestamp() {
    let now = MonotonicInstant.now()
    let event = LocalPointerEvent(
      kind: .down(.primary),
      location: .zero,
      targetRect: Rect(origin: .zero, size: Size(width: 1, height: 1)),
      timestamp: now
    )
    #expect(event.timestamp == now)
  }

  @Test("LocalPointerEvent defaults timestamp to .now()")
  func defaultTimestampIsNow() {
    let before = MonotonicInstant.now()
    let event = LocalPointerEvent(
      kind: .down(.primary),
      location: .zero,
      targetRect: Rect(origin: .zero, size: Size(width: 1, height: 1))
    )
    let after = MonotonicInstant.now()
    #expect(event.timestamp >= before && event.timestamp <= after)
  }
}
