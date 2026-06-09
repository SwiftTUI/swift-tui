#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#endif

public enum FigletError: Error, CustomStringConvertible, Sendable {
  case fontNotFound(String)
  case invalidFont(String)
  case characterDoesNotFit(Character, width: Int)
  case invalidConfiguration(String)

  public var description: String {
    switch self {
    case .fontNotFound(let font):
      return "requested font '\(font)' not found"
    case .invalidFont(let message):
      return message
    case .characterDoesNotFit(let character, let width):
      return "width \(width) is not enough to print character '\(character)'"
    case .invalidConfiguration(let message):
      return message
    }
  }
}

public enum FigletDirection: String, CaseIterable, Sendable {
  case automatic = "auto"
  case leftToRight = "left-to-right"
  case rightToLeft = "right-to-left"
}

public enum FigletJustification: String, CaseIterable, Sendable {
  case automatic = "auto"
  case left
  case center
  case right
}

public struct FigletConfiguration: Sendable {
  public var width: Int
  public var direction: FigletDirection
  public var justification: FigletJustification

  public init(
    width: Int = 80,
    direction: FigletDirection = .automatic,
    justification: FigletJustification = .automatic
  ) {
    self.width = width
    self.direction = direction
    self.justification = justification
  }
}

public struct FigletFontLibrary: Sendable {
  public let name: String?

  private let fonts: [String: [UInt8]]
  private let names: [String]

  public init(name: String? = nil, fonts: [String: [UInt8]]) {
    self.name = name
    let baseNameCounts = fonts.keys.reduce(into: [String: Int]()) { result, name in
      result[Self.baseFontName(for: name), default: 0] += 1
    }

    var lookupFonts: [String: [UInt8]] = [:]
    var displayNames = Set<String>()
    for (name, data) in fonts {
      let displayName = Self.displayFontName(for: name, baseNameCounts: baseNameCounts)
      displayNames.insert(displayName)
      lookupFonts[displayName] = data
      lookupFonts[name] = data

      if name.hasSupportedFontExtension, lookupFonts[Self.baseFontName(for: name)] == nil {
        lookupFonts[Self.baseFontName(for: name)] = data
      }
    }

    self.fonts = lookupFonts
    self.names = displayNames.sorted()
  }

  public init(name: String? = nil, fontData: [String: String]) {
    self.init(name: name, fonts: fontData.mapValues { Array($0.utf8) })
  }

  public var fontNames: [String] {
    names
  }

  public func font(named identifier: String) throws -> FigletFont? {
    guard let entry = fontEntry(named: identifier) else {
      return nil
    }

    return try FigletFont.parse(
      data: entry.data,
      name: entry.name
    )
  }

  private func fontEntry(named identifier: String) -> (name: String, data: [UInt8])? {
    guard !identifier.contains("/") else {
      return nil
    }

    let candidates =
      identifier.hasSupportedFontExtension
      ? [identifier, Self.baseFontName(for: identifier)]
      : [identifier]
    guard let matchedIdentifier = candidates.first(where: { fonts[$0] != nil }),
      let data = fonts[matchedIdentifier]
    else {
      return nil
    }

    return (Self.baseFontName(for: matchedIdentifier), data)
  }

  private static func displayFontName(
    for identifier: String,
    baseNameCounts: [String: Int]
  ) -> String {
    guard identifier.hasSupportedFontExtension,
      baseNameCounts[baseFontName(for: identifier), default: 0] == 1
    else {
      return identifier
    }

    return baseFontName(for: identifier)
  }

  private static func baseFontName(for identifier: String) -> String {
    if identifier.hasSupportedFontExtension {
      return identifier.lastPathComponentWithoutExtension
    }

    return identifier
  }
}

public struct FigletText: CustomStringConvertible, Equatable, Sendable {
  public let rawValue: String
  let surface: FigletSurface?

  public init(_ rawValue: String) {
    self.rawValue = rawValue
    self.surface = nil
  }

  public init(surface: FigletSurface) {
    self.rawValue = surface.render(.plain)
    self.surface = surface
  }

  public var description: String {
    rawValue
  }

  public static func == (lhs: FigletText, rhs: FigletText) -> Bool {
    lhs.rawValue == rhs.rawValue
  }

  public var containsANSIStyles: Bool {
    surface?.containsStyles ?? false
  }

  public var ansiDescription: String {
    surface?.render(.ansi) ?? rawValue
  }

  public func reversed() -> FigletText {
    if let surface {
      return FigletText(surface: surface.mapCharacters(Self.reverseMap).reversed())
    }

    let rows = rawValue.split(separator: "\n", omittingEmptySubsequences: false)
    let reversedRows = rows.map { row in
      String(row.map(Self.reverseMap).reversed())
    }
    return FigletText(reversedRows.joined(separator: "\n"))
  }

  public func flipped() -> FigletText {
    if let surface {
      return FigletText(surface: surface.mapCharacters(Self.flipMap).flipped())
    }

    let rows = rawValue.split(separator: "\n", omittingEmptySubsequences: false)
    let flippedRows = rows.reversed().map { row in
      String(row.map(Self.flipMap))
    }
    return FigletText(flippedRows.joined(separator: "\n"))
  }

  public func strippingSurroundingNewlines() -> String {
    let rows = rawValue.split(separator: "\n", omittingEmptySubsequences: false)
    var output: [Substring] = []
    var sawContent = false

    for row in rows {
      if row.containsNonWhitespace || sawContent {
        sawContent = true
        output.append(row)
      }
    }

    return output.joined(separator: "\n").trimmingTrailingWhitespaceAndNewlines()
  }

  public func strippedSurroundingNewlines() -> FigletText {
    guard let surface else {
      return FigletText(strippingSurroundingNewlines())
    }

    return FigletText(surface: surface.strippingSurroundingNewlines())
  }

  public func normalizingSurroundingNewlines() -> String {
    "\n\(strippingSurroundingNewlines())\n"
  }

  public func normalizedSurroundingNewlines() -> FigletText {
    guard let surface else {
      return FigletText(normalizingSurroundingNewlines())
    }

    return FigletText(surface: surface.normalizingSurroundingNewlines())
  }

  private static func reverseMap(_ character: Character) -> Character {
    switch character {
    case "(": return ")"
    case ")": return "("
    case "/": return "\\"
    case "\\": return "/"
    case "[": return "]"
    case "]": return "["
    case "{": return "}"
    case "}": return "{"
    case "<": return ">"
    case ">": return "<"
    default: return character
    }
  }

  private static func flipMap(_ character: Character) -> Character {
    switch character {
    case "/": return "\\"
    case "\\": return "/"
    case "_": return " "
    case "^": return "v"
    case "v": return "^"
    case "M": return "W"
    case "W": return "M"
    default: return character
    }
  }
}

public struct FigletSize: Equatable, Sendable {
  public let width: Int
  public let height: Int

