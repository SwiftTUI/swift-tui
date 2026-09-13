/// Displays a finite pre-composed image sequence.
public struct AnimatedImage: View {
  public var sequence: AnimatedImageSequence
  @State private var frameIndex = 0
  @State private var activeSequence: AnimatedImageSequence?

  public init(
    _ sequence: AnimatedImageSequence
  ) {
    self.sequence = sequence
  }

  public init(
    frames: [AnimatedImageFrame],
    framesPerSecond: Double
  ) {
    sequence = AnimatedImageSequence(
      frames: frames,
      framesPerSecond: framesPerSecond
    )
  }

  public init(
    frames: [AnimatedImageFrame],
    frameDelays: [Duration]
  ) {
    sequence = AnimatedImageSequence(
      frames: frames,
      frameDelays: frameDelays
    )
  }

  public init(
    gifData data: [UInt8]
  ) throws {
    self.init(try AnimatedGIF.decode(data: data))
  }

  public init(
    gifContentsOf path: String
  ) throws {
    self.init(try AnimatedGIF.decode(contentsOf: path))
  }

  public var body: some View {
    EnvironmentReader(\.renderingReduceMotion) { accessibilityReduceMotion in
      animatedImageBody(accessibilityReduceMotion: accessibilityReduceMotion)
    }
  }

  @ViewBuilder
  private func animatedImageBody(accessibilityReduceMotion: Bool) -> some View {
    let frameIndex = accessibilityReduceMotion ? 0 : boundedFrameIndex
    let image = Image(data: sequence.encodedImageData(at: frameIndex))
    if sequence.frames.count > 1 && !accessibilityReduceMotion {
      image.task(id: sequence) { @MainActor in
        await play()
      }
    } else {
      image
    }
  }

  private var boundedFrameIndex: Int {
    activeSequence == sequence ? min(frameIndex, sequence.frames.count - 1) : 0
  }

  @MainActor
  private func play() async {
    await AnimatedImagePlayback.run(
      sequence,
      onFrame: { index in
        activeSequence = sequence
        frameIndex = index
      })
  }
}
