import Foundation
import SwiftTUI
import SwiftTUIAnimatedImage
@_spi(Testing) import SwiftTUITestSupport
import Testing

@MainActor
@Suite
struct AnimatedImageTests {
  @Test("GIF encoding and decoding round-trips pre-composed frames and delays")
  func gifEncodingAndDecodingRoundTripsFramesAndDelays() throws {
    let sequence = AnimatedImageSequence(
      frames: [
        Self.frame(red: 255, green: 0, blue: 0),
        Self.frame(red: 0, green: 0, blue: 255),
      ],
      frameDelays: [.milliseconds(50), .milliseconds(120)]
    )

    let encoded = try AnimatedGIF.encode(sequence)
    let decoded = try AnimatedGIF.decode(data: encoded)

    #expect(decoded.frames.count == 2)
    #expect(decoded.frameDelays == [.milliseconds(50), .milliseconds(120)])
    #expect(decoded.frames.map(\.pixels) == sequence.frames.map(\.pixels))
  }

  @Test("Repo Nyan GIF decodes every source frame as a distinct composed frame")
  func repoNyanGIFDecodesEverySourceFrameAsDistinctComposedFrame() throws {
    let sequence = try AnimatedGIF.decode(
      contentsOf: Self.repoFixturePath("Fixtures/AnimatedImage/nyan.gif")
    )
    let uniqueComposedFrames = Set(sequence.frames.map { $0.pixels })

    #expect(sequence.frames.count == 12)
    #expect(uniqueComposedFrames.count == sequence.frames.count)
    #expect(sequence.frameDelays.count == sequence.frames.count)
  }

  @Test("AnimatedImage renders supplied frames through static image attachments")
  func animatedImageRendersSuppliedFramesThroughStaticImageAttachments() throws {
    let frame = Self.frame(red: 255, green: 255, blue: 255)
    let artifacts = DefaultRenderer().render(
      AnimatedImage(frames: [frame], framesPerSecond: 12)
    )
    let attachment = try #require(artifacts.rasterSurface.imageAttachments.first)

    #expect(artifacts.rasterSurface.imageAttachments.count == 1)
    #expect(attachment.resolvedReference == .embeddedImage(frame.imageData))
    #expect(attachment.pixelSize == .init(width: 1, height: 1))
  }

  @Test("AnimatedImage advances through every GIF-decoded frame")
  func animatedImageAdvancesThroughEveryGIFDecodedFrame() async throws {
    let frames = [
      Self.frame(red: 255, green: 0, blue: 0),
      Self.frame(red: 0, green: 0, blue: 255),
      Self.frame(red: 0, green: 255, blue: 0),
      Self.frame(red: 255, green: 255, blue: 0),
    ]
    let sequence = AnimatedImageSequence(
      frames: frames,
      frameDelays: [
        .milliseconds(20),
        .milliseconds(20),
        .milliseconds(20),
        .milliseconds(20),
      ]
    )
    let gifDecodedSequence = try AnimatedGIF.decode(data: AnimatedGIF.encode(sequence))
    let expectedFrameReferences = gifDecodedSequence.frames.map {
      ImageAssetReference.embeddedImage($0.imageData)
    }
    let host = AnimatedImageRecordingHost(size: CellSize(width: 4, height: 2))
    let inputReader = AnimatedImageConditionalInputReader(
      frameSignal: host.frameSignal
    ) {
      expectedFrameReferences.allSatisfy { host.observedReferences.contains($0) }
    }
    let rootIdentity = Identity(components: ["animated-image.tests"])
    let terminalSize = host.surfaceSize
    var environment = EnvironmentValues()
    environment.terminalAppearance = host.appearance
    environment.terminalSize = terminalSize

    let runLoop = SwiftTUIRuntime.RunLoop(
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
        AnimatedImage(gifDecodedSequence)
      }
    )

    let result = try await runLoop.run()

    #expect(
      result.exitReason
        == RunLoopExitReason.userExit(KeyPress(.character("d"), modifiers: .ctrl))
    )
    for expectedReference in expectedFrameReferences {
      #expect(host.observedReferences.contains(expectedReference))
    }
    #expect(result.renderedFrames >= expectedFrameReferences.count)
  }

  @Test("AnimatedImage renders first frame without playback task under reduced motion")
  func animatedImageRendersFirstFrameWithoutPlaybackTaskUnderReducedMotion() throws {
    let frames = [
      Self.frame(red: 255, green: 0, blue: 0),
      Self.frame(red: 0, green: 0, blue: 255),
    ]
    let sequence = AnimatedImageSequence(
      frames: frames,
      frameDelays: [.milliseconds(20), .milliseconds(20)]
    )
    let taskRegistry = LocalTaskRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.accessibilityReduceMotion = true

    let artifacts = DefaultRenderer().render(
      AnimatedImage(sequence),
      context: ResolveContext(
        identity: Identity(components: ["animated-image.reduced-motion"]),
        environmentValues: environmentValues,
        localTaskRegistry: taskRegistry,
        applyEnvironmentValues: true
      )
    )
    let attachment = try #require(artifacts.rasterSurface.imageAttachments.first)

    #expect(taskRegistry.snapshot().isEmpty)
    #expect(attachment.resolvedReference == .embeddedImage(frames[0].imageData))
  }

  private static func frame(
    red: UInt8,
    green: UInt8,
    blue: UInt8
  ) -> AnimatedImageFrame {
    AnimatedImageFrame(
      width: 1,
      height: 1,
      pixels: [AnimatedImagePixel(red: red, green: green, blue: blue)]
    )
  }

  private static func repoFixturePath(
    _ name: String
  ) -> String {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(name)
      .path
  }
}

private final class AnimatedImageRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var observedReferences: [ImageAssetReference] = []

  /// Notified after every present, so an awaited input reader can re-check its
  /// exit predicate the instant a frame lands instead of polling.
  let frameSignal = MainActorConditionSignal()

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
    // The run loop only ever presents on the MainActor; `assumeIsolated`
    // bridges this nonisolated witness to the MainActor-isolated signal.
    let frameSignal = self.frameSignal
    MainActor.assumeIsolated {
      frameSignal.notify()
    }
    return TerminalPresentationMetrics(
      bytesWritten: 0,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }
}

private final class AnimatedImageConditionalInputReader: InputReading {
  private let shouldExit: @MainActor () -> Bool
  private let frameSignal: MainActorConditionSignal

  init(
    frameSignal: MainActorConditionSignal,
    shouldExit: @escaping @MainActor () -> Bool
  ) {
    self.frameSignal = frameSignal
    self.shouldExit = shouldExit
  }

  func events() -> AsyncStream<KeyPress> {
    AsyncStream { continuation in
      let shouldExit = self.shouldExit
      let frameSignal = self.frameSignal
      let task = Task { @MainActor in
        await frameSignal.wait(until: shouldExit)
        continuation.yield(KeyPress(.character("d"), modifiers: .ctrl))
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}
