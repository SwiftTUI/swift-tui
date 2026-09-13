import Foundation
import SwiftTUIVendorPNG
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct OrderedImageCompositionTests {
  @Test(
    "STUI-157: overlapping image blends see prior images for every portable blend mode",
    arguments: [BlendMode.normal, .multiply, .screen, .overlay, .darken, .lighten])
  func orderedBlend(mode: BlendMode) throws {
    let lowerColor = Color(red: 0.2, green: 0.6, blue: 1)
    let upperColor = Color(red: 1, green: 0.4, blue: 0.2)
    let lower = try attachment("lower", color: lowerColor)
    var upper = try attachment("upper", color: upperColor, mode: mode)
    upper.opacity = 0.5
    let surface = RasterSurface(imageAttachments: [lower, upper])
    let compositor = ImageBlendCompositor()
    let prepared = compositor.orderedAttachments(in: surface, fallbackBackground: .white)
    #expect(prepared[0] == lower)
    #expect(prepared[1].compositing == nil)
    #expect(prepared[1].opacity == upper.opacity)
    let blended = upperColor.composited(over: lowerColor, mode: mode)
    #expect(try pixels(prepared[1]) == [pixel(blended)])
    #expect(compositor.orderedAttachments(in: surface, fallbackBackground: .white) == prepared)
    #expect(compositor.cacheSnapshot().encodedHits == 1)
  }

  @Test(
    "clipping, translucent lower layers, source changes and placement alpha invalidate ordered variants"
  )
  func placementAndInvalidation() throws {
    var lower = try attachment("lower", color: Color(red: 1, green: 0, blue: 0))
    lower.opacity = 0.5
    var upper = try attachment("upper", color: Color(red: 0, green: 0, blue: 1), mode: .multiply)
    upper.bounds.size.width = 2
    upper.visibleBounds = rect(x: 1)
    upper.compositing?.destinationBackdrop.bounds = upper.visibleBounds
    var surface = RasterSurface(imageAttachments: [lower, upper])
    let compositor = ImageBlendCompositor()
    #expect(compositor.orderedAttachments(in: surface, fallbackBackground: .white)[1] == upper)
    lower.bounds.origin.x = 1
    lower.visibleBounds = lower.bounds
    surface.imageAttachments[0] = lower
    let first = compositor.orderedAttachments(in: surface, fallbackBackground: .white)
    let destination = Color(red: 1, green: 0, blue: 0, alpha: 0.5).composited(over: .white)
    #expect(
      try pixels(first[1]) == [
        pixel(Color(red: 0, green: 0, blue: 1).composited(over: destination, mode: .multiply))
      ])
    #expect(first[1].bounds == upper.visibleBounds)
    surface.imageAttachments[0].opacity = 1
    let changedAlpha = compositor.orderedAttachments(in: surface, fallbackBackground: .white)
    #expect(try pixels(changedAlpha[1]) == [rgbaPixel(red: 0, green: 0, blue: 0)])
    surface.imageAttachments[0].source = try attachment("replacement", color: .white).source
    surface.imageAttachments[0].resolvedReference = nil
    let changedSource = compositor.orderedAttachments(in: surface, fallbackBackground: .white)
    #expect(try pixels(changedSource[1]) == [rgbaPixel(red: 0, green: 0, blue: 255)])
  }

  @Test("sidecar image order and intervening cell occlusion control the ordered backdrop")
  func cellOcclusionAndOrder() throws {
    let lower = try attachment("lower", color: Color(red: 1, green: 0, blue: 0))
    let upper = try attachment("upper", color: Color(red: 0, green: 0, blue: 1), mode: .multiply)
    var surface = RasterSurface(imageAttachments: [upper, lower])
    surface.presentationLayers = [
      .init(order: 0, bounds: lower.bounds, content: .image(lower), effects: []),
      .init(
        order: 1, bounds: lower.bounds, content: .cells(.init(bounds: lower.bounds, cells: [])),
        effects: []),
      .init(
        order: 2, bounds: upper.bounds, content: .image(upper), effects: [.blendMode(.multiply)]),
    ]
    let compositor = ImageBlendCompositor()
    let occluded = compositor.orderedAttachments(in: surface, fallbackBackground: .white)
    #expect(occluded[0] == lower)
    #expect(try pixels(occluded[1]) == [rgbaPixel(red: 0, green: 0, blue: 255)])
    surface.presentationLayers.remove(at: 1)
    #expect(
      try pixels(compositor.orderedAttachments(in: surface, fallbackBackground: .white)[1]) == [
        rgbaPixel(red: 0, green: 0, blue: 0)
      ])
  }

  @Test("full and delta wire records use identical sidecar occlusion and image identity")
  func fullAndDelta() throws {
    let lower = try attachment("lower", color: Color(red: 1, green: 0, blue: 0))
    let upper = try attachment("upper", color: Color(red: 0, green: 0, blue: 1), mode: .multiply)
    var surface = RasterSurface(
      size: .init(width: 1, height: 1), cells: [[.empty]], imageAttachments: [lower, upper])
    surface.presentationLayers = [
      .init(order: 0, bounds: lower.bounds, content: .image(lower), effects: []),
      .init(
        order: 1, bounds: lower.bounds, content: .cells(.init(bounds: lower.bounds, cells: [])),
        effects: []),
      .init(
        order: 2, bounds: upper.bounds, content: .image(upper), effects: [.blendMode(.multiply)]),
    ]
    var state = HostWireEncodingState(deltaEnabled: true)
    let full = WebSurfaceFrameEncoder.encode(surface, fallbackBackground: .white, state: &state)
    let delta = WebSurfaceFrameEncoder.encode(
      surface, damage: .init(textRows: [.init(row: 0)]), fallbackBackground: .white, state: &state)
    func object(_ wire: String) throws -> [String: Any] {
      let json = try #require(wire.firstIndex(of: "{"))
      return try #require(
        JSONSerialization.jsonObject(with: Data(wire[json...].utf8)) as? [String: Any])
    }
    let fullObject = try object(full)
    let deltaObject = try object(delta)
    #expect(deltaObject["deltaRows"] != nil)
    let fullImages = try #require(fullObject["images"] as? [[String: Any]])
    let deltaImages = try #require(deltaObject["images"] as? [[String: Any]])
    #expect(
      fullImages.compactMap { $0["id"] as? String }
        == deltaImages.compactMap { $0["id"] as? String })
    #expect(deltaImages.allSatisfy { $0["dataBase64"] == nil })
  }

  @Test("three image layers retain prior blend results and bounded variants evict safely")
  func threeLayersAndEviction() throws {
    let lower = try attachment("lower", color: Color(red: 1, green: 0, blue: 0))
    let middle = try attachment("middle", color: Color(red: 0, green: 1, blue: 0), mode: .screen)
    let upper = try attachment("upper", color: Color(red: 0, green: 0, blue: 1), mode: .multiply)
    let compositor = ImageBlendCompositor(
      cachePolicy: .init(maxEntries: 1, maxDecodedPixels: 10, maxEncodedBytes: 4096))
    let surface = RasterSurface(imageAttachments: [lower, middle, upper])
    let first = compositor.orderedAttachments(in: surface, fallbackBackground: .white)
    #expect(try pixels(first[1]) == [rgbaPixel(red: 255, green: 255, blue: 0)])
    #expect(try pixels(first[2]) == [rgbaPixel(red: 0, green: 0, blue: 0)])
    #expect(compositor.orderedAttachments(in: surface, fallbackBackground: .white) == first)
    #expect(compositor.cacheSnapshot().entryCount <= 1)
    #expect(compositor.cacheSnapshot().totalApproxBytes <= 4096)
  }

  @Test("host delivery and wire frames replay the same precomposed ordered variant")
  func hostAndWireDelivery() async throws {
    let lower = try attachment("lower", color: Color(red: 1, green: 0, blue: 0))
    let upper = try attachment("upper", color: Color(red: 0, green: 0, blue: 1), mode: .multiply)
    let surface = RasterSurface(
      size: .init(width: 1, height: 1), cells: [[.empty]], imageAttachments: [lower, upper])
    let host = HostedRasterSurface(
      surfaceSize: surface.size, appearance: .fallback, onFrame: { _ in })
    try host.present(surface)
    let delivered = await host.waitForSurface()
    #expect(try pixels(delivered.imageAttachments[1]) == [rgbaPixel(red: 0, green: 0, blue: 0)])
    var known: Set<String> = []
    let wire = WebSurfaceFrameEncoder.encodeImages(
      surface.imageAttachments, fallbackBackground: .white, knownImageIDs: &known)
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(wire[1].utf8)) as? [String: Any])
    let base64 = try #require(object["dataBase64"] as? String)
    let bytes = try #require(Data(base64Encoded: base64))
    #expect(delivered.imageAttachments[1].source == .data(Array(bytes)))
  }

  @Test("terminal preparation preserves authored graphics order and shares the ordered variant")
  func terminalReplay() throws {
    let lower = try attachment("z-lower", color: Color(red: 1, green: 0, blue: 0))
    let upper = try attachment("a-upper", color: Color(red: 0, green: 0, blue: 1), mode: .multiply)
    let surface = RasterSurface(
      size: .init(width: 1, height: 1), cells: [[.empty]], imageAttachments: [lower, upper])
    let capabilities = TerminalGraphicsCapabilities(
      supportedProtocols: [.kitty], preferredProtocol: .kitty,
      cellPixelSize: .init(width: 1, height: 1))
    let renderer = TerminalImageRenderer(repository: ImageAssetRepository())
    let prepared = renderer.preparedSurface(
      for: surface, capabilityProfile: .trueColor,
      graphicsCapabilities: capabilities, fallbackBackground: .white)
    #expect(prepared.imageAttachments[0].identity == lower.identity)
    #expect(try pixels(prepared.imageAttachments[1]) == [rgbaPixel(red: 0, green: 0, blue: 0)])
    var transmitted: Set<UInt32> = []
    let steps = renderer.graphicsWriteSteps(
      for: prepared, capabilityProfile: .trueColor,
      graphicsCapabilities: capabilities, fallbackBackground: .white,
      transmittedKittyImages: &transmitted)
    let first = try #require(steps.first { $0.contains("a=T") })
    let content = try #require(ImageContentRepository.shared.content(for: lower))
    #expect(first.contains("i=\(kittyImageID(content: content))"))
    #expect(transmitted.count == 2)
  }

  @Test("authored overlapping images produce equal fresh and incremental host variants")
  func authoredIncremental() throws {
    func draw(_ red: UInt8) throws -> (drawTree: DrawNode, rasterSurface: RasterSurface) {
      let lower = try makePNGBytes(width: 1, height: 1, pixels: [.init(red, 0, 0, 255)])
      let upper = try makePNGBytes(width: 1, height: 1, pixels: [.init(0, 0, 255, 255)])
      let rendered = DefaultRenderer().render(
        ZStack {
          Image(data: lower).resizable().frame(width: 2, height: 2)
          Image(data: upper).resizable().frame(width: 2, height: 2).blendMode(.multiply)
        }.background(Color.white))
      return (rendered.drawTree, rendered.rasterSurface)
    }
    let before = try draw(255)
    let after = try draw(128)
    let replay = Rasterizer(incrementalVerificationPolicy: .trustSoundDamage)
      .rasterizeCollectingVisibleIdentities(
        after.drawTree, minimumSize: .zero,
        previousSurface: before.rasterSurface, damage: .init(textRows: [.init(row: 0)]))
    #expect(replay.path == .incremental)
    let compositor = ImageBlendCompositor()
    let fresh = compositor.orderedAttachments(in: after.rasterSurface, fallbackBackground: .white)
    let incremental = compositor.orderedAttachments(in: replay.surface, fallbackBackground: .white)
    #expect(fresh.count == 2)
    #expect(fresh[1].compositing == nil)
    #expect(incremental == fresh)
    #expect(try pixels(fresh[1]).allSatisfy { $0 == rgbaPixel(red: 0, green: 0, blue: 0) })
  }

  private func attachment(_ id: String, color: Color, mode: BlendMode? = nil) throws
    -> RasterImageAttachment
  {
    let bounds = rect(x: 0)
    let compositing = mode.map { mode in
      RasterImageCompositing(
        blendMode: mode,
        destinationBackdrop: .init(bounds: bounds, cells: [.init(backgroundColor: .white)]),
        sourceBackdrop: nil, cellPixelSize: .init(width: 1, height: 1), backdropSignature: 1)
    }
    let value = pixel(color)
    let bytes = try makePNGBytes(
      width: 1, height: 1,
      pixels: [.init(UInt8(value.red), UInt8(value.green), UInt8(value.blue), UInt8(value.alpha))])
    return RasterImageAttachment(
      identity: Identity(components: [id]), bounds: bounds,
      source: .data(bytes), resolvedReference: .embeddedImage(bytes), compositing: compositing)
  }
  private func rect(x: Int) -> CellRect {
    .init(origin: .init(x: x, y: 0), size: .init(width: 1, height: 1))
  }
  private func pixels(_ image: RasterImageAttachment) throws -> [RGBAImagePixel] {
    try #require(
      ImageAssetRepository().decodedImage(
        for: {
          if case .data(let bytes) = image.source { return .embeddedImage(bytes) }
          return .embeddedImage([])
        }())
    ).pixels
  }
  private func rgbaPixel(red: Int, green: Int, blue: Int, alpha: Int = 255) -> RGBAImagePixel {
    .init(red: red, green: green, blue: blue, alpha: alpha)
  }
  private func pixel(_ color: Color) -> RGBAImagePixel {
    let color = color.converted(to: .sRGB, gamutMapping: .clip)
    func byte(_ value: Double) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
    return .init(
      red: byte(color.red), green: byte(color.green), blue: byte(color.blue),
      alpha: byte(color.alpha))
  }
}
