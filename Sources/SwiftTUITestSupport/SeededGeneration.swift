import Foundation

// Deterministic pseudo-random generation with shrinking for adversarial
// property tests (campaign two, lineage F5 and the child lineages).
//
// A `Gen` produces a `Shrinkable`: the drawn value plus a lazy list of
// strictly smaller candidates. `checkProperty` draws `iterations` values from
// a seeded SplitMix64 stream, treats the first body failure as a
// counterexample, shrinks it greedily, and returns a result the test asserts
// on with its own message. The TypeScript twin in swift-tui-web
// (`packages/web/test-support/SeededGenerator.ts`) shares the SplitMix64 stream, so a
// seed reproduces the same integer sequence on both sides.
//
// No Foundation randomness and no third-party dependency: public children
// must stay dependency-light, and a seed must mean the same thing on macOS,
// Linux, Windows and WASI.

/// SplitMix64. `next()` matches the reference implementation bit for bit.
@_spi(Testing) public struct SeededRandomSource: RandomNumberGenerator, Sendable {
  public private(set) var state: UInt64

  public init(seed: UInt64) {
    state = seed
  }

  public mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  /// Uniform integer in `range`, inclusive; safe for the full `Int` range.
  public mutating func int(in range: ClosedRange<Int>) -> Int {
    let span = UInt64(bitPattern: Int64(range.upperBound) &- Int64(range.lowerBound)) &+ 1
    if span == 0 { return Int(Int64(bitPattern: next())) }
    let offset = next() % span
    return Int(Int64(bitPattern: UInt64(bitPattern: Int64(range.lowerBound)) &+ offset))
  }

  /// Uniform double in `[0, 1)` with 53 bits of entropy.
  public mutating func unit() -> Double {
    Double(next() >> 11) / 9_007_199_254_740_992.0
  }
}

/// A drawn value with its lazily computed, strictly smaller candidates.
@_spi(Testing) public struct Shrinkable<Value: Sendable>: Sendable {
  public let value: Value
  public let shrinks: @Sendable () -> [Shrinkable<Value>]

  public init(value: Value, shrinks: @escaping @Sendable () -> [Shrinkable<Value>]) {
    self.value = value
    self.shrinks = shrinks
  }

  public static func leaf(_ value: Value) -> Shrinkable<Value> {
    Shrinkable(value: value, shrinks: { [] })
  }
}

/// A generator of shrinkable values from a seeded source.
@_spi(Testing) public struct Gen<Value: Sendable>: Sendable {
  public let run: @Sendable (inout SeededRandomSource) -> Shrinkable<Value>

  public init(run: @escaping @Sendable (inout SeededRandomSource) -> Shrinkable<Value>) {
    self.run = run
  }

  public static func constant(_ value: Value) -> Gen<Value> {
    Gen { _ in .leaf(value) }
  }

  public func map<Mapped: Sendable>(_ transform: @escaping @Sendable (Value) -> Mapped) -> Gen<
    Mapped
  > {
    @Sendable func lift(_ inner: Shrinkable<Value>) -> Shrinkable<Mapped> {
      Shrinkable(value: transform(inner.value)) { inner.shrinks().map(lift) }
    }
    return Gen<Mapped> { source in lift(run(&source)) }
  }

  /// Dependent generation; shrinks the outer value first, then the inner one.
  public func flatMap<Mapped: Sendable>(_ next: @escaping @Sendable (Value) -> Gen<Mapped>) -> Gen<
    Mapped
  > {
    Gen<Mapped> { source in
      let outer = run(&source)
      let innerSeed = source.next()
      @Sendable func build(_ outer: Shrinkable<Value>) -> Shrinkable<Mapped> {
        var innerSource = SeededRandomSource(seed: innerSeed)
        let inner = next(outer.value).run(&innerSource)
        return Shrinkable(value: inner.value) { outer.shrinks().map(build) + inner.shrinks() }
      }
      return build(outer)
    }
  }

  public static func zip<A: Sendable, B: Sendable>(_ a: Gen<A>, _ b: Gen<B>) -> Gen<(A, B)>
  where Value == (A, B) {
    @Sendable func pair(_ x: Shrinkable<A>, _ y: Shrinkable<B>) -> Shrinkable<(A, B)> {
      Shrinkable(value: (x.value, y.value)) {
        x.shrinks().map { pair($0, y) } + y.shrinks().map { pair(x, $0) }
      }
    }
    return Gen { source in
      let x = a.run(&source)
      let y = b.run(&source)
      return pair(x, y)
    }
  }
}

extension Gen where Value == Int {
  /// Integers in `range`; shrinks towards zero, or the bound nearest zero.
  public static func int(in range: ClosedRange<Int>) -> Gen<Int> {
    let target: Int
    if range.contains(0) {
      target = 0
    } else {
      target =
        range.lowerBound.magnitude < range.upperBound.magnitude
        ? range.lowerBound : range.upperBound
    }
    @Sendable func shrinkable(_ value: Int) -> Shrinkable<Int> {
      Shrinkable(value: value) {
        var candidates: [Int] = []
        if value != target { candidates.append(target) }
        var delta = value &- target
        while delta.magnitude > 1 {
          delta /= 2
          let candidate = value &- delta
          if candidate != value, range.contains(candidate), !candidates.contains(candidate) {
            candidates.append(candidate)
          }
        }
        return candidates.map(shrinkable)
      }
    }
    return Gen { source in shrinkable(source.int(in: range)) }
  }
}

