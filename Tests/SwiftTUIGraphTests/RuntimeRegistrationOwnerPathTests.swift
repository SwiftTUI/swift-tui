import Testing

@testable import SwiftTUIGraph

@MainActor
@Suite("F129 runtime registration owner decision")
struct RuntimeRegistrationOwnerPathTests {
  private func assertIdentityOwnedRemoval(
    _ kind: RuntimeRegistrationKind,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let authoredOwner = testIdentity("Root", "ForEach[0]", "Modifier")
    let runtimeRoot = testIdentity("Entity", "item")
    let registrationIdentity = testIdentity("Entity", "item", "Control")
    let node = RegistrationKindDriver.makeRecordingNode(identity: authoredOwner)
    ViewNodeContext.withValue(node) {
      RegistrationKindDriver.record(kind, on: node, identity: registrationIdentity)
    }

    let set = RuntimeRegistrationSet.scratch()
    set.restore(from: node.registeredHandlers)
    let populated = set.publicationOracleFingerprint()
    #expect(!populated.isEmpty, sourceLocation: sourceLocation)

    // F129 decision: the recording node's structural/authored location is not
    // a runtime-registration lifetime root. Removing it must not reach a
    // registration whose explicit owner is in a re-rooted entity namespace.
    set.removeSubtrees(rootedAt: [authoredOwner])
    #expect(
      set.publicationOracleFingerprint() == populated,
      "\(kind): an unrelated authored path removed the runtime owner",
      sourceLocation: sourceLocation
    )

    set.removeSubtrees(rootedAt: [runtimeRoot])
    #expect(
      set.publicationOracleFingerprint() != populated,
      "\(kind): the explicit runtime owner survived its identity subtree removal",
      sourceLocation: sourceLocation
    )
  }

  @Test("the owner-key family map is closed and contains exactly nine families")
  func ownerFamilyTotality() {
    let mapped = RuntimeRegistrationKind.allCases.compactMap(\.ownerFamily)
    #expect(mapped.count == 9)
    #expect(Set(mapped) == Set(RuntimeRegistrationOwnerFamily.allCases))
  }

  @Test("owner equality, hashing, ordering, and subtree matching are identity based")
  func identityBasedOwnerValue() {
    let identity = testIdentity("Entity", "item", "Control")
    let first = RuntimeRegistrationOwnerKey(
      viewNodeID: ViewNodeID(rawValue: 1),
      identity: identity
    )
    let equal = RuntimeRegistrationOwnerKey(
      viewNodeID: ViewNodeID(rawValue: 1),
      identity: identity
    )
    let otherNode = RuntimeRegistrationOwnerKey(
      viewNodeID: ViewNodeID(rawValue: 2),
      identity: identity
    )

    #expect(first == equal)
    #expect(Set([first, equal]).count == 1)
    #expect(first < otherNode)
    #expect(first.matchesAnySubtreeRoot([testIdentity("Entity", "item")]))
    #expect(!first.matchesAnySubtreeRoot([testIdentity("Root", "ForEach[0]")]))
  }

  @Test("action removal follows its explicit runtime owner")
  func actionOwner() { assertIdentityOwnedRemoval(.action) }

  @Test("key-handler removal follows its explicit runtime owner")
  func keyHandlerOwner() { assertIdentityOwnedRemoval(.keyHandler) }

  @Test("termination removal follows its explicit runtime owner")
  func terminationOwner() { assertIdentityOwnedRemoval(.termination) }

  @Test("pointer and hover removal follows their explicit runtime owner")
  func pointerOwner() { assertIdentityOwnedRemoval(.pointerHandler) }

  @Test("gesture removal follows its explicit runtime owner")
  func gestureOwner() { assertIdentityOwnedRemoval(.gesture) }

  @Test("gesture-state removal follows its explicit runtime owner")
  func gestureStateOwner() { assertIdentityOwnedRemoval(.gestureState) }

  @Test("task removal follows its explicit runtime owner")
  func taskOwner() { assertIdentityOwnedRemoval(.task) }

  @Test("command removal follows its explicit runtime owner")
  func commandOwner() { assertIdentityOwnedRemoval(.command) }

  @Test("drop-destination removal follows its explicit runtime owner")
  func dropDestinationOwner() { assertIdentityOwnedRemoval(.dropDestination) }

  @Test("the deleted structural-path leg cannot return through production source")
  func ownerSourceHasNoStructuralPathLeg() throws {
    let source = try SourceParsingTestSupport.sourceText(
      relativePath: "Sources/SwiftTUIGraph/Runtime/RuntimeRegistrationOwnerKey.swift"
    )
    #expect(!source.contains("structuralPath"))
    #expect(!source.contains("identityProjection"))
  }
}
