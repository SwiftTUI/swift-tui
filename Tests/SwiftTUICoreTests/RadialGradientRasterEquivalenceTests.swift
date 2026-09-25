import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

/// Output equivalence for the prepared radial sampler and the transparent
/// support walk (plan 2026-09-24-001 §4C, STUI-618).
///
/// Every scene is rasterized twice: once with `forceReferenceRadialWalk`
/// bound, which visits every cell of each fill rectangle and samples through
/// the unprepared gradient exactly as the rasterizer did before this change,
/// and once on the default path. The two surfaces — cells, styles, span
/// widths — and their presentation-layer records (bounds, order, effects)
/// must be identical. A work-counter assertion on a fixed sparse fixture
/// then separates *less work* from *faster work*: an output-correct walk that
/// still samples every cell fails it.
@Suite("Radial gradient raster equivalence")
struct RadialGradientRasterEquivalenceTests {
  // MARK: - Prepared perceptual mix

  @Test("the prepared perceptual mix is bit-identical to interpolated(to:progress:)")
  func preparedMixIsBitExact() {
    let colors: [Color] = [
      .red, .blue, .green, .clear, .white, .black,
      Color(red: 0.2, green: 0.9, blue: 0.4, alpha: 0.35),
      Color(red: 0.95, green: 0.1, blue: 0.6, alpha: 0),
      Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1, profile: .displayP3),
      Color(red: 0.8, green: 0.7, blue: 0.1, alpha: 0.5, profile: .displayP3),
      Color(red: 0.6, green: 0.6, blue: 0.9, alpha: 0.8, profile: .linearSRGB),
      Color(red: 0.3, green: 0.05, blue: 0.7, alpha: 0.2, profile: .rec2020),
    ]
    var checked = 0
    for lower in colors {
      let preparedLower = PreparedPerceptualMixEndpoint(lower)
      for upper in colors {
        let preparedUpper = PreparedPerceptualMixEndpoint(upper)
        for step in 0...64 {
          let t = Double(step) / 64
          let reference = lower.interpolated(to: upper, progress: t)
          let prepared = Color.perceptualMix(preparedLower, preparedUpper, progress: t)
          #expect(prepared == reference, "lower=\(lower) upper=\(upper) t=\(t)")
          checked += 1
        }
        // Out-of-range progress clamps the same way.
        #expect(
          Color.perceptualMix(preparedLower, preparedUpper, progress: 1.7)
            == lower.interpolated(to: upper, progress: 1.7))
        #expect(
          Color.perceptualMix(preparedLower, preparedUpper, progress: -0.3)
            == lower.interpolated(to: upper, progress: -0.3))
      }
    }
    #expect(checked == colors.count * colors.count * 65)
  }

  @Test("the prepared sampler matches the reference sampler cell for cell")
  func preparedSamplerMatchesReference() {
    let rasterizer = Rasterizer()
    let bounds = CellRect(origin: CellPoint(x: 3, y: 2), size: CellSize(width: 41, height: 17))
    for gradient in Self.gradientCatalog {
      for aspectRatio in [2.0, 1.0, 1.6, 0.5] {
        let prepared = PreparedRadialGradient(gradient, aspectRatio: aspectRatio, bounds: bounds)
        var hint = 0
        for y in (bounds.origin.y - 2)..<(bounds.origin.y + bounds.size.height + 2) {
          for x in (bounds.origin.x - 2)..<(bounds.origin.x + bounds.size.width + 2) {
            let reference = rasterizer.sample(
              gradient, in: bounds, aspectRatio: aspectRatio, x: x, y: y)
            let hinted = prepared.color(atCellX: x, y: y, segmentHint: &hint)
            let fresh = prepared.color(atCellX: x, y: y)
            #expect(hinted == reference, "hinted (\(x), \(y)) aspect \(aspectRatio)")
            #expect(fresh == reference, "fresh (\(x), \(y)) aspect \(aspectRatio)")
          }
        }
      }
    }
  }

  // MARK: - Surface equivalence

  @Test(
    "reference and support walks produce identical surfaces and records",
    arguments: RadialFillScene.catalog
  )
  func surfacesAndRecordsAreIdentical(scene: RadialFillScene) {
    let outcome = Self.rasterBothWays(scene)
    Self.expectIdentical(outcome, scene: scene)
  }

  @Test("incremental repaint of dirty rows matches the reference on both walks")
  func incrementalRepaintMatches() {
    // First frame fresh, then a second frame that repaints only a band of
    // rows through the incremental path, in both walk modes.
    let scene = RadialFillScene.overlappingScreenLayers
    let node = scene.node
    let damage = PresentationDamage(dirtyRows: [4, 5, 6, 7, 20, 21])
    let reference = Rasterizer.$forceReferenceRadialWalk.withValue(true) {
      let first = Rasterizer().rasterize(node, minimumSize: scene.surface)
      return Rasterizer().rasterizeCollectingVisibleIdentities(
        node, minimumSize: scene.surface, previousSurface: first, damage: damage)
    }
    let first = Rasterizer().rasterize(node, minimumSize: scene.surface)
    let optimized = Rasterizer().rasterizeCollectingVisibleIdentities(
      node, minimumSize: scene.surface, previousSurface: first, damage: damage)
    #expect(reference.path == .incremental)
    #expect(optimized.path == .incremental)
    Self.expectIdentical((reference.surface, optimized.surface), scene: scene)
    // And the incremental result is the fresh result, on the default path.
    #expect(optimized.surface.cells == first.cells)
  }

  // MARK: - Work counters

  @Test("a sparse ring samples a small fraction of its rectangle")
  func sparseRingSamplesOnlyItsSupport() {
    // 120 × 40 surface, a thin ring: stops clear → colour → clear between
    // 0.9 and 1.0 of a 30-cell radius, so only an annulus of a few cells
    // contributes.
    let surface = CellSize(width: 120, height: 40)
    let scene = RadialFillScene(
      name: "thin-ring",
      surface: surface,
      layers: [
        .init(
          bounds: CellRect(origin: .zero, size: surface),
          gradient: RadialGradient(
            gradient: Gradient(stops: [
              .init(color: .clear, location: 0),
              .init(color: .clear, location: 0.88),
              .init(color: .cyan, location: 0.94),
              .init(color: .clear, location: 1),
            ]),
            center: .center, startRadius: 0, endRadius: 30),
          blend: .screen)
      ]
    )
    let probe = RasterWorkProbe()
    let optimized = Rasterizer.$workProbe.withValue(probe) {
      Rasterizer().rasterize(scene.node, minimumSize: surface)
    }
    let referenceProbe = RasterWorkProbe()
    let reference = Rasterizer.$workProbe.withValue(referenceProbe) {
      Rasterizer.$forceReferenceRadialWalk.withValue(true) {
        Rasterizer().rasterize(scene.node, minimumSize: surface)
      }
    }
    #expect(reference == optimized)

    let work = probe.snapshot()
    let referenceWork = referenceProbe.snapshot()
    let area = surface.width * surface.height
    #expect(referenceWork.radialSamples == area, "reference samples every cell")
    #expect(work.radialSamples < area / 4, "sampled \(work.radialSamples) of \(area)")
    #expect(work.visitedCells < area / 4, "visited \(work.visitedCells) of \(area)")
    #expect(work.spanRows > 0 && work.spanRows <= surface.height)
    #expect(work.skippedRows > 0)
    // Every cell that survived to a write did so on both paths.
    #expect(work.blendedWrites == referenceWork.blendedWrites)
    #expect(work.blendedWrites > 0)
    #expect(work.fills == 1 && referenceWork.fills == 1)
  }

  @Test("a ring whose hole covers the whole surface is culled without a visit")
  func fullyTransparentCoverageIsCulled() {
    let surface = CellSize(width: 60, height: 20)
    let scene = RadialFillScene(
      name: "hole-covers-surface",
      surface: surface,
      layers: [
        .init(
          bounds: CellRect(origin: .zero, size: surface),
          gradient: RadialGradient(
            gradient: Gradient(stops: [
              .init(color: .clear, location: 0),
              .init(color: .clear, location: 0.9),
              .init(color: .red, location: 0.95),
              .init(color: .clear, location: 1),
            ]),
            center: .center, startRadius: 0, endRadius: 400),
          blend: .screen)
      ]
    )
    let probe = RasterWorkProbe()
    let optimized = Rasterizer.$workProbe.withValue(probe) {
      Rasterizer().rasterize(scene.node, minimumSize: surface)
    }
    let reference = Rasterizer.$forceReferenceRadialWalk.withValue(true) {
      Rasterizer().rasterize(scene.node, minimumSize: surface)
    }
    #expect(reference == optimized)
    let work = probe.snapshot()
    #expect(work.culledLayers == 1)
    #expect(work.visitedCells == 0)
    #expect(work.radialSamples == 0)
  }

  @Test("the shared probe tallies only while armed")
  func sharedProbeArmsAndDisarms() {
    let scene = RadialFillScene.sparseAnnulus
    RasterWorkProbe.shared.reset()
    RasterWorkProbe.setSharedArmed(false)
    _ = Rasterizer().rasterize(scene.node, minimumSize: scene.surface)
    #expect(RasterWorkProbe.shared.snapshot() == RasterWorkCounters())
    RasterWorkProbe.setSharedArmed(true)
    _ = Rasterizer().rasterize(scene.node, minimumSize: scene.surface)
    RasterWorkProbe.setSharedArmed(false)
    let work = RasterWorkProbe.shared.snapshot()
    #expect(work.fills >= 1)
    #expect(work.radialSamples > 0)
    RasterWorkProbe.shared.reset()
  }

  // MARK: - Helpers

  private static func rasterBothWays(
    _ scene: RadialFillScene
  ) -> (reference: RasterSurface, optimized: RasterSurface) {
    let node = scene.node
    let reference = Rasterizer.$forceReferenceRadialWalk.withValue(true) {
      Rasterizer().rasterize(node, minimumSize: scene.surface)
    }
    let optimized = Rasterizer().rasterize(node, minimumSize: scene.surface)
    return (reference, optimized)
  }

  private static func expectIdentical(
    _ outcome: (reference: RasterSurface, optimized: RasterSurface),
    scene: RadialFillScene
  ) {
    let reference = outcome.reference
    let optimized = outcome.optimized
    #expect(reference.size == optimized.size, Comment(rawValue: scene.name))
    #expect(reference.cells.count == optimized.cells.count, Comment(rawValue: scene.name))
    for (y, (referenceRow, optimizedRow)) in zip(reference.cells, optimized.cells).enumerated() {
      #expect(referenceRow.count == optimizedRow.count, "\(scene.name) row \(y)")
      for (x, (expected, actual)) in zip(referenceRow, optimizedRow).enumerated()
      where expected != actual {
        Issue.record(
          "\(scene.name): cell (\(x), \(y)) differs: reference \(expected) optimized \(actual)")
        return
      }
    }
    #expect(
      reference.presentationLayers.count == optimized.presentationLayers.count,
      "\(scene.name): \(reference.presentationLayers.count) vs \(optimized.presentationLayers.count) layers"
    )
    for (index, (expected, actual)) in zip(
      reference.presentationLayers, optimized.presentationLayers
    ).enumerated()
    where expected != actual {
      Issue.record(
        "\(scene.name): presentation layer \(index) differs: \(expected) vs \(actual)")
      return
    }
    #expect(reference == optimized, Comment(rawValue: scene.name))
    // Sanity: the scene painted something on the default path, or it was
    // authored to paint nothing.
    let paintedCells = optimized.cells.flatMap { $0 }.filter { $0.style != nil }.count
    #expect((paintedCells > 0) == scene.expectsPaint, "\(scene.name): painted \(paintedCells)")
  }

  /// Gradients spanning the eligibility boundary: sparse and full support,
  /// zero/one/many stops, partial alpha, opaque end stops, reversed and
  /// equal radii, out-of-order stops, and off-centre centres.
  static let gradientCatalog: [RadialGradient] = {
    var out: [RadialGradient] = [
      RadialGradient(colors: [], endRadius: 10),
      RadialGradient(colors: [.red], endRadius: 10),
      RadialGradient(colors: [.red, .blue], center: .center, startRadius: 0, endRadius: 10),
      RadialGradient(
        colors: [.clear, .red, .clear], center: .center, startRadius: 4, endRadius: 14),
      RadialGradient(
        colors: [Color.red.opacity(0.3), Color.blue.opacity(0.6), .clear], center: .topLeading,
        startRadius: 0, endRadius: 30),
      RadialGradient(colors: [.red, .blue], center: .center, startRadius: 5, endRadius: 5),
      RadialGradient(colors: [.red, .blue], center: .center, startRadius: 9, endRadius: 3),
      RadialGradient(
        colors: [.clear, .green, .clear], center: .bottomTrailing, startRadius: -2,
        endRadius: 12),
      RadialGradient(
        gradient: Gradient(stops: [
          .init(color: .clear, location: 0.2),
          .init(color: .clear, location: 0.4),
          .init(color: .yellow, location: 0.5),
          .init(color: .yellow, location: 0.5),
          .init(color: .clear, location: 0.7),
          .init(color: .clear, location: 1),
        ]),
        center: .init(x: 0.3, y: 0.7), startRadius: 1, endRadius: 20),
    ]
    var unsorted = RadialGradient(colors: [.clear, .red, .clear], endRadius: 12)
    unsorted.gradient.stops.swapAt(0, 1)
    out.append(unsorted)
    var outOfRange = RadialGradient(colors: [.clear, .red, .clear], endRadius: 12)
    outOfRange.gradient.stops[2].location = 1.4
    out.append(outOfRange)
    return out
  }()
}

