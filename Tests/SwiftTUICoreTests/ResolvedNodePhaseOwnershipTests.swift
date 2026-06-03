import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore

@Suite("ResolvedNode phase ownership")
struct ResolvedNodePhaseOwnershipTests {
  @Test("ResolvedNode stored fields have one phase ownership classification")
  func resolvedNodeStoredFieldsHaveOnePhaseOwnershipClassification() throws {
    let parsedFields = try parsedResolvedNodeStoredFields()
    let manifestFields = resolvedNodePhaseOwnershipManifest.map(\.field)

    #expect(parsedFields == manifestFields)
    #expect(Set(manifestFields).count == manifestFields.count)
  }
}

private enum ResolvedNodePhaseOwnership: String {
  case runtime
  case identity
  case structure
  case measurement
  case placement
  case semantics
  case draw
  case lifecycle
  case damage
  case commit
  case diagnostics
  case derivedCache
}

// Adding a ResolvedNode field is an architecture decision: record the phase
// owner here before relying on later pipeline products to mirror or ignore it.
private let resolvedNodePhaseOwnershipManifest:
  [(field: String, owner: ResolvedNodePhaseOwnership)] = [
    ("viewNodeID", .runtime),
    ("identity", .identity),
    ("structuralPath", .structure),
    ("structuralEdgeRole", .structure),
    ("entityIdentity", .identity),
    ("entityStructuralPath", .structure),
    ("declarationOwnerEdge", .structure),
    ("kind", .structure),
    ("typeDiscriminator", .structure),
    ("_storedChildren", .structure),
    ("environmentSnapshot", .semantics),
    ("transactionSnapshot", .commit),
    ("_storedLayoutBehavior", .measurement),
    ("layoutMetadata", .measurement),
    ("_boxedDrawMetadata", .draw),
    ("drawEffects", .draw),
    ("surfaceComposition", .damage),
    ("semanticMetadata", .semantics),
    ("lifecycleMetadata", .lifecycle),
    ("drawPayload", .draw),
    ("intrinsicSize", .measurement),
    ("indexedChildSource", .measurement),
    ("layoutDependentContent", .measurement),
    ("preferenceValues", .derivedCache),
    ("subtreeNodeCount", .derivedCache),
    ("customLayoutFallbackSummary", .derivedCache),
    ("supportsRetainedReuse", .derivedCache),
    ("matchedGeometry", .placement),
    ("isTransient", .semantics),
  ]

private func parsedResolvedNodeStoredFields() throws -> [String] {
  let source = try sourceText(relativePath: "Sources/SwiftTUICore/Resolve/ResolvedNode.swift")
  let body = try topLevelBody(named: "ResolvedNode", in: source)
  let lines = body.components(separatedBy: .newlines)
  var fields: [String] = []
  var depth = 0

  for (index, line) in lines.enumerated() {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if depth == 0,
      let field = parsedVarName(from: trimmed),
      isStoredPropertyDeclaration(lines: lines, startingAt: index)
    {
      fields.append(field)
    }
    depth += braceDelta(in: line)
  }
  return fields
}

private func parsedVarName(from line: String) -> String? {
  guard !line.hasPrefix("//") else { return nil }
  let tokens = line.split(whereSeparator: \.isWhitespace)
  guard let varIndex = tokens.firstIndex(of: "var"),
    tokens.indices.contains(tokens.index(after: varIndex))
  else {
    return nil
  }
  let nameToken = tokens[tokens.index(after: varIndex)]
  return String(nameToken.prefix { $0 != ":" && $0 != "=" && $0 != "{" })
}

private func isStoredPropertyDeclaration(
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

private func propertyAccessorBody(
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

private func braceDelta(in line: String) -> Int {
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

private func sourceText(relativePath: String) throws -> String {
  let root = try repositoryRoot()
  let url = root.appendingPathComponent(relativePath)
  return try String(contentsOf: url, encoding: .utf8)
}

private func topLevelBody(
  named structName: String,
  in source: String
) throws -> String {
  guard let declaration = source.range(of: "struct \(structName)") else {
    throw TestSourceParseError.missingStruct(structName)
  }
  guard let openingBrace = source[declaration.upperBound...].firstIndex(of: "{") else {
    throw TestSourceParseError.missingOpeningBrace(structName)
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
  throw TestSourceParseError.missingClosingBrace(structName)
}

private func repositoryRoot() throws -> URL {
  var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  while directory.path != "/" {
    if FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("Package.swift").path)
    {
      return directory
    }
    directory.deleteLastPathComponent()
  }
  throw TestSourceParseError.missingPackageRoot
}

private enum TestSourceParseError: Error {
  case missingPackageRoot
  case missingStruct(String)
  case missingOpeningBrace(String)
  case missingClosingBrace(String)
}
