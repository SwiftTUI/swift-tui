@_spi(Testing) import SwiftTUITestSupport
import Testing

// Campaign two tooling: the seeded generator and shrinker that the generative
// lineage (F5) and the child lineages build on. These tests pin the stream,
// the shrinking contract, and the failure report shape; the TypeScript twin
// in swift-tui-web pins the same SplitMix64 vector so one seed means one
// sequence on both sides.
@Suite("Seeded generation")
struct SeededGenerationTests {
  @Test func splitMix64MatchesTheReferenceVectorForSeedZero() {
    var source = SeededRandomSource(seed: 0)
    #expect(source.next() == 0xE220_A839_7B1D_CDAF)
    #expect(source.next() == 0x6E78_9E6A_A1B9_65F4)
    #expect(source.next() == 0x06C4_5D18_8009_454F)
  }

  @Test func theSameSeedDrawsTheSameValuesAndAnotherSeedDoesNot() {
    let gen = Gen<[Int]>.array(of: .int(in: -50...50), count: 0...8)
    func draw(_ seed: UInt64) -> [Int] {
      var source = SeededRandomSource(seed: seed)
      return gen.run(&source).value
    }
    #expect(draw(7) == draw(7))
    #expect(draw(7) != draw(8))
  }

  @Test func fullRangeIntegersDoNotTrap() {
    var source = SeededRandomSource(seed: 42)
    let full = Gen<Int>.int(in: Int.min...Int.max)
    let edge = Gen<Int>.int(in: (Int.max - 3)...Int.max)
    for _ in 0..<64 {
      _ = full.run(&source).value
      #expect(edge.run(&source).value >= Int.max - 3)
    }
  }

  @Test func integerShrinkingReachesTheSmallestFailingValue() {
    let result = checkProperty(Gen<Int>.int(in: 0...10_000), seed: 1, iterations: 200) { n in
      n >= 37 ? "too big: \(n)" : nil
    }
    #expect(result.failure?.minimal == 37, "\(result)")
  }

  @Test func arrayShrinkingRemovesUnrelatedElementsAndShrinksTheCulprit() {
    let result = checkProperty(
      Gen<[Int]>.array(of: .int(in: 0...100), count: 0...20), seed: 3, iterations: 200
    ) { items in
      items.contains { $0 > 60 } ? "has a large element" : nil
    }
    #expect(result.failure?.minimal == [61], "\(result)")
  }

  @Test func hostileStringsShrinkToTheOffendingPiece() {
    let result = checkProperty(
      Gen<String>.string(from: hostileGraphemeAlphabet, count: 1...12), seed: 11, iterations: 500
    ) { s in
      s.unicodeScalars.contains("\u{200D}") ? "contains ZWJ" : nil
    }
    let minimal = try? #require(result.failure?.minimal)
    #expect(minimal?.unicodeScalars.contains("\u{200D}") == true, "\(result)")
    #expect((minimal?.count ?? .max) <= 5, "\(result)")
  }

  @Test func specialDoublesAreDrawnAndAPassingPropertyReportsItsCount() {
    var seen: Set<String> = []
    let result = checkProperty(Gen<Double>.doubleWithSpecials(), seed: 5, iterations: 400) { x in
      seen.insert(x.isNaN ? "nan" : x == 0 && x.sign == .minus ? "-0" : "\(x)")
      return nil
    }
    #expect(result.isPassing)
    #expect(result.passed == 400)
    #expect(seen.contains("nan"))
    #expect(seen.contains("inf"))
    #expect(seen.contains("-0"))
  }

  @Test func throwingBodiesAndZipShrinkBothSides() {
    struct Boom: Error {}
    let result = checkProperty(
      Gen<(Int, Bool)>.zip(.int(in: 0...9), .bool), seed: 9, iterations: 100
    ) { pair in
      if pair.1, pair.0 > 2 { throw Boom() }
      return nil
    }
    let minimal = try? #require(result.failure?.minimal)
    #expect(minimal?.0 == 3 && minimal?.1 == true, "\(result)")
    #expect(result.description.contains("seed=0x9"))
    #expect(result.description.contains("threw"))
  }

  @Test func flatMapShrinksTheOuterValueBeforeTheInnerOne() {
    let gen = Gen<Int>.int(in: 1...8).flatMap { length in
      Gen<[Int]>.array(of: .int(in: 0...9), count: length...length)
    }
    let result = checkProperty(gen, seed: 13, iterations: 200) { items in
      items.count >= 3 ? "three or more" : nil
    }
    #expect(result.failure?.minimal.count == 3, "\(result)")
  }
}
