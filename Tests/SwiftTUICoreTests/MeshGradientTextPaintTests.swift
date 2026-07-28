import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Test("mesh foreground paints text with prepared cell samples")
func meshGradientTextPaint() {
  expectMeshForeground(
    command: .text(
      bounds: meshTextBounds,
      content: "ABCD",
      style: meshTextStyle(),
      lineLimit: nil,
      truncationMode: .tail,
      wrappingStrategy: .wordBoundary
    ),
    identity: "mesh-text"
  )
}

@Test("mesh foreground paints preformatted text with prepared cell samples")
func meshGradientPreformattedTextPaint() {
  expectMeshForeground(
    command: .preformattedText(
      bounds: meshTextBounds,
      lines: ["ABCD"],
      style: meshTextStyle()
    ),
    identity: "mesh-preformatted"
  )
}

@Test("mesh foreground paints styled preformatted text with prepared cell samples")
func meshGradientStyledPreformattedTextPaint() {
  expectMeshForeground(
    command: .styledPreformattedText(
      bounds: meshTextBounds,
      lines: [
        PreformattedTextLine(
          runs: [
            PreformattedTextRun(content: "ABCD")
          ])
      ],
      style: meshTextStyle()
    ),
    identity: "mesh-styled-preformatted"
  )
}

@Test("mesh foreground paints rich text with prepared cell samples")
func meshGradientRichTextPaint() {
  expectMeshForeground(
    command: .richText(
      bounds: meshTextBounds,
      payload: RichTextPayload(runs: [RichTextRun(text: "ABCD", style: meshTextStyle())]),
      lineLimit: nil,
      truncationMode: .tail,
      wrappingStrategy: .wordBoundary
    ),
    identity: "mesh-rich-text"
  )
}

@Test("mesh foreground resolves from the style environment")
func meshGradientEnvironmentTextPaint() {
  let mesh = meshTextGradient()
  let surface = rasterizedTextSurface(
    command: .text(
      bounds: meshTextBounds,
      content: "ABCD",
      style: .init(),
      lineLimit: nil,
      truncationMode: .tail,
      wrappingStrategy: .wordBoundary
    ),
    identity: "mesh-environment",
    environment: .init(style: .init(foregroundStyle: .meshGradient(mesh)))
  )

  expectForegroundSamples(surface, mesh: mesh)
}

@Test("opacity-wrapped mesh foreground preserves per-cell sampling")
func opacityWrappedMeshGradientTextPaint() {
  let mesh = meshTextGradient()
  let opacity = 0.4
  let surface = rasterizedTextSurface(
    command: .text(
      bounds: meshTextBounds,
      content: "ABCD",
      style: .init(foregroundStyle: .opacity(.meshGradient(mesh), opacity)),
      lineLimit: nil,
      truncationMode: .tail,
      wrappingStrategy: .wordBoundary
    ),
    identity: "mesh-opacity-wrapper"
  )
  let faded = MeshGradient(
    width: mesh.width,
    height: mesh.height,
    points: mesh.points,
    colors: mesh.colors.map { $0.opacity(opacity) },
    background: mesh.background.opacity(opacity),
    smoothsColors: mesh.smoothsColors,
    colorSpace: mesh.colorSpace
  )

  expectForegroundSamples(surface, mesh: faded)
}

@Test("mesh background paints text with prepared cell samples")
func meshGradientBackgroundTextPaint() {
  let mesh = meshTextGradient()
  let surface = rasterizedTextSurface(
    command: .text(
      bounds: meshTextBounds,
      content: "ABCD",
      style: .init(foregroundStyle: .color(.white), backgroundStyle: .meshGradient(mesh)),
      lineLimit: nil,
      truncationMode: .tail,
      wrappingStrategy: .wordBoundary
    ),
    identity: "mesh-background"
  )
  let prepared = preparedTextMesh(mesh)

  for x in 0..<meshTextBounds.size.width {
    #expect(surface.cells[0][x].style?.backgroundColor == prepared.color(atCellX: x, y: 0))
  }
}

