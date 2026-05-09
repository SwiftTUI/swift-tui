import SwiftTUI
import SwiftTUIAnimatedImage
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

  @Test("AnimatedImage advances through supplied frames")
  func animatedImageAdvancesThroughSuppliedFrames() async throws {
    let frames = [
      Self.frame(red: 255, green: 0, blue: 0),
      Self.frame(red: 0, green: 0, blue: 255),
    ]
    let sequence = AnimatedImageSequence(
      frames: frames,
      frameDelays: [.milliseconds(20), .milliseconds(20)]
    )
    let expectedSecondFrame = ImageAssetReference.embeddedImage(frames[1].imageData)
    let host = AnimatedImageRecordingHost(size: CellSize(width: 4, height: 2))
    let inputReader = AnimatedImageConditionalInputReader {
      host.observedReferences.contains(expectedSecondFrame)
    }
    let rootIdentity = Identity(components: ["animated-image.tests"])
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
        AnimatedImage(sequence)
      }
    )

    let result = try await runLoop.run()

    #expect(
      result.exitReason
        == RunLoopExitReason.userExit(KeyPress(.character("c"), modifiers: .ctrl))
    )
    #expect(host.observedReferences.contains(expectedSecondFrame))
    #expect(result.renderedFrames >= 2)
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
}

private final class AnimatedImageRecordingHost: PresentationSurface {
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

private final class AnimatedImageConditionalInputReader: InputReading {
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

        continuation.yield(KeyPress(.character("c"), modifiers: .ctrl))
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}
