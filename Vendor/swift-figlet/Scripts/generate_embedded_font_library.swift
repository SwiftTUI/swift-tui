#!/usr/bin/env swift
import Foundation

struct FontEntry {
  let fontName: String
  let caseName: String
  let fileURL: URL
}

let supportedExtensions = ["flf", "tlf", "tdf"]
let bundledFontNames = [
  "standard",
  "slant",
  "small",
  "doom",
  "ansi-shadow",
  "calvin-sm",
  "208",
  "pagga",
  "bloodyx",
  "cnerip",
  "3d",
  "sm-block",
]
let swiftKeywords = [
  "actor",
  "as",
  "associatedtype",
  "await",
  "break",
  "case",
  "catch",
  "class",
  "continue",
  "default",
  "defer",
  "deinit",
  "do",
  "else",
  "enum",
  "extension",
  "false",
  "fileprivate",
  "for",
  "func",
  "guard",
  "if",
  "import",
  "in",
  "init",
  "inout",
  "internal",
  "is",
  "let",
  "nil",
  "operator",
  "private",
  "protocol",
  "public",
  "repeat",
  "rethrows",
  "return",
  "self",
  "Self",
  "some",
  "static",
  "struct",
  "subscript",
  "super",
  "switch",
  "throw",
  "throws",
  "true",
  "try",
  "typealias",
  "var",
  "where",
  "while",
]

func resolvedFileURL(_ path: String, relativeTo repositoryRoot: URL) -> URL {
  if NSString(string: path).isAbsolutePath {
    return URL(fileURLWithPath: path)
  }

  return repositoryRoot.appending(path: path)
}

func identifierTokens(for value: String) -> [String] {
  var tokens: [String] = []
  var current = ""
  var previousWasDigit: Bool?

  func flushCurrent() {
    guard !current.isEmpty else {
      return
    }
    tokens.append(current)
    current = ""
  }

  for scalar in value.unicodeScalars {
    guard CharacterSet.alphanumerics.contains(scalar) else {
      flushCurrent()
      previousWasDigit = nil
      continue
    }

    let isDigit = CharacterSet.decimalDigits.contains(scalar)
    if let previousWasDigit, previousWasDigit != isDigit {
      flushCurrent()
    }

    current.unicodeScalars.append(scalar)
    previousWasDigit = isDigit
  }

  flushCurrent()
  return tokens
}

func normalizeIdentifierToken(_ token: String, uppercaseFirst: Bool) -> String {
  guard !token.isEmpty else {
    return token
  }

  if token.allSatisfy(\.isNumber) {
    return token
  }

  let lowercased = token.lowercased()
  guard uppercaseFirst else {
    return lowercased
  }

  return lowercased.prefix(1).uppercased() + lowercased.dropFirst()
}

func swiftCaseName(for fontName: String) -> String {
  let tokens = identifierTokens(for: fontName)
  guard !tokens.isEmpty else {
    return "font"
  }

  let baseName: String
  if tokens[0].allSatisfy(\.isNumber) {
    baseName = "font" + tokens.map { normalizeIdentifierToken($0, uppercaseFirst: true) }.joined()
  } else {
    baseName =
      normalizeIdentifierToken(tokens[0], uppercaseFirst: false)
      + tokens.dropFirst().map { normalizeIdentifierToken($0, uppercaseFirst: true) }.joined()
  }

  return swiftKeywords.contains(baseName) ? "\(baseName)Font" : baseName
}

func fontName(for fileURL: URL, baseNameCounts: [String: Int]) -> String {
  let baseName = fileURL.deletingPathExtension().lastPathComponent
  guard baseNameCounts[baseName, default: 0] > 1 else {
    return baseName
  }

  if fileURL.pathExtension == "tdf" {
    return fileURL.lastPathComponent
  }

  return baseName
}