  public init(width: Int, height: Int) {
    self.width = max(0, width)
    self.height = max(0, height)
  }
}

public struct FigletLayoutMetrics: Equatable, Sendable {
  public let minimumWidth: Int
  public let idealSize: FigletSize

  public init(minimumWidth: Int, idealSize: FigletSize) {
    self.minimumWidth = max(0, minimumWidth)
    self.idealSize = idealSize
  }
}

public enum FigletTerminalColor: Int, CaseIterable, Sendable {
  case black = 0
  case blue = 1
  case green = 2
  case cyan = 3
  case red = 4
  case magenta = 5
  case yellow = 6
  case white = 7
  case brightBlack = 8
  case brightBlue = 9
  case brightGreen = 10
  case brightCyan = 11
  case brightRed = 12
  case brightMagenta = 13
  case brightYellow = 14
  case brightWhite = 15
}

public struct FigletStyle: Equatable, Sendable {
  public static let plain = FigletStyle()

  public var foreground: FigletTerminalColor?
  public var background: FigletTerminalColor?

  public init(
    foreground: FigletTerminalColor? = nil,
    background: FigletTerminalColor? = nil
  ) {
    self.foreground = foreground
    self.background = background
  }

  var isPlain: Bool {
    foreground == nil && background == nil
  }

  static func theDrawAttribute(_ rawAttribute: UInt8) -> FigletStyle {
    let foreground = FigletTerminalColor(rawValue: Int(rawAttribute & 0x0F))
    let background = FigletTerminalColor(rawValue: Int((rawAttribute & 0xF0) >> 4))
    return FigletStyle(foreground: foreground, background: background)
  }
}

public struct FigletCell: Equatable, Sendable {
  public var character: Character
  public var style: FigletStyle

  static let space = FigletCell(character: " ")

  public init(character: Character, style: FigletStyle = .plain) {
    self.character = character
    self.style = style
  }

  var hasStyle: Bool {
    !style.isPlain
  }
}

public enum FigletSurfaceFormat: Sendable {
  case plain
  case ansi
}

public enum FigletSurfaceFilter: Sendable {
  case stripStyles
  case fillStyle(FigletStyle)
  case overrideStyle(FigletStyle)
}

public struct FigletSurface: CustomStringConvertible, Equatable, Sendable {
  public let rows: [[FigletCell]]

  public init(rows: [[FigletCell]]) {
    self.rows = rows
  }

  public var description: String {
    render(.plain)
  }

  public var containsStyles: Bool {
    rows.contains { row in row.contains(where: \.hasStyle) }
  }

  public var size: FigletSize {
    measureCellRows(rows)
  }

  public func render(_ format: FigletSurfaceFormat = .plain) -> String {
    FigletSurfaceSerializer(format: format).render(self)
  }

  public func applying(_ filter: FigletSurfaceFilter) -> FigletSurface {
    switch filter {
    case .stripStyles:
      return mapCells { cell in
        FigletCell(character: cell.character)
      }
    case .fillStyle(let style):
      return mapCells { cell in
        guard !cell.hasStyle, !cell.character.isFigletWhitespace else {
          return cell
        }
        var styledCell = cell
        styledCell.style = style
        return styledCell
      }
    case .overrideStyle(let style):
      return mapCells { cell in
        guard !cell.character.isFigletWhitespace else {
          return cell
        }
        var styledCell = cell
        styledCell.style = style
        return styledCell
      }
    }
  }

  public func applying(_ filters: [FigletSurfaceFilter]) -> FigletSurface {
    filters.reduce(self) { surface, filter in
      surface.applying(filter)
    }
  }

  func reversed() -> FigletSurface {
    FigletSurface(rows: rows.map { Array($0.reversed()) })
  }

  func flipped() -> FigletSurface {
    FigletSurface(rows: Array(rows.reversed()))
  }

  func mapCharacters(_ transform: (Character) -> Character) -> FigletSurface {
    mapCells { cell in
      var mappedCell = cell
      mappedCell.character = transform(cell.character)
      return mappedCell
    }
  }

  func strippingSurroundingNewlines() -> FigletSurface {
    var output: [[FigletCell]] = []
    var sawContent = false

    for row in rows {
      if row.contains(where: { !$0.character.isFigletWhitespace }) || sawContent {
        sawContent = true
        output.append(row)
      }
    }

    while let lastRow = output.last {
      var trimmedRow = lastRow
      while let lastCell = trimmedRow.last, lastCell.character.isFigletWhitespace {
        trimmedRow.removeLast()
      }

      if trimmedRow.isEmpty {
        output.removeLast()
      } else {
        output[output.count - 1] = trimmedRow
        break
      }
    }

    return FigletSurface(rows: output)
  }

  func normalizingSurroundingNewlines() -> FigletSurface {
    var normalizedRows = strippingSurroundingNewlines().rows
    if normalizedRows.isEmpty {
      return FigletSurface(rows: [[], []])
    }
    normalizedRows.insert([], at: 0)
    return FigletSurface(rows: normalizedRows)
  }

  private func mapCells(_ transform: (FigletCell) -> FigletCell) -> FigletSurface {
    FigletSurface(rows: rows.map { row in row.map(transform) })
  }
}

private struct FigletSurfaceSerializer {
  static let ansiReset = "\u{001B}[0m"

  let format: FigletSurfaceFormat

  func render(_ surface: FigletSurface) -> String {
    let renderedRows = surface.rows.map { row in
      switch format {
      case .plain:
        return String(row.map(\.character))
      case .ansi:
        return ansiRowDescription(row)
      }
    }
    return renderedRows.joined(separator: "\n") + (surface.rows.isEmpty ? "" : "\n")
  }

  private func ansiRowDescription(_ row: [FigletCell]) -> String {
    var output = ""
    var activeStyle = FigletStyle.plain

    for cell in row {
      if cell.style != activeStyle {
        output += ansiEscape(for: cell.style)
        activeStyle = cell.style
      }

      output.append(cell.character)
    }

    if !activeStyle.isPlain {
      output += Self.ansiReset
    }

    return output
  }

  private func ansiEscape(for style: FigletStyle) -> String {
    var codes: [Int] = []
    if let foreground = style.foreground {
      codes.append(ansiForegroundCode(for: foreground))
    }
    if let background = style.background {
      codes.append(ansiBackgroundCode(for: background))
    }
    return codes.isEmpty
      ? Self.ansiReset : "\u{001B}[\(codes.map(String.init).joined(separator: ";"))m"
  }

  private func ansiForegroundCode(for color: FigletTerminalColor) -> Int {
    [30, 34, 32, 36, 31, 35, 33, 37, 90, 94, 92, 96, 91, 95, 93, 97][color.rawValue]
  }

