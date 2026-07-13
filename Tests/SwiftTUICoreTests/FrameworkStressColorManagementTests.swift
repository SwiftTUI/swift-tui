import Testing

@testable import SwiftTUICore
@testable import SwiftTUIPrimitives

@Suite("Framework stress: color management", .serialized)
struct FrameworkStressColorManagementTests {
  @Test("stress color management 001 repeated Bradford adaptation remains reversible")
  func colorManagement001RepeatedBradfordAdaptationRemainsReversible() {
    let original = XYZColor(x: 0.31, y: 0.42, z: 0.17, whitePoint: .d65)
    var cycled = original

    for _ in 0..<256 {
      cycled = adapt(adapt(cycled, to: .d50, method: .bradford), to: .d65, method: .bradford)
    }

    expectXYZ(cycled, equals: original, tolerance: 1e-10)
  }

  @Test("stress color management 002 repeated CAT02 adaptation remains reversible")
  func colorManagement002RepeatedCAT02AdaptationRemainsReversible() {
    let original = XYZColor(x: 0.73, y: 0.11, z: 0.09, whitePoint: .d60)
    var cycled = original

    for _ in 0..<256 {
      cycled = adapt(adapt(cycled, to: .d75, method: .cat02), to: .d60, method: .cat02)
    }

    expectXYZ(cycled, equals: original, tolerance: 1e-10)
  }

  @Test("stress color management 003 repeated wide-gamut profile cycles preserve appearance")
  func colorManagement003RepeatedWideGamutProfileCyclesPreserveAppearance() {
    let original = Color(red: 0.21, green: 0.72, blue: 0.43, alpha: 0.61, profile: .displayP3)
    var cycled = original

    for _ in 0..<64 {
      cycled = cycled.converted(to: .proPhotoRGB, gamutMapping: .preserve)
      cycled = cycled.converted(to: .adobeRGB, gamutMapping: .preserve)
      cycled = cycled.converted(to: .rec2020, gamutMapping: .preserve)
      cycled = cycled.converted(to: .displayP3, gamutMapping: .preserve)
    }

    #expect(cycled.profile == .displayP3)
    #expect(abs(cycled.alpha - original.alpha) < 1e-12)
    #expect(cycled.deltaE(to: original) < 1e-8)
  }

  @Test("stress color management 004 absolute conversion preserves source white luminance")
  func colorManagement004AbsoluteConversionPreservesSourceWhiteLuminance() {
    let sourceWhite = Color(white: 1, profile: .proPhotoRGB)
    let relative = sourceWhite.converted(to: .sRGB, gamutMapping: .relativeColorimetric)
    let absolute = sourceWhite.converted(to: .sRGB, gamutMapping: .absoluteColorimetric)

    #expect(relative.deltaE(to: .white) < 1e-4)
    withKnownIssue("Absolute and relative colorimetric policies currently share one clip path") {
      #expect(absolute.deltaE(to: relative) > 0.5)
    }
  }

  @Test("stress color management 005 preserve and clip diverge for P3-only green")
  func colorManagement005PreserveAndClipDivergeForP3OnlyGreen() {
    let p3Green = Color(red: 0, green: 1, blue: 0, profile: .displayP3)
    let preserved = p3Green.converted(to: .sRGB, gamutMapping: .preserve)
    let clipped = p3Green.converted(to: .sRGB, gamutMapping: .clip)

    #expect(!preserved.isInGamut(for: .sRGB))
    #expect(clipped.red >= 0 && clipped.red <= 1)
    #expect(clipped.green >= 0 && clipped.green <= 1)
    #expect(clipped.blue >= 0 && clipped.blue <= 1)
    #expect(clipped != preserved)
  }

  @Test("stress color management 006 lightness compression contains extreme Rec. 2020 color")
  func colorManagement006LightnessCompressionContainsExtremeRec2020Color() {
    let source = Color(red: 1.4, green: -0.3, blue: 0.9, profile: .rec2020)
    let compressed = source.converted(to: .sRGB, gamutMapping: .compressLightness)

    #expect(compressed.profile == .sRGB)
    #expect(compressed.red >= -1e-9 && compressed.red <= 1 + 1e-9)
    #expect(compressed.green >= -1e-9 && compressed.green <= 1 + 1e-9)
    #expect(compressed.blue >= -1e-9 && compressed.blue <= 1 + 1e-9)
    #expect(compressed.alpha == source.alpha)
  }

  @Test("stress color management 007 linear-light midpoint remains physically linear")
  func colorManagement007LinearLightMidpointRemainsPhysicallyLinear() {
    let midpoint = Color.black.interpolated(to: .white, progress: 0.5, method: .linearLight)
    let expected = TransferFunction.sRGB.encode(0.5)

    #expect(abs(midpoint.red - expected) < 1e-10)
    #expect(abs(midpoint.green - expected) < 1e-10)
    #expect(abs(midpoint.blue - expected) < 1e-10)
    #expect(midpoint.profile == .sRGB)
  }

  private func expectXYZ(_ actual: XYZColor, equals expected: XYZColor, tolerance: Double) {
    #expect(actual.whitePoint == expected.whitePoint)
    #expect(abs(actual.x - expected.x) < tolerance)
    #expect(abs(actual.y - expected.y) < tolerance)
    #expect(abs(actual.z - expected.z) < tolerance)
  }
}
