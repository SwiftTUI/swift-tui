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

private enum OccupantInput: CaseIterable { case source, backdrop, buffer }

private struct OccupantJourneyRoot: View {
  let startingAt: Int
  let input: OccupantInput

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      OccupantPanel(startingAt: startingAt, input: input)
    }
  }
}

private struct OccupantPanel: View {
  @State private var step: Int

  let input: OccupantInput
  init(startingAt step: Int = 0, input: OccupantInput) {
    self.input = input
    _step = State(wrappedValue: step)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("before")
      ZStack(alignment: .topLeading) {
        Text("................")
        let word = HStack(spacing: 0) {
          Text("       ")
          Text(step == 0 ? "界" : step < 3 ? "語" : "x")
            .foregroundStyle(step < 2 ? Color.red : Color.blue)
            .frame(width: 2, height: 1, alignment: .leading)
        }.frame(width: 16, height: 1, alignment: .topLeading)
        switch input {
        case .source:
          word.layerEffect(CellLayerShader(TailMarker()), maxSampleOffset: .zero)
        case .backdrop:
          word
          Spacer(minLength: 0).frame(width: 16, height: 1)
            .layerEffect(
              .compositing { p, _, lower, context in
                if p.x == 7, lower.glyph(occupying: p)?.width == 2 {
                  return .replace(.glyph(CellGlyph(".")))
                }
                return .replace(TailMarker().shade(at: p, in: lower, context: context))
              }, maxSampleOffset: .zero)
        case .buffer:
          word.layerEffect(
            .region { _, buffer, _ in
              let lead = CellPoint(x: 7, y: 0)
              let tail = CellPoint(x: 8, y: 0)
              let snapshot = buffer.snapshot()
              guard case .continuation(columnsBack: 1) = snapshot.sample(at: tail),
                var glyph = snapshot.glyph(occupying: tail)
              else { return }
              buffer.clear(at: tail)
              #expect(buffer.sample(at: lead) == .empty)
              glyph.character = glyph.character == "界" ? "J" : "G"
              buffer.set(glyph, at: tail)
              #expect(snapshot.glyph(occupying: tail)?.width == 2)
            }, maxSampleOffset: .zero)
        }
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
    arguments: 0..<3, OccupantInput.allCases)
  fileprivate func occupantSurvivesIncrementalRaster(start: Int, input: OccupantInput) async throws
  {
    let size = CellSize(width: 24, height: 8)
    let identity = testIdentity("CellLayerOccupant")
    let journey = try await runSegmentedRowJourney(
      rootIdentity: identity, terminalSize: size, steps: [.keys([.arrowRight])]
    ) { OccupantJourneyRoot(startingAt: start, input: input) }

    var environment = EnvironmentValues()
    environment.terminalSize = size
    let states = [start, start + 1]
    let fresh = states.map { step in
      DefaultRenderer().render(
        OccupantJourneyRoot(startingAt: step, input: input),
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

extension CellLayerOccupantJourneyTests {
  @Test(
    "A sampled lower image is projected at its paint event and keeps native fragments outside the selected region"
  )
  func partialBackdropImage() throws {
    let bytes = try makePNGBytes(
      width: 2, height: 2,
      pixels: Array(repeating: rgbaPixel(red: 230, green: 20, blue: 80), count: 4))
    let read = CellRect(origin: .init(x: 1, y: 0), size: .init(width: 2, height: 1))
    func scene(_ enabled: Bool) -> some View {
      ZStack(alignment: .topLeading) {
        Text("01234")
        Image(data: bytes).resizable().frame(width: 5, height: 1)
        Text("T").offset(x: 1)
        Spacer(minLength: 0).frame(width: 5, height: 1).layerEffect(
          .compositing { point, _, lower, _ in
            guard var glyph = lower.glyph(occupying: point) else { return .keepDestination }
            if glyph.character == "T" { glyph.character = "t" }
            return .replace(.glyph(glyph))
          }.drawing(in: .rect(read)), maxSampleOffset: .zero, isEnabled: enabled)
        Text("H").offset(x: 3)
      }
    }
    let renderer = DefaultRenderer()
    let size = ProposedSize(width: 5, height: 1)
    let active = renderer.render(scene(true), proposal: size).rasterSurface
    #expect(active.cells[0].map(\.character) == Array("0t▀H4"))
    #expect(active.cells[0][2].style?.foregroundColor?.hexString(format: .rrggbb) == "#E61450")
    #expect(
      active.imageAttachments.map(\.visibleBounds) == [
        .init(origin: .zero, size: .init(width: 1, height: 1)),
        .init(origin: .init(x: 3, y: 0), size: .init(width: 2, height: 1)),
      ])
    let bypass = renderer.render(scene(false), proposal: size).rasterSurface
    #expect(
      bypass.imageAttachments.map(\.visibleBounds) == [
        .init(origin: .zero, size: .init(width: 5, height: 1))
      ])
    #expect(bypass == DefaultRenderer().render(scene(false), proposal: size).rasterSurface)
    #expect(active == renderer.render(scene(true), proposal: size).rasterSurface)
  }
}

extension CellLayerOccupantJourneyTests {
  @Test("Disabling backdrop and region programs restores ordinary cells without a capture")
  func disabledComposition() {
    let probe = RasterWorkProbe()
    let renderer = DefaultRenderer()
    let size = ProposedSize(width: 6, height: 1)
    let ordinary = renderer.render(Text("source"), proposal: size).rasterSurface
    Rasterizer.$workProbe.withValue(probe) {
      let program = CellLayerShader.region { _, _, _ in Issue.record("Disabled region ran") }
      let view = Text("source")
        .layerEffect(program, maxSampleOffset: .layerBounds, isEnabled: false)
        .backdropEffect(
          .compositing { _, _, _, _ in
            Issue.record("Disabled compositing kernel ran")
            return .keepDestination
          }, in: .viewport, maxSampleOffset: .layerBounds, isEnabled: false)
      #expect(renderer.render(view, proposal: size).rasterSurface == ordinary)
      #expect(probe.snapshot().cellEffectCaptures == 0)
    }
  }
}
