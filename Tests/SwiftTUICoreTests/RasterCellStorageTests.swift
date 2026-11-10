import Foundation
import Testing

@testable import SwiftTUICore

// A raster surface holds one cell per column per row, and every phase from
// rasterization to host encoding copies and compares cells in bulk. The cell
// keeps its glyph and column counts inline and shares its style and hyperlink
// with the rest of its run. These tests pin the layout, the public value
// semantics that sharing must not change, and the sharing itself.

@Suite("Raster cell storage")
struct RasterCellStorageTests {
  @Test("a cell, a colour and a colour profile stay compact")
  func layoutsStayCompact() {
    #expect(MemoryLayout<RasterCell>.stride <= 32)
    #expect(MemoryLayout<Color>.stride <= 40)
    #expect(MemoryLayout<RGBColorProfile>.size <= MemoryLayout<UInt64>.size)
  }

  @Test("the public fields read back what was stored")
  func publicFieldsRoundTrip() {
    let style = ResolvedTextStyle(foregroundColor: .red, emphasis: [.bold])
    var cell = RasterCell(
      character: "界", spanWidth: 2, continuationLeadX: nil, style: style, hyperlink: "https://a")
    #expect(cell.character == "界")
    #expect(cell.spanWidth == 2)
    #expect(cell.continuationLeadX == nil)
    #expect(!cell.isContinuation)
    #expect(cell.style == style)
    #expect(cell.hyperlink == "https://a")

    // Each setter keeps the other field.
    cell.style = nil
    #expect(cell.style == nil)
    #expect(cell.hyperlink == "https://a")
    cell.style = style
    cell.hyperlink = nil
    #expect(cell.style == style)
    #expect(cell.hyperlink == nil)

    // Clearing both leaves the one spelling of "no attributes".
    cell.style = nil
    #expect(cell.attributes == nil)
    #expect(cell == RasterCell(character: "界", spanWidth: 2))

    // The default style is a style, distinct from no style.
    cell.style = ResolvedTextStyle()
    #expect(cell.style == ResolvedTextStyle())
    #expect(cell != RasterCell(character: "界", spanWidth: 2))
  }

  @Test("span width and continuation lead keep every valid column")
  func spanAndLeadStorage() {
    var cell = RasterCell(character: " ", spanWidth: 0, continuationLeadX: 0)
    #expect(cell.spanWidth == 0)
    #expect(cell.continuationLeadX == 0)
    #expect(cell.isContinuation)

    cell.continuationLeadX = 65_535
    #expect(cell.continuationLeadX == 65_535)
    cell.continuationLeadX = -3
    #expect(cell.continuationLeadX == -3)
    cell.continuationLeadX = nil
    #expect(cell.continuationLeadX == nil)
    #expect(!cell.isContinuation)

    // Values no surface can hold stay ordered and never read as `nil`.
    cell.spanWidth = .max
    #expect(cell.spanWidth == Int(Int32.max))
    cell.continuationLeadX = .min
    #expect(cell.continuationLeadX != nil)
    #expect(cell.isContinuation)
  }

  @Test("equality is by value whether or not attributes are shared")
  func equalityIsByValue() {
    let style = ResolvedTextStyle(backgroundColor: .blue)
    let shared = RasterCellAttributes.make(style: style, hyperlink: nil)
    let sharedA = RasterCell(character: "a", attributes: shared)
    let sharedB = RasterCell(character: "a", attributes: shared)
    let separate = RasterCell(character: "a", style: style)
    #expect(sharedA == sharedB)
    #expect(sharedA == separate)
    #expect(sharedA != RasterCell(character: "b", attributes: shared))
    #expect(sharedA != RasterCell(character: "a", style: ResolvedTextStyle(backgroundColor: .red)))
    #expect(sharedA != RasterCell(character: "a"))
    #expect(sharedA != RasterCell(character: "a", style: style, hyperlink: "https://a"))
    #expect(RasterCell() == .empty)
    #expect(RasterCell.empty.isEmpty)
    #expect(!sharedA.isEmpty)
    #expect(!RasterCell(character: " ", spanWidth: 0, continuationLeadX: 0).isEmpty)
    #expect(RasterCellAttributes.make(style: nil, hyperlink: nil) == nil)
  }

