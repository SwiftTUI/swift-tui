import Foundation
import SwiftTUI
import SwiftTUIAnimatedImage
import Testing

@testable import GifCat

@MainActor
@Suite
struct GifCatViewTests {
  @Test("arguments become absolute paths in passed order")
  func argumentsBecomeAbsolutePathsInPassedOrder() throws {
    let root = try temporaryDirectory()
    let firstURL = root.appendingPathComponent("first.gif")
    let secondURL = root.appendingPathComponent("nested/second.gif")
    try FileManager.default.createDirectory(
      at: secondURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(Self.singlePixelGIF).write(to: firstURL)
    try Data(Self.singlePixelGIF).write(to: secondURL)
    defer {
      try? FileManager.default.removeItem(at: root)
    }

    let items = GifCatInput.items(
      paths: ["first.gif", "nested/second.gif"],
      currentDirectory: root.path
    )

    #expect(items.map(\.path) == [firstURL.path, secondURL.path])
    #expect(items.map(\.id) == [0, 1])
    #expect(items.allSatisfy { $0.exists })
  }

  @Test("grid plan tiles row-major in argument order")
  func gridPlanTilesRowMajorInArgumentOrder() {
    let plan = GifCatGridPlan(
      itemCount: 5
    )

    #expect(plan.columns == 3)
    #expect(plan.rows == 2)
    #expect(Array(plan.itemIndices(inRow: 0)) == [0, 1, 2])
    #expect(Array(plan.itemIndices(inRow: 1)) == [3, 4])
    #expect(Array(plan.itemIndices(inRow: 2)).isEmpty)
  }

  @Test("view resolves GIF paths into regular-size image attachments")
  func viewResolvesGIFPathsIntoRegularSizeImageAttachments() throws {
    let root = try temporaryDirectory()
    let firstURL = root.appendingPathComponent("first.gif")
    let secondURL = root.appendingPathComponent("second.gif")
    try Data(Self.singlePixelGIF).write(to: firstURL)
    try Data(Self.singlePixelGIF).write(to: secondURL)
    defer {
      try? FileManager.default.removeItem(at: root)
    }

    let items = GifCatInput.items(
      paths: ["first.gif", "second.gif"],
      currentDirectory: root.path
    )
    let artifacts = render(GifCatView(items: items), width: 80, height: 24)
    let attachments = artifacts.rasterSurface.imageAttachments
    let firstFrame = try #require(items[0].animation?.frames.first)
    let secondFrame = try #require(items[1].animation?.frames.first)

    #expect(attachments.count == 2)
    #expect(
      attachments.map(\.resolvedReference) == [
        .embeddedImage(firstFrame.imageData),
        .embeddedImage(secondFrame.imageData),
      ])
    #expect(attachments[0].bounds.origin.x < attachments[1].bounds.origin.x)
    #expect(attachments[1].bounds.origin.x == attachments[0].bounds.origin.x + 2)
    #expect(
      attachments.map(\.bounds.size) == [
        CellSize(width: 1, height: 1),
        CellSize(width: 1, height: 1),
      ])
  }

  @Test("animated GIFs load individual frame payloads and source delays")
  func animatedGIFsLoadIndividualFramePayloadsAndSourceDelays() throws {
    let animation = try AnimatedGIF.decode(data: Self.animatedGIFBytes())

    #expect(animation.frames.count == 2)
    #expect(animation.frameDelays == [.milliseconds(50), .milliseconds(120)])
    #expect(animation.frames[0].imageData != animation.frames[1].imageData)
  }

  @Test("animated GIF view advances frames for every passed GIF")
  func animatedGIFViewAdvancesFramesForEveryPassedGIF() async throws {
    let root = try temporaryDirectory()
    let gifSpecs = [
      ("first.gif", GIFColor(r: 255, g: 0, b: 0), GIFColor(r: 0, g: 0, b: 255)),
      ("second.gif", GIFColor(r: 0, g: 255, b: 0), GIFColor(r: 255, g: 255, b: 0)),
      ("third.gif", GIFColor(r: 0, g: 255, b: 255), GIFColor(r: 255, g: 0, b: 255)),
      ("fourth.gif", GIFColor(r: 255, g: 128, b: 0), GIFColor(r: 128, g: 0, b: 255)),
    ]
    for spec in gifSpecs {
      let url = root.appendingPathComponent(spec.0)
      try Data(Self.animatedGIFBytes(first: spec.1, second: spec.2)).write(to: url)
    }
    defer {
      try? FileManager.default.removeItem(at: root)
    }

    let items = GifCatInput.items(
      paths: gifSpecs.map(\.0),
      currentDirectory: root.path
    )
    let expectedSecondFrameReferences = try items.map { item in
      ImageAssetReference.embeddedImage(try #require(item.animation?.frames[1].imageData))
    }
    let host = GifCatRecordingHost(size: CellSize(width: 20, height: 8))
    let inputReader = GifCatConditionalInputReader {
      expectedSecondFrameReferences.allSatisfy { host.observedReferences.contains($0) }
    }
    let rootIdentity = Identity(components: ["gifcat.animation.tests"])
    let terminalSize = host.surfaceSize
    var environment = EnvironmentValues()
    environment.terminalAppearance = host.appearance
    environment.terminalSize = terminalSize

    let runLoop = SwiftTUI.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      inputReader: inputReader,
      signalReader: nil,
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: environment,
      proposal: ProposedSize(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        GifCatView(items: items)
      }
    )

    let result = try await runLoop.run()

    #expect(
      result.exitReason
        == RunLoopExitReason.userExit(KeyPress(.character("d"), modifiers: .ctrl))
    )
    for expectedReference in expectedSecondFrameReferences {
      #expect(host.observedReferences.contains(expectedReference))
    }
    #expect(result.renderedFrames >= 2)
  }

  @Test("missing GIF paths render a compact diagnostic")
  func missingGIFPathsRenderACompactDiagnostic() {
    let item = GifCatItem(
      id: 0,
      originalPath: "missing.gif",
      path: "/tmp/missing.gif",
      exists: false
    )
    let artifacts = render(GifCatView(items: [item]), width: 40, height: 8)

    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("missing:"))
    #expect(artifacts.rasterSurface.imageAttachments.isEmpty)
  }

  @Test("empty invocation renders usage")
  func emptyInvocationRendersUsage() {
    let artifacts = render(GifCatView(items: []), width: 40, height: 8)

    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("usage: gifcat"))
    #expect(artifacts.rasterSurface.imageAttachments.isEmpty)
  }

  private static let singlePixelGIF: [UInt8] = [
    0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00,
    0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0x21, 0xf9, 0x04, 0x00, 0x0a,
    0x00, 0x00, 0x00, 0x2c, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
    0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x3b,
  ]

  private static func animatedGIFBytes(
    first: GIFColor = GIFColor(r: 255, g: 0, b: 0),
    second: GIFColor = GIFColor(r: 0, g: 0, b: 255)
  ) throws -> [UInt8] {
    try AnimatedGIF.encode(
      AnimatedImageSequence(
        frames: [
          AnimatedImageFrame(width: 1, height: 1, pixels: [first.pixel]),
          AnimatedImageFrame(width: 1, height: 1, pixels: [second.pixel]),
        ],
        frameDelays: [.milliseconds(50), .milliseconds(120)]
      )
    )
  }
}

