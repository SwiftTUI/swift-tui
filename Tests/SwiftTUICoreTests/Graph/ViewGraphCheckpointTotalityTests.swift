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

    // ViewGraph stores exactly `root` plus one property per field group, plus
    // the checkpoint mutation epoch — tracker *metadata* about mutations, not
    // state: it lives outside the groups so the group didSet observers can bump
    // it without recursing, restores never write it back (monotonicity is what
    // keeps "epoch equal ⇒ graph state equal" sound), and it is deliberately
    // absent from DebugTotalStateSnapshot so state-equality oracles do not
    // fail on bookkeeping differences.
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
    #expect(
      Set(viewGraphGroupFields)
        == groupPropertyNames.union(["root", "checkpointMutationEpoch"])
    )
    // The checkpoint stores the same groups plus `root`, `nodeCheckpoints`,
    // and the capture-metadata epoch.
    #expect(
      Set(viewGraphCheckpointGroupFields)
        == groupPropertyNames.union([
          "root", "nodeCheckpoints", "checkpointMutationEpoch",
        ])
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

  @Test("ViewNode field-group members are all mirrored in the flat debug snapshot")
  func viewNodeFieldGroupsAreDebugSnapshotCovered() throws {
    // The ViewNode field groups (in ViewNodeFieldGroups.swift) are checkpointed
    // and restored as whole structs, so makeCheckpoint / restoreCheckpoint are
    // compiler-enforced complete for their members. The flat
    // debugTotalStateSnapshot is the one remaining hand-mirror of those members;
    // guard that every group field is read into the snapshot so a field added to
    // a group cannot silently fall out of the debug-state contract.
    let groupNames = ["FrameState", "EvaluationState", "ReuseState", "PersistentState"]
    let groupMembers = try groupNames.flatMap { name in
      try parsedStoredVarNames(
        typeKind: "struct",
        typeName: name,
        relativePath: "Sources/SwiftTUICore/Resolve/ViewNodeFieldGroups.swift"
      )
    }
    // 12 FrameState + 5 EvaluationState + 3 ReuseState + 5 PersistentState
    // (the checkpoint mutation generation is tracker metadata stored outside
    // the groups; see ViewNode.checkpointMutationGeneration).
    #expect(groupMembers.count == 25)

    let snapshotBody = functionBodyText(
      named: "debugTotalStateSnapshot",
      in: try sourceText(relativePath: "Sources/SwiftTUICore/Resolve/ViewNode.swift")
    )
    #expect(!snapshotBody.isEmpty, "could not locate ViewNode.debugTotalStateSnapshot()")
    for field in groupMembers {
      #expect(
        snapshotBody.contains(field),
        "ViewNode group field \(field) is not read into debugTotalStateSnapshot — the flat debug mirror has drifted from the groups."
      )
    }
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

  // The same parallel-field-mirror landmine that the checkpoint guard catches
  // for ViewGraph also lurks in two other hand-maintained families. Generalize
  // the source-level totality guard to them.

  @Test("every PlacedNodeResolvedMetadata field is applied on the setter path")
  func placedNodeMetadataFieldsAreAllApplied() throws {
    // PlacedNode mirrors its metadata four ways. The getter (resolvedMetadata)
    // is compiler-enforced (a missing init arg won't compile); the SETTER
    // (applyResolvedMetadata) is not — drop a field there and that field silently
    // stales after every metadata application (animation ticks reuse this path).
    // Guard it: each metadata field must be read as `metadata.<field>`.
    let path = "Sources/SwiftTUICore/Place/PlacedNode.swift"
    let fields = try parsedStoredVarNames(
      typeKind: "struct",
      typeName: "PlacedNodeResolvedMetadata",
      relativePath: path
    )
    #expect(fields.count >= 14)  // the metadata mirror is non-trivial
    let source = try sourceText(relativePath: path)
    for field in fields {
      #expect(
        source.contains("metadata.\(field)"),
        "PlacedNodeResolvedMetadata.\(field) is never read as metadata.\(field): applyResolvedMetadata likely drops it, silently staling that field after metadata application."
      )
    }
  }

  @Test("every RuntimeRegistrationSet registry is wired into the lifecycle fan-out list")
  func registriesAreCoveredByLifecycleOperations() throws {
    // The bulk lifecycle operations (reset, subtree removal, restore,
    // fingerprinting, frame-drop blockers) are loops over `allRegistries`, so
    // the one place a stored registry can still be forgotten is the `members`
    // list in the set's init. A member missing there silently drops out of
    // EVERY fan-out — stale state leaks across frames (a strand).
    // `RuntimeRegistrationKindTotalityTests` behaviorally covers every
    // declared `RuntimeRegistrationKind`; this source guard additionally
    // catches a stored registry property that never gained a kind at all.
    let registries = try parsedStoredVarNames(
      typeKind: "struct",
      typeName: "RuntimeRegistrationSet",
      relativePath: "Sources/SwiftTUICore/Runtime/RuntimeRegistrationSet.swift"
    )
    .filter { $0.hasSuffix("Registry") }
    #expect(registries.count >= 15)

    let source = try sourceText(
      relativePath: "Sources/SwiftTUICore/Runtime/RuntimeRegistrationSet.swift"
    )
    guard
      let membersStart = source.range(of: "let members: [(any RuntimeRegistry)?] = ["),
      let membersEnd = source.range(
        of: "allRegistries = members",
        range: membersStart.upperBound..<source.endIndex
      )
    else {
      Issue.record(
        "could not locate the `members` fan-out list in RuntimeRegistrationSet.init"
      )
      return
    }
    let membersList = source[membersStart.upperBound..<membersEnd.lowerBound]
    for registry in registries {
      #expect(
        membersList.contains(registry),
        "\(registry) is not wired into RuntimeRegistrationSet's allRegistries fan-out list: every bulk lifecycle operation would skip that family and a scoped restore would diverge from a full rebuild."
      )
    }
  }
}

/// Returns the source text of the first `func <name>(` and its body (balanced
/// braces), or "" if not found.
private func functionBodyText(named name: String, in source: String) -> String {
  let lines = source.components(separatedBy: .newlines)
  guard let start = lines.firstIndex(where: { $0.contains("func \(name)(") }) else {
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
