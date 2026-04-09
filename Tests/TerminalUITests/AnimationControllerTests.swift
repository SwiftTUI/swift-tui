import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite("AnimationController snapshot extraction")
struct AnimationControllerSnapshotTests {
  @Test("extracts foregroundColor from local drawMetadata")
  func extractsLocalForegroundColor() throws {
    var drawMetadata = DrawMetadata()
    drawMetadata.baseStyle.foregroundStyle = .color(Color.red)

    let node = ResolvedNode(
      identity: Identity(components: [.named("test")]),
      kind: .view("Leaf"),
      drawMetadata: drawMetadata
    )

    let snapshot = AnimatableSnapshot.extract(from: node)
    #expect(snapshot.foregroundColor == Color.red)
  }

  @Test("falls back to environment snapshot when local drawMetadata has no foreground")
  func extractsForegroundFromEnvironmentFallback() throws {
    // Mirror the gallery case: a leaf (TextFigure) whose drawMetadata
    // is default but whose resolved environment carries the foreground
    // style set by an ancestor `.foregroundStyle(color)` modifier.
    var style = StyleEnvironmentSnapshot()
    style.foregroundStyle = .color(Color.blue)
    let environment = EnvironmentSnapshot(style: style)

    let node = ResolvedNode(
      identity: Identity(components: [.named("test")]),
      kind: .view("Leaf"),
      environmentSnapshot: environment,
      drawMetadata: DrawMetadata()
    )

    let snapshot = AnimatableSnapshot.extract(from: node)
    #expect(
      snapshot.foregroundColor == Color.blue,
      "environment-carried foreground styles must be extracted so `.foregroundStyle(color)` on non-Text views animates"
    )
  }

  @Test("local drawMetadata takes priority over environment snapshot")
  func localDrawMetadataWinsOverEnvironment() throws {
    var style = StyleEnvironmentSnapshot()
    style.foregroundStyle = .color(Color.blue)
    let environment = EnvironmentSnapshot(style: style)

    var drawMetadata = DrawMetadata()
    drawMetadata.baseStyle.foregroundStyle = .color(Color.red)

    let node = ResolvedNode(
      identity: Identity(components: [.named("test")]),
      kind: .view("Leaf"),
      environmentSnapshot: environment,
      drawMetadata: drawMetadata
    )

    let snapshot = AnimatableSnapshot.extract(from: node)
    #expect(snapshot.foregroundColor == Color.red)
  }
}
