import SwiftTUICore
import SwiftTUIRuntime
import Testing

// Stage 3 acceptance fixture (plan 2026-08-04-003 §7): a third-party dynamic
// property written against the PUBLIC authoring surface only — the wrapper
// and view below use nothing beyond what `import SwiftTUI` re-exports (the
// non-@testable imports here expose package-level plumbing to the *driver*
// code only; the fixture declarations stick to public API). It must behave
// on both the one-shot renderer path and the composed terminal runtime path.
import SwiftTUI

/// The example third-party wrapper: composes `@State` for storage, exposes
/// an imperative mutator through its projection. Conforming to
/// `DynamicProperty` is what gives each instance distinct composed storage.
@propertyWrapper
@MainActor
private struct CountedBumps: DynamicProperty {
  @State private var count = 0

  init() {}

  var wrappedValue: Int {
    count
  }

  var projectedValue: CountedBumps {
    self
  }

  func bump() {
    count += 1
  }
}

private struct BumpPairView: View {
  @CountedBumps private var left: Int
  @CountedBumps private var right: Int

  var body: some View {
    VStack {
      Button("Bump Left") { [_left] in _left.bump() }
      Button("Bump Right") { [_right] in _right.bump() }
      Text("L \(left) R \(right)")
    }
  }
}

@MainActor
struct DynamicPropertyPublicSurfaceTests {
  @Test("a public-API wrapper keeps distinct per-instance state on the one-shot renderer path")
  func publicWrapperOnOneShotRendererPath() throws {
    let renderer = DefaultRenderer()
    let registry = LocalActionRegistry()

    let initial = renderer.render(
      BumpPairView(),
      context: ResolveContext(
        identity: testIdentity("PublicWrapperOneShot"),
        localActionRegistry: registry,
        applyEnvironmentValues: true
      )
    )
    #expect(initial.rasterSurface.lines.contains { $0.contains("L 0 R 0") })

    let regions = initial.semanticSnapshot.focusRegions
    #expect(regions.count == 2)
    let leftIdentity = try #require(regions.first?.identity)
    let rightIdentity = try #require(regions.last?.identity)

    #expect(registry.dispatch(identity: leftIdentity))
    #expect(registry.dispatch(identity: leftIdentity))
    #expect(registry.dispatch(identity: rightIdentity))

    let secondRegistry = LocalActionRegistry()
    let updated = renderer.render(
      BumpPairView(),
      context: ResolveContext(
        identity: testIdentity("PublicWrapperOneShot"),
        localActionRegistry: secondRegistry,
        applyEnvironmentValues: true
      )
    )
    #expect(
      updated.rasterSurface.lines.contains { $0.contains("L 2 R 1") },
      "distinct per-instance storage did not round-trip; lines: \(updated.rasterSurface.lines)"
    )
  }

  @Test("a public-API wrapper keeps distinct per-instance state on the terminal runtime path")
  func publicWrapperOnTerminalRuntimePath() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PublicWrapperTerminal"),
      size: .init(width: 40, height: 8)
    ) {
      BumpPairView()
    }
    defer { harness.shutdown() }

    var frame = try harness.clickText("Bump Left")
    #expect(frame.contains("L 1 R 0"), "frame: \(frame)")
    frame = try harness.clickText("Bump Right")
    #expect(frame.contains("L 1 R 1"), "frame: \(frame)")
    frame = try harness.clickText("Bump Left")
    #expect(frame.contains("L 2 R 1"), "frame: \(frame)")
  }
}
