import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore

/// Field-coverage totality lock for every hand-maintained mirror of
/// `PlacedNode`'s stored fields (F133). Three mirrors each encode a deliberate
/// per-field policy but nothing forced a newly added stored field to be
/// classified — `lazyChildScrollEstimates` shipped consumed by the semantic
/// extractor yet invisible to the phase-reuse signature AND to `==`, so an
/// out-of-window lazy row identity change proved `.wholeTreeIdentical` and
/// served a stale `SemanticSnapshot` (`scrollTo(newID)` no-oped). This suite
/// derives the canonical field set from the production source (the F96
/// technique; parsing helpers are file-private per this target's convention —
/// consolidation candidate with `ResolvedNodePhaseOwnershipTests` /
/// `RetainedReuseInvariantTests`) and requires every mirror to mention or
/// explicitly exempt every stored field.
@Suite("PlacedNode mirror totality")
struct PlacedNodeMirrorTotalityTests {
  private static let placedNodePath = "Sources/SwiftTUICore/Place/PlacedNode.swift"
  private static let extractionPath = "Sources/SwiftTUICore/Commit/RetainedPhaseExtraction.swift"

  /// Stored properties whose public surface goes by another name: mirrors
  /// reference the computed accessor, not the storage.
  private static let storageAliases: [String: String] = [
    "_semanticMetadata": "semanticMetadata",
    "_boxedLayoutBehavior": "layoutBehavior",
  ]

  /// Per-mirror exemption manifests: stored fields the mirror deliberately
  /// does NOT carry, each with the reason. A field missing from both the
  /// mirror text and its manifest fails the totality test.
  private static let exemptions: [String: [String: String]] = [
    "signature": [
      "viewNodeID":
        "runtime node stamp — retained phase products are keyed and reused by authored "
        + "identity; a re-minted node with byte-identical content reuses them deliberately",
      "subtreeBounds":
        "derived cache recomputed from bounds/children didSets — the walk compares every "
        + "node's bounds, which subsumes it",
    ],
    "==": [
      "viewNodeID":
        "runtime node stamp, re-assigned on adoption — mirrors ResolvedNode.== policy",
      "subtreeBounds":
        "derived cache recomputed from bounds/children didSets — comparing bounds and "
        + "children subsumes it",
    ],
    "resolvedMetadata": [
      "identity": "placement-owned: the placement key, not resolved-projected metadata",
      "bounds": "placement-owned geometry (the type doc: placement owns final bounds)",
      "contentBounds": "placement-owned geometry",
      "clipBounds": "placement-owned geometry (clipping)",
      "zIndex": "placement-owned geometry (z-order)",
      "children": "placement-owned (child placement)",
      "subtreeNodeCount": "derived cache recomputed from placement geometry",
      "subtreeBounds": "derived cache recomputed from placement geometry",
      "lazyChildScrollEstimates":
        "placement-owned: populated by the layout engine's lazy allocation loop, not "
        + "projected from the resolved node",
    ],
  ]

  private func placedNodeFieldNames() throws -> [String] {
    try parsedStoredVarNames(
      typeKind: "struct",
      typeName: "PlacedNode",
      relativePath: Self.placedNodePath
    ).map { Self.storageAliases[$0] ?? $0 }
  }

  /// The mirror's source text to mention-check, per mirror key.
  private func mirrorText(for mirror: String) throws -> String {
    switch mirror {
    case "signature":
      // The signature struct's field list plus the `make` walk that populates
      // it — a field is covered when either names it.
      let source = try sourceText(relativePath: Self.extractionPath)
      let structBody = try typeBody(kind: "struct", name: "NodeSignature", in: source)
      let makeBody = functionBodyText(named: "make", in: source)
      return structBody + "\n" + makeBody
    case "==":
      let source = try sourceText(relativePath: Self.placedNodePath)
      return functionBodyText(named: "==", in: source)
    case "resolvedMetadata":
      // The projection type's own stored fields are the mirror list; the
      // existing round-trip + manifest tests in `RetainedReuseInvariantTests`
      // tie the getter/applier to that list.
      let source = try sourceText(relativePath: Self.placedNodePath)
      return try typeBody(kind: "struct", name: "PlacedNodeResolvedMetadata", in: source)
    default:
      return ""
    }
  }

