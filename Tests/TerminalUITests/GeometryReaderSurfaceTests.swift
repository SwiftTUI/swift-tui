import Testing

@testable import Core
@testable import TerminalUI
@testable import View

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
      )
    )

    #expect(artifacts.rasterSurface.lines.contains("Geometry 52x13"))
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
}