// MARK: - Scenes

struct RadialFillScene: CustomTestStringConvertible, Sendable {
  struct Layer: Sendable {
    var bounds: CellRect
    var gradient: RadialGradient
    var blend: BlendMode?
    var geometry: ShapeGeometry = .rectangle
    var mode: ShapeFillMode = .full
    var opacity: Double?
    var clip: CellRect?
  }

  var name: String
  var surface: CellSize
  var layers: [Layer]
  var textUnderneath: Bool = false
  var metrics: CellPixelMetrics = .estimated
  var expectsPaint: Bool = true

  var testDescription: String { name }

  var node: DrawNode {
    let environment = EnvironmentSnapshot(
      style: .init(cellPixelMetrics: metrics)
    )
    var children: [DrawNode] = []
    if textUnderneath {
      let textBounds = CellRect(
        origin: CellPoint(x: 2, y: surface.height / 2),
        size: CellSize(width: min(surface.width - 4, 30), height: 1))
      children.append(
        DrawNode(
          identity: testIdentity("radial-scene", "text"),
          environmentSnapshot: environment,
          bounds: textBounds,
          commands: [
            .text(
              bounds: textBounds,
              content: "underlying label text here",
              style: TextStyle(foregroundStyle: .color(.white), backgroundStyle: .color(.black)),
              lineLimit: 1,
              truncationMode: .tail,
              wrappingStrategy: .wordBoundary)
          ]))
    }
    for (index, layer) in layers.enumerated() {
      let style: AnyShapeStyle =
        if let opacity = layer.opacity {
          .opacity(.radialGradient(layer.gradient), opacity)
        } else {
          .radialGradient(layer.gradient)
        }
      children.append(
        DrawNode(
          identity: testIdentity("radial-scene", "layer-\(index)"),
          environmentSnapshot: environment,
          bounds: layer.bounds,
          clipBounds: layer.clip,
          drawEffects: layer.blend.map { DrawEffects([.blendMode($0)]) } ?? .init(),
          commands: [
            .fill(
              bounds: layer.bounds,
              geometry: layer.geometry,
              insetAmount: 0,
              style: style,
              mode: layer.mode)
          ]))
    }
    return DrawNode(
      identity: testIdentity("radial-scene"),
      environmentSnapshot: environment,
      bounds: CellRect(origin: .zero, size: surface),
      children: children
    )
  }

