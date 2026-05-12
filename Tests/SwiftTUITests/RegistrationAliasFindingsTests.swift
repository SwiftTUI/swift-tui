import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Characterization test suite for Item 7 of
/// `docs/proposals/ARCHITECTURE_NOTES.md`.
///
/// These tests don't exist to catch regressions in the traditional
/// sense — they exist to **pin the current behavior** of the
/// registration alias layer so any future change to the view
/// resolution path that alters the observed divergence frequency will
/// show up loudly in test output.
///
/// Each test builds a small view tree through `DefaultRenderer`, reads
/// the resulting `RegistrationAliasDiagnostics`, and asserts the
/// observed counts.  If a refactor either introduces new divergences
/// or removes existing ones, these tests will fail and can be updated
/// with the new expected numbers — the delta is the signal about what
/// changed in the alias population logic.
@MainActor
@Suite
struct RegistrationAliasFindingsTests {
  @Test("plain Text view produces no non-trivial aliases")
  func plainTextHasNoAliases() {
    let renderer = DefaultRenderer()
    _ = renderer.render(
      Text("Hello"),
      context: .init(identity: testIdentity("Root"))
    )

    let diagnostics = renderer.debugRegistrationAliasDiagnostics
    #expect(diagnostics.nonTrivialCallCount == 0)
    #expect(diagnostics.uniqueDivergenceCount == 0)
  }

  @Test("nested VStack with Text children produces no non-trivial aliases")
  func vStackOfTextHasNoAliases() {
    let renderer = DefaultRenderer()
    _ = renderer.render(
      VStack {
        Text("Hello")
        Text("World")
        Text("!")
      },
      context: .init(identity: testIdentity("Root"))
    )

    let diagnostics = renderer.debugRegistrationAliasDiagnostics
    #expect(diagnostics.nonTrivialCallCount == 0)
    #expect(diagnostics.uniqueDivergenceCount == 0)
  }

  @Test("Group wrapping content produces no non-trivial aliases")
  func groupProducesNoAliases() {
    let renderer = DefaultRenderer()
    _ = renderer.render(
      VStack {
        Group {
          Text("A")
          Text("B")
        }
      },
      context: .init(identity: testIdentity("Root"))
    )

    let diagnostics = renderer.debugRegistrationAliasDiagnostics
    #expect(diagnostics.nonTrivialCallCount == 0)
    #expect(diagnostics.uniqueDivergenceCount == 0)
  }

  @Test("EmptyView inside a builder produces no non-trivial aliases")
  func emptyViewProducesNoAliases() {
    let renderer = DefaultRenderer()
    _ = renderer.render(
      VStack {
        Text("A")
        EmptyView()
        Text("B")
      },
      context: .init(identity: testIdentity("Root"))
    )

    let diagnostics = renderer.debugRegistrationAliasDiagnostics
    #expect(diagnostics.nonTrivialCallCount == 0)
    #expect(diagnostics.uniqueDivergenceCount == 0)
  }

  @Test("AnyView type erasure produces no non-trivial aliases")
  func anyViewProducesNoAliases() {
    let renderer = DefaultRenderer()
    _ = renderer.render(
      VStack {
        AnyView(Text("erased"))
      },
      context: .init(identity: testIdentity("Root"))
    )

    let diagnostics = renderer.debugRegistrationAliasDiagnostics
    #expect(diagnostics.nonTrivialCallCount == 0)
    #expect(diagnostics.uniqueDivergenceCount == 0)
  }

  @Test("ForEach with explicit IDs produces no aliases (normalized through Group)")
  func forEachDoesNotProduceAliases() {
    let renderer = DefaultRenderer()
    _ = renderer.render(
      VStack {
        ForEach([10, 20, 30], id: \.self) { value in
          Text("value \(value)")
        }
      },
      context: .init(identity: testIdentity("Root"))
    )

    let diagnostics = renderer.debugRegistrationAliasDiagnostics
    // The first version of this test expected non-zero based on the
    // architecture note's hypothesis that ForEach's explicit-ID
    // stamping would produce divergences at appendDeclaredChildNodes.
    // The instrumentation proved that wrong: ForEach.resolveElements
    // returns multiple ResolvedNodes, normalizeResolvedElements wraps
    // them in a synthetic Group whose identity is the *context*
    // identity, so the outer node matches childContext.identity and
    // the alias call is trivial.  The explicit-ID children are then
    // flattened into the parent's resolved array without ever going
    // through recordRegistrationAlias.
    //
    // See RegistrationAliasFindings.md for the full analysis.
    #expect(diagnostics.nonTrivialCallCount == 0)
  }

