import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
struct PaletteStyleReuseTests {
  @Test func typedEquality() {
    #expect(AnyPaletteStyle.automatic.isEqualForReuse(to: AnyPaletteStyle.automatic))
    #expect(
      AnyPaletteStyle(ConsumerPaletteStyle(tag: "a")).isEqualForReuse(
        to: AnyPaletteStyle(ConsumerPaletteStyle(tag: "a"))))
    #expect(
      !AnyPaletteStyle(ConsumerPaletteStyle(tag: "a")).isEqualForReuse(
        to: AnyPaletteStyle(ConsumerPaletteStyle(tag: "b"))))
    #expect(
      !AnyPaletteStyle.automatic.isEqualForReuse(
        to: AnyPaletteStyle(ConsumerPaletteStyle(tag: "a"))))
    #expect(
      !AnyPaletteStyle(OpaquePaletteStyle()).isEqualForReuse(
        to: AnyPaletteStyle(OpaquePaletteStyle())))
  }
}

private struct OpaquePaletteStyle: PaletteStyle {
  let callback: @Sendable () -> Void = {}
  func makeBody(configuration: PaletteStyleConfiguration) -> some View { Text(configuration.title) }
}
