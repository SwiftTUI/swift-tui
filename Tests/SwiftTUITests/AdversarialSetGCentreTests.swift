@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

private typealias SetGGuide = (value: Int, isHalfCell: Bool, length: Int)

/// Guides from consecutive draws: value -6...12, a half-cell flag and a
/// length 0...12.
private func setGGuides(_ n: [Int], count: Int) -> [SetGGuide] {
  (0..<count).map { index in
    let raw = n[index]
    return (value: raw % 19 - 6, isHalfCell: raw / 19 % 2 == 1, length: raw / 38 % 13)
  }
}

private enum SetGCentreH: AlignmentID {
  static func defaultValue(in context: ViewDimensions) -> Int {
    context[HorizontalAlignment.center]
  }
}

private enum SetGCentreV: AlignmentID {
  static func defaultValue(in context: ViewDimensions) -> Int {
    context[VerticalAlignment.center]
  }
}

@MainActor
private func setGLines(_ view: some View, width: Int = 40, height: Int = 8) -> [String] {
  DefaultRenderer().render(view, proposal: .init(width: width, height: height)).rasterSurface.lines
}

private func setGBlock(_ character: Character, width: Int, height: Int) -> String {
  Array(repeating: String(repeating: character, count: width), count: height).joined(
    separator: "\n")
}

@MainActor
@Suite("Campaign F5 pass 2 centre-rounding properties", .serialized)
struct AdversarialSetGCentreTests {
  @Test(arguments: Array(118...125))
  func centre(id: Int) {
    switch id {
    case 118: mergeIsUnion(id)
    case 119: emptyLineIsIdentity(id)
    case 120: lazyMatchesEagerWithNegativeGuides(id)
    case 121: offsetsRoundTowardLeading(id)
    case 122: extentIsUnion(id)
    case 123: stackMeasuresUnion(id)
    case 124: defaultCentresUseCentredOffset(id)
    default: centreDerivedGuidesPlaceAlike(id)
    }
  }

  private func mergeIsUnion(_ id: Int) {
    setGProperty(id, setGDraws(12)) { n in
      let first = setGGuides(Array(n[2..<7]), count: n[0] % 5 + 1)
      let second = setGGuides(Array(n[7..<12]), count: n[1] % 5 + 1)
      let union = AlignmentLine(guides: first + second)
      let merged = AlignmentLine(guides: first).merged(with: AlignmentLine(guides: second))
      return union == merged ? nil : "union \(union), merged \(merged)"
    }
  }

  private func emptyLineIsIdentity(_ id: Int) {
    setGProperty(id, setGDraws(7)) { n in
      let base = setGGuides(Array(n[2..<7]), count: n[0] % 5 + 1)
      let run: [SetGGuide] = base.map { guide in
        switch n[1] % 3 {
        case 0:
          (value: -1 - Int(guide.value.magnitude % 6), isHalfCell: guide.isHalfCell, guide.length)
        case 1:
          (
            value: guide.length + 1 + Int(guide.value.magnitude % 6), isHalfCell: false,
            guide.length
          )
        default: guide
        }
      }
      let line = AlignmentLine(guides: run)
      let seeded = AlignmentLine(guides: []).merged(with: line)
      return seeded == line ? nil : "seed merged with \(line) gives \(seeded)"
    }
  }