@Test("fractional text opacity blends mesh foreground against each painted cell background")
func meshGradientFractionalOpacityTextPaint() throws {
  let mesh = meshTextGradient()
  let opacity = 0.35
  let underlay = LinearGradient(
    colors: [.blue, .yellow],
    startPoint: .leading,
    endPoint: .trailing
  )
  let draw = DrawNode(
    identity: testIdentity("mesh-fractional-opacity"),
    bounds: meshTextBounds,
    commands: [
      .fill(
        bounds: meshTextBounds,
        geometry: .rectangle,
        insetAmount: 0,
        style: .linearGradient(underlay),
        mode: .full
      ),
      .text(
        bounds: meshTextBounds,
        content: "ABCD",
        style: .init(foregroundStyle: .meshGradient(mesh), opacity: opacity),
        lineLimit: nil,
        truncationMode: .tail,
        wrappingStrategy: .wordBoundary
      ),
    ]
  )
  let surface = Rasterizer().rasterize(draw)
  let prepared = preparedTextMesh(mesh)
  let rasterizer = Rasterizer()

  for x in 0..<meshTextBounds.size.width {
    let background = try #require(
      rasterizer.sample(underlay, in: meshTextBounds, x: x, y: 0)
    )
    let expected = prepared.color(atCellX: x, y: 0).mixed(
      with: background,
      amount: 1 - opacity
    )
    #expect(surface.cells[0][x].style?.foregroundColor == expected)
    #expect(surface.cells[0][x].style?.backgroundColor == background)
  }
}

@Test("styled text resolves a distinct mesh once per run")
func meshGradientStyledTextRunPaint() {
  let first = meshTextGradient()
  let second = MeshGradient(
    width: 2,
    height: 2,
    points: [.init(0, 0), .init(1, 0), .init(0, 1), .init(1, 1)],
    colors: [.cyan, .magenta, .yellow, .white],
    background: .black,
    smoothsColors: false,
    colorSpace: .device
  )
  let bounds = CellRect(origin: .zero, size: .init(width: 4, height: 1))
  let surface = rasterizedTextSurface(
    command: .styledPreformattedText(
      bounds: bounds,
      lines: [
        PreformattedTextLine(
          runs: [
            PreformattedTextRun(
              content: "AB",
              style: .init(foregroundStyle: .meshGradient(first))
            ),
            PreformattedTextRun(
              content: "CD",
              style: .init(foregroundStyle: .meshGradient(second))
            ),
          ])
      ],
      style: .init()
    ),
    identity: "mesh-runs"
  )
  let firstPrepared = preparedTextMesh(first, bounds: bounds)
  let secondPrepared = preparedTextMesh(second, bounds: bounds)

  for x in 0..<2 {
    #expect(surface.cells[0][x].style?.foregroundColor == firstPrepared.color(atCellX: x, y: 0))
  }
  for x in 2..<4 {
    #expect(surface.cells[0][x].style?.foregroundColor == secondPrepared.color(atCellX: x, y: 0))
  }
}

@Test("non-mesh linear semantic and tile foreground styles remain cell-identical")
func nonMeshStyledTextPaint() {
  let bounds = CellRect(origin: .zero, size: .init(width: 4, height: 3))
  let linearBounds = CellRect(origin: .zero, size: .init(width: 4, height: 1))
  let linear = LinearGradient(
    colors: [.red, .blue],
    startPoint: .leading,
    endPoint: .trailing
  )
  let tile = TileStyle(.dots, foreground: .red, background: .blue)
  let environment = EnvironmentSnapshot(
    style: .init(
      theme: Theme(foreground: .green),
      foregroundStyle: .semantic(.foreground)
    ))
  let draw = DrawNode(
    identity: testIdentity("non-mesh-text"),
    environmentSnapshot: environment,
    bounds: bounds,
    commands: [
      .text(
        bounds: linearBounds,
        content: "ABCD",
        style: .init(foregroundStyle: .linearGradient(linear)),
        lineLimit: nil,
        truncationMode: .tail,
        wrappingStrategy: .wordBoundary
      ),
      .preformattedText(
        bounds: .init(origin: .init(x: 0, y: 1), size: .init(width: 4, height: 1)),
        lines: ["EFGH"],
        style: .init(foregroundStyle: .semantic(.foreground))
      ),
      .preformattedText(
        bounds: .init(origin: .init(x: 0, y: 2), size: .init(width: 4, height: 1)),
        lines: ["IJKL"],
        style: .init(foregroundStyle: .tileStyle(tile))
      ),
    ]
  )
  let surface = Rasterizer().rasterize(draw)
  let rasterizer = Rasterizer()

  for x in 0..<4 {
    #expect(
      surface.cells[0][x].style?.foregroundColor
        == rasterizer.sample(linear, in: linearBounds, x: x, y: 0)
    )
    #expect(surface.cells[1][x].style?.foregroundColor == .green)
    #expect(surface.cells[2][x].style?.foregroundColor == .red)
  }
}

