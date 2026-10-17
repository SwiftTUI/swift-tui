import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

@Suite
struct TerminalPresentationContractTests {
  @Test func fullTextRepaintIsRequiredEvenWhenCellsAreUnchanged() {
    let surface = RasterSurface(size: .init(width: 4, height: 1), lines: ["same"])
    let planner = TerminalPresentationPlanner(capabilityProfile: .previewUnicode)
    #expect(
      planner.plan(previousSurface: surface, currentSurface: surface).strategy == .incremental)
    #expect(
      planner.plan(
        previousSurface: surface, currentSurface: surface,
        damage: .init(requiresFullTextRepaint: true)
      ).strategy == .fullRepaint)
  }

  @Test func declaredBoundsLimitFullAndIncrementalOutput() {
    let previous = RasterSurface(
      size: .init(width: 2, height: 1),
      cells: [
        "abcd".map { RasterCell(character: $0) }, "outside".map { RasterCell(character: $0) },
      ])
    let current = RasterSurface(
      size: previous.size,
      cells: [
        "abXY".map { RasterCell(character: $0) }, "CHANGED".map { RasterCell(character: $0) },
      ])
    let renderer = TerminalSurfaceRenderer(capabilityProfile: .previewUnicode)
    let planner = TerminalPresentationPlanner(capabilityProfile: .previewUnicode)
    #expect(renderer.render(current) == "ab")
    #expect(fullRepaintWriteSteps(for: current, capabilityProfile: .previewUnicode) == ["ab"])
    #expect(planner.plan(previousSurface: previous, currentSurface: current).rowBatches.isEmpty)
  }

  @Test func explicitGraphicsDamageReplaysUnchangedAttachments() {
    let image = RasterImageAttachment(
      identity: Identity(components: [.named("image")]),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
      source: .path("asset.png"), resolvedReference: .filePath("/tmp/asset.png"),
      pixelSize: .init(width: 8, height: 8), isResizable: false, scalingMode: .stretch)
    let surface = RasterSurface(
      size: .init(width: 4, height: 1), lines: ["same"], imageAttachments: [image])
    let planner = TerminalPresentationPlanner(
      capabilityProfile: .previewUnicode,
      graphicsCapabilities: .init(supportedProtocols: [.kitty], preferredProtocol: .kitty))
    for full in [false, true] {
      let damage = PresentationDamage(
        dirtyRows: [], graphicsInvalidation: full ? [] : [image.identity],
        requiresFullGraphicsReplay: full)
      let plan = planner.plan(previousSurface: surface, currentSurface: surface, damage: damage)
      #expect(plan.strategy == .incremental)
      #expect(plan.rowBatches.isEmpty)
      #expect(plan.graphicsReplay.scope == (full ? .full : .targeted))
      #expect(plan.graphicsReplay.attachmentsToReplay == [image])
      let sixel = TerminalPresentationPlanner(
        capabilityProfile: .previewUnicode,
        graphicsCapabilities: .init(supportedProtocols: [.sixel], preferredProtocol: .sixel))
      #expect(
        sixel.plan(previousSurface: surface, currentSurface: surface, damage: damage).strategy
          == .fullRepaint)
    }
  }

  @Test func droppedFrameDoesNotCancelExplicitRepaintIntent() {
    var session = TerminalPresentationSession()
    session.lastWrittenSurface = RasterSurface(size: .init(width: 4, height: 3), lines: ["old"])
    session.requestedDamageTrustsBaseline = false
    let requested = PresentationDamage(
      dirtyRows: [2], requiresFullTextRepaint: true, requiresFullGraphicsReplay: true)
    let recovered = session.presentationDamage(requested: requested)
    #expect(recovered?.requiresFullTextRepaint == true)
    #expect(recovered?.requiresFullGraphicsReplay == true)
    #expect(recovered?.dirtyRows == [0, 1, 2])
  }
}