  static let ripple = RadialGradient(
    gradient: Gradient(stops: [
      .init(color: .clear, location: 0),
      .init(color: Color(red: 0.4, green: 0.8, blue: 1.0, alpha: 0.9), location: 0.55),
      .init(color: .clear, location: 1),
    ]),
    center: .center, startRadius: 0, endRadius: 40)

  static func ring(_ progress: Double, color: Color = .cyan, alpha: Double = 0.85) -> RadialGradient
  {
    let radius = 4 + 60 * progress
    return RadialGradient(
      gradient: Gradient(stops: [
        .init(color: .clear, location: 0),
        .init(color: color.opacity(alpha * (1 - progress)), location: 0.6),
        .init(color: .clear, location: 1),
      ]),
      center: .center, startRadius: radius * 0.7, endRadius: radius)
  }

  static let sparseAnnulus = RadialFillScene(
    name: "sparse-annulus",
    surface: CellSize(width: 80, height: 24),
    layers: [
      .init(
        bounds: CellRect(origin: .zero, size: CellSize(width: 80, height: 24)),
        gradient: ring(0.5), blend: .screen)
    ])

  static let overlappingScreenLayers: RadialFillScene = {
    let surface = CellSize(width: 90, height: 30)
    // Spelled out with explicit types: the closure-with-ternary form drove the
    // type checker past its budget under the gate's build flags.
    var layers: [Layer] = []
    for index in 0..<12 {
      let color: Color = index.isMultiple(of: 2) ? .cyan : .magenta
      layers.append(
        Layer(
          bounds: CellRect(origin: .zero, size: surface),
          gradient: ring(Double(index) / 12, color: color),
          blend: .screen))
    }
    return RadialFillScene(
      name: "overlapping-screen-layers-over-text",
      surface: surface,
      layers: layers,
      textUnderneath: true)
  }()

