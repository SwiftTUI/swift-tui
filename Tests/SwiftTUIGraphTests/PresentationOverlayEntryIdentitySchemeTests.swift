import Testing

@testable import SwiftTUIGraph

/// F168: the overlay-entry identity scheme is single-sourced — the mint, the
/// runtime re-derivation, and the graph matchers must agree byte-for-byte.
/// This suite ties them: an identity built the way the Views-side mint
/// builds it (structural literals + the scheme's entry component) MUST be
/// recognized by the scheme's matcher and reproduced by its derivation.
@MainActor
@Suite("Presentation overlay-entry identity scheme")
struct PresentationOverlayEntryIdentitySchemeTests {
  private let portalRoot = testIdentity("App", "window")

  @Test("the mint's structural spelling matches the scheme's derivation")
  func mintSpellingMatchesDerivation() {
    // The Views-side mint spells the path with `.named` literals (they must
    // stay byte-identical to the scheme; `.named` requires StaticString).
    let minted =
      portalRoot
      .child("PortalHost")
      .child("overlays")
      .child(PresentationOverlayEntryIdentityScheme.entryComponent(id: "sheet-3"))

    let derived = PresentationOverlayEntryIdentityScheme.entryIdentity(
      portalRootIdentity: portalRoot,
      entryID: "sheet-3"
    )

    #expect(minted == derived)
  }

  @Test("the matcher recognizes minted entry roots and their descendants")
  func matcherRecognizesMintAndDescendants() {
    let entry = PresentationOverlayEntryIdentityScheme.entryIdentity(
      portalRootIdentity: portalRoot,
      entryID: "sheet-3"
    )
    #expect(
      PresentationOverlayEntryIdentityScheme.isEntryIdentity(
        entry, portalRootIdentity: portalRoot, entryRootOnly: true
      )
    )
    #expect(
      PresentationOverlayEntryIdentityScheme.isEntryIdentity(
        entry.child("VStack[0]"), portalRootIdentity: portalRoot, entryRootOnly: false
      )
    )
    // A descendant is NOT an entry root.
    #expect(
      !PresentationOverlayEntryIdentityScheme.isEntryIdentity(
        entry.child("VStack[0]"), portalRootIdentity: portalRoot, entryRootOnly: true
      )
    )
    // The host itself is not an entry.
    #expect(
      !PresentationOverlayEntryIdentityScheme.isEntryIdentity(
        PresentationOverlayEntryIdentityScheme.hostIdentity(portalRootIdentity: portalRoot),
        portalRootIdentity: portalRoot,
        entryRootOnly: false
      )
    )
    // A foreign subtree that merely contains an "entry:"-named component is
    // not an overlay entry.
    #expect(
      !PresentationOverlayEntryIdentityScheme.isEntryIdentity(
        portalRoot.child("Sidebar").child("overlays").child("entry:sheet-3"),
        portalRootIdentity: portalRoot,
        entryRootOnly: true
      )
    )
  }
}
