@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore

@MainActor
func setGCheck<Value: Sendable>(
  _ id: Int, _ generator: Gen<Value>, _ body: (Value) throws -> String?
) {
  let result = checkProperty(
    generator, seed: 0xF500_0000 + UInt64(id),
    iterations: stressIterations(full: 320, hotPath: 32), maxShrinkSteps: 64, body
  )
  #expect(result.isPassing, "setG\(id): \(result)")
}

let setGNumbers = Gen<[Int]>.array(of: .int(in: 0...255), count: 4...4)
let setGAlphabet = ["a", "Z", "界", "😀", "e\u{301}", "🇨🇦", "👩‍💻", " ", "."]
let setGText = Gen<String>.string(from: setGAlphabet, count: 0...12)

func setGNear(_ a: Double, _ b: Double, tolerance: Double = 1e-8) -> Bool {
  a.isFinite && b.isFinite && abs(a - b) <= tolerance * max(1, abs(a), abs(b))
}

func setGPointNear(_ a: Point, _ b: Point) -> Bool {
  setGNear(a.x, b.x) && setGNear(a.y, b.y)
}
