import Foundation
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Keep the real wire-limit workload in the isolated core lane (STUI-1521).
// Reducing the source to fit the runtime latency ratchet would stop testing
// the oversized ordinary-Text regression from STUI-809.
@MainActor
@Suite
struct AccessibilityLargeTextWireBudgetTests {
  @Test func largeOrdinaryTextStillPublishesItsClippedRaster() throws {
    let source = String(repeating: "x", count: HostWireBudget.recordBytes + 1)
    let rendered = DefaultRenderer().render(
      Text(source).lineLimit(1),
      context: .init(identity: testIdentity("OversizedText")),
      proposal: .init(width: 10, height: 1))
    #expect(rendered.semanticSnapshot.accessibilityNodes.contains { $0.label == source })
    let frame = SemanticHostFrame(
      sequence: 1, raster: rendered.rasterSurface,
      semantics: rendered.semanticSnapshot, focusedIdentity: nil)
    let output = WebSurfaceFrameEncoder.encode(frame)
    #expect(output.hasPrefix("\u{1e}surface:"))
    #expect(output.utf8.count <= HostWireBudget.recordBytes + 1)
    #expect(output.filter { $0 == "\n" }.count == 1)
    let decoded = try #require(
      JSONSerialization.jsonObject(
        with: Data(output.dropFirst("\u{1e}surface:".count).utf8)) as? [String: Any])
    #expect((decoded["accessibilityTree"] as? [Any] ?? []).isEmpty)
    #expect(decoded["width"] as? Int == 10)
    #expect(decoded["height"] as? Int == 1)
  }
}
