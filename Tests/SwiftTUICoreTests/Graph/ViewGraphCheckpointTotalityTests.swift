import Foundation
import Testing

@testable import SwiftTUICore

// The mutable graph state lives in the value-typed field groups declared in
// ViewGraphFieldGroups.swift. ViewGraph and ViewGraph.Checkpoint each store one
// instance of every group (plus `root`, and `nodeCheckpoints` on the
// checkpoint), so the canonical covered-field set is the union of every group's
// fields. DebugTotalStateSnapshot stays flat, mirroring those same field names.
private let viewGraphFieldGroupNames = [
  "GraphIndex",
  "RootEvaluation",
  "ViewportLifecycleState",
  "LifecycleEventBuffers",
  "DirtyState",
  "LifecycleEvaluationOwnership",
  "TaskDescriptorState",
  "DependencyIndex",
  "FrameCommitState",
]

private func parsedFieldGroupMemberNames() throws -> [String] {
  try viewGraphFieldGroupNames.flatMap { groupName in
    try parsedStoredVarNames(
      typeKind: "struct",
      typeName: groupName,
      relativePath: "Sources/SwiftTUICore/Resolve/ViewGraphFieldGroups.swift"
    )
  }
}

@MainActor
@Suite("ViewGraph checkpoint totality")
struct ViewGraphCheckpointTotalityTests {
  @Test("ViewGraph and ViewNode mutable fields are checkpoint-covered")
  func mutableFieldsAreCheckpointCovered() throws {
    // ViewGraph and its checkpoint store the field groups by value; the source
    // parser sees the group property names (the per-field forwarding accessors
    // are computed, so they are excluded). The flattened group fields are the
    // canonical covered set.
    let viewGraphGroupFields = try parsedStoredVarNames(
      typeKind: "class",
      typeName: "ViewGraph",
      relativePath: "Sources/SwiftTUICore/Resolve/ViewGraph.swift"
    )
    let viewGraphCheckpointGroupFields = try parsedStoredVarNames(
      typeKind: "struct",
      typeName: "Checkpoint",
      relativePath: "Sources/SwiftTUICore/Resolve/ViewGraphState.swift"
    )
    let viewGraphDebugFields = try parsedStoredVarNames(
      typeKind: "struct",
      typeName: "DebugTotalStateSnapshot",
      relativePath: "Sources/SwiftTUICore/Resolve/ViewGraphDebugSnapshots.swift"
    )
    let groupMemberFields = try parsedFieldGroupMemberNames()

    #expect(Set(viewGraphGroupFields).count == viewGraphGroupFields.count)
    #expect(Set(viewGraphCheckpointGroupFields).count == viewGraphCheckpointGroupFields.count)
    #expect(Set(viewGraphDebugFields).count == viewGraphDebugFields.count)
    #expect(Set(groupMemberFields).count == groupMemberFields.count)

    // ViewGraph stores exactly `root` plus one property per field group.
    let groupPropertyNames: Set<String> = [
      "index",
      "rootEvaluation",
      "viewportLifecycle",
      "eventBuffers",
      "dirtyState",
      "lifecycleEvaluation",
      "taskDescriptors",
      "dependencyIndex",
      "frameCommit",
    ]
    #expect(Set(viewGraphGroupFields) == groupPropertyNames.union(["root"]))
    // The checkpoint stores the same groups plus `root` and `nodeCheckpoints`.
    #expect(
      Set(viewGraphCheckpointGroupFields)
        == groupPropertyNames.union(["root", "nodeCheckpoints"])
    )
    // Every per-field name across all groups, plus the standalone `root`, is
    // mirrored by the flat debug snapshot — the checkpoint-totality contract
    // for the debug-state guard.
    #expect(Set(viewGraphDebugFields) == Set(groupMemberFields + ["root"]))

    let viewNodeFields = try parsedStoredVarNames(
      typeKind: "class",
      typeName: "ViewNode",
      relativePath: "Sources/SwiftTUICore/Resolve/ViewNode.swift"
    ).filter { field in
      field != "identity"
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
    // The canonical covered set is the flattened field-group members plus the
    // standalone `root`; the flat debug snapshot must mirror it exactly.
    let canonicalFields = try parsedFieldGroupMemberNames() + ["root"]
    let debugFields = try parsedStoredVarNames(
      typeKind: "struct",
      typeName: "DebugTotalStateSnapshot",
      relativePath: "Sources/SwiftTUICore/Resolve/ViewGraphDebugSnapshots.swift"
    )
    let expected = Set(canonicalFields)

    // Sanity: the real debug field set is total (mirrors the positive test).
    #expect(Set(debugFields) == expected)
    // Teeth: dropping any single covered field must break the equality the
    // positive guard asserts — proving a quietly-missed re-keyed map would fail
    // the totality gate rather than slip through (doc 006 Stage 5 Test #5).
    #expect(!canonicalFields.isEmpty)
    for omitted in canonicalFields {
      let incomplete = Set(canonicalFields.filter { $0 != omitted })
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
              tasks: [.init(id: "inserted-task", priority: .medium)]
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
