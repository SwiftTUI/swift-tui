import Foundation
import Testing

@testable import SwiftTUICore

@MainActor
@Suite("ViewGraph checkpoint totality")
struct ViewGraphCheckpointTotalityTests {
  @Test("ViewGraph and ViewNode mutable fields are checkpoint-covered")
  func mutableFieldsAreCheckpointCovered() throws {
    let viewGraphFields = try parsedStoredVarNames(
      typeKind: "class",
      typeName: "ViewGraph",
      relativePath: "Sources/SwiftTUICore/Resolve/ViewGraph.swift"
    )
    let viewGraphCheckpointFields = try parsedStoredVarNames(
      typeKind: "struct",
      typeName: "Checkpoint",
      relativePath: "Sources/SwiftTUICore/Resolve/ViewGraphState.swift"
    )
    let viewGraphDebugFields = try parsedStoredVarNames(
      typeKind: "struct",
      typeName: "DebugTotalStateSnapshot",
      relativePath: "Sources/SwiftTUICore/Resolve/ViewGraphDebugSnapshots.swift"
    )

    #expect(Set(viewGraphFields).count == viewGraphFields.count)
    #expect(Set(viewGraphCheckpointFields).count == viewGraphCheckpointFields.count)
    #expect(Set(viewGraphDebugFields).count == viewGraphDebugFields.count)
    #expect(Set(viewGraphCheckpointFields) == Set(viewGraphFields + ["nodeCheckpoints"]))
    #expect(Set(viewGraphDebugFields) == Set(viewGraphFields))

    let viewNodeFields = try parsedStoredVarNames(
      typeKind: "class",
      typeName: "ViewNode",
      relativePath: "Sources/SwiftTUICore/Resolve/ViewNode.swift"
    ).filter { field in
      // `identity` is immutable; `memoDiagnosticViewValue` is DEBUG-only
      // best-effort memoization diagnostics state that is intentionally not
      // checkpointed (a stale value across an aborted frame only perturbs the
      // histogram, never behavior — see MemoSkipTrace).
      field != "identity" && field != "memoDiagnosticViewValue"
    }
    let viewNodeCheckpointFields = try parsedStoredVarNames(
      typeKind: "struct",
      typeName: "Checkpoint",
      relativePath: "Sources/SwiftTUICore/Resolve/ViewNode.swift"
    )

    #expect(Set(viewNodeFields).count == viewNodeFields.count)
    #expect(Set(viewNodeCheckpointFields).count == viewNodeCheckpointFields.count)
    #expect(Set(viewNodeCheckpointFields) == Set(viewNodeFields))
  }

  @Test("checkpoint totality set-equality rejects any single missing map (guard has teeth)")
  func totalityGuardCatchesMissingField() throws {
    let viewGraphFields = try parsedStoredVarNames(
      typeKind: "class",
      typeName: "ViewGraph",
      relativePath: "Sources/SwiftTUICore/Resolve/ViewGraph.swift"
    )
    let checkpointFields = try parsedStoredVarNames(
      typeKind: "struct",
      typeName: "Checkpoint",
      relativePath: "Sources/SwiftTUICore/Resolve/ViewGraphState.swift"
    )
    let expected = Set(viewGraphFields + ["nodeCheckpoints"])

    // Sanity: the real checkpoint field set is total (mirrors the positive test).
    #expect(Set(checkpointFields) == expected)
    // Teeth: dropping any single covered field must break the equality the
    // positive guard asserts — proving a quietly-missed re-keyed map would fail
    // the totality gate rather than slip through (doc 006 Stage 5 Test #5).
    #expect(!checkpointFields.isEmpty)
    for omitted in checkpointFields {
      let incomplete = Set(checkpointFields.filter { $0 != omitted })
      #expect(incomplete != expected)
    }
  }

  @Test("checkpoint then mutate then restore is identity over graph state")
  func checkpointRestoreRoundTrips() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("CheckpointRoot")
    let childIdentity = testIdentity("CheckpointRoot", "Child")
    let insertedIdentity = testIdentity("CheckpointRoot", "Inserted")

    graph.setRootEvaluator(rootIdentity: rootIdentity) {}
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(
            identity: childIdentity,
            kind: .view("Child"),
            lifecycleMetadata: .init(
              appearHandlerIDs: ["child-appear"],
              disappearHandlerIDs: ["child-disappear"]
            )
          )
        ]
      )
    )
    graph.setEvaluator(for: childIdentity) {}
    graph.invalidateAndQueueDirty([childIdentity])

    let before = graph.debugTotalStateSnapshot()
    let checkpoint = graph.makeCheckpoint()

    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(
            identity: childIdentity,
            kind: .view("ChildUpdated")
          ),
          ResolvedNode(
            identity: insertedIdentity,
            kind: .view("Inserted"),
            lifecycleMetadata: .init(
              appearHandlerIDs: ["inserted-appear"],
              task: .init(id: "inserted-task", priority: .medium)
            )
          ),
        ]
      )
    )
    graph.invalidateAndQueueDirty([insertedIdentity])

    #expect(graph.debugTotalStateSnapshot() != before)

    graph.restoreCheckpoint(checkpoint)

    #expect(graph.debugTotalStateSnapshot() == before)
  }
}

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

private func typeBody(
  kind: String,
  name: String,
  in source: String
) throws -> String {
  guard let declaration = source.range(of: "\(kind) \(name)") else {
    throw CheckpointTotalitySourceParseError.missingType(kind: kind, name: name)
  }
  guard let openingBrace = source[declaration.upperBound...].firstIndex(of: "{") else {
    throw CheckpointTotalitySourceParseError.missingOpeningBrace(kind: kind, name: name)
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
  throw CheckpointTotalitySourceParseError.missingClosingBrace(kind: kind, name: name)
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
  throw CheckpointTotalitySourceParseError.missingPackageRoot
}

private enum CheckpointTotalitySourceParseError: Error {
  case missingPackageRoot
  case missingType(kind: String, name: String)
  case missingOpeningBrace(kind: String, name: String)
  case missingClosingBrace(kind: String, name: String)
}
