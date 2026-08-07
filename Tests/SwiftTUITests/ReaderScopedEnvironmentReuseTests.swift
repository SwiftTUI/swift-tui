import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The reader-scoped environment toleration: a reuse door may serve a subtree
/// across an `.environment` change when the changed key is reader-attributed
/// only and nothing in the subtree reads or writes it.
///
/// The fixture key is declared in the *test* module on purpose — that is what
/// makes it reader-attributed-only. Keys declared inside the framework are also
/// read *without* attribution (style extraction, the `[untracked:]` text
/// attributes), so the classification excludes them wholesale and the
/// toleration must never fire for them.
private enum ReaderScopedThemeKey: EnvironmentKey {
  static let defaultValue = "base"
}

extension EnvironmentValues {
  fileprivate var readerScopedTheme: String {
    get { self[ReaderScopedThemeKey.self] }
    set { self[ReaderScopedThemeKey.self] = newValue }
  }
}

/// Flips a body between reading and not reading the themed key.
///
/// Deliberately a plain class, not `@Observable`: reading it records no
/// dependency at all, which is the exact shape of the hole under test. The
/// first resolve records *no* environment read for the theme key, so the reader
/// index cannot deny the serve — and a later re-run reads the key for the first
/// time.
@MainActor
private final class ConditionalReadToggle {
  var readsTheme = false
}

private struct ThemeReader: View {
  @Environment(\.readerScopedTheme) private var theme

  var body: some View {
    Text("theme:\(theme)")
  }
}

/// A conditional read: `@Environment` wrappers update unconditionally, so the
/// only way a body can read a key it did not read before is for the reading
/// *view* to appear. That is what makes the read invisible to the reader index
/// that authorized the serve.
private struct ConditionalReader: View {
  let toggle: ConditionalReadToggle

  var body: some View {
    if toggle.readsTheme {
      ThemeReader()
    } else {
      Text("theme:unread")
    }
  }
}

/// A read-free `Equatable` memo boundary whose value never changes across the
/// frames under test, so the gate's value compare always passes and the
/// environment verdict is the only thing that can deny the serve.
private struct Boundary<Content: View>: View, Equatable {
  let content: Content

  // The memo comparator runs off the authoring actor, so the conformance must
  // be `nonisolated`.
  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    true
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("boundary")
      content
    }
  }
}

@MainActor
@Suite("Reader-scoped environment reuse")
struct ReaderScopedEnvironmentReuseTests {
  private let rootIdentity = testIdentity("Root")
  /// Every fixture below puts `Boundary` in the root stack's first slot, so the
  /// boundary under test always resolves here.
  private let boundaryIdentity = testIdentity("Root", "VStack[0]")

  private func makeRenderer() -> DefaultRenderer {
    DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
  }

  /// Whether the boundary was served *by toleration* — the only externally
  /// visible difference between "the door matched" and "the door tolerated".
  /// Aggregate reuse counts cannot tell them apart: a denied boundary's
  /// read-free siblings are tolerated regardless.
  private func toleratedBoundary(in renderer: DefaultRenderer) -> Bool {
    renderer.viewGraph.environmentDriftBoundaryIdentities.contains(boundaryIdentity)
  }

  // MARK: - The win

