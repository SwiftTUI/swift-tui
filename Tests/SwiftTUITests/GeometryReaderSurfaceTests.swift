import Testing

@testable import SwiftTUICore
@testable import SwiftTUI
@testable import SwiftTUIViews

@MainActor
@Suite
struct GeometryReaderSurfaceTests {
  @Test("geometry reader exposes the current terminal surface size")
  func geometryReaderExposesTerminalSurfaceSize() {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = CellSize(width: 52, height: 13)

    let artifacts = DefaultRenderer().render(
      GeometryReader { proxy in
        Text("Geometry \(proxy.size.width)x\(proxy.size.height)")
      },
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      ),
      proposal: .init(width: 52, height: 13)
    )

    #expect(artifacts.rasterSurface.lines.contains("Geometry 52x13"))
  }

  @Test("geometry reader uses a 10x10 ideal size under an unspecified proposal")
  func geometryReaderUsesTenByTenIdealSizeUnderUnspecifiedProposal() {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = CellSize(width: 52, height: 13)

    let artifacts = DefaultRenderer().render(
      GeometryReader { proxy in
        Text("\(proxy.size.width)x\(proxy.size.height)")
      },
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      )
    )

    #expect(artifacts.rasterSurface.lines.contains("10x10"))
  }

  @Test("geometry reader sees exact frame constraints")
  func geometryReaderSeesExactFrameConstraints() {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = CellSize(width: 40, height: 10)

    let artifacts = DefaultRenderer().render(
      GeometryReader { proxy in
        Text(proxy.size == CellSize(width: 7, height: 2) ? "Y" : "N")
      }
      .frame(width: 7, height: 2),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      ),
      proposal: .init(width: 40, height: 10)
    )

    #expect(artifacts.rasterSurface.lines.contains("Y"))
    #expect(!artifacts.rasterSurface.lines.contains("N"))
  }

  @Test("terminalSize remains the host surface inside local geometry")
  func terminalSizeRemainsHostSurfaceInsideLocalGeometry() {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = CellSize(width: 40, height: 10)

    let artifacts = DefaultRenderer().render(
      GeometryReader { proxy in
        EnvironmentReader(\.terminalSize) { terminalSize in
          Text(
            "local \(proxy.size.width)x\(proxy.size.height) host "
              + "\(terminalSize.width)x\(terminalSize.height)"
          )
        }
      }
      .frame(width: 24, height: 2),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      ),
      proposal: .init(width: 40, height: 10)
    )

    #expect(artifacts.rasterSurface.lines.contains("local 24x2 host 40x10"))
  }

  @Test("geometry reader sees padding-reduced constraints")
  func geometryReaderSeesPaddingReducedConstraints() {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = CellSize(width: 10, height: 5)

    let artifacts = DefaultRenderer().render(
      GeometryReader { proxy in
        Text(proxy.size == CellSize(width: 6, height: 3) ? "Y" : "N")
      }
      .padding(EdgeInsets(horizontal: 2, vertical: 1)),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      ),
      proposal: .init(width: 10, height: 5)
    )

    #expect(artifacts.rasterSurface.lines.contains { $0.contains("Y") })
    #expect(!artifacts.rasterSurface.lines.contains { $0.contains("N") })
  }

  @Test("geometry reader sees outset border-reduced constraints")
  func geometryReaderSeesOutsetBorderReducedConstraints() {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = CellSize(width: 10, height: 5)

    let artifacts = DefaultRenderer().render(
      GeometryReader { proxy in
        Text(proxy.size == CellSize(width: 8, height: 3) ? "Y" : "N")
      }
      .border(set: .single),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      ),
      proposal: .init(width: 10, height: 5)
    )

    #expect(artifacts.rasterSurface.lines.contains { $0.contains("Y") })
    #expect(!artifacts.rasterSurface.lines.contains { $0.contains("N") })
  }

  @Test("geometry reader sees finite flexible frame constraints")
  func geometryReaderSeesFiniteFlexibleFrameConstraints() {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = CellSize(width: 40, height: 10)

    let artifacts = DefaultRenderer().render(
      GeometryReader { proxy in
        Text(proxy.size == CellSize(width: 1, height: 1) ? "Y" : "N")
      }
      .frame(
        minWidth: 1,
        idealWidth: 1,
        maxWidth: 1,
        minHeight: 1,
        idealHeight: 1,
        maxHeight: 1
      ),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      ),
      proposal: .init(width: 40, height: 10)
    )

    #expect(artifacts.rasterSurface.lines.contains("Y"))
    #expect(!artifacts.rasterSurface.lines.contains("N"))
  }

  @Test("geometry reader preserves unconstrained axes inside flexible frames")
  func geometryReaderPreservesUnconstrainedAxesInsideFlexibleFrames() {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = CellSize(width: 40, height: 10)

    let artifacts = DefaultRenderer().render(
      GeometryReader { proxy in
        Text(proxy.size == CellSize(width: 8, height: 10) ? "Y" : "N")
      }
      .frame(maxWidth: 8),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      ),
      proposal: .init(width: 40, height: 10)
    )

    #expect(artifacts.rasterSurface.lines.contains("Y"))
    #expect(!artifacts.rasterSurface.lines.contains("N"))
  }

  @Test("geometry reader exposes the environment cellPixelMetrics")
  func geometryReaderExposesCellPixelMetrics() {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = CellSize(width: 40, height: 10)
    environmentValues.cellPixelMetrics = CellPixelMetrics(
      width: 10, height: 20, source: .reported
    )

    let artifacts = DefaultRenderer().render(
      GeometryReader { proxy in
        Text("Aspect \(Int(proxy.cellPixelMetrics.aspectRatio * 10))")
      },
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      )
    )

    // aspectRatio = 20/10 = 2.0; 2.0 * 10 = 20
    #expect(artifacts.rasterSurface.lines.contains("Aspect 20"))
  }

  @Test("geometry reader exposes .estimated when environment is default")
  func geometryReaderDefaultMetrics() {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = CellSize(width: 40, height: 10)

    let artifacts = DefaultRenderer().render(
      GeometryReader { proxy in
        Text(proxy.cellPixelMetrics.source == .estimated ? "est" : "rep")
      },
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      )
    )

    #expect(artifacts.rasterSurface.lines.contains("est"))
  }

  @Test("geometry reader sees custom Layout placement proposal instead of measurement proposal")
  func geometryReaderSeesCustomLayoutPlacementProposal() {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = CellSize(width: 40, height: 10)

    let artifacts = DefaultRenderer().render(
      DivergentProposalLayout {
        GeometryReader { proxy in
          Text(proxy.size == CellSize(width: 9, height: 3) ? "Y" : "N")
        }
      },
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      ),
      proposal: .init(width: 40, height: 10)
    )

    #expect(artifacts.rasterSurface.lines.contains { $0.contains("Y") })
    #expect(!artifacts.rasterSurface.lines.contains { $0.contains("N") })
  }

  @Test("repeated measurement does not realize geometry reader content repeatedly")
  func repeatedMeasurementDoesNotRealizeGeometryReaderContentRepeatedly() {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = CellSize(width: 40, height: 10)
    var realizationCount = 0

    let artifacts = DefaultRenderer().render(
      RepeatedMeasurementLayout {
        GeometryReader { proxy in
          countedGeometryText(
            "\(proxy.size.width)x\(proxy.size.height)",
            count: &realizationCount
          )
        }
      },
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      ),
      proposal: .init(width: 40, height: 10)
    )

    #expect(realizationCount == 1)
    #expect(artifacts.diagnostics.layoutDependentRealizations == 1)
    #expect(artifacts.rasterSurface.lines.contains { $0.contains("12x4") })
  }

  @Test("state inside geometry reader content persists across resize")
  func stateInsideGeometryReaderContentPersistsAcrossResize() throws {
    let renderer = DefaultRenderer()
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = CellSize(width: 20, height: 6)
    let firstActionRegistry = LocalActionRegistry()
    let identity = testIdentity("GeometryState")

    let first = renderer.render(
      GeometryReaderStatefulCounter(),
      context: ResolveContext(
        identity: identity,
        environmentValues: environmentValues,
        localActionRegistry: firstActionRegistry,
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 20, height: 6)
    )
    let actionIdentity = try #require(first.semanticSnapshot.focusRegions.first?.identity)
    #expect(firstActionRegistry.dispatch(identity: actionIdentity))

    environmentValues.terminalSize = CellSize(width: 30, height: 6)
    let updated = renderer.render(
      GeometryReaderStatefulCounter(),
      context: ResolveContext(
        identity: identity,
        environmentValues: environmentValues,
        localActionRegistry: LocalActionRegistry(),
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 30, height: 6)
    )

    #expect(updated.rasterSurface.lines.contains { $0.contains("Count 1") })
    #expect(updated.rasterSurface.lines.contains { $0.contains("Size 30x6") })
  }
}

private struct DivergentProposalLayout: Layout {
  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    _ = subviews.first?.sizeThatFits(.init(width: 4, height: 1))
    return LayoutSize(width: 9, height: 3)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    subviews.first?.place(
      at: bounds.origin,
      proposal: .init(width: 9, height: 3)
    )
  }
}

@MainActor
private func countedGeometryText(
  _ text: String,
  count: inout Int
) -> Text {
  count += 1
  return Text(text)
}

private struct RepeatedMeasurementLayout: Layout {
  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    _ = subviews.first?.sizeThatFits(.init(width: 4, height: 1))
    _ = subviews.first?.sizeThatFits(.init(width: 8, height: 2))
    return LayoutSize(width: 12, height: 4)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    subviews.first?.place(
      at: bounds.origin,
      proposal: .init(width: 12, height: 4)
    )
  }
}

private struct GeometryReaderStatefulCounter: View {
  var body: some View {
    GeometryReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        Text("Size \(proxy.size.width)x\(proxy.size.height)")
        GeometryCounterBody()
      }
    }
  }
}

private struct GeometryCounterBody: View {
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Count \(count)")
      Button(
        "Increment",
        action: {
          count += 1
        })
    }
  }
}
