import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The marker is drawn where the tail was. Hiding the original lead keeps it from
/// claiming the marker's output column when the renderer reconstructs wide spans.
private struct TailMarker: CellLayerKernel {
  func shade(at point: CellPoint, in source: CellLayer, context: CellEffectContext) -> CellSample {
    let sample = source.sample(at: point)
    if point.x == 7, case .glyph(let glyph) = sample, glyph.width == 2 { return .empty }
    guard point.x == 8, case .continuation(columnsBack: 1) = sample else { return sample }
    let lead = CellPoint(x: point.x - 1, y: point.y)
    guard !source.readableBounds.contains(lead), source.sample(at: lead) == .empty,
      source.glyph(occupying: lead) == nil,
      var owner = source.glyph(occupying: point), owner.width == 2
    else { return .glyph(CellGlyph("!")) }
    switch owner.character {
    case "界": owner.character = "J"
    case "語": owner.character = "G"
    default: owner.character = "?"
    }
    return .glyph(owner)
  }
}

private struct OccupantJourneyRoot: View {
  let startingAt: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      OccupantPanel(startingAt: startingAt)
    }
  }
}

private struct OccupantPanel: View {
  @State private var step: Int

  init(startingAt step: Int = 0) {
    _step = State(wrappedValue: step)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("before")
      ZStack(alignment: .topLeading) {
        Text("................")
        HStack(spacing: 0) {
          Text("       ")
          Text(step == 0 ? "界" : step < 3 ? "語" : "x")
            .foregroundStyle(step < 2 ? Color.red : Color.blue)
            .frame(width: 2, height: 1, alignment: .leading)
        }
        .frame(width: 16, height: 1, alignment: .topLeading)
        .layerEffect(CellLayerShader(TailMarker()), maxSampleOffset: .zero)
      }
      Text("after")
    }
    .frame(width: 24, height: 8, alignment: .topLeading)
    .focusable()
    .onKeyPress(.key(.arrowRight)) { _ in
      step = min(3, step + 1)
      return .handled
    }
  }
}

@MainActor
@Suite("Cell layer occupant across a damage boundary", .serialized)
struct CellLayerOccupantJourneyTests {
  @Test(
    "A live run loop updates a marker on the far side of the lead's damage boundary",
    arguments: 0..<3)
  func occupantSurvivesIncrementalRaster(start: Int) async throws {
    let size = CellSize(width: 24, height: 8)
    let identity = testIdentity("CellLayerOccupant")
    let journey = try await runSegmentedRowJourney(
      rootIdentity: identity, terminalSize: size, steps: [.keys([.arrowRight])]
    ) { OccupantJourneyRoot(startingAt: start) }

    var environment = EnvironmentValues()
    environment.terminalSize = size
    let states = [start, start + 1]
    let fresh = states.map { step in
      DefaultRenderer().render(
        OccupantJourneyRoot(startingAt: step),
        context: ResolveContext(identity: identity, environmentValues: environment),
        proposal: ProposedSize(width: size.width, height: size.height)
      ).rasterSurface.cells
    }
    let markers: [Character] = ["J", "G", "G", "."]
    for (step, frame) in zip(states, fresh) {
      try #require(frame.count == size.height && frame[1].count == size.width)
      #expect(frame[1][7].character == (step == 3 ? "x" : "."))
      let marker = frame[1][8]
      #expect(marker.character == markers[step])
      #expect(marker.spanWidth == 1)
      #expect(marker.continuationLeadX == nil)
      if step < 3 {
        #expect(marker.style?.foregroundColor == (step < 2 ? Color.red : Color.blue))
      }
    }

    var observed: [Int] = []
    for frame in journey.frames {
      let index = try #require(
        fresh.firstIndex(of: frame.cells),
        "Live cells differed from every fresh repaint: \(frame.lines)")
      if observed.last != states[index] { observed.append(states[index]) }
    }
    #expect(observed == states, "\(journey.renderedFrames)")
    #expect(journey.reachedIncrementalRaster, "\(journey.summary)")
    #expect(journey.mismatchGrowth == 0, "\(journey.summary)")
  }

  @Test("Clipping one half of a wide glyph removes its structural sample and owner")
  func hardClipSuppressesOccupant() throws {
    let subject = ZStack(alignment: .topLeading) {
      Text("界").fixedSize().frame(width: 1, height: 1, alignment: .leading).clipped()
      Spacer(minLength: 0).frame(width: 2, height: 1)
    }
    .layerEffect(maxSampleOffset: .zero) { point, layer, _ in
      let absent = layer.sample(at: point) == .empty && layer.glyph(occupying: point) == nil
      return .glyph(CellGlyph(absent ? "-" : "!"))
    }
    let frame = DefaultRenderer().render(subject, proposal: .init(width: 2, height: 1))
      .rasterSurface
    #expect(frame.lines == ["--"])
  }
}

extension CellLayerOccupantJourneyTests {
  @Test("A text-over-image source uses the shared fallback until bypass restores native placement")
  func mixedImageOrder() throws {
    let bytes = try makePNGBytes(
      width: 2, height: 2,
      pixels: Array(repeating: rgbaPixel(red: 230, green: 20, blue: 80), count: 4))
    func scene(_ enabled: Bool) -> some View {
      ZStack(alignment: .topLeading) {
        Text("LOW")
        Image(data: bytes).resizable().frame(width: 3, height: 1)
        Text("T")
      }
      .layerEffect(maxSampleOffset: .zero, isEnabled: enabled) { p, layer, _ in layer.sample(at: p)
      }
    }
    let renderer = DefaultRenderer()
    let size = ProposedSize(width: 3, height: 1)
    let active = renderer.render(scene(true), proposal: size).rasterSurface
    #expect(active.imageAttachments.isEmpty)
    #expect(active.cells[0].map(\.character) == ["T", "▀", "▀"])
    let imageInk = try #require(active.cells[0][1].style?.foregroundColor)
    #expect(Int((imageInk.red * 255).rounded()) == 230)
    #expect(active.cells[0][1].style?.backgroundColor == imageInk)
    let restored = renderer.render(scene(false), proposal: size).rasterSurface
    #expect(restored.imageAttachments.count == 1)
    #expect(restored == DefaultRenderer().render(scene(false), proposal: size).rasterSurface)
    #expect(restored.cells[0].map(\.character) == ["T", "O", "W"])
  }
}
