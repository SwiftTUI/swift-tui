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
