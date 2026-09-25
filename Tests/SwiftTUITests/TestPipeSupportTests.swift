@_spi(Testing) import SwiftTUITestSupport
import Testing

@Suite("Cross-platform test pipe and sleep helpers")
struct TestPipeSupportTests {
  /// `(microseconds, milliseconds)`. From 4,294,966,297 up, adding 999
  /// before dividing would wrap `UInt32` and shrink the sleep to 1 ms.
  private static let sleepRoundingCases: [(UInt32, UInt32)] = [
    (0, 1),
    (1, 1),
    (999, 1),
    (1_000, 1),
    (1_001, 2),
    (5_000, 5),
    (4_294_966_296, 4_294_967),
    (4_294_966_297, 4_294_967),
    (4_294_967_000, 4_294_967),
    (4_294_967_001, 4_294_968),
    (UInt32.max, 4_294_968),
  ]

  @Test(
    "the Windows sleep length rounds microseconds up to whole milliseconds",
    arguments: sleepRoundingCases
  )
  func windowsSleepMillisecondsRoundUp(microseconds: UInt32, milliseconds: UInt32) {
    #expect(testSleepMilliseconds(microseconds: microseconds) == milliseconds)
  }
}