  @Test("the run comparator agrees with cell equality")
  func comparatorAgreesWithEquality() {
    let blue = ResolvedTextStyle(backgroundColor: .blue)
    let red = ResolvedTextStyle(backgroundColor: .red)
    let shared = RasterCellAttributes.make(style: blue, hyperlink: nil)
    let cells: [RasterCell] = [
      .empty,
      RasterCell(character: "a"),
      RasterCell(character: "a", attributes: shared),
      RasterCell(character: "a", attributes: shared),
      RasterCell(character: "a", style: blue),
      RasterCell(character: "b", style: blue),
      RasterCell(character: "a", style: red),
      RasterCell(character: "a", style: blue, hyperlink: "https://a"),
      RasterCell(character: "界", spanWidth: 2, style: blue),
      RasterCell(character: " ", spanWidth: 0, continuationLeadX: 3, style: blue),
      RasterCell(character: " ", spanWidth: 0, continuationLeadX: 4, style: blue),
    ]
    // One comparator across every pair, so remembered answers from earlier
    // pairs are exercised against later ones.
    var comparator = RasterCellRunComparator()
    for lhs in cells {
      for rhs in cells {
        #expect(comparator.areEqual(lhs, rhs) == (lhs == rhs))
        #expect(comparator.areEqual(lhs, rhs) == (lhs == rhs))
      }
    }
  }

  @Test("reflection names the public fields")
  func reflectionNamesPublicFields() {
    let cell = RasterCell(character: "a", style: ResolvedTextStyle(emphasis: [.bold]))
    let labels = Mirror(reflecting: cell).children.map(\.label)
    #expect(labels == ["character", "spanWidth", "continuationLeadX", "style", "hyperlink"])
  }

  @Test("rows share storage only when they are the same buffer")
  func rowsShareStorage() {
    let row = Array(repeating: RasterCell.empty, count: 4)
    var copy = row
    #expect(RasterCell.rowsShareStorage(row, copy))
    copy[0] = RasterCell(character: "x")
    #expect(!RasterCell.rowsShareStorage(row, copy))
    copy[0] = .empty
    // Equal cells in a different buffer are not shared storage.
    #expect(row == copy)
    #expect(!RasterCell.rowsShareStorage(row, copy))
    #expect(RasterCell.rowsShareStorage([], []))
    #expect(!RasterCell.rowsShareStorage(row, Array(row.prefix(3))))
  }

  @Test("a text run shares one attributes object per underlay")
  func textRunSharesAttributes() {
    let size = CellSize(width: 8, height: 1)
    let bounds = CellRect(origin: .zero, size: size)
    let leftHalf = CellRect(origin: .zero, size: CellSize(width: 4, height: 1))
    let draw = DrawNode(
      identity: testIdentity("run"),
      bounds: bounds,
      commands: [
        .fill(
          bounds: leftHalf, geometry: .rectangle, insetAmount: 0, style: .color(.blue),
          mode: .full),
        .text(
          bounds: bounds,
          content: "abcdefgh",
          style: TextStyle(foregroundStyle: .color(.red)),
          lineLimit: nil,
          truncationMode: .tail,
          wrappingStrategy: .wordBoundary
        ),
      ]
    )
    let row = Rasterizer().rasterize(draw, minimumSize: size).cells[0]

    #expect(String(row.map(\.character)) == "abcdefgh")
    for cell in row[..<4] {
      #expect(cell.style?.foregroundColor == .red)
      #expect(cell.style?.backgroundColor == .blue)
      #expect(cell.attributes === row[0].attributes)
    }
    for cell in row[4...] {
      #expect(cell.style?.foregroundColor == .red)
      #expect(cell.style?.backgroundColor == nil)
      #expect(cell.attributes === row[4].attributes)
    }
    #expect(row[0].attributes !== row[4].attributes)
  }

  @Test("a sampled text paint still resolves every cell")
  func sampledTextResolvesPerCell() {
    let size = CellSize(width: 6, height: 1)
    let bounds = CellRect(origin: .zero, size: size)
    let gradient = LinearGradient(
      gradient: Gradient(colors: [.red, .blue]), startPoint: .leading, endPoint: .trailing)
    let draw = DrawNode(
      identity: testIdentity("gradient"),
      bounds: bounds,
      commands: [
        .text(
          bounds: bounds,
          content: "abcdef",
          style: TextStyle(foregroundStyle: .linearGradient(gradient)),
          lineLimit: nil,
          truncationMode: .tail,
          wrappingStrategy: .wordBoundary
        )
      ]
    )
    let row = Rasterizer().rasterize(draw, minimumSize: size).cells[0]
    let foregrounds = row.map { $0.style?.foregroundColor }
    #expect(foregrounds.allSatisfy { $0 != nil })
    #expect(foregrounds.first != foregrounds.last)
    #expect(Set(foregrounds.compactMap { $0 }).count > 2)
  }
}