  private func ansiBackgroundCode(for color: FigletTerminalColor) -> Int {
    [40, 44, 42, 46, 41, 45, 43, 47][min(color.rawValue, 7)]
  }
}

struct FigletGlyph: Equatable, Sendable {
  let width: Int
  let rows: [[FigletCell]]

  init(width: Int, rows: [[FigletCell]]) {
    self.width = width
    self.rows = rows
  }

  init(width: Int, plainRows: [String]) {
    self.width = width
    self.rows = plainRows.map { row in
      row.map { FigletCell(character: $0) }
    }
  }
}

public struct FigletFont: Sendable {
  public static let defaultFontName = "standard"

  public let name: String
  public let height: Int
  public let baseline: Int
  public let hardBlank: Character
  public let printDirection: Int?
  public let smushMode: Int
  public let comment: String

  let glyphs: [Int: FigletGlyph]
  let widths: [Int: Int]

  public init(named name: String) throws {
    self = try Self.load(identifier: name)
  }

  public init(named name: String, fontLibrary: FigletFontLibrary) throws {
    self = try Self.load(identifier: name, fontLibraries: [fontLibrary])
  }

  public init(named name: String, fontLibraries: [FigletFontLibrary]) throws {
    self = try Self.load(identifier: name, fontLibraries: fontLibraries)
  }

  public init(named name: String, searchDirectories: [String]) throws {
    self = try Self.load(identifier: name, searchDirectories: searchDirectories)
  }

  public init(named name: String, fontLibrary: FigletFontLibrary, searchDirectories: [String])
    throws
  {
    self = try Self.load(
      identifier: name,
      fontLibraries: [fontLibrary],
      searchDirectories: searchDirectories
    )
  }

  public init(named name: String, fontLibraries: [FigletFontLibrary], searchDirectories: [String])
    throws
  {
    self = try Self.load(
      identifier: name,
      fontLibraries: fontLibraries,
      searchDirectories: searchDirectories
    )
  }

  public init(filePath: String) throws {
    self = try Self.load(
      filePath: filePath, fallbackName: filePath.lastPathComponentWithoutExtension)
  }

  public var info: String {
    comment
  }

  public static func bundledFontNames() -> [String] {
    availableFontNames()
  }

  public static func availableFontNames() -> [String] {
    availableFontNames(in: defaultFontSearchDirectories())
  }

  public static func availableFontNames(fontLibraries: [FigletFontLibrary]) -> [String] {
    availableFontNames(in: defaultFontSearchDirectories(), libraries: fontLibraries)
  }

  public static func availableFontNames(in searchDirectories: [String]) -> [String] {
    availableFontNames(in: searchDirectories, libraries: [])
  }

  public static func availableFontNames(
    in searchDirectories: [String],
    libraries: [FigletFontLibrary]
  ) -> [String] {
    uniquePaths(searchDirectories)
      .flatMap { directory in
        directoryEntries(at: directory)
          .filter { $0.hasSupportedFontExtension }
          .map(\.lastPathComponentWithoutExtension)
      }
      .reduce(into: Set(libraries.flatMap(\.fontNames))) { result, name in
        result.insert(name)
      }
      .sorted()
  }

  static func load(identifier: String) throws -> FigletFont {
    try load(
      identifier: identifier,
      fontLibraries: [],
      searchDirectories: defaultFontSearchDirectories()
    )
  }

  static func load(identifier: String, fontLibraries: [FigletFontLibrary]) throws -> FigletFont {
    try load(
      identifier: identifier,
      fontLibraries: fontLibraries,
      searchDirectories: defaultFontSearchDirectories()
    )
  }

  static func load(identifier: String, searchDirectories: [String]) throws -> FigletFont {
    try load(identifier: identifier, fontLibraries: [], searchDirectories: searchDirectories)
  }

  static func load(
    identifier: String,
    fontLibraries: [FigletFontLibrary],
    searchDirectories: [String]
  ) throws -> FigletFont {
    if let filePath = resolveExternalFontPath(for: identifier) {
      return try load(filePath: filePath, fallbackName: filePath.lastPathComponentWithoutExtension)
    }

    for fontLibrary in fontLibraries {
      if let font = try fontLibrary.font(named: identifier) {
        return font
      }
    }

    for directory in uniquePaths(searchDirectories) {
      if let filePath = resolveFontPath(named: identifier, in: directory) {
        return try load(
          filePath: filePath, fallbackName: filePath.lastPathComponentWithoutExtension)
      }
    }

    throw FigletError.fontNotFound(identifier)
  }

  private static func load(filePath: String, fallbackName: String) throws -> FigletFont {
    let data = try readFile(at: filePath)
    return try parse(data: data, name: fallbackName)
  }

  private static func resolveExternalFontPath(for identifier: String) -> String? {
    if fileExists(at: identifier) {
      return identifier
    }

    for ext in supportedFontExtensions {
      let candidate = "\(identifier).\(ext)"
      if fileExists(at: candidate) {
        return candidate
      }
    }

    return nil
  }

  private static func resolveFontPath(named identifier: String, in directory: String) -> String? {
    if identifier.hasSupportedFontExtension {
      let directPath = pathByAppending(directory, identifier)
      return fileExists(at: directPath) ? directPath : nil
    }

    for ext in supportedFontExtensions {
      let candidate = pathByAppending(directory, "\(identifier).\(ext)")
      if fileExists(at: candidate) {
        return candidate
      }
    }

    return nil
  }

  private static func defaultFontSearchDirectories() -> [String] {
    var directories: [String] = []

    if let envValue = environmentValue(named: "SWIFT_FIGLET_FONT_DIRS") {
      directories.append(contentsOf: envValue.split(separator: ":").map(String.init))
    }

    if let envValue = environmentValue(named: "SWIFT_FIGLET_FONT_DIR") {
      directories.append(envValue)
    }

    if let homeDirectory = environmentValue(named: "HOME") {
      directories.append(pathByAppending(homeDirectory, ".figfonts"))
    }

    directories.append("figfonts")

    return uniquePaths(directories).filter(isDirectory(at:))
  }

  fileprivate static func parse(data: [UInt8], name: String) throws -> FigletFont {
    if data.starts(with: theDrawMagic) {
      return try parseTheDrawFont(data: data, name: name)
    }

    return try parseFigletFont(data: String(decoding: data, as: UTF8.self), name: name)
  }

