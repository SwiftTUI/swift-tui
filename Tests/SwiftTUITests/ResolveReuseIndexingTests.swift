import Testing

@testable import Core
@testable import View

@MainActor
@Suite
struct ResolveReuseIndexingTests {
  @Test("resolved trees expose nested subtree identities without retained frame indexes")
  func resolvedTreeCollectsNestedSubtreeIdentities() throws {
    let rootIdentity = testIdentity("Root")
    let nestedIdentity = testIdentity("Root", "VStack[1]")
    let nestedLeafIdentity = testIdentity("Root", "VStack[1]", "VStack[1]")

    let resolvedTree = VStack(alignment: .leading, spacing: 1) {
      Text("Stable")
      VStack(alignment: .leading, spacing: 0) {
        Text("Nested")
        Text("Leaf")
      }
    }
    .resolve(in: .init(identity: rootIdentity))

    let nestedTree = try #require(
      resolvedTree.children.first(where: { $0.identity == nestedIdentity })
    )
    let subtreeIdentities = nestedTree.collectIdentities()

    #expect(subtreeIdentities.first == nestedIdentity)
    #expect(subtreeIdentities.contains(nestedLeafIdentity))
    #expect(!subtreeIdentities.contains(testIdentity("Root", "VStack[0]")))
    #expect(
      resolvedTree.path(to: nestedLeafIdentity) == [
        rootIdentity, nestedIdentity, nestedLeafIdentity,
      ])
  }
}