  private func lazyMatchesEagerWithNegativeGuides(_ id: Int) {
    setGProperty(id, setGDraws(5)) { n in
      let guides = [-1 - n[1] % 5, -1 - n[2] % 5, -1 - n[3] % 5]
      let overshoot = n[0] % 2 == 1
      let count = 30 + n[4] % 10
      func guide(_ index: Int) -> @Sendable (ViewDimensions) -> Int {
        let shift = -guides[index % 3]
        if overshoot { return { dimensions in dimensions.width + shift } }
        return { _ in -shift }
      }
      // Every label is six cells wide, as "header" is, so any three measured
      // rows carry every guide value and the measured line is the eager line.
      // A wider unmeasured row ("row 10" beside "row 9") with a larger
      // past-the-width guide may move the line once measured
      // (Divergences-And-Gaps.md:398-404); that is not this property.
      func label(_ index: Int) -> String { index < 10 ? "row 0\(index)" : "row \(index)" }
      let lazy = setGLines(
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            Text("header").alignmentGuide(.leading, computeValue: guide(0))
            ForEach(0..<count, id: \.self) { index in
              Text(label(index)).alignmentGuide(.leading, computeValue: guide(index))
            }
          }
        }, width: 30, height: 8)
      let eager = setGLines(
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            Text("header").alignmentGuide(.leading, computeValue: guide(0))
            ForEach(0..<count, id: \.self) { index in
              Text(label(index)).alignmentGuide(.leading, computeValue: guide(index))
            }
          }
        }, width: 30, height: 8)
      return lazy == eager ? nil : "lazy \(lazy) != eager \(eager)"
    }
  }

  private func offsetsRoundTowardLeading(_ id: Int) {
    setGProperty(id, setGDraws(7)) { n in
      let guides = setGGuides(Array(n[1..<7]), count: n[0] % 6 + 1)
      let line = AlignmentLine(guides: guides)
      var offsets: [Int] = []
      for guide in guides {
        let offset = line.offset(guideValue: guide.value, isHalfCell: guide.isHalfCell)
        let gap =
          2 * line.leading + (line.isHalfCell ? 1 : 0) - 2 * (offset + guide.value)
          - (guide.isHalfCell ? 1 : 0)
        if offset < 0 || !(0...1).contains(gap) {
          return "guide \(guide) placed at \(offset) on \(line)"
        }
        offsets.append(offset)
      }
      return offsets.min() == 0 ? nil : "no child at the leading edge: \(offsets)"
    }
  }

  private func extentIsUnion(_ id: Int) {
    setGProperty(id, setGDraws(7)) { n in
      let guides: [SetGGuide] = setGGuides(Array(n[1..<7]), count: n[0] % 6 + 1).map {
        let value = $0.value.magnitude % 9
        return (Int(value), $0.isHalfCell, Int(value) + $0.length % 6 + ($0.isHalfCell ? 1 : 0))
      }
      let line = AlignmentLine(guides: guides)
      let union =
        guides.map {
          line.offset(guideValue: $0.value, isHalfCell: $0.isHalfCell) + $0.length
        }.max() ?? 0
      return line.extent == union ? nil : "guides \(guides): extent \(line.extent), union \(union)"
    }
  }

  private func stackMeasuresUnion(_ id: Int) {
    setGProperty(id, setGDraws(3)) { n in
      let top = n[0] % 9 + 1
      let bottom = n[1] % 9 + 1
      let guide = n[2] % 11
      let lines = setGLines(
        HStack(spacing: 0) {
          VStack(alignment: .center, spacing: 0) {
            Text(String(repeating: "a", count: top))
            Text(String(repeating: "b", count: bottom))
              .alignmentGuide(HorizontalAlignment.center) { _ in guide }
          }
          Text("|")
        })
      var rightmost = -1
      var bar: Int?
      for line in lines {
        for (column, character) in line.enumerated() {
          if character == "a" || character == "b" { rightmost = max(rightmost, column) }
          if character == "|" { bar = column }
        }
      }
      guard let bar else { return "no bar in \(lines)" }
      return bar == rightmost + 1
        ? nil : "a\(top) b\(bottom) guide \(guide): bar at \(bar), children end at \(rightmost)"
    }
  }

  private func defaultCentresUseCentredOffset(_ id: Int) {
    setGProperty(id, setGDraws(7)) { n in
      let lengths = (0..<(n[0] % 6 + 1)).map { n[1 + $0] % 16 }
      let line = AlignmentLine(
        guides: lengths.map { (value: $0 / 2, isHalfCell: $0 % 2 != 0, length: $0) })
      for length in lengths {
        let offset = line.offset(guideValue: length / 2, isHalfCell: length % 2 != 0)
        let expected = LayoutEngine.centredOffset(length: length, in: line.extent)
        if offset != expected {
          return "length \(length) in \(line.extent): offset \(offset), centred \(expected)"
        }
      }
      return nil
    }
  }

  private func centreDerivedGuidesPlaceAlike(_ id: Int) {
    setGProperty(id, setGDraws(7)) { n in
      let widths = [n[1] % 9 + 1, n[2] % 9 + 1, n[3] % 9 + 1]
      let heights = [n[4] % 3 + 1, n[5] % 3 + 1, n[6] % 3 + 1]
      let characters: [Character] = ["a", "b", "c"]
      let kind = n[0] % 5
      let custom = Alignment(
        horizontal: HorizontalAlignment(SetGCentreH.self),
        vertical: VerticalAlignment(SetGCentreV.self))
      @MainActor func guided(_ index: Int) -> some View {
        Text(setGBlock(characters[index], width: widths[index], height: heights[index]))
          .alignmentGuide(HorizontalAlignment.center) { $0[HorizontalAlignment.center] }
          .alignmentGuide(VerticalAlignment.center) { $0[VerticalAlignment.center] }
      }
      @MainActor func plain(_ index: Int) -> some View {
        Text(setGBlock(characters[index], width: widths[index], height: heights[index]))
      }
      let builtIn: [String]
      let identity: [String]
      let derived: [String]
      switch kind {
      case 0:
        builtIn = setGLines(
          VStack(alignment: .center, spacing: 0) {
            plain(0)
            plain(1)
            plain(2)
          })
        identity = setGLines(
          VStack(alignment: .center, spacing: 0) {
            guided(0)
            guided(1)
            guided(2)
          })
        derived = setGLines(
          VStack(alignment: custom.horizontal, spacing: 0) {
            plain(0)
            plain(1)
            plain(2)
          })
      case 1:
        builtIn = setGLines(
          HStack(alignment: .center, spacing: 0) {
            plain(0)
            plain(1)
            plain(2)
          })
        identity = setGLines(
          HStack(alignment: .center, spacing: 0) {
            guided(0)
            guided(1)
            guided(2)
          })
        derived = setGLines(
          HStack(alignment: custom.vertical, spacing: 0) {
            plain(0)
            plain(1)
            plain(2)
          })
      case 2:
        builtIn = setGLines(
          ZStack(alignment: .center) {
            plain(0)
            plain(1)
            plain(2)
          })
        identity = setGLines(
          ZStack(alignment: .center) {
            guided(0)
            guided(1)
            guided(2)
          })
        derived = setGLines(
          ZStack(alignment: custom) {
            plain(0)
            plain(1)
            plain(2)
          })
      case 3:
        let frame = (width: widths[1] + widths[2], height: heights[1] + heights[2] + 1)
        builtIn = setGLines(plain(0).frame(width: frame.width, height: frame.height))
        identity = setGLines(guided(0).frame(width: frame.width, height: frame.height))
        derived = setGLines(
          plain(0).frame(width: frame.width, height: frame.height, alignment: custom))
      default:
        builtIn = setGLines(plain(0).overlay(alignment: .center) { plain(1) })
        identity = setGLines(plain(0).overlay(alignment: .center) { guided(1) })
        derived = setGLines(plain(0).overlay(alignment: custom) { plain(1) })
      }
      if identity != builtIn { return "identity guide \(identity) != built-in \(builtIn)" }
      return derived == builtIn ? nil : "custom centre \(derived) != built-in \(builtIn)"
    }
  }
}