  private static func parseFigletFont(data: String, name: String) throws -> FigletFont {
    let sanitized = data.sanitizedFontData()

    let lines = sanitized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var lineIndex = 0

    let headerLine = try consumeLine(from: lines, index: &lineIndex)
    guard headerLine.hasPrefix("flf2") || headerLine.hasPrefix("tlf2") else {
      throw FigletError.invalidFont("\(name) is not a valid figlet font")
    }
    guard headerLine.count >= 6 else {
      throw FigletError.invalidFont("malformed header for \(name)")
    }

    let headerRemainder = String(headerLine.dropFirst(5))
    let headerParts = headerRemainder.split(whereSeparator: \.isWhitespace).map(String.init)
    guard headerParts.count >= 6 else {
      throw FigletError.invalidFont("malformed header for \(name)")
    }

    guard let hardBlank = headerParts[0].first,
      let height = Int(headerParts[1]),
      let baseline = Int(headerParts[2]),
      Int(headerParts[3]) != nil,
      let oldLayout = Int(headerParts[4]),
      let commentLines = Int(headerParts[5])
    else {
      throw FigletError.invalidFont("malformed header for \(name)")
    }

    let printDirection = headerParts.count > 6 ? Int(headerParts[6]) : nil
    let fullLayout = headerParts.count > 7 ? Int(headerParts[7]) : nil
    let smushMode: Int
    if let fullLayout {
      smushMode = fullLayout
    } else if oldLayout == 0 {
      smushMode = 64
    } else if oldLayout < 0 {
      smushMode = 0
    } else {
      smushMode = (oldLayout & 31) | 128
    }

    var commentLinesBuffer: [String] = []
    for _ in 0..<commentLines {
      commentLinesBuffer.append(try consumeLine(from: lines, index: &lineIndex))
    }

    var glyphs: [Int: FigletGlyph] = [:]
    var widths: [Int: Int] = [:]

    for codePoint in 32..<127 {
      let glyph = try consumeGlyph(from: lines, index: &lineIndex, height: height)
      if codePoint == 32 || !glyph.rows.joined().isEmpty {
        glyphs[codePoint] = FigletGlyph(width: glyph.width, plainRows: glyph.rows)
        widths[codePoint] = glyph.width
      }
    }

    do {
      for character in ["Ä", "Ö", "Ü", "ä", "ö", "ü", "ß"] {
        guard lineIndex < lines.count, glyphIdentifier(in: lines[lineIndex]) == nil else {
          break
        }

        let glyph = try consumeGlyph(from: lines, index: &lineIndex, height: height)
        if !glyph.rows.joined().isEmpty, let scalar = character.unicodeScalars.first {
          glyphs[Int(scalar.value)] = FigletGlyph(width: glyph.width, plainRows: glyph.rows)
          widths[Int(scalar.value)] = glyph.width
        }
      }

      while lineIndex < lines.count {
        let definition = try consumeLine(from: lines, index: &lineIndex).trimmingFigletWhitespace()
        guard !definition.isEmpty else {
          continue
        }

        guard let codePoint = glyphIdentifier(in: definition) else {
          continue
        }

        let glyph = try consumeGlyph(from: lines, index: &lineIndex, height: height)
        if !glyph.rows.joined().isEmpty {
          glyphs[codePoint] = FigletGlyph(width: glyph.width, plainRows: glyph.rows)
          widths[codePoint] = glyph.width
        }
      }
    } catch {
      // Extended glyph tables are optional; keep the ASCII core usable even if
      // a font's supplementary section is truncated or uses an unsupported layout.
    }

    return FigletFont(
      name: name,
      height: height,
      baseline: baseline,
      hardBlank: hardBlank,
      printDirection: printDirection,
      smushMode: smushMode,
      comment: commentLinesBuffer.joined(separator: "\n"),
      glyphs: glyphs,
      widths: widths
    )
  }

  private init(
    name: String,
    height: Int,
    baseline: Int,
    hardBlank: Character,
    printDirection: Int?,
    smushMode: Int,
    comment: String,
    glyphs: [Int: FigletGlyph],
    widths: [Int: Int]
  ) {
    self.name = name
    self.height = height
    self.baseline = baseline
    self.hardBlank = hardBlank
    self.printDirection = printDirection
    self.smushMode = smushMode
    self.comment = comment
    self.glyphs = glyphs
    self.widths = widths
  }

  private static let theDrawMagic = Array("\u{0013}TheDraw FONTS file\u{001A}".utf8)
  private static let theDrawCharacters = Array(
    "!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
      .unicodeScalars
      .map { Int($0.value) })

  private static func parseTheDrawFont(data: [UInt8], name: String) throws -> FigletFont {
    let dataStart = 233
    guard data.count >= dataStart else {
      throw FigletError.invalidFont("\(name) is not a valid TheDraw font")
    }
    guard data[41] == 2 else {
      throw FigletError.invalidFont("\(name) uses an unsupported TheDraw font type")
    }

    let spacing = Int(data[42])
    let offsets = (0..<theDrawCharacters.count).map { index in
      readLittleEndianUInt16(from: data, at: 45 + index * 2)
    }

    var fontHeight = 0
    for offset in offsets where offset != 0xFFFF {
      let glyphStart = dataStart + Int(offset)
      guard glyphStart + 1 < data.count else {
        throw FigletError.invalidFont("\(name) contains an invalid TheDraw glyph offset")
      }
      fontHeight = max(fontHeight, Int(data[glyphStart + 1]))
    }

    var glyphs: [Int: FigletGlyph] = [:]
    var widths: [Int: Int] = [:]

    for (index, offset) in offsets.enumerated() where offset != 0xFFFF {
      let glyph = try parseTheDrawGlyph(
        data: data,
        dataStart: dataStart,
        offset: Int(offset),
        fontHeight: fontHeight,
        spacing: spacing,
        fontName: name
      )
      let codePoint = theDrawCharacters[index]
      glyphs[codePoint] = glyph
      widths[codePoint] = glyph.width
    }

    return FigletFont(
      name: name,
      height: fontHeight,
      baseline: fontHeight,
      hardBlank: " ",
      printDirection: 0,
      smushMode: 0,
      comment: theDrawFontName(from: data) ?? "",
      glyphs: glyphs,
      widths: widths
    )
  }

  private static func parseTheDrawGlyph(
    data: [UInt8],
    dataStart: Int,
    offset: Int,
    fontHeight: Int,
    spacing: Int,
    fontName: String
  ) throws -> FigletGlyph {
    let glyphStart = dataStart + offset
    guard glyphStart + 1 < data.count else {
      throw FigletError.invalidFont("\(fontName) contains an invalid TheDraw glyph offset")
    }

    let glyphWidth = Int(data[glyphStart])
    let glyphHeight = Int(data[glyphStart + 1])
    let renderedWidth = glyphWidth + spacing
    var cells = Array(
      repeating: Array(repeating: FigletCell.space, count: renderedWidth),
      count: fontHeight
    )

    var row = 0
    var column = 0
    var index = glyphStart + 2

    while index < data.count {
      let byte = data[index]
      index += 1

      if byte == 0 {
        break
      }

      if byte == 13 {
        row += 1
        column = 0
        continue
      }

      guard index < data.count else {
        throw FigletError.invalidFont("\(fontName) contains a truncated TheDraw glyph")
      }
      let color = data[index]
      index += 1

      if row < min(glyphHeight, fontHeight), column < glyphWidth {
        cells[row][column] = FigletCell(
          character: theDrawCharacter(for: byte),
          style: .theDrawAttribute(color)
        )
      }
      column += 1
    }

    return FigletGlyph(width: renderedWidth, rows: cells)
  }

