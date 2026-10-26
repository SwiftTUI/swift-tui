@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIPrimitives
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

private let setGEdgeIntegers: [Int] = [
  0, 1, -1, 1 << 24, -(1 << 24), Int.max / 2, Int.min / 2, Int.max, Int.min, Int.max - 1,
  Int.min + 1,
]

/// An edge value or a uniformly drawn `Int`.
private let setGAnyInt: Gen<Int> = Gen<Int>.int(in: 0...1).flatMap { edge in
  edge == 0
    ? Gen<Int>.element(of: setGEdgeIntegers)
    : Gen<Int>.int(in: Int.min...Int.max)
}

private func setGClamp(_ value: Int128) -> Int {
  Int(min(max(value, Int128(Int.min)), Int128(Int.max)))
}

private let setGRules: [FloatingPointRoundingRule] = [
  .down, .up, .towardZero, .awayFromZero, .toNearestOrEven, .toNearestOrAwayFromZero,
]

@MainActor
@Suite("Campaign F5 pass 2 saturation properties", .serialized)
struct AdversarialSetGSaturationTests {
  @Test(arguments: Array(137...142))
  func saturation(id: Int) {
    switch id {
    case 137: saturatingAddition(id)
    case 138: saturatingConversion(id)
    case 139: scrollOffsets(id)
    case 140: steppedValues(id)
    case 141: wheelCoalescing(id)
    default: cellFraction(id)
    }
  }

  private func saturatingAddition(_ id: Int) {
    setGProperty(id, Gen<(Int, Int)>.zip(setGAnyInt, setGAnyInt)) { pair in
      let (lhs, rhs) = pair
      let actual = SaturatingConversion.adding(lhs, rhs)
      let expected = setGClamp(Int128(lhs) + Int128(rhs))
      return actual == expected ? nil : "\(lhs) + \(rhs) = \(actual), expected \(expected)"
    }
  }

  private func saturatingConversion(_ id: Int) {
    let values = Gen<Double>.doubleWithSpecials(ordinary: -1e20...1e20)
    let generator = Gen<(Double, (Double, Int))>.zip(
      values, Gen<(Double, Int)>.zip(values, .int(in: 0...5)))
    setGProperty(id, generator) { draw in
      let (first, (second, ruleIndex)) = draw
      let rule = setGRules[ruleIndex]
      func expected(_ value: Double) -> Int {
        let lower = Int128(SaturatingConversion.lowerBound)
        let upper = Int128(SaturatingConversion.upperBound)
        guard !value.isNaN else { return SaturatingConversion.lowerBound }
        let rounded = value.rounded(rule)
        let exact: Int128 =
          rounded.magnitude < 0x1p120
          ? Int128(rounded) : (rounded < 0 ? Int128.min : Int128.max)
        return Int(min(max(exact, lower), upper))
      }
      for value in [first, second, first * 0x1p42, second * 0x1p43] {
        let actual = SaturatingConversion.int(value, rounding: rule)
        if actual != expected(value) {
          return "int(\(value), \(rule)) = \(actual), expected \(expected(value))"
        }
      }
      if !first.isNaN, !second.isNaN {
        let (low, high) = first <= second ? (first, second) : (second, first)
        if SaturatingConversion.int(low, rounding: rule)
          > SaturatingConversion.int(high, rounding: rule)
        {
          return "not monotone between \(low) and \(high)"
        }
      }
      return nil
    }
  }

  private func scrollOffsets(_ id: Int) {
    let generator = Gen<[Int]>.array(of: setGAnyInt, count: 4...4)
    setGProperty(id, generator) { n in
      let offset = ScrollCellOffset(x: n[0], y: n[1])
      let moved = offset.scrolledBy(x: n[2], y: n[3])
      let expected = ScrollCellOffset(
        x: setGClamp(Int128(n[0]) + Int128(n[2])), y: setGClamp(Int128(n[1]) + Int128(n[3])))
      guard moved == expected else { return "scrolled to \(moved), expected \(expected)" }
      let unsaturated =
        Int128(moved.x) == Int128(n[0]) + Int128(n[2])
        && Int128(moved.y) == Int128(n[1]) + Int128(n[3])
      guard unsaturated, n[2] != Int.min, n[3] != Int.min else { return nil }
      var back = moved
      back.scrollBy(x: -n[2], y: -n[3])
      return back == offset ? nil : "scrolling back reached \(back), not \(offset)"
    }
  }