private struct GIFColor {
  var r: UInt8
  var g: UInt8
  var b: UInt8

  var pixel: AnimatedImagePixel {
    AnimatedImagePixel(red: r, green: g, blue: b)
  }
}

@MainActor
private func render(
  _ view: some View,
  width: Int,
  height: Int
) -> FrameArtifacts {
  var env = EnvironmentValues()
  env.terminalSize = CellSize(width: width, height: height)
  return DefaultRenderer().render(
    view,
    context: ResolveContext(
      identity: Identity(components: ["gifcat.tests"]),
      environmentValues: env
    ),
    proposal: ProposedSize(width: width, height: height)
  )
}

private func temporaryDirectory() throws -> URL {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("gifcat-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(
    at: root,
    withIntermediateDirectories: true
  )
  return root
}

private final class GifCatRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var observedReferences: [ImageAssetReference] = []

  init(size: CellSize) {
    surfaceSize = size
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func write(_: String) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    observedReferences.append(
      contentsOf: surface.imageAttachments.compactMap(\.resolvedReference)
    )
    return TerminalPresentationMetrics(
      bytesWritten: 0,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }
}

private final class GifCatConditionalInputReader: InputReading {
  private let shouldExit: @MainActor () -> Bool

  init(shouldExit: @escaping @MainActor () -> Bool) {
    self.shouldExit = shouldExit
  }

  func events() -> AsyncStream<KeyPress> {
    AsyncStream { continuation in
      let shouldExit = self.shouldExit
      let task = Task { @MainActor in
        let timeoutNanoseconds: UInt64 = 1_000_000_000
        let pollNanoseconds: UInt64 = 10_000_000
        var elapsedNanoseconds: UInt64 = 0

        while !shouldExit() && elapsedNanoseconds < timeoutNanoseconds {
          try? await Task.sleep(nanoseconds: pollNanoseconds)
          elapsedNanoseconds += pollNanoseconds
        }

        continuation.yield(KeyPress(.character("d"), modifiers: .ctrl))
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}
