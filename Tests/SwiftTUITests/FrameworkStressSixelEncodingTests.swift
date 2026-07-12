import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

@Suite(.serialized)
struct FrameworkStressSixelEncodingTests {
  @Test("stress sixel encoding 001 reported cell metrics scale both output axes")
  func sixelEncoding001ReportedCellMetricsScaleBothOutputAxes() {
    // Hypothesis: terminal cell metrics can be transposed when expanded into image pixels.
    let size = sixelOutputSize(
      for: .init(origin: .zero, size: .init(width: 7, height: 3)),
      graphicsCapabilities: .init(cellPixelSize: .init(width: 9, height: 18))
    )

    #expect(size == PixelSize(width: 63, height: 54))
  }

  @Test("stress sixel encoding 002 absent metrics use the stable eight by sixteen fallback")
  func sixelEncoding002AbsentMetricsUseStableFallback() {
    // Hypothesis: a missing metric report can collapse Sixel output to cell dimensions.
    let size = sixelOutputSize(
      for: .init(origin: .zero, size: .init(width: 7, height: 3)),
      graphicsCapabilities: .init()
    )

    #expect(size == PixelSize(width: 56, height: 48))
  }

  @Test("stress sixel encoding 003 empty visible bounds produce no pixel footprint")
  func sixelEncoding003EmptyVisibleBoundsProduceNoPixelFootprint() {
    // Hypothesis: minimum-one clamping can create a phantom Sixel for an empty clip.
    let size = sixelOutputSize(
      for: .init(origin: .zero, size: .zero),
      graphicsCapabilities: .init(cellPixelSize: .init(width: 9, height: 18))
    )

    #expect(size == .init(width: 0, height: 0))
  }

  @Test("stress sixel encoding 004 ANSI terminals retain the sixteen color ceiling")
  func sixelEncoding004ANSITerminalsRetainSixteenColorCeiling() {
    // Hypothesis: the Sixel palette can ignore the lower text-color capability ceiling.
    let budget = sixelPaletteBudget(
      capabilityProfile: .ansi16,
      graphicsCapabilities: .init(sixelColorRegisters: 256)
    )

    #expect(budget == 16)
  }

  @Test("stress sixel encoding 005 reported register count caps true color terminals")
  func sixelEncoding005ReportedRegisterCountCapsTrueColorTerminals() {
    // Hypothesis: true-color detection can override a smaller terminal Sixel register bank.
    let budget = sixelPaletteBudget(
      capabilityProfile: .trueColor,
      graphicsCapabilities: .init(sixelColorRegisters: 64)
    )

    #expect(budget == 64)
  }

  @Test("stress sixel encoding 006 invalid one register report is never exceeded")
  func sixelEncoding006InvalidOneRegisterReportIsNeverExceeded() {
    // Hypothesis: minimum-two clamping can promise more registers than the terminal reported.
    let budget = sixelPaletteBudget(
      capabilityProfile: .trueColor,
      graphicsCapabilities: .init(sixelColorRegisters: 1)
    )

    #expect(budget <= 1)
  }

  @Test("stress sixel encoding 007 transparent images produce no terminal payload")
  func sixelEncoding007TransparentImagesProduceNoTerminalPayload() {
    // Hypothesis: a fully transparent source can synthesize a black palette and phantom image.
    let image = sixelStressImage(
      width: 1,
      height: 1,
      pixels: [RGBAImagePixel(red: 20, green: 40, blue: 60, alpha: 0)]
    )

    #expect(
      makeSixelPayload(
        for: image,
        outputSize: .init(width: 1, height: 1),
        paletteBudget: 16
      ) == nil
    )
  }

  @Test("stress sixel encoding 008 zero output geometry produces no payload")
  func sixelEncoding008ZeroOutputGeometryProducesNoPayload() {
    // Hypothesis: zero-sized scaling can still emit a syntactically complete phantom Sixel.
    let image = sixelStressImage(
      width: 1,
      height: 1,
      pixels: [RGBAImagePixel(red: 255, green: 0, blue: 0, alpha: 255)]
    )

    #expect(
      makeSixelPayload(
        for: image,
        outputSize: .zero,
        paletteBudget: 16
      ) == nil
    )
  }
}

private func sixelStressImage(
  width: Int,
  height: Int,
  pixels: [RGBAImagePixel]
) -> DecodedImage {
  DecodedImage(
    encodedBytes: [1],
    encodedFormat: .png,
    pixelSize: .init(width: width, height: height),
    pixels: pixels
  )
}