  private static func readLittleEndianUInt16(from data: [UInt8], at index: Int) -> Int {
    Int(data[index]) | (Int(data[index + 1]) << 8)
  }

  private static func theDrawFontName(from data: [UInt8]) -> String? {
    let nameLength = Int(data[24])
    guard nameLength > 0 else {
      return nil
    }

    let upperBound = min(25 + nameLength, 41, data.count)
    let bytes = data[25..<upperBound].prefix { $0 != 0 }
    let characters = bytes.map(theDrawCharacter)
    return characters.isEmpty ? nil : String(characters)
  }

  private static func theDrawCharacter(for byte: UInt8) -> Character {
    if byte < 0x20 {
      return " "
    }

    if byte < 0x7F {
      return Character(UnicodeScalar(Int(byte))!)
    }

    return Character(cp437Scalars[Int(byte) - 0x7F])
  }
}

private let supportedFontExtensions = ["flf", "tlf", "tdf"]

private let cp437Scalars: [UnicodeScalar] = [
  "\u{2302}", "\u{00C7}", "\u{00FC}", "\u{00E9}", "\u{00E2}", "\u{00E4}", "\u{00E0}",
  "\u{00E5}", "\u{00E7}", "\u{00EA}", "\u{00EB}", "\u{00E8}", "\u{00EF}", "\u{00EE}",
  "\u{00EC}", "\u{00C4}", "\u{00C5}", "\u{00C9}", "\u{00E6}", "\u{00C6}", "\u{00F4}",
  "\u{00F6}", "\u{00F2}", "\u{00FB}", "\u{00F9}", "\u{00FF}", "\u{00D6}", "\u{00DC}",
  "\u{00A2}", "\u{00A3}", "\u{00A5}", "\u{20A7}", "\u{0192}", "\u{00E1}", "\u{00ED}",
  "\u{00F3}", "\u{00FA}", "\u{00F1}", "\u{00D1}", "\u{00AA}", "\u{00BA}", "\u{00BF}",
  "\u{2310}", "\u{00AC}", "\u{00BD}", "\u{00BC}", "\u{00A1}", "\u{00AB}", "\u{00BB}",
  "\u{2591}", "\u{2592}", "\u{2593}", "\u{2502}", "\u{2524}", "\u{2561}", "\u{2562}",
  "\u{2556}", "\u{2555}", "\u{2563}", "\u{2551}", "\u{2557}", "\u{255D}", "\u{255C}",
  "\u{255B}", "\u{2510}", "\u{2514}", "\u{2534}", "\u{252C}", "\u{251C}", "\u{2500}",
  "\u{253C}", "\u{255E}", "\u{255F}", "\u{255A}", "\u{2554}", "\u{2569}", "\u{2566}",
  "\u{2560}", "\u{2550}", "\u{256C}", "\u{2567}", "\u{2568}", "\u{2564}", "\u{2565}",
  "\u{2559}", "\u{2558}", "\u{2552}", "\u{2553}", "\u{256B}", "\u{256A}", "\u{2518}",
  "\u{250C}", "\u{2588}", "\u{2584}", "\u{258C}", "\u{2590}", "\u{2580}", "\u{03B1}",
  "\u{00DF}", "\u{0393}", "\u{03C0}", "\u{03A3}", "\u{03C3}", "\u{00B5}", "\u{03C4}",
  "\u{03A6}", "\u{0398}", "\u{03A9}", "\u{03B4}", "\u{221E}", "\u{03C6}", "\u{03B5}",
  "\u{2229}", "\u{2261}", "\u{00B1}", "\u{2265}", "\u{2264}", "\u{2320}", "\u{2321}",
  "\u{00F7}", "\u{2248}", "\u{00B0}", "\u{2219}", "\u{00B7}", "\u{221A}", "\u{207F}",
  "\u{00B2}", "\u{25A0}", "\u{00A0}",
]

private func parseGlyphIdentifier(_ token: String) -> Int? {
  if token.lowercased().hasPrefix("0x") {
    return Int(token.dropFirst(2), radix: 16)
  }

  return Int(token)
}

private func glyphIdentifier(in definition: String) -> Int? {
  guard
    let identifier =
      definition
      .trimmingFigletWhitespace()
      .split(separator: " ", maxSplits: 1)
      .first
  else {
    return nil
  }

  return parseGlyphIdentifier(String(identifier))
}

public struct Figlet: Sendable {
  public let font: FigletFont
  public let configuration: FigletConfiguration

  public init(
    fontNamed name: String = FigletFont.defaultFontName,
    configuration: FigletConfiguration = FigletConfiguration()
  ) throws {
    self.font = try FigletFont(named: name)
    self.configuration = configuration
  }

  public init(
    fontNamed name: String = FigletFont.defaultFontName,
    configuration: FigletConfiguration = FigletConfiguration(),
    fontLibrary: FigletFontLibrary
  ) throws {
    try self.init(fontNamed: name, configuration: configuration, fontLibraries: [fontLibrary])
  }

  public init(
    fontNamed name: String = FigletFont.defaultFontName,
    configuration: FigletConfiguration = FigletConfiguration(),
    fontLibraries: [FigletFontLibrary]
  ) throws {
    self.font = try FigletFont(named: name, fontLibraries: fontLibraries)
    self.configuration = configuration
  }

  public init(
    fontNamed name: String = FigletFont.defaultFontName,
    configuration: FigletConfiguration = FigletConfiguration(),
    searchDirectories: [String]
  ) throws {
    self.font = try FigletFont(named: name, searchDirectories: searchDirectories)
    self.configuration = configuration
  }

  public init(font: FigletFont, configuration: FigletConfiguration = FigletConfiguration()) {
    self.font = font
    self.configuration = configuration
  }

  public init(
    fontNamed name: String = FigletFont.defaultFontName,
    configuration: FigletConfiguration = FigletConfiguration(),
    fontLibrary: FigletFontLibrary,
    searchDirectories: [String]
  ) throws {
    try self.init(
      fontNamed: name,
      configuration: configuration,
      fontLibraries: [fontLibrary],
      searchDirectories: searchDirectories
    )
  }

  public init(
    fontNamed name: String = FigletFont.defaultFontName,
    configuration: FigletConfiguration = FigletConfiguration(),
    fontLibraries: [FigletFontLibrary],
    searchDirectories: [String]
  ) throws {
    self.font = try FigletFont(
      named: name,
      fontLibraries: fontLibraries,
      searchDirectories: searchDirectories
    )
    self.configuration = configuration
  }

