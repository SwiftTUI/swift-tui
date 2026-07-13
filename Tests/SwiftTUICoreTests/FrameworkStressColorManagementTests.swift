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

  private func expectXYZ(_ actual: XYZColor, equals expected: XYZColor, tolerance: Double) {
    #expect(actual.whitePoint == expected.whitePoint)
    #expect(abs(actual.x - expected.x) < tolerance)
    #expect(abs(actual.y - expected.y) < tolerance)
    #expect(abs(actual.z - expected.z) < tolerance)
  }
}
