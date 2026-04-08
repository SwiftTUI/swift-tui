public import Foundation

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

public struct FigletText: CustomStringConvertible, Equatable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }

    public func reversed() -> FigletText {
        let rows = rawValue.split(separator: "\n", omittingEmptySubsequences: false)
        let reversedRows = rows.map { row in
            String(row.map(Self.reverseMap).reversed())
        }
        return FigletText(reversedRows.joined(separator: "\n"))
    }

    public func flipped() -> FigletText {
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
            if !row.trimmingCharacters(in: .whitespaces).isEmpty || sawContent {
                sawContent = true
                output.append(row)
            }
        }

        return output.joined(separator: "\n").trimmingTrailingWhitespaceAndNewlines()
    }

    public func normalizingSurroundingNewlines() -> String {
        "\n\(strippingSurroundingNewlines())\n"
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

public struct FigletFont: Sendable {
    public static let defaultFontName = "standard"

    public let name: String
    public let height: Int
    public let baseline: Int
    public let hardBlank: Character
    public let printDirection: Int?
    public let smushMode: Int
    public let comment: String

    let characters: [Int: [String]]
    let widths: [Int: Int]

    public init(named name: String) throws {
        self = try Self.load(identifier: name)
    }

    public init(fileURL: URL) throws {
        self = try Self.load(fileURL: fileURL, fallbackName: fileURL.deletingPathExtension().lastPathComponent)
    }

    public var info: String {
        comment
    }

    public static func bundledFontNames() -> [String] {
        guard let resourceURL = Bundle.module.resourceURL else {
            return [defaultFontName]
        }

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: resourceURL,
            includingPropertiesForKeys: nil
        )) ?? []

        return urls
            .filter { ["flf", "tlf"].contains($0.pathExtension.lowercased()) }
            .map { $0.deletingPathExtension().lastPathComponent }
            .reduce(into: Set<String>()) { result, name in
                result.insert(name)
            }
            .sorted()
    }

    static func load(identifier: String) throws -> FigletFont {
        if let fileURL = resolveExternalFontURL(for: identifier) {
            return try load(fileURL: fileURL, fallbackName: fileURL.deletingPathExtension().lastPathComponent)
        }

        for ext in ["flf", "tlf"] {
            if let resourceURL = Bundle.module.url(forResource: identifier, withExtension: ext, subdirectory: "Fonts") {
                return try load(fileURL: resourceURL, fallbackName: identifier)
            }
            if let resourceURL = Bundle.module.url(forResource: identifier, withExtension: ext) {
                return try load(fileURL: resourceURL, fallbackName: identifier)
            }
        }

        throw FigletError.fontNotFound(identifier)
    }

    private static func load(fileURL: URL, fallbackName: String) throws -> FigletFont {
        let data: String
        do {
            data = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw FigletError.invalidFont("unable to read font at \(fileURL.path)")
        }

        return try parse(data: data, name: fallbackName)
    }

    private static func resolveExternalFontURL(for identifier: String) -> URL? {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: identifier) {
            return URL(fileURLWithPath: identifier)
        }

        for ext in ["flf", "tlf"] {
            let candidate = "\(identifier).\(ext)"
            if fileManager.fileExists(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        return nil
    }

    private static func parse(data: String, name: String) throws -> FigletFont {
        let sanitized = data
            .replacingOccurrences(of: "\u{0085}", with: " ")
            .replacingOccurrences(of: "\u{2028}", with: " ")
            .replacingOccurrences(of: "\u{2029}", with: " ")
            .normalizedNewlines()

        var lines = ArraySlice(sanitized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))

        let headerLine = try consumeLine(from: &lines)
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
            commentLinesBuffer.append(try consumeLine(from: &lines))
        }

        var characters: [Int: [String]] = [:]
        var widths: [Int: Int] = [:]

        for codePoint in 32..<127 {
            let glyph = try consumeGlyph(from: &lines, height: height)
            if codePoint == 32 || !glyph.rows.joined().isEmpty {
                characters[codePoint] = glyph.rows
                widths[codePoint] = glyph.width
            }
        }

        for character in ["Ä", "Ö", "Ü", "ä", "ö", "ü", "ß"] {
            guard !lines.isEmpty else { break }
            let glyph = try consumeGlyph(from: &lines, height: height)
            if !glyph.rows.joined().isEmpty, let scalar = character.unicodeScalars.first {
                characters[Int(scalar.value)] = glyph.rows
                widths[Int(scalar.value)] = glyph.width
            }
        }

        while !lines.isEmpty {
            let definition = try consumeLine(from: &lines).trimmingCharacters(in: .whitespaces)
            guard !definition.isEmpty else {
                continue
            }

            guard let identifier = definition.split(separator: " ", maxSplits: 1).first else {
                continue
            }

            let token = String(identifier)
            guard token.lowercased().hasPrefix("0x"), let codePoint = Int(token.dropFirst(2), radix: 16) else {
                continue
            }

            let glyph = try consumeGlyph(from: &lines, height: height)
            if !glyph.rows.joined().isEmpty {
                characters[codePoint] = glyph.rows
                widths[codePoint] = glyph.width
            }
        }

        return FigletFont(
            name: name,
            height: height,
            baseline: baseline,
            hardBlank: hardBlank,
            printDirection: printDirection,
            smushMode: smushMode,
            comment: commentLinesBuffer.joined(separator: "\n"),
            characters: characters,
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
        characters: [Int: [String]],
        widths: [Int: Int]
    ) {
        self.name = name
        self.height = height
        self.baseline = baseline
        self.hardBlank = hardBlank
        self.printDirection = printDirection
        self.smushMode = smushMode
        self.comment = comment
        self.characters = characters
        self.widths = widths
    }
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

    public init(font: FigletFont, configuration: FigletConfiguration = FigletConfiguration()) {
        self.font = font
        self.configuration = configuration
    }

    public func render(_ text: String) throws -> FigletText {
        guard configuration.width > 0 else {
            throw FigletError.invalidConfiguration("width must be greater than zero")
        }

        var builder = FigletBuilder(
            text: text,
            font: font,
            direction: resolvedDirection,
            width: configuration.width,
            justification: resolvedJustification
        )
        return try builder.render()
    }

    public static func availableFonts() -> [String] {
        FigletFont.bundledFontNames()
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

private struct FigletBuilder {
    private let text: [Int]
    private let font: FigletFont
    private let direction: ResolvedDirection
    private let width: Int
    private let justification: ResolvedJustification

    private var iterator = 0
    private var maxSmush = 0
    private var currentCharacterWidth = 0
    private var previousCharacterWidth = 0
    private var blankMarkers: [([String], Int)] = []
    private var productQueue: [[String]] = []
    private var buffer: [String]

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
        self.buffer = Array(repeating: "", count: font.height)
    }

    mutating func render() throws -> FigletText {
        while iterator < text.count {
            try addCurrentCharacterToProduct()
            iterator += 1
        }

        if buffer.first?.isEmpty == false {
            productQueue.append(buffer)
        }

        return FigletText(formatProduct())
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

        if nextWidth >= width {
            handleNewline()
        } else {
            for row in 0..<font.height {
                addGlyphRow(glyph, row: row)
            }
        }

        previousCharacterWidth = currentCharacterWidth
    }

    private func formatProduct() -> String {
        productQueue.reduce(into: "") { result, queuedBuffer in
            let justified = justify(queuedBuffer)
            result += replaceHardBlanks(in: justified)
        }
    }

    private func glyph(at index: Int) -> [String]? {
        guard index >= 0, index < text.count else {
            return nil
        }
        return font.characters[text[index]]
    }

    private func glyphWidth(at index: Int) -> Int? {
        guard index >= 0, index < text.count else {
            return nil
        }
        return font.widths[text[index]]
    }

    private func smushedLeftCharacter(at position: Int, in left: String) -> (Character, Int)? {
        let index = left.count - maxSmush + position
        let characters = Array(left)
        guard index >= 0, index < characters.count else {
            return nil
        }
        return (characters[index], index)
    }

    private mutating func addGlyphRow(_ glyph: [String], row: Int) {
        var left = buffer[row]
        var right = glyph[row]

        if direction == .rightToLeft {
            swap(&left, &right)
        }

        for position in 0..<maxSmush {
            let leftEntry = smushedLeftCharacter(at: position, in: left)
            let rightCharacters = Array(right)
            let rightCharacter = rightCharacters[position]
            let merged = smush(left: leftEntry?.0, right: rightCharacter)

            if let merged, let leftIndex = leftEntry?.1 {
                left = left.replacingCharacter(at: leftIndex, with: merged)
            }
        }

        buffer[row] = left + String(Array(right).dropFirst(maxSmush))
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
        buffer = Array(repeating: "", count: font.height)
        blankMarkers.removeAll(keepingCapacity: true)
        previousCharacterWidth = 0
        currentCharacterWidth = 0
        maxSmush = 0
    }

    private func justify(_ buffer: [String]) -> [String] {
        switch justification {
        case .left:
            return buffer
        case .right:
            return buffer.map { row in
                String(repeating: " ", count: max(0, width - row.count - 1)) + row
            }
        case .center:
            return buffer.map { row in
                String(repeating: " ", count: max(0, (width - row.count) / 2)) + row
            }
        }
    }

    private func replaceHardBlanks(in buffer: [String]) -> String {
        let output = buffer.joined(separator: "\n") + "\n"
        return output.replacingOccurrences(of: String(font.hardBlank), with: " ")
    }

    private func smushAmount(buffer: [String], glyph: [String]) -> Int {
        let smushOrKern = smushMode(.smush) || smushMode(.kern)
        guard smushOrKern else {
            return 0
        }

        var maxSmush = currentCharacterWidth

        for row in 0..<font.height {
            var leftLine = buffer[row]
            var rightLine = glyph[row]
            if direction == .rightToLeft {
                swap(&leftLine, &rightLine)
            }

            let leftCharacters = Array(leftLine)
            let rightCharacters = Array(rightLine)

            let lastNonSpaceIndex = leftCharacters.lastIndex(where: { $0 != " " }) ?? 0
            let leftCharacter = leftCharacters.indices.contains(lastNonSpaceIndex) ? leftCharacters[lastNonSpaceIndex] : nil

            let firstNonSpaceIndex = rightCharacters.firstIndex(where: { $0 != " " }) ?? rightCharacters.count
            let rightCharacter = rightCharacters.indices.contains(firstNonSpaceIndex) ? rightCharacters[firstNonSpaceIndex] : nil

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

private func consumeLine(from lines: inout ArraySlice<String>) throws -> String {
    guard let line = lines.popFirst() else {
        throw FigletError.invalidFont("unexpected end of font data")
    }
    return line
}

private func consumeGlyph(from lines: inout ArraySlice<String>, height: Int) throws -> (width: Int, rows: [String]) {
    var rows: [String] = []
    var width = 0
    var endMarker: Character?

    for _ in 0..<height {
        let rawLine = try consumeLine(from: &lines)
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

private extension String {
    func normalizedNewlines() -> String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    func trimmingTrailingWhitespace() -> String {
        var characters = Array(self)
        while let last = characters.last, last == " " || last == "\t" {
            characters.removeLast()
        }
        return String(characters)
    }

    func replacingCharacter(at index: Int, with replacement: Character) -> String {
        var characters = Array(self)
        guard characters.indices.contains(index) else {
            return self
        }
        characters[index] = replacement
        return String(characters)
    }

    func trimmingTrailingWhitespaceAndNewlines() -> String {
        var value = self
        while let last = value.last, last.isWhitespace || last.isNewline {
            value.removeLast()
        }
        return value
    }
}
