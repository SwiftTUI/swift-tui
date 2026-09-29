import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct TextParagraphTests {
  @Test(arguments: [0, 2])
  func authoredParagraphsReserveHostSpacingWithoutChangingTheirTextBounds(spacing: Int) throws {
    var environment = EnvironmentValues()
    environment.hostParagraphSpacing = spacing
    let result = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("First paragraph").paragraph().accessibilityHidden(true)
        Text("Second paragraph").paragraph()
        Text("Ordinary\ntext")
      },
      context: .init(identity: testIdentity("Paragraphs"), environmentValues: environment),
      proposal: .init(width: 32, height: 16)
    )
    let paragraphs = result.semanticSnapshot.paragraphs
    #expect(paragraphs.count == 2)
    let first = try #require(paragraphs.first)
    let second = try #require(paragraphs.last)
    #expect(first.rect.size.height == 1)
    #expect(second.rect.origin.y - first.rect.origin.y == 1 + spacing)
    #expect(result.rasterSurface.lines.joined().contains("First paragraph"))
    #expect(!result.semanticSnapshot.accessibilityNodes.contains { $0.label == "First paragraph" })
  }

  @Test func geometryBoundsParagraphSpacing() throws {
    let size = CellSize(width: 32, height: 16)
    let pitch = PixelSize(width: 10, height: 24)
    #expect(
      HostGeometryRequest(revision: 1, size: size, cellPixelSize: pitch)?.paragraphSpacing == 0)
    #expect(
      HostGeometryRequest(revision: 1, size: size, cellPixelSize: pitch, paragraphSpacing: 2)?
        .paragraphSpacing == 2)
    #expect(
      HostGeometryRequest(revision: 1, size: size, cellPixelSize: pitch, paragraphSpacing: -1)
        == nil)
    #expect(
      HostGeometryRequest(revision: 1, size: size, cellPixelSize: pitch, paragraphSpacing: 8193)
        == nil)
  }
}
