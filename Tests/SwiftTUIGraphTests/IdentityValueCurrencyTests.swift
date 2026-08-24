import Foundation
import Testing

@testable import SwiftTUIGraph

/// Pins `Identity`'s hand-written conformances: the mint-time cached hash
/// must stay a pure function of `components` (every mint route must agree),
/// and the `Codable` wire shape must stay byte-compatible with the
/// synthesized form it replaced — a single `components` key — because
/// identities travel in debug bundles.
@Suite
struct IdentityValueCurrencyTests {
  @Test("equal identities minted through different routes agree on hash and equality")
  func mintRoutesAgree() {
    let direct = Identity(components: ["app", "stack[0]", "row"])
    let chained = Identity(components: ["app"])
      .child(IdentityComponent.indexed("stack", index: 0))
      .child("row")

    #expect(direct == chained)
    #expect(direct.hashValue == chained.hashValue)

    let probe: Set<Identity> = [direct]
    #expect(probe.contains(chained))
  }

  @Test("prefix-related identities stay unequal in both directions")
  func prefixRelationsStayUnequal() {
    let parent = Identity(components: ["app", "stack[0]"])
    let child = parent.child("row")

    #expect(parent != child)
    #expect(child.parent == parent)
    #expect(parent.isAncestor(of: child))
    #expect(!child.isAncestor(of: parent))
  }

  @Test("occurrence stripping mints identities that agree with directly built forms")
  func occurrenceStrippingAgreesWithDirectForms() {
    let occurrence = Identity(components: ["app"]).explicitID("x", occurrence: 2)
    let stripped = occurrence.strippingEntityOccurrences
    let direct = Identity(components: ["app"]).explicitID("x")

    #expect(stripped == direct)
    #expect(stripped.hashValue == direct.hashValue)
  }

  @Test("codable wire shape stays a single components key and round-trips")
  func codableWireShapeStable() throws {
    let identity = Identity(components: ["app", #"ID["x"]"#])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let encoded = String(decoding: try encoder.encode(identity), as: UTF8.self)
    #expect(encoded == #"{"components":["app","ID[\"x\"]"]}"#)

    let decoded = try JSONDecoder().decode(
      Identity.self,
      from: try encoder.encode(identity)
    )
    #expect(decoded == identity)
    #expect(decoded.hashValue == identity.hashValue)
  }

  @Test("structural paths minted through different routes agree on hash and equality")
  func structuralPathMintRoutesAgree() {
    let components = [
      IdentityComponent.named("app"),
      IdentityComponent.indexed("stack", index: 0),
      IdentityComponent.named("row"),
    ]
    let direct = StructuralPath(components: components)
    let appended = StructuralPath(components: [components[0]])
      .appending(components[1])
      .appending(components[2])

    #expect(direct == appended)
    #expect(direct.hashValue == appended.hashValue)

    let probe: Set<StructuralPath> = [direct]
    #expect(probe.contains(appended))
    #expect(direct != appended.appending(.named("extra")))
  }

  @Test("identity and structural path conversions preserve hash agreement")
  func identityStructuralPathConversionsAgree() {
    let identity = Identity(components: ["app", "stack[0]", "row"])
    let path = StructuralPath(identity: identity)
    let direct = StructuralPath(
      components: identity.components.map { IdentityComponent(rawValue: $0) }
    )

    #expect(path == direct)
    #expect(path.hashValue == direct.hashValue)

    let projected = path.identityProjection
    #expect(projected == identity)
    #expect(projected.hashValue == identity.hashValue)
  }

  @Test("structural path codable wire shape stays a single components key and round-trips")
  func structuralPathCodableWireShapeStable() throws {
    let path = StructuralPath(components: [
      IdentityComponent.named("app"),
      IdentityComponent.indexed("stack", index: 3),
    ])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let encoded = String(decoding: try encoder.encode(path), as: UTF8.self)
    #expect(encoded == #"{"components":[{"rawValue":"app"},{"rawValue":"stack[3]"}]}"#)

    let decoded = try JSONDecoder().decode(
      StructuralPath.self,
      from: try encoder.encode(path)
    )
    #expect(decoded == path)
    #expect(decoded.hashValue == path.hashValue)
  }
}
