public struct FramePhaseTimings: Equatable, Sendable {
  public var resolve: Duration
  public var measure: Duration
  public var place: Duration
  public var semantics: Duration
  public var draw: Duration
  public var raster: Duration
  public var commit: Duration

  public init(
    resolve: Duration = .zero,
    measure: Duration = .zero,
    place: Duration = .zero,
    semantics: Duration = .zero,
    draw: Duration = .zero,
    raster: Duration = .zero,
    commit: Duration = .zero
  ) {
    self.resolve = resolve
    self.measure = measure
    self.place = place
    self.semantics = semantics
    self.draw = draw
    self.raster = raster
    self.commit = commit
  }

  public var total: Duration {
    resolve
      + measure
      + place
      + semantics
      + draw
      + raster
      + commit
  }
}

/// Monotonic identity assigned to one renderer pass.
public struct RenderGeneration: Comparable, Equatable, Hashable, Sendable {
  public var rawValue: UInt64

  public init(_ rawValue: UInt64 = 0) {
    self.rawValue = rawValue
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

extension RenderGeneration {
  public static var zero: Self {
    Self()
  }
}

/// Generation IDs observed while rendering one frame.
public struct FrameRenderGenerations: Equatable, Sendable {
  public var render: RenderGeneration
  public var layoutInput: RenderGeneration?
  public var layoutOutput: RenderGeneration?
  public var rasterInput: RenderGeneration?
  public var rasterOutput: RenderGeneration?

  public init(
    render: RenderGeneration = .zero,
    layoutInput: RenderGeneration? = nil,
    layoutOutput: RenderGeneration? = nil,
    rasterInput: RenderGeneration? = nil,
    rasterOutput: RenderGeneration? = nil
  ) {
    self.render = render
    self.layoutInput = layoutInput
    self.layoutOutput = layoutOutput
    self.rasterInput = rasterInput
    self.rasterOutput = rasterOutput
  }
}

/// Timing summaries for work submitted to the frame-tail renderer.
public struct FrameWorkerTimings: Equatable, Sendable {
  public var layoutEnqueueToStart: Duration
  public var layoutCompute: Duration
  public var rasterEnqueueToStart: Duration
  public var rasterCompute: Duration
  public var completionToMainCommit: Duration

  public init(
    layoutEnqueueToStart: Duration = .zero,
    layoutCompute: Duration = .zero,
    rasterEnqueueToStart: Duration = .zero,
    rasterCompute: Duration = .zero,
    completionToMainCommit: Duration = .zero
  ) {
    self.layoutEnqueueToStart = layoutEnqueueToStart
    self.layoutCompute = layoutCompute
    self.rasterEnqueueToStart = rasterEnqueueToStart
    self.rasterCompute = rasterCompute
    self.completionToMainCommit = completionToMainCommit
  }
}

/// Main-actor timing summaries for one render pass.
public struct FrameMainActorTimings: Equatable, Sendable {
  public var blocked: Duration
  public var suspended: Duration

  public init(
    blocked: Duration = .zero,
    suspended: Duration = .zero
  ) {
    self.blocked = blocked
    self.suspended = suspended
  }
}