extension Gen where Value == Bool {
  /// Shrinks `true` to `false`.
  public static var bool: Gen<Bool> {
    Gen { source in
      let value = source.int(in: 0...1) == 1
      return Shrinkable(value: value) { value ? [.leaf(false)] : [] }
    }
  }
}

extension Gen where Value == Double {
  /// Uniform doubles in `range`; shrinks towards zero, the truncated integer, and half.
  public static func double(in range: ClosedRange<Double>) -> Gen<Double> {
    @Sendable func shrinkable(_ value: Double) -> Shrinkable<Double> {
      Shrinkable(value: value) {
        var candidates: [Double] = []
        if value != 0, range.contains(0) { candidates.append(0) }
        let truncated = value.rounded(.towardZero)
        if truncated != value, range.contains(truncated) { candidates.append(truncated) }
        let half = value / 2
        if half != value, range.contains(half) { candidates.append(half) }
        return candidates.map(shrinkable)
      }
    }
    return Gen { source in
      shrinkable(range.lowerBound + source.unit() * (range.upperBound - range.lowerBound))
    }
  }

  /// The IEEE values every numeric seam must survive, mixed one-in-four with
  /// ordinary draws: signed zeros, infinities, NaN, the extremes, subnormals,
  /// epsilon, values just past 2^53, and the classic inexact sums.
  public static let doubleSpecialValues: [Double] = [
    0, -0.0, .infinity, -.infinity, .nan, .greatestFiniteMagnitude, -.greatestFiniteMagnitude,
    .leastNonzeroMagnitude, -.leastNonzeroMagnitude, .leastNormalMagnitude, .ulpOfOne,
    9_007_199_254_740_992, 9_007_199_254_740_994, -9_007_199_254_740_992, 1e308, -1e308, 1e-308,
    Double(Int.max), Double(Int.min), 0.1 + 0.2, 1.0 / 3.0,
  ]

  public static func doubleWithSpecials(ordinary range: ClosedRange<Double> = -1e6...1e6) -> Gen<
    Double
  > {
    let ordinary = Gen<Double>.double(in: range)
    return Gen { source in
      if source.int(in: 0...3) == 0 {
        let value = doubleSpecialValues[source.int(in: 0...(doubleSpecialValues.count - 1))]
        return Shrinkable(value: value) { [.leaf(0)] }
      }
      return ordinary.run(&source)
    }
  }
}

extension Gen {
  /// One of `values`; shrinks towards the first element.
  public static func element(of values: [Value]) -> Gen<Value> {
    precondition(!values.isEmpty, "Gen.element(of:) needs at least one value")
    return Gen { source in
      let index = source.int(in: 0...(values.count - 1))
      return Shrinkable(value: values[index]) { index == 0 ? [] : [.leaf(values[0])] }
    }
  }

  /// Arrays with `count` elements; shrinks by dropping halves, then single
  /// elements, then by shrinking elements in place.
  public static func array<Element: Sendable>(of element: Gen<Element>, count: ClosedRange<Int>)
    -> Gen<[Element]>
  where Value == [Element] {
    @Sendable func shrinkable(_ items: [Shrinkable<Element>]) -> Shrinkable<[Element]> {
      Shrinkable(value: items.map(\.value)) {
        var candidates: [[Shrinkable<Element>]] = []
        var chunk = items.count / 2
        while chunk >= 1 {
          var start = 0
          while start + chunk <= items.count {
            var candidate = items
            candidate.removeSubrange(start..<(start + chunk))
            if candidate.count >= count.lowerBound { candidates.append(candidate) }
            start += chunk
          }
          chunk /= 2
        }
        for (index, item) in items.enumerated() {
          for smaller in item.shrinks() {
            var candidate = items
            candidate[index] = smaller
            candidates.append(candidate)
          }
        }
        return candidates.map(shrinkable)
      }
    }
    return Gen { source in
      let length = source.int(in: count)
      var items: [Shrinkable<Element>] = []
      items.reserveCapacity(length)
      for _ in 0..<length { items.append(element.run(&source)) }
      return shrinkable(items)
    }
  }
}

extension Gen where Value == String {
  /// Strings assembled from `alphabet` pieces (grapheme clusters or longer).
  public static func string(from alphabet: [String], count: ClosedRange<Int>) -> Gen<String> {
    Gen<[String]>.array(of: .element(of: alphabet), count: count).map { $0.joined() }
  }
}

