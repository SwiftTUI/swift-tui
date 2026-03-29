import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@Suite
struct GeometryReaderSurfaceTests {
  @Test("geometry reader exposes the current terminal surface size")
  func geometryReaderExposesTerminalSurfaceSize() {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = Size(width: 52, height: 13)

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
}