  public func render(_ text: String) throws -> FigletText {
    try FigletText(surface: renderSurface(text))
  }

  public func renderSurface(_ text: String) throws -> FigletSurface {
    guard configuration.width > 0 else {
      throw FigletError.invalidConfiguration("width must be greater than zero")
    }

    var layoutEngine = FigletLayoutEngine(
      text: text,
      font: font,
      direction: resolvedDirection,
      width: configuration.width,
      justification: resolvedJustification
    )
    return try layoutEngine.renderSurface()
  }

  public func layoutMetrics(for text: String) throws -> FigletLayoutMetrics {
    guard configuration.width > 0 else {
      throw FigletError.invalidConfiguration("width must be greater than zero")
    }

    guard !text.isEmpty else {
      return FigletLayoutMetrics(
        minimumWidth: 0,
        idealSize: FigletSize(width: 0, height: 0)
      )
    }

    let minimumWidth = minimumRenderableWidth(for: text)
    let idealWidth = max(1, nonWrappingWidthUpperBound(for: text))
    var layoutEngine = FigletLayoutEngine(
      text: text,
      font: font,
      direction: resolvedDirection,
      width: idealWidth,
      justification: resolvedJustification
    )
    let surface = try layoutEngine.renderSurface()

    return FigletLayoutMetrics(
      minimumWidth: minimumWidth,
      idealSize: surface.size
    )
  }

  public func measure(_ text: String, forWidth width: Int) throws -> FigletSize {
    guard width > 0 else {
      throw FigletError.invalidConfiguration("width must be greater than zero")
    }

    let figlet = Figlet(
      font: font,
      configuration: FigletConfiguration(
        width: width,
        direction: configuration.direction,
        justification: configuration.justification
      )
    )
    return measureRenderedText(try figlet.render(text))
  }

  public static func availableFonts() -> [String] {
    FigletFont.bundledFontNames()
  }

  public static func availableFonts(fontLibraries: [FigletFontLibrary]) -> [String] {
    FigletFont.availableFontNames(fontLibraries: fontLibraries)
  }

  public static func availableFonts(
    searchDirectories: [String],
    fontLibraries: [FigletFontLibrary]
  ) -> [String] {
    FigletFont.availableFontNames(in: searchDirectories, libraries: fontLibraries)
  }

  private var resolvedDirection: ResolvedDirection {
    switch configuration.direction {
    case .leftToRight:
      return .leftToRight
    case .rightToLeft:
      return .rightToLeft
    case .automatic:
      return font.printDirection == 1 ? .rightToLeft : .leftToRight
    }
  }

  private var resolvedJustification: ResolvedJustification {
    switch configuration.justification {
    case .left:
      return .left
    case .center:
      return .center
    case .right:
      return .right
    case .automatic:
      return resolvedDirection == .leftToRight ? .left : .right
    }
  }

  private func minimumRenderableWidth(for text: String) -> Int {
    text.unicodeScalars.reduce(into: 0) { currentMaximum, scalar in
      currentMaximum = max(currentMaximum, font.widths[Int(scalar.value)] ?? 0)
    }
  }

  private func nonWrappingWidthUpperBound(for text: String) -> Int {
    text.unicodeScalars.reduce(into: 0) { total, scalar in
      total += font.widths[Int(scalar.value)] ?? 0
    }
  }
}

private enum ResolvedDirection: Sendable {
  case leftToRight
  case rightToLeft
}

private enum ResolvedJustification: Sendable {
  case left
  case center
  case right
}

private struct FigletLayoutEngine {
  private let text: [Int]
  private let font: FigletFont
  private let direction: ResolvedDirection
  private let width: Int
  private let justification: ResolvedJustification

  private var iterator = 0
  private var maxSmush = 0
  private var currentCharacterWidth = 0
  private var previousCharacterWidth = 0
  private var blankMarkers: [([[FigletCell]], Int)] = []
  private var productQueue: [[[FigletCell]]] = []
  private var buffer: [[FigletCell]]

  init(
    text: String,
    font: FigletFont,
    direction: ResolvedDirection,
    width: Int,
    justification: ResolvedJustification
  ) {
    self.text = text.unicodeScalars.map { Int($0.value) }
    self.font = font
    self.direction = direction
    self.width = width
    self.justification = justification
    self.buffer = Array(repeating: [], count: font.height)
  }

  mutating func renderSurface() throws -> FigletSurface {
    while iterator < text.count {
      try addCurrentCharacterToProduct()
      iterator += 1
    }

    if buffer.first?.isEmpty == false {
      productQueue.append(buffer)
    }

    return FigletSurface(rows: formatRows())
  }

  private mutating func addCurrentCharacterToProduct() throws {
    let currentCode = text[iterator]

    if currentCode == 10 {
      blankMarkers.append((buffer, iterator))
      handleNewline()
      return
    }

    guard let glyph = glyph(at: iterator) else {
      return
    }

    guard let glyphWidth = glyphWidth(at: iterator) else {
      return
    }

    if width < glyphWidth, let scalar = UnicodeScalar(currentCode) {
      throw FigletError.characterDoesNotFit(Character(scalar), width: width)
    }

    currentCharacterWidth = glyphWidth
    maxSmush = smushAmount(buffer: buffer, glyph: glyph)
    let nextWidth = buffer[0].count + currentCharacterWidth - maxSmush

    if currentCode == 32 {
      blankMarkers.append((buffer, iterator))
    }

    if nextWidth > width {
      handleNewline()
    } else {
      for row in 0..<font.height {
        addGlyphRow(glyph, row: row)
      }
    }

    previousCharacterWidth = currentCharacterWidth
  }

  private func formatRows() -> [[FigletCell]] {
    productQueue.flatMap { replaceHardBlanks(in: justify($0)) }
  }

  private func glyph(at index: Int) -> FigletGlyph? {
    guard index >= 0, index < text.count else {
      return nil
    }
    return font.glyphs[text[index]]
  }

  private func glyphWidth(at index: Int) -> Int? {
    guard index >= 0, index < text.count else {
      return nil
    }
    return font.widths[text[index]]
  }

  private func smushedLeftCell(at position: Int, in left: [FigletCell]) -> (FigletCell, Int)? {
    let index = left.count - maxSmush + position
    guard index >= 0, index < left.count else {
      return nil
    }
    return (left[index], index)
  }

  private mutating func addGlyphRow(_ glyph: FigletGlyph, row: Int) {
    var left = buffer[row]
    var right = glyph.rows[row]

    if direction == .rightToLeft {
      swap(&left, &right)
    }

    for position in 0..<maxSmush {
      let leftEntry = smushedLeftCell(at: position, in: left)
      let rightCell = right[position]
      let merged = smushedCell(left: leftEntry?.0, right: rightCell)

      if let merged, let leftIndex = leftEntry?.1 {
        left[leftIndex] = merged
      }
    }

    buffer[row] = left + Array(right.dropFirst(maxSmush))
  }