/// Grapheme clusters that have broken SwiftTUI seams before: combining marks,
/// ZWJ sequences, regional indicators, skin tones, Hangul jamo, wide CJK,
/// every newline convention, zero-width and bidi controls, soft hyphen, NUL,
/// ESC, DEL and the replacement character. Pair with `Gen.string(from:count:)`.
@_spi(Testing) public let hostileGraphemeAlphabet: [String] = [
  "a", "Z", "0", " ", "-", ".", "'",
  "e\u{0301}", "\u{0301}", "a\u{20DD}", "\u{00E9}",
  "\u{1F469}\u{1F3FD}\u{200D}\u{1F4BB}", "\u{1F1FA}\u{1F1F8}", "\u{1F600}", "\u{1F44D}\u{1F3FF}",
  "\u{1100}\u{1161}\u{11A8}", "\u{AC00}", "界", "宽", "ｗ",
  "\r", "\n", "\r\n", "\t", "\u{2028}", "\u{2029}", "\u{0085}",
  "\u{200B}", "\u{200D}", "\u{00AD}", "\u{200E}", "\u{200F}", "\u{2066}", "\u{2069}",
  "\u{FFFD}", "\u{0000}", "\u{001B}", "\u{007F}",
]

/// The first failing draw, shrunk as far as the budget allowed.
@_spi(Testing) public struct PropertyFailure<Value: Sendable>: Sendable, CustomStringConvertible {
  public let seed: UInt64
  public let iteration: Int
  public let original: Value
  public let minimal: Value
  public let shrinkSteps: Int
  public let message: String

  public var description: String {
    "seed=0x\(String(seed, radix: 16)) iteration=\(iteration) shrinkSteps=\(shrinkSteps)\n"
      + "minimal=\(String(reflecting: minimal))\noriginal=\(String(reflecting: original))\n\(message)"
  }
}

@_spi(Testing) public struct PropertyResult<Value: Sendable>: Sendable, CustomStringConvertible {
  public let passed: Int
  public let failure: PropertyFailure<Value>?

  public var isPassing: Bool { failure == nil }

  public var description: String {
    failure.map(\.description) ?? "passed \(passed) iterations"
  }
}

/// Default seed and iteration count. `SWIFTTUI_PROPERTY_SEED` (decimal or
/// `0x` hex) and `SWIFTTUI_PROPERTY_ITERATIONS` override them;
/// `SWIFTTUI_STRESS_FULL=1` raises the default count tenfold.
@_spi(Testing) public enum PropertyDefaults {
  public static let hotPathIterations = 100
  public static let fullIterations = 1_000

  public static var seed: UInt64 {
    guard let raw = ProcessInfo.processInfo.environment["SWIFTTUI_PROPERTY_SEED"], !raw.isEmpty
    else {
      return 0x5A17_7A11
    }
    if raw.hasPrefix("0x") || raw.hasPrefix("0X") {
      return UInt64(raw.dropFirst(2), radix: 16) ?? 0x5A17_7A11
    }
    return UInt64(raw) ?? 0x5A17_7A11
  }

  public static var iterations: Int {
    if let raw = ProcessInfo.processInfo.environment["SWIFTTUI_PROPERTY_ITERATIONS"],
      let value = Int(raw), value > 0
    {
      return value
    }
    return stressFullLaneRequested ? fullIterations : hotPathIterations
  }
}

/// Runs `body` over generated values. The body returns `nil` to accept a
/// value or a message to reject it; a thrown error also rejects. The first
/// rejection is shrunk greedily (depth first, most aggressive candidate
/// first) within `maxShrinkSteps` body calls. The result is returned, not
/// thrown, so the test asserts `result.isPassing` with `"\(result)"` as the
/// message and the seed travels with the failure.
@_spi(Testing) public func checkProperty<Value: Sendable>(
  _ gen: Gen<Value>,
  seed: UInt64? = nil,
  iterations: Int? = nil,
  maxShrinkSteps: Int = 500,
  _ body: (Value) throws -> String?
) -> PropertyResult<Value> {
  let seed = seed ?? PropertyDefaults.seed
  let iterations = iterations ?? PropertyDefaults.iterations
  var source = SeededRandomSource(seed: seed)

  func rejection(_ value: Value) -> String? {
    do {
      return try body(value)
    } catch {
      return "threw \(error)"
    }
  }

  for iteration in 0..<iterations {
    let candidate = gen.run(&source)
    guard let message = rejection(candidate.value) else { continue }
    var current = candidate
    var currentMessage = message
    var steps = 0
    var progressed = true
    while progressed, steps < maxShrinkSteps {
      progressed = false
      for smaller in current.shrinks() {
        steps += 1
        if let smallerMessage = rejection(smaller.value) {
          current = smaller
          currentMessage = smallerMessage
          progressed = true
          break
        }
        if steps >= maxShrinkSteps { break }
      }
    }
    return PropertyResult(
      passed: iteration,
      failure: PropertyFailure(
        seed: seed, iteration: iteration, original: candidate.value, minimal: current.value,
        shrinkSteps: steps, message: currentMessage))
  }
  return PropertyResult(passed: iterations, failure: nil)
}