@MainActor
@Test("mesh text reuses one shared preparation across paints")
func meshGradientTextReusesSharedPreparation() throws {
  let cache = PreparedMeshGradientCache.shared
  cache.reset()
  defer { cache.reset() }
  let mesh = MeshGradient(
    width: 2,
    height: 2,
    points: [.init(0, 0), .init(1, 0), .init(0, 1), .init(1, 1)],
    colors: [
      Color(red: 0.123, green: 0.234, blue: 0.345),
      Color(red: 0.456, green: 0.567, blue: 0.678),
      Color(red: 0.789, green: 0.321, blue: 0.654),
      Color(red: 0.246, green: 0.813, blue: 0.579),
    ],
    background: .clear,
    smoothsColors: false,
    colorSpace: .device
  )
  let input = MeshGradientRasterInput(
    width: mesh.width,
    height: mesh.height,
    points: mesh.points,
    colors: mesh.colors,
    background: mesh.background,
    smoothsColors: mesh.smoothsColors,
    colorSpace: .device
  )
  let command = DrawCommand.text(
    bounds: meshTextBounds,
    content: "ABCD",
    style: .init(foregroundStyle: .meshGradient(mesh)),
    lineLimit: nil,
    truncationMode: .tail,
    wrappingStrategy: .wordBoundary
  )
  let draw = DrawNode(
    identity: testIdentity("mesh-shared-cache"),
    bounds: meshTextBounds,
    commands: [command]
  )

  let first = Rasterizer().rasterize(draw)
  let second = Rasterizer().rasterize(draw)

  #expect(first == second)
  #expect(
    cache.entryMetrics(for: input, bounds: meshTextBounds)
      == .init(lookups: 2, hits: 1, misses: 1)
  )

  let snapshot = try #require(
    MemoryMetricRegistry.shared.snapshotAll().first {
      $0.name == "PreparedMeshGradientCache.entries"
    })
  #expect(snapshot.count >= 1)
  #expect(
    snapshot.detail?["triangles"] ?? 0
      >= PreparedMeshGradient(input: input, bounds: meshTextBounds).diagnostics.triangleCount
  )
}

private let meshTextBounds = CellRect(origin: .zero, size: .init(width: 4, height: 1))

private func meshTextGradient() -> MeshGradient {
  MeshGradient(
    width: 3,
    height: 3,
    points: [
      .init(0, 0), .init(0.5, -0.05), .init(1, 0),
      .init(-0.05, 0.5), .init(0.65, 0.2), .init(1.05, 0.5),
      .init(0, 1), .init(0.5, 1.05), .init(1, 1),
    ],
    colors: [
      .red, .green, .blue,
      .yellow, .magenta, .cyan,
      .white, .gray, .black,
    ],
    background: .clear,
    smoothsColors: true,
    colorSpace: .perceptual
  )
}

private func meshTextStyle() -> TextStyle {
  .init(foregroundStyle: .meshGradient(meshTextGradient()))
}

private func preparedTextMesh(
  _ mesh: MeshGradient,
  bounds: CellRect = meshTextBounds
) -> PreparedMeshGradient {
  PreparedMeshGradient(
    input: MeshGradientRasterInput(
      width: mesh.width,
      height: mesh.height,
      points: mesh.points,
      colors: mesh.colors,
      background: mesh.background,
      smoothsColors: mesh.smoothsColors,
      colorSpace: mesh.colorSpace == .device ? .device : .perceptual
    ),
    bounds: bounds
  )
}

private func rasterizedTextSurface(
  command: DrawCommand,
  identity: String,
  environment: EnvironmentSnapshot = .init()
) -> RasterSurface {
  Rasterizer().rasterize(
    DrawNode(
      identity: testIdentity(identity),
      environmentSnapshot: environment,
      bounds: meshTextBounds,
      commands: [command]
    ))
}

private func expectMeshForeground(
  command: DrawCommand,
  identity: String
) {
  let mesh = meshTextGradient()
  let surface = rasterizedTextSurface(command: command, identity: identity)
  expectForegroundSamples(surface, mesh: mesh)
}

private func expectForegroundSamples(
  _ surface: RasterSurface,
  mesh: MeshGradient
) {
  let prepared = preparedTextMesh(mesh)
  for x in 0..<meshTextBounds.size.width {
    #expect(surface.cells[0][x].style?.foregroundColor == prepared.color(atCellX: x, y: 0))
  }
}