  private mutating func handleNewline() {
    if let (savedBuffer, savedIterator) = blankMarkers.popLast() {
      productQueue.append(savedBuffer)
      iterator = savedIterator
      resetBuffer()
    } else {
      productQueue.append(buffer)
      iterator -= 1
      resetBuffer()
    }
  }

  private mutating func resetBuffer() {
    buffer = Array(repeating: [], count: font.height)
    blankMarkers.removeAll(keepingCapacity: true)
    previousCharacterWidth = 0
    currentCharacterWidth = 0
    maxSmush = 0
  }

  private func justify(_ buffer: [[FigletCell]]) -> [[FigletCell]] {
    switch justification {
    case .left:
      return buffer
    case .right:
      return buffer.map { row in
        Array(repeating: FigletCell.space, count: max(0, width - row.count - 1)) + row
      }
    case .center:
      return buffer.map { row in
        Array(repeating: FigletCell.space, count: max(0, (width - row.count) / 2)) + row
      }
    }
  }

  private func replaceHardBlanks(in buffer: [[FigletCell]]) -> [[FigletCell]] {
    buffer.map { row in
      row.map { cell in
        guard cell.character == font.hardBlank else {
          return cell
        }
        var replacement = cell
        replacement.character = " "
        return replacement
      }
    }
  }

  private func smushAmount(buffer: [[FigletCell]], glyph: FigletGlyph) -> Int {
    let smushOrKern = smushMode(.smush) || smushMode(.kern)
    guard smushOrKern else {
      return 0
    }

    var maxSmush = currentCharacterWidth

    for row in 0..<font.height {
      var leftLine = buffer[row]
      var rightLine = glyph.rows[row]
      if direction == .rightToLeft {
        swap(&leftLine, &rightLine)
      }

      let leftCharacters = leftLine.map(\.character)
      let rightCharacters = rightLine.map(\.character)

      let lastNonSpaceIndex = leftCharacters.lastIndex(where: { $0 != " " }) ?? 0
      let leftCharacter =
        leftCharacters.indices.contains(lastNonSpaceIndex) ? leftCharacters[lastNonSpaceIndex] : nil

      let firstNonSpaceIndex =
        rightCharacters.firstIndex(where: { $0 != " " }) ?? rightCharacters.count
      let rightCharacter =
        rightCharacters.indices.contains(firstNonSpaceIndex)
        ? rightCharacters[firstNonSpaceIndex] : nil

      var amount = firstNonSpaceIndex + leftCharacters.count - 1 - lastNonSpaceIndex

      if leftCharacter == nil || leftCharacter == " " {
        amount += 1
      } else if let rightCharacter, smush(left: leftCharacter, right: rightCharacter) != nil {
        amount += 1
      }

      if amount < maxSmush {
        maxSmush = amount
      }
    }

    return maxSmush
  }

  private func smush(left: Character?, right: Character?) -> Character? {
    guard let right else {
      return left
    }

    if left == " " || left == nil {
      return right
    }

    guard let left else {
      return right
    }

    if right == " " {
      return left
    }

    if previousCharacterWidth < 2 || currentCharacterWidth < 2 {
      return nil
    }

    guard smushMode(.smush) else {
      return nil
    }

    if (font.smushMode & 63) == 0 {
      if left == font.hardBlank {
        return right
      }
      if right == font.hardBlank {
        return left
      }
      return direction == .rightToLeft ? left : right
    }

    if smushMode(.hardBlank), left == font.hardBlank, right == font.hardBlank {
      return left
    }

    if left == font.hardBlank || right == font.hardBlank {
      return nil
    }

    if smushMode(.equal), left == right {
      return left
    }

    if smushMode(.lowLine), left == "_", "|/\\[]{}()<>".contains(right) {
      return right
    }
    if smushMode(.lowLine), right == "_", "|/\\[]{}()<>".contains(left) {
      return left
    }

    let hierarchies: [(String, String)] = [
      ("|", "/\\[]{}()<>"),
      ("/\\", "[]{}()<>"),
      ("[]", "{}()<>"),
      ("{}", "()<>"),
      ("()", "<>"),
    ]
    if smushMode(.hierarchy) {
      for (dominant, recessive) in hierarchies {
        if dominant.contains(left), recessive.contains(right) {
          return right
        }
        if dominant.contains(right), recessive.contains(left) {
          return left
        }
      }
    }

    if smushMode(.pair) {
      let pair = String([left, right])
      let reversePair = String([right, left])
      if ["[]", "{}", "()"].contains(pair) || ["[]", "{}", "()"].contains(reversePair) {
        return "|"
      }
    }

    if smushMode(.bigX) {
      if left == "/", right == "\\" {
        return "|"
      }
      if left == "\\", right == "/" {
        return "Y"
      }
      if left == ">", right == "<" {
        return "X"
      }
    }

    return nil
  }

  private func smushedCell(left: FigletCell?, right: FigletCell) -> FigletCell? {
    guard let mergedCharacter = smush(left: left?.character, right: right.character) else {
      return nil
    }

    if let left, mergedCharacter == left.character {
      var mergedCell = left
      mergedCell.character = mergedCharacter
      return mergedCell
    }

    var mergedCell = right
    mergedCell.character = mergedCharacter
    return mergedCell
  }

  private func smushMode(_ mode: SmushMode) -> Bool {
    (font.smushMode & mode.rawValue) != 0
  }

  private enum SmushMode: Int {
    case equal = 1
    case lowLine = 2
    case hierarchy = 4
    case pair = 8
    case bigX = 16
    case hardBlank = 32
    case kern = 64
    case smush = 128
  }
}

private func measureRenderedText(_ text: FigletText) -> FigletSize {
  measureRows(renderedRows(from: text.rawValue))
}

private func renderedRows(from rawValue: String) -> [String] {
  var rows = rawValue.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  if rows.last == "" {
    rows.removeLast()
  }
  return rows
}

private func measureRows(_ rows: [String]) -> FigletSize {
  FigletSize(
    width: rows.map(\.count).max() ?? 0,
    height: rows.count
  )
}

private func measureCellRows(_ rows: [[FigletCell]]) -> FigletSize {
  FigletSize(
    width: rows.map(\.count).max() ?? 0,
    height: rows.count
  )
}

private func consumeLine(from lines: [String], index: inout Int) throws -> String {
  guard index < lines.count else {
    throw FigletError.invalidFont("unexpected end of font data")
  }
  defer { index += 1 }
  return lines[index]
}

