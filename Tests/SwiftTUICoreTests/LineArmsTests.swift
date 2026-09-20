import Testing

@testable import SwiftTUICore

@Suite
struct LineArmsTests {
  @Test("every Unicode box-drawing line glyph is reachable from its arms")
  func tableMatchesUnicodeNames() throws {
    var checked = 0
    for value in UInt32(0x2500)...UInt32(0x257F) {
      let scalar = try #require(Unicode.Scalar(value))
      let name = try #require(scalar.properties.name)
      guard let arms = Self.arms(fromUnicodeName: name) else {
        continue
      }
      #expect(arms.glyph() == Character(scalar), "\(name)")
      checked += 1
    }
    // 128 code points, less 12 dashed, 3 diagonal and 4 arc glyphs.
    #expect(checked == 109)
  }

  @Test("hand-checked glyphs pin the table independently of the name parser")
  func spotChecks() {
    #expect(LineArms(east: .light, south: .light).glyph() == "┌")
    #expect(LineArms(north: .light, west: .light).glyph() == "┘")
    #expect(LineArms(north: .light, east: .light, south: .light).glyph() == "├")
    #expect(
      LineArms(north: .light, east: .light, south: .light, west: .light).glyph() == "┼")
    #expect(LineArms(east: .heavy, west: .heavy).glyph() == "━")
    #expect(LineArms(east: .double, south: .double).glyph() == "╔")
    #expect(LineArms(east: .light, south: .double).glyph() == "╓")
    #expect(
      LineArms(north: .light, east: .double, south: .light, west: .double).glyph() == "╪")
    #expect(LineArms(north: .light, east: .heavy, south: .light, west: .heavy).glyph() == "┿")
    #expect(LineArms.none.glyph() == " ")
  }

  @Test("a single arm is a half-line, which is how a dash or trim end draws")
  func halfLines() {
    #expect(LineArms(west: .light).glyph() == "╴")
    #expect(LineArms(north: .light).glyph() == "╵")
    #expect(LineArms(east: .light).glyph() == "╶")
    #expect(LineArms(south: .light).glyph() == "╷")
    #expect(LineArms(west: .heavy).glyph() == "╸")
    #expect(LineArms(south: .heavy).glyph() == "╻")
  }

  @Test("Unicode has no glyph for some arm sets")
  func missingGlyphs() {
    // Double has no half-line.
    #expect(LineArms(west: .double).glyph() == nil)
    // Heavy and double never mix.
    #expect(LineArms(east: .heavy, south: .double).glyph() == nil)
    // Light and double mix only when each axis has one weight.
    #expect(LineArms(north: .light, south: .double).glyph() == nil)
  }

  @Test("arcs exist only for a corner of two light arms")
  func roundedCorners() {
    #expect(LineArms(east: .light, south: .light).glyph(roundedCorner: true) == "╭")
    #expect(LineArms(south: .light, west: .light).glyph(roundedCorner: true) == "╮")
    #expect(LineArms(north: .light, west: .light).glyph(roundedCorner: true) == "╯")
    #expect(LineArms(north: .light, east: .light).glyph(roundedCorner: true) == "╰")
    // No heavy arc, no arc for a straight line, no arc for a junction.
    #expect(LineArms(east: .heavy, south: .heavy).glyph(roundedCorner: true) == "┏")
    #expect(LineArms(east: .light, west: .light).glyph(roundedCorner: true) == "─")
    #expect(
      LineArms(north: .light, east: .light, south: .light).glyph(roundedCorner: true) == "├")
  }

  @Test("reweighting keeps the shape and changes the weight")
  func reweighting() {
    let mixed = LineArms(east: .heavy, south: .double)
    #expect(mixed.glyph() == nil)
    #expect(mixed.reweighted(to: .light).glyph() == "┌")
    #expect(mixed.reweighted(to: .double).glyph() == "╔")
  }

  /// Parses names such as `BOX DRAWINGS DOWN LIGHT AND RIGHT HEAVY`. A part
  /// that names no weight inherits the previous part's, as in
  /// `BOX DRAWINGS LIGHT DOWN AND RIGHT`.
  private static func arms(fromUnicodeName name: String) -> LineArms? {
    guard name.hasPrefix("BOX DRAWINGS ") else {
      return nil
    }
    if name.contains("DASH") || name.contains("DIAGONAL") || name.contains("ARC") {
      return nil
    }
    var arms = LineArms()
    var carried: LineWeight?
    let body = name.dropFirst("BOX DRAWINGS ".count)
    for part in body.split(separator: " AND ", omittingEmptySubsequences: true) {
      let tokens = part.split(separator: " ").map(String.init)
      let weight = tokens.lazy.compactMap(Self.weight(named:)).first ?? carried
      guard let weight else {
        return nil
      }
      carried = weight
      for token in tokens {
        switch token {
        case "UP": arms.north = weight
        case "RIGHT": arms.east = weight
        case "DOWN": arms.south = weight
        case "LEFT": arms.west = weight
        case "HORIZONTAL":
          arms.east = weight
          arms.west = weight
        case "VERTICAL":
          arms.north = weight
          arms.south = weight
        default: break
        }
      }
    }
    return arms
  }

  private static func weight(named token: String) -> LineWeight? {
    switch token {
    case "LIGHT", "SINGLE": .light
    case "HEAVY": .heavy
    case "DOUBLE": .double
    default: nil
    }
  }
}