  /// A themed `.environment` write above a read-free boundary changes value.
  /// Nothing under the boundary reads the key, so the whole subtree is served
  /// instead of re-descending.
  @Test("an unread environment change no longer denies the memo door")
  func unreadEnvironmentChangeServesTheSubtree() {
    let renderer = makeRenderer()
    let toggle = ConditionalReadToggle()

    struct Root: View {
      let theme: String
      let toggle: ConditionalReadToggle
      let dynamic: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: ConditionalReader(toggle: toggle))
          Text(dynamic)
        }
        .environment(\.readerScopedTheme, theme)
      }
    }

    _ = renderer.render(
      Root(theme: "base", toggle: toggle, dynamic: "v1"),
      context: .init(identity: rootIdentity)
    )
    let frame = renderer.render(
      Root(theme: "dark", toggle: toggle, dynamic: "v2"),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("boundary"))
    #expect(rendered.contains("theme:unread"))
    #expect(rendered.contains("v2"))
    #expect(!rendered.contains("v1"))
    // The boundary's whole subtree is served across the environment change.
    #expect(toleratedBoundary(in: renderer))
    #expect(frame.diagnostics.work.resolvedNodesReused > 1)
  }

  // MARK: - Soundness

  /// The reader index is what authorizes the serve. A subtree that *does* read
  /// the changed key must be denied and must show the new value.
  @Test("a subtree that reads the changed key is denied")
  func readerInSubtreeDeniesTheServe() {
    let renderer = makeRenderer()

    struct Root: View {
      let theme: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: ThemeReader())
        }
        .environment(\.readerScopedTheme, theme)
      }
    }

    _ = renderer.render(
      Root(theme: "base"),
      context: .init(identity: rootIdentity)
    )
    let frame = renderer.render(
      Root(theme: "dark"),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("theme:dark"))
    #expect(!rendered.contains("theme:base"))
    #expect(!toleratedBoundary(in: renderer))
  }

  /// An interior writer makes its subtree's value authored rather than
  /// inherited, so the boundary's change says nothing about it — including the
  /// case no diff can see, where the interior write authors the boundary's
  /// prior value.
  @Test("an interior writer of the changed key denies the serve")
  func interiorWriterDeniesTheServe() {
    let renderer = makeRenderer()

    struct Root: View {
      let theme: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(
            content: Text("inner")
              .environment(\.readerScopedTheme, "interior")
          )
        }
        .environment(\.readerScopedTheme, theme)
      }
    }

    _ = renderer.render(
      Root(theme: "base"),
      context: .init(identity: rootIdentity)
    )
    _ = renderer.render(
      Root(theme: "dark"),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    #expect(!toleratedBoundary(in: renderer))
  }

  /// Framework-declared keys are consumed without read attribution, so no
  /// reader-set argument holds for them and the toleration must never fire.
  @Test("a framework-declared key change is never tolerated")
  func frameworkKeyChangeIsNeverTolerated() {
    let renderer = makeRenderer()

    struct Root: View {
      let limit: Int

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: Text("inner"))
        }
        .lineLimit(limit)
      }
    }

    _ = renderer.render(
      Root(limit: 1),
      context: .init(identity: rootIdentity)
    )
    _ = renderer.render(
      Root(limit: 2),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    #expect(renderer.viewGraph.environmentDriftBoundaryIdentities.isEmpty)
  }

  // MARK: - The conditional-read repair

  /// The hole the drift repair exists to close.
  ///
  /// Frame 1 resolves a subtree that does not read the themed key, so no reader
  /// edge is recorded. Frame 2 changes the key above it; the memo door sees no
  /// reader and serves — stranding every evaluator closure captured inside the
  /// subtree on the prior value. Frame 3 re-runs one of those closures on the
  /// dirty frontier, and its body reads the key *for the first time*. It must
  /// observe the current value; the reader index that authorized the serve
  /// could never have predicted this read.
  @Test("a first-time read after a tolerated serve observes the current value")
  func conditionalReadAfterToleratedServeObservesCurrentValue() throws {
    let renderer = makeRenderer()
    let toggle = ConditionalReadToggle()
    var rootBodyEvaluations = 0

    struct Root: View {
      let theme: String
      let toggle: ConditionalReadToggle
      let onBodyEvaluation: () -> Void

      var body: some View {
        let _ = onBodyEvaluation()
        VStack(alignment: .leading, spacing: 0) {
          Boundary(content: ConditionalReader(toggle: toggle))
        }
        .environment(\.readerScopedTheme, theme)
      }
    }

    _ = renderer.render(
      Root(theme: "base", toggle: toggle, onBodyEvaluation: { rootBodyEvaluations += 1 }),
      context: .init(identity: rootIdentity)
    )
    _ = renderer.render(
      Root(theme: "dark", toggle: toggle, onBodyEvaluation: { rootBodyEvaluations += 1 }),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )
    // Frame 2 must actually have tolerated the boundary, or frame 3 proves
    // nothing about the repair.
    #expect(toleratedBoundary(in: renderer))

    // The `false` arm of `ConditionalReader`'s builder condition — the node
    // whose re-run flips the branch and performs the first read.
    let readerIdentity = try #require(
      renderer.viewGraph.debugTotalStateSnapshot().identityByNodeID.values
        .first { $0.components.last == "false" },
      "could not locate the conditional reader's branch node"
    )

    toggle.readsTheme = true
    renderer.enableSelectiveEvaluation()
    let evaluationsBeforeFrameThree = rootBodyEvaluations
    let frame = renderer.render(
      Root(theme: "dark", toggle: toggle, onBodyEvaluation: { rootBodyEvaluations += 1 }),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [readerIdentity]
      )
    )

    // Guard against a vacuous pass: if the root body re-ran, the reader would
    // have been rebuilt from a fresh context and the repair never exercised.
    #expect(rootBodyEvaluations == evaluationsBeforeFrameThree)

    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("theme:dark"))
    #expect(!rendered.contains("theme:base"))
  }
}