func makeFontEntries(from fontFiles: [URL]) -> [FontEntry] {
  let baseNameCounts = fontFiles.reduce(into: [String: Int]()) { result, fileURL in
    result[fileURL.deletingPathExtension().lastPathComponent, default: 0] += 1
  }
  let fontFilesByName = fontFiles.reduce(into: [String: URL]()) { result, fileURL in
    let name = fontName(for: fileURL, baseNameCounts: baseNameCounts)
    result[name] = fileURL
  }
  let fontNames = fontFilesByName.keys.sorted()
  var usedCaseNames: [String] = []
  var entries: [FontEntry] = []
  entries.reserveCapacity(fontNames.count)

  for fontName in fontNames {
    let baseCaseName = swiftCaseName(for: fontName)
    var caseName = baseCaseName
    var suffix = 2

    while usedCaseNames.contains(caseName) {
      caseName = "\(baseCaseName)\(suffix)"
      suffix += 1
    }

    usedCaseNames.append(caseName)
    entries.append(
      FontEntry(
        fontName: fontName,
        caseName: caseName,
        fileURL: fontFilesByName[fontName]!
      )
    )
  }

  return entries
}

func bundledFontFiles(from fontFiles: [URL], requestedFontNames: [String]) throws -> [URL] {
  var remainingFontFiles = fontFiles
  var bundledFontFiles: [URL] = []
  bundledFontFiles.reserveCapacity(requestedFontNames.count)

  for requestedFontName in requestedFontNames {
    guard
      let index = remainingFontFiles.firstIndex(where: { fileURL in
        fileURL.lastPathComponent == requestedFontName
          || fileURL.deletingPathExtension().lastPathComponent == requestedFontName
      })
    else {
      throw NSError(
        domain: "generate_embedded_font_library",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Missing bundled font '\(requestedFontName)'"]
      )
    }

    bundledFontFiles.append(remainingFontFiles.remove(at: index))
  }

  return bundledFontFiles
}

func chunked(_ value: String, maxLength: Int) -> [String] {
  guard !value.isEmpty else {
    return [""]
  }

  var chunks: [String] = []
  var start = value.startIndex

  while start < value.endIndex {
    let end = value.index(start, offsetBy: maxLength, limitedBy: value.endIndex) ?? value.endIndex
    chunks.append(String(value[start..<end]))
    start = end
  }

  return chunks
}

func swiftStringLiteral(_ value: String) -> String {
  var result = ""
  result.reserveCapacity(value.count)

  for scalar in value.unicodeScalars {
    switch scalar {
    case "\"":
      result += "\\\""
    case "\\":
      result += "\\\\"
    case "\n":
      result += "\\n"
    case "\r":
      result += "\\r"
    case "\t":
      result += "\\t"
    default:
      if scalar.value < 0x20 || scalar.value == 0x7F {
        result += "\\u{\(String(scalar.value, radix: 16))}"
      } else {
        result.unicodeScalars.append(scalar)
      }
    }
  }

  return result
}

let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let arguments = Array(CommandLine.arguments.dropFirst())

let inputDirectory =
  arguments.indices.contains(0)
  ? resolvedFileURL(arguments[0], relativeTo: repositoryRoot)
  : repositoryRoot.appending(path: "Fonts", directoryHint: .isDirectory)

let outputFile =
  arguments.indices.contains(1)
  ? resolvedFileURL(arguments[1], relativeTo: repositoryRoot)
  : repositoryRoot.appending(path: "Sources/EmbeddedFonts/EmbeddedFonts.swift")

let fileManager = FileManager.default
let discoveredFontFiles = try fileManager.contentsOfDirectory(
  at: inputDirectory,
  includingPropertiesForKeys: nil
)
.filter { supportedExtensions.contains($0.pathExtension) }
.sorted { $0.lastPathComponent < $1.lastPathComponent }

guard !discoveredFontFiles.isEmpty else {
  throw NSError(
    domain: "generate_embedded_font_library",
    code: 1,
    userInfo: [NSLocalizedDescriptionKey: "No FIGlet fonts found in \(inputDirectory.path())"]
  )
}

