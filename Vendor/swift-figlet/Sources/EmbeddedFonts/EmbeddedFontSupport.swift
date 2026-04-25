import Foundation
public import SwiftFiglet

enum EmbeddedFontStorage {
  static func decode(_ encodedFontData: String, fontName: String) -> [UInt8] {
    guard let data = Data(base64Encoded: encodedFontData) else {
      preconditionFailure("Embedded font data for \(fontName) is not valid base64")
    }

    return Array(data)
  }
}

extension Figlet {
  public init(
    embeddedFont font: EmbeddedFigletFont = .standard,
    configuration: FigletConfiguration = FigletConfiguration()
  ) throws {
    try self.init(
      fontNamed: font.rawValue,
      configuration: configuration,
      fontLibrary: EmbeddedFigletFont.library
    )
  }
}
