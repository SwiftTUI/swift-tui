#!/usr/bin/env swift
import Foundation

struct FontEntry {
  let fontName: String
  let caseName: String
  let fileURL: URL
}

let supportedExtensions = ["flf", "tlf"]
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

func makeFontEntries(from uniqueFontFilesByName: [String: URL]) -> [FontEntry] {
  let fontNames = uniqueFontFilesByName.keys.sorted()
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
        fileURL: uniqueFontFilesByName[fontName]!
      )
    )
  }

  return entries
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

var uniqueFontFilesByName: [String: URL] = [:]
for fontFile in discoveredFontFiles {
  uniqueFontFilesByName[fontFile.deletingPathExtension().lastPathComponent] = fontFile
}

let fontEntries = makeFontEntries(from: uniqueFontFilesByName)
let outputDirectory = outputFile.deletingLastPathComponent()
try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

var renderedAssignments: [String] = []
renderedAssignments.reserveCapacity(fontEntries.count)
var renderedCases: [String] = []
renderedCases.reserveCapacity(fontEntries.count)

for fontEntry in fontEntries {
  let fontBytes = try Data(contentsOf: fontEntry.fileURL)
  let fontData = String(decoding: fontBytes, as: UTF8.self)
  let chunks = chunked(fontData, maxLength: 4_096)
  var renderedLines = [
    "        fontData = String()",
    "        fontData.reserveCapacity(\(fontBytes.count))",
  ]

  renderedLines.append(
    contentsOf: chunks.map { chunk in
      "        fontData += \"\(swiftStringLiteral(chunk))\""
    })
  renderedLines.append(
    "        fonts[EmbeddedFigletFont.\(fontEntry.caseName).rawValue] = fontData")

  renderedAssignments.append(renderedLines.joined(separator: "\n"))
  renderedCases.append(
    "        case \(fontEntry.caseName) = \"\(swiftStringLiteral(fontEntry.fontName))\"")
}

let output = """
  // Generated by Scripts/generate_embedded_font_library.swift.
  // Do not edit by hand.

  public import SwiftFiglet

  public enum EmbeddedFigletFont: String, CaseIterable, Sendable {
  \(renderedCases.joined(separator: "\n"))

      public static let library: FigletFontLibrary = {
          var fonts: [String: String] = [:]
          fonts.reserveCapacity(\(fontEntries.count))
          var fontData = String()
  \(renderedAssignments.joined(separator: "\n\n"))
          return FigletFontLibrary(
              name: "swift-figlet embedded fonts",
              fontData: fonts
          )
      }()
  }
  """

try output.write(to: outputFile, atomically: true, encoding: .utf8)
