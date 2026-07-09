import Foundation

/// Shared source-parsing support for totality-lock suites (checkpoint
/// totality, comparator totality). These locks parse the production source
/// text for stored-property declarations and function bodies so a newly added
/// field cannot silently fall out of a hand-maintained mirror (a checkpoint, a
/// debug snapshot, an equivalence comparator) — the canonical covered set is
/// derived from the source itself, never from a second hand-written list.
///
/// Namespaced as enum statics because two older suites
/// (`ResolvedNodePhaseOwnershipTests`, `RetainedReuseInvariantTests`) still
/// carry file-private copies of similar helpers; bare module-scope functions
/// with the same signatures would collide with them.
enum SourceParsingTestSupport {
  /// Returns the source text of the first `func <name>(` and its body
  /// (balanced braces), or "" if not found. Tolerates the formatter's
  /// operator spacing (`static func == (lhs:` declares `==` with a space
  /// before the paren).
  static func functionBodyText(named name: String, in source: String) -> String {
    let lines = source.components(separatedBy: .newlines)
    guard
      let start = lines.firstIndex(where: { line in
        line.contains("func \(name)(") || line.contains("func \(name) (")
      })
    else {
      return ""
    }
    var depth = 0
    var started = false
    var collected: [String] = []
    for line in lines[start...] {
      collected.append(line)
      if line.contains("{") {
        started = true
      }
      depth += braceDelta(in: line)
      if started && depth <= 0 {
        break
      }
    }
    return collected.joined(separator: "\n")
  }

  /// Parses the stored `var`/`let` declarations of one type's body. A
  /// property whose accessor block is only `didSet`/`willSet` observers still
  /// counts as stored; computed properties (get/set accessors) are excluded.
  static func parsedStoredVarNames(
    typeKind: String,
    typeName: String,
    relativePath: String
  ) throws -> [String] {
    let source = try sourceText(relativePath: relativePath)
    let body = try typeBody(kind: typeKind, name: typeName, in: source)
    let lines = body.components(separatedBy: .newlines)
    var fields: [String] = []
    var depth = 0

    for (index, line) in lines.enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if depth == 0,
        let field = parsedStoredPropertyName(from: trimmed),
        isStoredPropertyDeclaration(lines: lines, startingAt: index)
      {
        fields.append(field)
      }
      depth += braceDelta(in: line)
    }

    return fields
  }

  static func braceDelta(in line: String) -> Int {
    line.reduce(0) { partial, character in
      switch character {
      case "{":
        partial + 1
      case "}":
        partial - 1
      default:
        partial
      }
    }
  }

  static func sourceText(relativePath: String) throws -> String {
    let root = try repositoryRoot()
    let url = root.appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
  }

  static func typeBody(
    kind: String,
    name: String,
    in source: String
  ) throws -> String {
    guard let declaration = source.range(of: "\(kind) \(name)") else {
      throw SourceParseError.missingType(kind: kind, name: name)
    }
    guard let openingBrace = source[declaration.upperBound...].firstIndex(of: "{") else {
      throw SourceParseError.missingOpeningBrace(kind: kind, name: name)
    }

    var depth = 0
    var index = openingBrace
    while index < source.endIndex {
      let character = source[index]
      if character == "{" {
        depth += 1
      } else if character == "}" {
        depth -= 1
        if depth == 0 {
          let bodyStart = source.index(after: openingBrace)
          return String(source[bodyStart..<index])
        }
      }
      index = source.index(after: index)
    }
    throw SourceParseError.missingClosingBrace(kind: kind, name: name)
  }

  static func repositoryRoot() throws -> URL {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
      if FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("Package.swift").path
      ) {
        return directory
      }
      directory.deleteLastPathComponent()
    }
    throw SourceParseError.missingPackageRoot
  }

  enum SourceParseError: Error {
    case missingPackageRoot
    case missingType(kind: String, name: String)
    case missingOpeningBrace(kind: String, name: String)
    case missingClosingBrace(kind: String, name: String)
  }

  private static func parsedStoredPropertyName(from line: String) -> String? {
    guard !line.hasPrefix("//") else { return nil }
    let tokens = line.split(whereSeparator: \.isWhitespace)
    guard
      let declarationIndex = tokens.firstIndex(where: { token in
        token == "var" || token == "let"
      }),
      tokens.indices.contains(tokens.index(after: declarationIndex))
    else {
      return nil
    }
    let nameToken = tokens[tokens.index(after: declarationIndex)]
    return String(nameToken.prefix { $0 != ":" && $0 != "=" && $0 != "{" })
  }

  private static func isStoredPropertyDeclaration(
    lines: [String],
    startingAt index: Int
  ) -> Bool {
    let line = lines[index]
    guard line.contains("{") else {
      return true
    }
    let accessorBody = propertyAccessorBody(lines: lines, startingAt: index)
    if accessorBody.contains("didSet") || accessorBody.contains("willSet") {
      return true
    }
    return false
  }

  private static func propertyAccessorBody(
    lines: [String],
    startingAt index: Int
  ) -> String {
    var depth = 0
    var collected: [String] = []
    for line in lines[index...] {
      collected.append(line)
      depth += braceDelta(in: line)
      if depth == 0 {
        break
      }
    }
    return collected.joined(separator: "\n")
  }
}
