import Foundation
import Testing

@testable import SwiftTUIGraph

/// Locks each registry's subtree-matcher family (F106). Three deliberately
/// different matching semantics exist (explicit owner identity;
/// focus-detached-owner; bare identity-prefix) and the header of
/// `RuntimeRegistrationSubtreeMatching.swift` warns collapsing them is
/// unsafe — but until this suite, nothing failed if a registry's
/// `removeSubtrees` was switched to the wrong matcher. The source lock pins
/// which family each registry file calls; the behavioral test pins the
/// load-bearing family-2 semantic (detached-owner removal — the F04
/// focus-stacking shape) against the owner-key family's behavior.
@Suite("Registry matcher-family lock")
struct RegistryMatcherFamilyLockTests {
  enum MatcherFamily: String, Sendable {
    case ownerKey
    case focusDetachedOwner
    case identityPrefix

    /// A marker unique to the family's matcher call. The paren-dot prefix on
    /// the owner-key marker keeps it from matching inside the two free
    /// functions' longer names.
    var marker: String {
      switch self {
      case .ownerKey: ").matchesAnySubtreeRoot("
      case .focusDetachedOwner: "focusRegistrationMatchesAnySubtreeRoot("
      case .identityPrefix: "identityMatchesAnySubtreeRoot("
      }
    }
  }

  struct FamilyAssignment: Sendable {
    let relativePath: String
    let family: MatcherFamily
  }

  /// The documented family of every registry storage file that performs
  /// subtree removal. Switching a file to a different matcher must fail here
  /// and be justified against the header of
  /// `RuntimeRegistrationSubtreeMatching.swift`.
  static let assignments: [FamilyAssignment] = [
    .init(
      relativePath: "Sources/SwiftTUIGraph/Runtime/IdentityKeyedRegistryStorage.swift",
      family: .ownerKey
    ),
    .init(
      relativePath: "Sources/SwiftTUIGraph/Runtime/LocalKeyHandlerRegistry.swift",
      family: .ownerKey
    ),
    .init(
      relativePath: "Sources/SwiftTUIGraph/Runtime/LocalGestureRegistry.swift",
      family: .ownerKey
    ),
    .init(
      relativePath: "Sources/SwiftTUIGraph/Runtime/LocalGestureStateRegistry.swift",
      family: .ownerKey
    ),
    .init(
      relativePath: "Sources/SwiftTUIGraph/Runtime/LocalPointerHandlerRegistry.swift",
      family: .ownerKey
    ),
    .init(
      relativePath: "Sources/SwiftTUIGraph/Runtime/LocalFocusBindingRegistry.swift",
      family: .focusDetachedOwner
    ),
    .init(
      relativePath: "Sources/SwiftTUIGraph/Runtime/LocalFocusedValuesRegistry.swift",
      family: .focusDetachedOwner
    ),
    .init(
      relativePath: "Sources/SwiftTUIGraph/Runtime/LocalScrollPositionRegistry.swift",
      family: .identityPrefix
    ),
    .init(
      relativePath: "Sources/SwiftTUIGraph/Runtime/LocalLifecycleRegistry.swift",
      family: .identityPrefix
    ),
    .init(
      relativePath: "Sources/SwiftTUIGraph/Runtime/LocalPreferenceObservationRegistry.swift",
      family: .identityPrefix
    ),
  ]

  @Test(
    "each registry file calls exactly its documented matcher family",
    arguments: assignments
  )
  func registryFileCallsItsDocumentedFamily(_ assignment: FamilyAssignment) throws {
    let source = try SourceParsingTestSupport.sourceText(
      relativePath: assignment.relativePath
    )
    #expect(
      source.contains(assignment.family.marker),
      "\(assignment.relativePath): documented matcher family call is missing"
    )
    for family in [MatcherFamily.ownerKey, .focusDetachedOwner, .identityPrefix]
    where family != assignment.family {
      #expect(
        !source.contains(family.marker),
        "\(assignment.relativePath): calls the \(family.rawValue) matcher — a family switch"
      )
    }
  }

  @MainActor
  @Test("the focus family removes by detached owner; the owner-key family does not")
  func focusFamilyRemovesByDetachedOwner() {
    let publisher = testIdentity("Root", "Publisher")
    let detached = testIdentity("Detached", "Slot")

    // Family 2: a focus snapshot published at a detached identity is removed
    // when its PUBLISHER's subtree tears down — otherwise the scoped restore
    // stacks one copy per commit (the F04 stacking shape).
    let focusRegistry = LocalFocusedValuesRegistry()
    var values = FocusedValues()
    values[TotalityProbeFocusedValueKey.self] = "probe"
    focusRegistry.restore([
      FocusedValuesRegistrationSnapshot(
        identity: detached,
        descendantIdentities: [detached],
        values: values,
        ownerIdentity: publisher
      )
    ])
    focusRegistry.removeSubtrees(rootedAt: [publisher])
    #expect(
      focusRegistry.snapshot().isEmpty,
      "the focus family must clear detached-identity snapshots via their owner"
    )

    // Family 1: an owner-key registration at the same detached identity is
    // keyed by that identity's own owner projection — the publisher's subtree
    // is not its lifetime anchor, so the same removal must NOT touch it.
    let actionRegistry = LocalActionRegistry()
    actionRegistry.register(identity: detached, handler: { true })
    actionRegistry.removeSubtrees(rootedAt: [publisher])
    #expect(
      actionRegistry.hasHandler(identity: detached),
      "the owner-key family must not adopt the focus family's owner match"
    )
  }
}
