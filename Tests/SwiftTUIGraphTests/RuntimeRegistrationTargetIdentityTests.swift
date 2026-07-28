import Testing

@testable import SwiftTUIGraph

@MainActor
@Suite("Runtime registration target identity")
struct RuntimeRegistrationTargetIdentityTests {
  @Test("a released registry cannot lend its token to a replacement at the same lookup key")
  func releasedRegistryCannotLendTokenToReplacement() {
    let table = RuntimeRegistryIdentityTokenTable()
    let lookupKeyAnchor = LocalActionRegistry()
    let reusedLookupKey = ObjectIdentifier(lookupKeyAnchor)

    var priorRegistry: LocalActionRegistry? = LocalActionRegistry()
    weak let releasedRegistry = priorRegistry
    let priorToken = table.token(
      for: priorRegistry!,
      lookupKey: reusedLookupKey
    )
    priorRegistry = nil
    #expect(releasedRegistry == nil)

    let replacementRegistry = LocalActionRegistry()
    let replacementToken = table.token(
      for: replacementRegistry,
      lookupKey: reusedLookupKey
    )

    #expect(replacementToken != priorToken)
    #expect(
      table.token(for: replacementRegistry, lookupKey: reusedLookupKey)
        == replacementToken
    )
  }
}
