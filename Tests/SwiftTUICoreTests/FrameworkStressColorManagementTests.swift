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

  private func expectXYZ(_ actual: XYZColor, equals expected: XYZColor, tolerance: Double) {
    #expect(actual.whitePoint == expected.whitePoint)
    #expect(abs(actual.x - expected.x) < tolerance)
    #expect(abs(actual.y - expected.y) < tolerance)
    #expect(abs(actual.z - expected.z) < tolerance)
  }
}