@Suite("RGB colour profile storage")
struct RGBColorProfileStorageTests {
  private static let builtIns: [RGBColorProfile] = [
    .sRGB, .displayP3, .adobeRGB, .rec2020, .proPhotoRGB, .acescg, .linearSRGB, .linearDisplayP3,
  ]

  @Test("a definition equal to a built-in profile is that built-in")
  func builtInDefinitionMapsToBuiltIn() {
    for builtIn in Self.builtIns {
      let rebuilt = RGBColorProfile(
        name: "  \(builtIn.name) ",
        primaries: builtIn.primaries,
        whitePoint: builtIn.whitePoint,
        transferFunction: builtIn.transferFunction
      )
      #expect(rebuilt == builtIn)
      #expect(rebuilt.hashValue == builtIn.hashValue)
      #expect(rebuilt.name == builtIn.name)
      #expect(rebuilt.rgbToXYZMatrix == builtIn.rgbToXYZMatrix)
      #expect(rebuilt.xyzToRGBMatrix == builtIn.xyzToRGBMatrix)
    }
    // Every built-in is distinct from every other.
    for (index, lhs) in Self.builtIns.enumerated() {
      for rhs in Self.builtIns[(index + 1)...] {
        #expect(lhs != rhs)
      }
    }
  }

  @Test("a caller-defined profile compares by its definition")
  func customProfilesCompareByDefinition() {
    func custom(_ name: String, gamma: Double = 2.4) -> RGBColorProfile {
      RGBColorProfile(
        name: name,
        primaries: RGBColorProfile.sRGB.primaries,
        whitePoint: .d65,
        transferFunction: .gamma(gamma)
      )
    }
    let first = custom("Mine")
    let second = custom("Mine")
    #expect(first == second)
    #expect(first.hashValue == second.hashValue)
    #expect(first == first)
    #expect(first != custom("Yours"))
    #expect(first != custom("Mine", gamma: 2.2))
    #expect(first != .sRGB)
    #expect(RGBColorProfile.sRGB != first)
    #expect(first.name == "Mine")
    #expect(first.transferFunction == .gamma(2.4))
    #expect(first.xyzToRGBMatrix == first.rgbToXYZMatrix.inverse)
    // Same name as a built-in, different definition: not that built-in.
    let impostor = custom("sRGB")
    #expect(impostor != .sRGB)
    #expect(impostor.name == "sRGB")
  }

  @Test("the cached inverse matrices equal the computed inverses")
  func inverseMatricesMatch() {
    for profile in Self.builtIns {
      #expect(profile.xyzToRGBMatrix == profile.rgbToXYZMatrix.inverse)
    }
  }

  @Test("encoding keeps the four definition fields")
  func codableRoundTrip() throws {
    let custom = RGBColorProfile(
      name: "Mine",
      primaries: RGBColorProfile.displayP3.primaries,
      whitePoint: .d50,
      transferFunction: .gamma(1.8)
    )
    for profile in Self.builtIns + [custom] {
      let data = try JSONEncoder().encode(profile)
      let object = try #require(
        try JSONSerialization.jsonObject(with: data) as? [String: Any])
      #expect(Set(object.keys) == ["name", "primaries", "whitePoint", "transferFunction"])
      #expect(object["name"] as? String == profile.name)
      #expect(try JSONDecoder().decode(RGBColorProfile.self, from: data) == profile)
    }
    let color = Color(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.5, profile: custom)
    let decoded = try JSONDecoder().decode(
      Color.self, from: try JSONEncoder().encode(color))
    #expect(decoded == color)
  }

  @Test("reflection names the definition, not the storage")
  func reflectionNamesDefinition() {
    let labels = Mirror(reflecting: RGBColorProfile.sRGB).children.map(\.label)
    #expect(labels == ["name", "primaries", "whitePoint", "transferFunction"])
    let description = String(reflecting: RGBColorProfile.displayP3)
    #expect(description.hasPrefix("SwiftTUIPrimitives.RGBColorProfile(name: \"Display P3\", "))
    #expect(description.contains("transferFunction: SwiftTUIPrimitives.TransferFunction.sRGB"))
  }
}
