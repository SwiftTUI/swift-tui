import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

/// F52-C1: `RGBAImagePixel` packs its 0-255 channels into four bytes rather than
/// four `Int`s. Locks the footprint (an 8x shrink in every retained pixel buffer)
/// and confirms the `Int` accessors + clamping behave exactly as before.
@Suite
struct RGBAImagePixelTests {
  @Test("RGBAImagePixel is four bytes, not four Ints")
  func rgbaImagePixelIsFourBytes() {
    #expect(MemoryLayout<RGBAImagePixel>.stride == 4)
    #expect(MemoryLayout<RGBAImagePixel>.size == 4)
  }

  @Test("channels round-trip and clamp through the Int accessors")
  func channelsRoundTripAndClamp() {
    let pixel = RGBAImagePixel(red: 10, green: 128, blue: 255, alpha: 200)
    #expect(pixel.red == 10)
    #expect(pixel.green == 128)
    #expect(pixel.blue == 255)
    #expect(pixel.alpha == 200)

    let clamped = RGBAImagePixel(red: -5, green: 300, blue: 256, alpha: -1)
    #expect(clamped.red == 0)
    #expect(clamped.green == 255)
    #expect(clamped.blue == 255)
    #expect(clamped.alpha == 0)

    // Equality is preserved by the packed storage.
    #expect(
      RGBAImagePixel(red: 1, green: 2, blue: 3, alpha: 4)
        == RGBAImagePixel(red: 1, green: 2, blue: 3, alpha: 4))
    #expect(
      RGBAImagePixel(red: 1, green: 2, blue: 3, alpha: 4)
        != RGBAImagePixel(red: 1, green: 2, blue: 3, alpha: 5))
  }
}