  @Test("AnyView wrapping ForEach also produces no aliases")
  func anyViewWrappingForEachAlsoNoAliases() {
    let renderer = DefaultRenderer()
    _ = renderer.render(
      VStack {
        AnyView(
          ForEach([1, 2], id: \.self) { value in
            Text("row \(value)")
          }
        )
      },
      context: .init(identity: testIdentity("Root"))
    )

    let diagnostics = renderer.debugRegistrationAliasDiagnostics
    // Wrapping the ForEach in AnyView changes nothing: AnyView's
    // resolveElements just forwards to the inner view, and the same
    // Group-normalization path absorbs any identity divergence.
    #expect(diagnostics.nonTrivialCallCount == 0)
  }

  @Test(".id(_:) modifier DOES produce non-trivial aliases")
  func idModifierProducesNonTrivialAliases() {
    // `.id(_:)` is the only common view API that actually triggers the
    // alias path.  IDView.resolveElements calls
    // `content.resolve(in: context.replacingIdentity(with: identity))`
    // and returns that single-element array.  normalizeResolvedElements
    // with count==1 passes the element through unchanged — so the
    // outer resolved node has the replaced identity while
    // childContext.identity is still the positional path.
    // appendDeclaredChildNodes then records a real non-trivial alias.
    let renderer = DefaultRenderer()
    _ = renderer.render(
      VStack {
        Text("A").id(testIdentity("explicit-a"))
        Text("B").id(testIdentity("explicit-b"))
      },
      context: .init(identity: testIdentity("Root"))
    )

    let diagnostics = renderer.debugRegistrationAliasDiagnostics
    #expect(diagnostics.nonTrivialCallCount > 0)
    #expect(diagnostics.uniqueDivergenceCount > 0)

    // The divergences should be for the Text kind (IDView's single
    // element is the Text it wraps).
    let top = diagnostics.topDivergences()
    #expect(top.contains { $0.key.kindDescription == "view(Text)" })
  }

  /// This test is a **dashboard**.  It renders a realistic composite
  /// tree exercising every control-flow shape in the view builder
  /// (Text, Group, EmptyView, AnyView, ForEach, if, if-else) and
  /// measures the resulting alias divergences.
  ///
  /// Key finding (documented in RegistrationAliasFindings.md): the
  /// standard composition primitives do **not** produce non-trivial
  /// aliases.  `normalizeResolvedElements` wraps multi-element results
  /// in a synthetic `Group` with the caller's context identity, and
  /// `appendDeclaredChildNodes` flattens that Group away before the
  /// alias call, absorbing any identity divergence.  The assertion
  /// therefore pins `nonTrivialCallCount == 0` for this shape — a
  /// future change that starts producing divergences will fail the
  /// test loudly and can be investigated.
  @Test("composite tree without .id(_:) produces zero non-trivial aliases")
  func compositeTreeInventory() {
    let renderer = DefaultRenderer()
    _ = renderer.render(
      VStack {
        Text("header")
        Group {
          Text("group A")
          Text("group B")
        }
        ForEach([1, 2, 3], id: \.self) { value in
          VStack {
            Text("row \(value)")
            if value.isMultiple(of: 2) {
              Text("even")
            } else {
              Text("odd")
            }
          }
        }
        AnyView(
          ForEach(["x", "y"], id: \.self) { token in
            Text(token)
          }
        )
        EmptyView()
      },
      context: .init(identity: testIdentity("Root"))
    )

    let diagnostics = renderer.debugRegistrationAliasDiagnostics
    #expect(diagnostics.nonTrivialCallCount == 0)
    #expect(diagnostics.uniqueDivergenceCount == 0)
  }

  /// Dashboard test that exercises `.id(_:)` scattered through the
  /// same composite shape and dumps the observed divergences via
  /// `print()` so developers running the test individually can see
  /// what the alias layer is actually catching.
  @Test("composite tree with .id(_:) reveals the only real divergence source")
  func compositeTreeWithIDsDumps() {
    let renderer = DefaultRenderer()
    _ = renderer.render(
      VStack {
        Text("header").id(testIdentity("header"))
        ForEach([1, 2, 3], id: \.self) { value in
          Text("row \(value)").id(testIdentity("row", "\(value)"))
        }
        AnyView(Text("trailer").id(testIdentity("trailer")))
      },
      context: .init(identity: testIdentity("Root"))
    )

    let diagnostics = renderer.debugRegistrationAliasDiagnostics
    #expect(diagnostics.nonTrivialCallCount > 0)
    #expect(diagnostics.uniqueDivergenceCount > 0)

    print("--- RegistrationAliasFindings: composite tree with .id(_:) ---")
    print("nonTrivialCallCount = \(diagnostics.nonTrivialCallCount)")
    print("uniqueDivergenceCount = \(diagnostics.uniqueDivergenceCount)")
    for (key, count) in diagnostics.topDivergences() {
      print("  [\(count)] \(key.description)")
    }
    print("--- end findings ---")
  }
}