  private func steppedValues(_ id: Int) {
    let generator = Gen<([Int], [Int])>.zip(
      Gen<[Int]>.array(of: setGAnyInt, count: 5...5), setGDraws(1))
    setGProperty(id, generator) { draw in
      let (n, mode) = draw
      let value = n[0]
      let delta = n[1]
      let step = n[2]
      let bounds: ClosedRange<Int>? =
        mode[0] % 3 == 0 ? nil : min(n[3], n[4])...max(n[3], n[4])
      let sanitized = Int128(max(1, Int(clamping: step.magnitude)))
      var expected = setGClamp(Int128(value) + Int128(delta) * sanitized)
      if let bounds { expected = min(max(expected, bounds.lowerBound), bounds.upperBound) }
      let actual = Int.steppedControlValue(from: value, delta: delta, step: step, bounds: bounds)
      return actual == expected
        ? nil
        : "step \(value) by \(delta) x \(step) within \(String(describing: bounds)): \(actual), expected \(expected)"
    }
  }

  private func wheelCoalescing(_ id: Int) {
    setGProperty(id, setGDraws(13, 0...Int(UInt32.max))) { n in
      let count = n[0] % 13
      var events: [InputEvent] = []
      var expected: [(kind: String, cell: Int, modifiers: UInt8, deltaX: Int, deltaY: Int)] = []
      for index in 0..<count {
        let raw = n[1 + index]
        if raw % 5 == 0 {
          events.append(.key(.arrowUp))
          expected.append(("key", 0, 0, 0, 0))
          continue
        }
        let cell = raw / 5 % 2
        let modifiers: EventModifiers = raw / 10 % 2 == 0 ? [] : .shift
        let span = 1 << 24
        let deltaX = raw / 20 % 3 == 0 ? (raw / 60) % (2 * span + 1) - span : 0
        let deltaY = (raw / 7) % (2 * span + 1) - span
        events.append(
          .mouse(
            MouseEvent(
              kind: .scrolled(deltaX: deltaX, deltaY: deltaY),
              location: .cellFallback(CellPoint(x: cell, y: 0)), modifiers: modifiers)))
        if let last = expected.last, last.kind == "wheel", last.cell == cell,
          last.modifiers == modifiers.rawValue
        {
          expected[expected.count - 1].deltaX += deltaX
          expected[expected.count - 1].deltaY += deltaY
        } else {
          expected.append(("wheel", cell, modifiers.rawValue, deltaX, deltaY))
        }
      }
      let coalesced = coalescedInputEvents(events)
      guard coalesced.count == expected.count else {
        return "\(coalesced.count) events after coalescing, expected \(expected.count)"
      }
      for (event, model) in zip(coalesced, expected) {
        switch event {
        case .key:
          if model.kind != "key" { return "a key replaced a wheel run" }
        case .mouse(let mouse):
          guard case .scrolled(let deltaX, let deltaY) = mouse.kind, model.kind == "wheel",
            mouse.location.cell.x == model.cell, mouse.modifiers.rawValue == model.modifiers,
            deltaX == model.deltaX, deltaY == model.deltaY
          else { return "wheel run \(model) coalesced to \(mouse.kind) at \(mouse.location.cell)" }
        default:
          return "unexpected event \(event)"
        }
      }
      return nil
    }
  }

  private func cellFraction(_ id: Int) {
    let generator = Gen<(Int, Int)>.zip(.int(in: 0...2), .int(in: 0...2_000_000))
    setGProperty(id, generator) { draw in
      let (mode, raw) = draw
      let value: Double
      switch mode {
      case 0:
        value = -Double(sign: .plus, exponent: -(raw % 1074 + 1), significand: 1)
      case 1:
        value = Double(raw - 1_000_000) / 997
      default:
        value = Double(sign: raw % 2 == 0 ? .plus : .minus, exponent: raw % 60, significand: 1.25)
      }
      let point = Point(x: value, y: -value)
      for (coordinate, fraction, cell) in [
        (point.x, point.fractionInCell.x, point.containingCell.x),
        (point.y, point.fractionInCell.y, point.containingCell.y),
      ] {
        guard fraction >= 0, fraction < 1 else {
          return "fractionInCell of \(coordinate) is \(fraction)"
        }
        if coordinate.magnitude < 0x1p52, Double(cell) + fraction != coordinate {
          return "cell \(cell) + fraction \(fraction) != \(coordinate)"
        }
      }
      return nil
    }
  }
}
