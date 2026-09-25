import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite
struct CanonicalDrawSnapshotTests {
  private let bounds = CellRect(origin: .zero, size: .init(width: 4, height: 2))

  private func tree(_ commands: [DrawCommand] = []) -> DrawNode {
    DrawNode(identity: testIdentity("canonical"), bounds: bounds, commands: commands)
  }

  private func fill(_ color: Color) -> DrawCommand {
    .fill(bounds: bounds, geometry: .rectangle, insetAmount: 0, style: .color(color), mode: .full)
  }

  @Test("every stored draw-node field is preserved or explicitly normalized")
  func projectionCensus() {
    let fields = Set(Mirror(reflecting: tree()).children.compactMap(\.label))
    let preserved: Set<String> = [
      "identity", "environmentSnapshot", "bounds", "clipBounds", "metadata",
      "drawEffects", "commands", "postCommands", "children",
    ]
    let normalized: Set<String> = ["viewNodeID", "subtreeNodeSummary", "subtreeBounds"]
    #expect(fields == preserved.union(normalized))
  }

  @Test("opaque drawing payloads nested in groups fail instead of comparing equal")
  func unsupportedPayload() {
    let command = DrawCommand.canvas(
      bounds: bounds, payload: .init(drawing: CanonicalOpaqueDrawing()),
      foregroundStyle: .color(.red)
    )
    #expect(
      throws: SnapshotRenderer.CanonicalDrawError.unsupportedValue("canvas or foreignSurface")
    ) {
      try SnapshotRenderer().canonicalDrawTree(tree([.group(bounds: bounds, children: [command])]))
    }
  }

  @Test("allocation IDs and environment bookkeeping normalize without changing raster output")
  func incidentalFields() throws {
    var first = tree([fill(.red)])
    first.viewNodeID = .init(rawValue: 1)
    first.environmentSnapshot.debugSignature = "first allocation"
    first.environmentSnapshot.values = ["debug-only": "one"]
    var second = first
    second.viewNodeID = .init(rawValue: 99)
    second.environmentSnapshot.debugSignature = "second allocation"
    second.environmentSnapshot.values = ["debug-only": "two"]
    let printer = SnapshotRenderer()
    #expect(try printer.canonicalDrawTree(first) == printer.canonicalDrawTree(second))
    #expect(Rasterizer().rasterize(first) == Rasterizer().rasterize(second))
    #expect(try printer.canonicalDrawDifference(first, second) == "canonical draw v1: equal")
  }

  @Test("paint and child order, clipping, post-paint and effects remain distinct")
  func orderedComposition() throws {
    let printer = SnapshotRenderer()
    let first = tree([fill(.red), fill(.blue)])
    let reversed = tree([fill(.blue), fill(.red)])
    #expect(try printer.canonicalDrawTree(first) != printer.canonicalDrawTree(reversed))
    #expect(Rasterizer().rasterize(first) != Rasterizer().rasterize(reversed))
    var root = tree()
    root.children = [tree([fill(.red)]), tree([fill(.blue)])]
    var changed = root
    changed.children.reverse()
    #expect(try printer.canonicalDrawTree(root) != printer.canonicalDrawTree(changed))
    changed = root
    changed.clipBounds = .init(origin: .zero, size: .init(width: 1, height: 1))
    #expect(try printer.canonicalDrawTree(root) != printer.canonicalDrawTree(changed))
    changed = root
    changed.postCommands = [fill(.red)]
    #expect(try printer.canonicalDrawTree(root) != printer.canonicalDrawTree(changed))
    changed = root
    changed.drawEffects = .init([.compositingGroup, .blendMode(.multiply)])
    #expect(try printer.canonicalDrawTree(root) != printer.canonicalDrawTree(changed))
  }

  @Test("gradient colors, opacity and full text lines are retained")
  func nonAbbreviatedValues() throws {
    let printer = SnapshotRenderer()
    func gradient(_ color: Color) -> DrawNode {
      tree([
        .fill(
          bounds: bounds, geometry: .rectangle, insetAmount: 0,
          style: .angularGradient(.init(colors: [.red, color], center: .center)), mode: .full)
      ])
    }
    #expect(
      try printer.canonicalDrawTree(gradient(.blue)) != printer.canonicalDrawTree(gradient(.green)))
    let first = tree([.preformattedText(bounds: bounds, lines: ["same", "one"], style: .init())])
    let second = tree([
      .preformattedText(bounds: bounds, lines: ["same", "two"], style: .init(opacity: 0.5))
    ])
    #expect(try printer.canonicalDrawTree(first) != printer.canonicalDrawTree(second))
    let textOnly = tree([
      .preformattedText(bounds: bounds, lines: ["same", "two"], style: .init())
    ])
    let opacityOnly = tree([
      .preformattedText(bounds: bounds, lines: ["same", "one"], style: .init(opacity: 0.5))
    ])
    #expect(try printer.canonicalDrawTree(first) != printer.canonicalDrawTree(textOnly))
    #expect(try printer.canonicalDrawTree(first) != printer.canonicalDrawTree(opacityOnly))
    let nested = tree([.group(bounds: bounds, children: [.clip(bounds: bounds, child: fill(.red))])]
    )
    #expect(try printer.canonicalDrawTree(nested) != printer.canonicalDrawTree(tree()))
  }

  @Test("mesh gradients in commands and styles serialize structurally")
  func meshGradientValues() throws {
    let printer = SnapshotRenderer()
    func mesh(corner: Color = .yellow, x: Float = 1) -> MeshGradient {
      MeshGradient(
        width: 2, height: 2,
        points: [SIMD2(0, 0), SIMD2(x, 0), SIMD2(0, 1), SIMD2(1, 1)],
        colors: [.red, .blue, .green, corner])
    }
    func filled(_ mesh: MeshGradient) -> DrawNode {
      tree([
        .fill(
          bounds: bounds, geometry: .rectangle, insetAmount: 0, style: .meshGradient(mesh),
          mode: .full)
      ])
    }
    let first = try printer.canonicalDrawTree(filled(mesh()))
    #expect(first.contains("MeshGradient{\"width\":2,\"height\":2,"))
    #expect(try first == printer.canonicalDrawTree(filled(mesh())))
    #expect(try first != printer.canonicalDrawTree(filled(mesh(corner: .white))))
    #expect(try first != printer.canonicalDrawTree(filled(mesh(x: 0.5))))
    var styled = tree()
    styled.environmentSnapshot.style.foregroundStyle = .meshGradient(mesh())
    #expect(try printer.canonicalDrawTree(styled).contains("MeshGradient{"))
  }

  @Test("overlapping image order, bytes, identity and opacity remain distinct")
  func images() throws {
    let printer = SnapshotRenderer()
    func image(_ name: String, _ bytes: [UInt8], opacity: Double = 1) -> DrawCommand {
      var payload = ImagePayload(source: .data(bytes))
      payload.opacity = opacity
      return .image(bounds: bounds, identity: testIdentity(name), payload: payload)
    }
    let first = tree([image("a", [1, 2]), image("b", [3, 4])])
    for commands in [
      [image("b", [3, 4]), image("a", [1, 2])],
      [image("a", [2, 1]), image("b", [3, 4])],
      [image("renamed", [1, 2]), image("b", [3, 4])],
      [image("a", [1, 2], opacity: 0.5), image("b", [3, 4])],
    ] {
      #expect(try printer.canonicalDrawTree(first) != printer.canonicalDrawTree(tree(commands)))
    }
  }

  @Test("canonical diagnostic compares actual raster paints and emits a useful artifact")
  func diagnosticComparison() throws {
    let expected = tree([fill(.red)])
    let actual = tree([fill(.blue)])
    let printer = SnapshotRenderer()
    let difference = try printer.canonicalDrawDifference(expected, actual)
    #expect(Rasterizer().rasterize(expected) != Rasterizer().rasterize(actual))
    #expect(difference.contains("root.paint[0]"))
    #expect(difference.contains("@@ line"))
    print("[canonical-draw expected]\n\(try printer.canonicalDrawTree(expected))")
    print("[canonical-draw actual]\n\(try printer.canonicalDrawTree(actual))")
    print("[canonical-draw difference]\n\(difference)")
  }
}

private struct CanonicalOpaqueDrawing: CanvasDrawing {
  func draw(into context: inout CanvasContext) {}
}