private func consumeGlyph(from lines: [String], index: inout Int, height: Int) throws -> (
  width: Int, rows: [String]
) {
  var rows: [String] = []
  var width = 0
  var endMarker: Character?

  for _ in 0..<height {
    let rawLine = try consumeLine(from: lines, index: &index)
    if endMarker == nil {
      endMarker = rawLine.trimmingTrailingWhitespace().last
    }

    let stripped = stripEndMarker(from: rawLine, marker: endMarker ?? "@")
    rows.append(stripped)
    width = max(width, stripped.count)
  }

  return (width, rows)
}

private func stripEndMarker(from line: String, marker: Character) -> String {
  var characters = Array(line.trimmingTrailingWhitespace())

  if characters.last == marker {
    characters.removeLast()
  }
  if characters.last == marker {
    characters.removeLast()
  }

  return String(characters)
}

#if canImport(WASILibc)
  private let wasiExternalFontAccessError =
    "external font files are unavailable in WASI builds; use FigletFontLibrary or EmbeddedFonts"

  private func fileExists(at path: String) -> Bool {
    false
  }

  private func isDirectory(at path: String) -> Bool {
    false
  }

  private func directoryEntries(at path: String) -> [String] {
    []
  }

  private func readFile(at path: String) throws -> [UInt8] {
    throw FigletError.invalidConfiguration(wasiExternalFontAccessError)
  }

  private func environmentValue(named name: String) -> String? {
    nil
  }
#else
  private func fileExists(at path: String) -> Bool {
    unsafe path.withCString { unsafe access($0, F_OK) == 0 }
  }

  private func isDirectory(at path: String) -> Bool {
    guard let directory = unsafe opendir(path) else {
      return false
    }
    unsafe closedir(directory)
    return true
  }

  private func directoryEntries(at path: String) -> [String] {
    guard let directory = unsafe opendir(path) else {
      return []
    }
    defer { unsafe closedir(directory) }

    var entries: [String] = []
    while let entryPointer = unsafe readdir(directory) {
      let name = unsafe withUnsafePointer(to: &entryPointer.pointee.d_name) { pointer in
        unsafe pointer.withMemoryRebound(
          to: CChar.self, capacity: MemoryLayout.size(ofValue: entryPointer.pointee.d_name)
        ) {
          unsafe String(cString: $0)
        }
      }

      if name != "." && name != ".." {
        entries.append(name)
      }
    }

    return entries
  }

  private func readFile(at path: String) throws -> [UInt8] {
    guard let file = unsafe fopen(path, "rb") else {
      throw FigletError.invalidFont("unable to read font at \(path)")
    }
    defer { unsafe fclose(file) }

    guard unsafe fseek(file, 0, SEEK_END) == 0 else {
      throw FigletError.invalidFont("unable to read font at \(path)")
    }

    let size = unsafe ftell(file)
    guard size >= 0 else {
      throw FigletError.invalidFont("unable to read font at \(path)")
    }

    unsafe rewind(file)

    var buffer = [UInt8](repeating: 0, count: Int(size))
    let bufferCount = buffer.count
    guard bufferCount > 0 else {
      return []
    }
    let bytesRead = unsafe buffer.withUnsafeMutableBytes { bytes in
      unsafe fread(bytes.baseAddress!, 1, bufferCount, file)
    }

    return Array(buffer.prefix(bytesRead))
  }

  private func environmentValue(named name: String) -> String? {
    guard let value = unsafe getenv(name) else {
      return nil
    }
    return unsafe String(cString: value)
  }
#endif

private func pathByAppending(_ base: String, _ component: String) -> String {
  if component.hasPrefix("/") {
    return component
  }
  if base.isEmpty || base == "." {
    return component
  }
  if component == ".." {
    return base.deletingLastPathComponent
  }
  if component.hasPrefix("../") {
    return pathByAppending(base.deletingLastPathComponent, String(component.dropFirst(3)))
  }
  if base.hasSuffix("/") {
    return base + component
  }
  return base + "/" + component
}

private func uniquePaths(_ paths: [String]) -> [String] {
  var seen = Set<String>()
  var result: [String] = []

  for path in paths where !path.isEmpty {
    let normalized = path.normalizedPath
    if seen.insert(normalized).inserted {
      result.append(normalized)
    }
  }

  return result
}

extension String {
  fileprivate func sanitizedFontData() -> String {
    var characters: [Character] = []
    let source = Array(self)
    var index = 0

    while index < source.count {
      let character = source[index]

      switch character {
      case "\r":
        if index + 1 < source.count, source[index + 1] == "\n" {
          index += 1
        }
        characters.append("\n")
      case "\u{0085}", "\u{2028}", "\u{2029}":
        characters.append(" ")
      default:
        characters.append(character)
      }

      index += 1
    }

    return String(characters)
  }

  fileprivate func trimmingTrailingWhitespace() -> String {
    var characters = Array(self)
    while let last = characters.last, last == " " || last == "\t" {
      characters.removeLast()
    }
    return String(characters)
  }

  fileprivate func trimmingFigletWhitespace() -> String {
    let characters = Array(self)
    var start = 0
    var end = characters.count

    while start < end, characters[start].isFigletWhitespace {
      start += 1
    }

    while end > start, characters[end - 1].isFigletWhitespace {
      end -= 1
    }

    return String(characters[start..<end])
  }

  fileprivate func trimmingTrailingWhitespaceAndNewlines() -> String {
    var value = self
    while let last = value.last, last.isFigletWhitespaceOrNewline {
      value.removeLast()
    }
    return value
  }

  fileprivate var lastPathComponentWithoutExtension: String {
    let lastComponent = split(separator: "/").last.map(String.init) ?? self
    guard let dotIndex = lastComponent.lastIndex(of: ".") else {
      return lastComponent
    }
    return String(lastComponent[..<dotIndex])
  }

  fileprivate var deletingLastPathComponent: String {
    guard let slashIndex = lastIndex(of: "/") else {
      return "."
    }
    if slashIndex == startIndex {
      return "/"
    }
    return String(self[..<slashIndex])
  }

  fileprivate var normalizedPath: String {
    let absolute = hasPrefix("/")
    var components: [Substring] = []

    for component in split(separator: "/", omittingEmptySubsequences: true) {
      if component == "." {
        continue
      }
      if component == ".." {
        if !components.isEmpty {
          components.removeLast()
        }
        continue
      }
      components.append(component)
    }

    let joined = components.joined(separator: "/")
    if absolute {
      return "/" + joined
    }
    return joined.isEmpty ? (absolute ? "/" : ".") : joined
  }

  fileprivate var hasSupportedFontExtension: Bool {
    supportedFontExtensions.contains { hasSuffix(".\($0)") }
  }
}

extension Substring {
  fileprivate var containsNonWhitespace: Bool {
    contains { !$0.isFigletWhitespace }
  }
}

extension Character {
  fileprivate var isFigletWhitespace: Bool {
    self == " " || self == "\t"
  }

  fileprivate var isFigletWhitespaceOrNewline: Bool {
    isFigletWhitespace || self == "\n" || self == "\r"
  }
}
