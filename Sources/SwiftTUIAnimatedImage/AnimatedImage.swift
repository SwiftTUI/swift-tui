/// Displays a finite pre-composed image sequence.
public struct AnimatedImage: View {
  public var sequence: AnimatedImageSequence
  @State private var frameIndex = 0

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
    EnvironmentReader(\.accessibilityReduceMotion) { accessibilityReduceMotion in
      animatedImageBody(accessibilityReduceMotion: accessibilityReduceMotion)
    }
  }

  @ViewBuilder
  private func animatedImageBody(accessibilityReduceMotion: Bool) -> some View {
    let frameIndex = accessibilityReduceMotion ? 0 : boundedFrameIndex
    let image = Image(data: sequence.frames[frameIndex].imageData)
    if sequence.frames.count > 1 && !accessibilityReduceMotion {
      image.task(id: sequence) { @MainActor in
        await play()
      }
    } else {
      image
    }
  }

  private var boundedFrameIndex: Int {
    min(frameIndex, sequence.frames.count - 1)
  }

  @MainActor
  private func play() async {
    frameIndex = 0
    while !Task.isCancelled && sequence.frames.count > 1 {
      let currentFrame = min(frameIndex, sequence.frames.count - 1)
      try? await Task.sleep(nanoseconds: sequence.delayNanoseconds[currentFrame])
      if Task.isCancelled {
        break
      }
      frameIndex = (currentFrame + 1) % sequence.frames.count
    }
  }
}