  @Test(
    "every stored field is mirrored or explicitly exempted, per mirror",
    arguments: ["signature", "==", "resolvedMetadata"])
  func mirrorIsFieldTotal(mirror: String) throws {
    let fields = try placedNodeFieldNames()
    #expect(Set(fields).count == fields.count)
    #expect(fields.count >= 20, "parser found implausibly few stored fields: \(fields)")
    #expect(
      fields.contains("lazyChildScrollEstimates"),
      "parser lost the F133 field — check the stored-property discrimination"
    )

    let body = try mirrorText(for: mirror)
    #expect(!body.isEmpty, "could not locate the \(mirror) mirror source")

    let exempt = Self.exemptions[mirror] ?? [:]
    for field in fields {
      let mentioned = body.contains(field)
      let isExempt = exempt[field] != nil
      #expect(
        mentioned || isExempt,
        "\(mirror) neither carries nor exempts PlacedNode.\(field) — classify the field: mirror it, or add it to this suite's exemption manifest with a reason."
      )
      #expect(
        !(mentioned && isExempt),
        "\(mirror) both carries and exempts PlacedNode.\(field) — the manifest has drifted from the mirror; remove the stale exemption."
      )
    }
  }

  @Test("exemption manifests only name real stored fields (no stale entries)")
  func exemptionManifestsNameRealFields() throws {
    let fields = Set(try placedNodeFieldNames())
    for (mirror, exempt) in Self.exemptions {
      for field in exempt.keys {
        #expect(
          fields.contains(field),
          "\(mirror) exempts '\(field)', which is not a stored PlacedNode field — remove or rename the manifest entry."
        )
      }
    }
  }

  @Test("totality guard has teeth: an unclassified field fails the check")
  func totalityGuardCatchesUnclassifiedField() throws {
    let fields = try placedNodeFieldNames()
    let body = try mirrorText(for: "signature")
    let exempt = Self.exemptions["signature"] ?? [:]
    let phantom = "phantomNewField"
    #expect(!fields.contains(phantom))
    #expect(!(body.contains(phantom) || exempt[phantom] != nil))
  }
}

// MARK: - File-private source parsing (SourceParsingTestSupport pattern)

private func parsedStoredVarNames(
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

private func parsedStoredPropertyName(from line: String) -> String? {
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

/// A property whose accessor block is only `didSet`/`willSet` observers still
/// counts as stored; computed properties (get/set accessors) are excluded.
private func isStoredPropertyDeclaration(
  lines: [String],
  startingAt index: Int
) -> Bool {
  let line = lines[index]
  guard line.contains("{") else {
    return true
  }
  var depth = 0
  var accessorLines: [String] = []
  for accessorLine in lines[index...] {
    accessorLines.append(accessorLine)
    depth += braceDelta(in: accessorLine)
    if depth == 0 {
      break
    }
  }
  let accessorBody = accessorLines.joined(separator: "\n")
  return accessorBody.contains("didSet") || accessorBody.contains("willSet")
}

/// Returns the source text of the first `func <name>(` and its body
/// (balanced braces), or "" if not found.
private func functionBodyText(named name: String, in source: String) -> String {
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

private func typeBody(
  kind: String,
  name: String,
  in source: String
) throws -> String {
  // Boundary-aware match: `struct PlacedNode` must not match
  // `struct PlacedNodeResolvedMetadata` earlier in the same file.
  var searchRange = source.startIndex..<source.endIndex
  var declaration: Range<String.Index>?
  while let candidate = source.range(of: "\(kind) \(name)", range: searchRange) {
    let after = candidate.upperBound
    let isBoundary: Bool
    if after == source.endIndex {
      isBoundary = true
    } else {
      let next = source[after]
      isBoundary = !(next.isLetter || next.isNumber || next == "_")
    }
    if isBoundary {
      declaration = candidate
      break
    }
    searchRange = candidate.upperBound..<source.endIndex
  }
  guard let declaration else {
    throw MirrorTotalityParseError.missingType(kind: kind, name: name)
  }
  guard let openingBrace = source[declaration.upperBound...].firstIndex(of: "{") else {
    throw MirrorTotalityParseError.missingOpeningBrace(kind: kind, name: name)
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
  throw MirrorTotalityParseError.missingClosingBrace(kind: kind, name: name)
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

private func repositoryRoot() throws -> URL {
  var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  while directory.path != "/" {
    if FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("Package.swift").path
    ) {
      return directory
    }
    directory.deleteLastPathComponent()
  }
  throw MirrorTotalityParseError.missingPackageRoot
}

private enum MirrorTotalityParseError: Error {
  case missingPackageRoot
  case missingType(kind: String, name: String)
  case missingOpeningBrace(kind: String, name: String)
  case missingClosingBrace(kind: String, name: String)
}
