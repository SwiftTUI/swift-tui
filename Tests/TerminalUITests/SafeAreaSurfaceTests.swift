import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct SafeAreaSurfaceTests {
  @Test("GeometryReader exposes container safe area insets")
  func geometryReaderExposesContainerSafeAreaInsets() {
    let artifacts = render(
      GeometryReader { proxy in
        Text(
          "size \(proxy.size.width)x\(proxy.size.height) safe \(proxy.safeAreaInsets.top),\(proxy.safeAreaInsets.leading),\(proxy.safeAreaInsets.bottom),\(proxy.safeAreaInsets.trailing)"
        )
      },
      terminalSize: .init(width: 40, height: 12),
      safeAreaInsets: .init(top: 1, leading: 2, bottom: 3, trailing: 4)
    )

    #expect(
      artifacts.rasterSurface.lines.contains { line in
        line.contains("size 40x12 safe 1,2,3,4")
      }
    )
  }

  @Test("container safe area offsets root content by default")
  func containerSafeAreaOffsetsRootContentByDefault() throws {
    let artifacts = render(
      Text("X"),
      terminalSize: .init(width: 20, height: 8),
      safeAreaInsets: .init(top: 1, leading: 2, bottom: 1, trailing: 0)
    )

    let rootChild = try #require(artifacts.placedTree.children.first)
    #expect(rootChild.bounds.origin == .init(x: 2, y: 1))
    #expect(rootChild.bounds.size == .init(width: 1, height: 1))
  }

  @Test("ignoresSafeArea reclaims selected edges and zeroes geometry safe area")
  func ignoresSafeAreaReclaimsSelectedEdgesAndZeroesGeometry() throws {
    let artifacts = render(
      GeometryReader { proxy in
        Text(
          "size \(proxy.size.width)x\(proxy.size.height) safe \(proxy.safeAreaInsets.top),\(proxy.safeAreaInsets.leading)"
        )
      }
      .ignoresSafeArea([.top, .leading]),
      terminalSize: .init(width: 20, height: 8),
      safeAreaInsets: .init(top: 1, leading: 2, bottom: 0, trailing: 0)
    )

    let ignoreWrapper = try #require(artifacts.placedTree.children.first)
    let content = try #require(ignoreWrapper.children.first)
    #expect(content.bounds.origin == .init(x: 0, y: 0))
    #expect(
      artifacts.rasterSurface.lines.contains { line in
        line.contains("size 20x8 safe 0,0")
      }
    )
  }

  @Test("ignoresSafeArea restores safeAreaPadding-tightened GeometryReader size")
  func ignoresSafeAreaRestoresSafeAreaPaddingTightenedGeometrySize() throws {
    let artifacts = render(
      GeometryReader { proxy in
        Text(proxy.size == CellSize(width: 20, height: 8) ? "Y" : "N")
      }
      .ignoresSafeArea([.top, .leading])
      .safeAreaPadding([.top, .leading]),
      terminalSize: .init(width: 20, height: 8),
      safeAreaInsets: .init(top: 1, leading: 2, bottom: 0, trailing: 0)
    )

    #expect(artifacts.rasterSurface.lines.contains { $0.contains("Y") })
    #expect(!artifacts.rasterSurface.lines.contains { $0.contains("N") })
  }

  @Test("ignoresSafeArea restores only selected safeAreaPadding geometry edges")
  func ignoresSafeAreaRestoresOnlySelectedSafeAreaPaddingGeometryEdges() throws {
    let artifacts = render(
      GeometryReader { proxy in
        Text(proxy.size == CellSize(width: 18, height: 8) ? "Y" : "N")
      }
      .ignoresSafeArea(.top)
      .safeAreaPadding([.top, .leading]),
      terminalSize: .init(width: 20, height: 8),
      safeAreaInsets: .init(top: 1, leading: 2, bottom: 0, trailing: 0)
    )

    #expect(artifacts.rasterSurface.lines.contains { $0.contains("Y") })
    #expect(!artifacts.rasterSurface.lines.contains { $0.contains("N") })
  }

  @Test("safeAreaPadding adds safe-area-derived layout space on selected edges")
  func safeAreaPaddingAddsSafeAreaDerivedLayoutSpace() throws {
    let artifacts = render(
      Text("X").safeAreaPadding([.top, .leading]),
      terminalSize: .init(width: 20, height: 8),
      safeAreaInsets: .init(top: 1, leading: 2, bottom: 0, trailing: 0)
    )

    let paddingWrapper = try #require(artifacts.placedTree.children.first)
    let content = try #require(paddingWrapper.children.first)
    #expect(paddingWrapper.bounds.origin == .init(x: 2, y: 1))
    #expect(content.bounds.origin == .init(x: 4, y: 2))
  }

  @Test("safeAreaPadding tightens GeometryReader size")
  func safeAreaPaddingTightensGeometryReaderSize() throws {
    let artifacts = render(
      GeometryReader { proxy in
        Text(proxy.size == CellSize(width: 18, height: 7) ? "Y" : "N")
      }
      .safeAreaPadding([.top, .leading]),
      terminalSize: .init(width: 20, height: 8),
      safeAreaInsets: .init(top: 1, leading: 2, bottom: 0, trailing: 0)
    )

    #expect(artifacts.rasterSurface.lines.contains { $0.contains("Y") })
    #expect(!artifacts.rasterSurface.lines.contains { $0.contains("N") })
  }

  @Test("safeAreaInset uses reclaimed safe area before shrinking the base content")
  func safeAreaInsetUsesReclaimedSafeAreaBeforeShrinkingBaseContent() throws {
    let artifacts = render(
      Text("B")
        .safeAreaInset(edge: .top, alignment: .topLeading) {
          VStack(spacing: 0) {
            Text("I")
            Text("J")
          }
        },
      terminalSize: .init(width: 20, height: 8),
      safeAreaInsets: .init(top: 1, leading: 0, bottom: 0, trailing: 0)
    )

    let insetWrapper = try #require(artifacts.placedTree.children.first)
    let base = try #require(insetWrapper.children.first)
    let inset = try #require(insetWrapper.children.dropFirst().first)

    #expect(inset.bounds.origin == .init(x: 0, y: 0))
    #expect(inset.bounds.size == .init(width: 1, height: 2))
    #expect(base.bounds.origin == .init(x: 0, y: 2))
    #expect(base.bounds.size == .init(width: 1, height: 1))
  }

  private func render<V: View>(
    _ view: V,
    terminalSize: CellSize,
    safeAreaInsets: EdgeInsets
  ) -> FrameArtifacts {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = terminalSize
    environmentValues.safeAreaInsets = safeAreaInsets
    return DefaultRenderer().render(
      view,
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      ),
      proposal: .init(
        width: terminalSize.width,
        height: terminalSize.height
      )
    )
  }
}