  static let catalog: [RadialFillScene] = {
    let surface = CellSize(width: 64, height: 20)
    let full = CellRect(origin: .zero, size: surface)
    // One statement per scene: a single literal of this size drove the type
    // checker past its budget under the gate's build flags.
    var scenes: [RadialFillScene] = [sparseAnnulus, overlappingScreenLayers]
    scenes.append(
      RadialFillScene(
        name: "opaque-full-support",
        surface: surface,
        layers: [
          .init(
            bounds: full, gradient: RadialGradient(colors: [.red, .blue], endRadius: 20), blend: nil
          )
        ])
    )
    scenes.append(
      RadialFillScene(
        name: "opaque-end-stop-under-screen",
        surface: surface,
        layers: [
          .init(
            bounds: full, gradient: RadialGradient(colors: [.clear, .blue], endRadius: 20),
            blend: .screen)
        ])
    )
    scenes.append(
      RadialFillScene(
        name: "single-stop", surface: surface,
        layers: [
          .init(bounds: full, gradient: RadialGradient(colors: [.green], endRadius: 20), blend: nil)
        ])
    )
    scenes.append(
      RadialFillScene(
        name: "no-stops", surface: surface,
        layers: [
          .init(bounds: full, gradient: RadialGradient(colors: [], endRadius: 20), blend: nil)
        ],
        expectsPaint: false)
    )
    scenes.append(
      RadialFillScene(
        name: "partial-alpha-tint-no-blend", surface: surface,
        layers: [
          .init(
            bounds: full,
            gradient: RadialGradient(
              colors: [.clear, Color.red.opacity(0.5), .clear], endRadius: 25), blend: nil)
        ])
    )
    scenes.append(
      RadialFillScene(
        name: "reversed-radii", surface: surface,
        layers: [
          .init(
            bounds: full,
            gradient: RadialGradient(
              colors: [.clear, .red, .clear], startRadius: 12, endRadius: 4), blend: .screen)
        ],
        // Reversed radii collapse the normalized location to a step at the
        // start radius: every cell lands on a transparent end stop.
        expectsPaint: false)
    )
    scenes.append(
      RadialFillScene(
        name: "equal-radii", surface: surface,
        layers: [
          .init(
            bounds: full,
            gradient: RadialGradient(colors: [.clear, .red, .clear], startRadius: 8, endRadius: 8),
            blend: .screen)
        ],
        expectsPaint: false)
    )
    scenes.append(
      RadialFillScene(
        name: "opacity-wrapped", surface: surface,
        layers: [.init(bounds: full, gradient: ripple, blend: .screen, opacity: 0.4)])
    )
    scenes.append(
      RadialFillScene(
        name: "offset-bounds-and-clip", surface: surface,
        layers: [
          .init(
            bounds: CellRect(
              origin: CellPoint(x: -10, y: -5), size: CellSize(width: 90, height: 40)),
            gradient: ripple, blend: .screen,
            clip: CellRect(origin: CellPoint(x: 5, y: 3), size: CellSize(width: 40, height: 12)))
        ])
    )
    scenes.append(
      RadialFillScene(
        name: "rounded-rectangle-geometry", surface: surface,
        layers: [
          .init(
            bounds: full, gradient: ripple, blend: .screen,
            geometry: .roundedRectangle(cornerRadius: 2))
        ])
    )
    scenes.append(
      RadialFillScene(
        name: "interior-fill-mode", surface: surface,
        layers: [
          .init(bounds: full, gradient: ripple, blend: .screen, mode: .interior(strokeWidth: 2))
        ])
    )
    scenes.append(
      RadialFillScene(
        name: "square-cells", surface: surface,
        layers: [.init(bounds: full, gradient: ripple, blend: .screen)],
        metrics: CellPixelMetrics(width: 10, height: 10, source: .reported))
    )
    scenes.append(
      RadialFillScene(
        name: "tall-cells", surface: surface,
        layers: [.init(bounds: full, gradient: ripple, blend: .screen)],
        metrics: CellPixelMetrics(width: 7, height: 21, source: .reported))
    )
    scenes.append(
      RadialFillScene(
        name: "hole-and-outer-outside-surface", surface: surface,
        layers: [
          .init(
            bounds: full,
            gradient: RadialGradient(
              colors: [.clear, .clear, .red, .clear], center: .init(x: 1.4, y: -0.3),
              startRadius: 30, endRadius: 90),
            blend: .screen)
        ])
    )
    let ceiling = CellSize(width: 512, height: 128)
    var ceilingLayers: [RadialFillScene.Layer] = []
    for index in 0..<4 {
      let stops: [Gradient.Stop] = [
        Gradient.Stop(color: .clear, location: 0),
        Gradient.Stop(color: Color.cyan.opacity(0.7), location: 0.6),
        Gradient.Stop(color: .clear, location: 1),
      ]
      let gradient = RadialGradient(
        gradient: Gradient(stops: stops),
        center: .center, startRadius: Double(40 + index * 50),
        endRadius: Double(70 + index * 50))
      ceilingLayers.append(
        RadialFillScene.Layer(
          bounds: CellRect(origin: .zero, size: ceiling), gradient: gradient, blend: .screen))
    }
    scenes.append(
      RadialFillScene(name: "web-host-ceiling", surface: ceiling, layers: ceilingLayers))
    for gradient in RadialGradientRasterEquivalenceTests.gradientCatalog.enumerated() {
      scenes.append(
        RadialFillScene(
          name: "catalog-\(gradient.offset)", surface: surface,
          layers: [.init(bounds: full, gradient: gradient.element, blend: .screen)],
          // The text underneath always paints; the gradient may not.
          textUnderneath: true))
    }
    return scenes
  }()
}