let fontEntries = makeFontEntries(
  from: try bundledFontFiles(from: discoveredFontFiles, requestedFontNames: bundledFontNames))
let outputDirectory = outputFile.deletingLastPathComponent()
try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

var renderedCases: [String] = []
renderedCases.reserveCapacity(fontEntries.count)

func renderedAssignment(for fontEntry: FontEntry) throws -> String {
  let fontBytes = try Data(contentsOf: fontEntry.fileURL)
  let encodedFontData = fontBytes.base64EncodedString()
  let chunks = chunked(encodedFontData, maxLength: 4_096).map(swiftStringLiteral)
  var renderedLines = [
    "        encodedFontData = String()",
    "        encodedFontData.reserveCapacity(\(encodedFontData.count))",
  ]

  renderedLines.append(
    contentsOf: chunks.map { chunk in
      "        encodedFontData += \"\(chunk)\""
    })
  renderedLines.append(
    "        fonts[EmbeddedFigletFont.\(fontEntry.caseName).rawValue] = EmbeddedFontStorage.decode(encodedFontData, fontName: \"\(swiftStringLiteral(fontEntry.fontName))\")"
  )

  return renderedLines.joined(separator: "\n")
}

func renderedPartFile(partIndex: Int, fontEntries: ArraySlice<FontEntry>) throws -> String {
  var renderedAssignments: [String] = []
  renderedAssignments.reserveCapacity(fontEntries.count)

  for fontEntry in fontEntries {
    renderedAssignments.append(try renderedAssignment(for: fontEntry))
  }

  return """
    // Generated by Scripts/generate_embedded_font_library.swift.
    // Do not edit by hand.

    extension EmbeddedFigletFont {
        static func embeddedFontDataPart\(partIndex)() -> [String: [UInt8]] {
            var fonts: [String: [UInt8]] = [:]
            fonts.reserveCapacity(\(fontEntries.count))
            var encodedFontData = String()
    \(renderedAssignments.joined(separator: "\n\n"))
            return fonts
        }
    }
    """
}

for fontEntry in fontEntries {
  renderedCases.append(
    "  case \(fontEntry.caseName) = \"\(swiftStringLiteral(fontEntry.fontName))\"")
}

let outputBaseName = outputFile.deletingPathExtension().lastPathComponent
let stalePartFiles = try fileManager.contentsOfDirectory(
  at: outputDirectory,
  includingPropertiesForKeys: nil
)
.filter {
  $0.lastPathComponent.hasPrefix("\(outputBaseName)+Part") && $0.pathExtension == "swift"
}
for stalePartFile in stalePartFiles {
  try fileManager.removeItem(at: stalePartFile)
}

let partSize = 100
let partRanges = stride(from: 0, to: fontEntries.count, by: partSize).map { start in
  start..<min(start + partSize, fontEntries.count)
}
let renderedPartMerges = partRanges.indices.map { partIndex in
  "    fonts.merge(embeddedFontDataPart\(partIndex)()) { current, _ in current }"
}

let output = """
  // Generated by Scripts/generate_embedded_font_library.swift.
  // Do not edit by hand.

  public import SwiftFiglet

  public enum EmbeddedFigletFont: String, CaseIterable, Sendable {
  \(renderedCases.joined(separator: "\n"))

    public static let library: FigletFontLibrary = {
      var fonts: [String: [UInt8]] = [:]
      fonts.reserveCapacity(\(fontEntries.count))
  \(renderedPartMerges.joined(separator: "\n"))
      return FigletFontLibrary(
        name: "swift-figlet embedded fonts",
        fonts: fonts
      )
    }()
  }
  """

try output.write(to: outputFile, atomically: true, encoding: .utf8)

for (partIndex, range) in partRanges.enumerated() {
  let partFile = outputDirectory.appending(path: "\(outputBaseName)+Part\(partIndex).swift")
  let partOutput = try renderedPartFile(
    partIndex: partIndex,
    fontEntries: fontEntries[range]
  )
  try partOutput.write(to: partFile, atomically: true, encoding: .utf8)
}
