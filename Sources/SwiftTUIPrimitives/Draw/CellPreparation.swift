import Synchronization

/// Geometry and logical animation time for one preparation of a mounted cell effect.
public struct CellPreparationContext: Equatable, Sendable {
  public let geometry: CellEffectContext
  public let elapsed: Duration
  public let delta: Duration
  public let previousSourceBounds: CellRect?

  public init(
    geometry: CellEffectContext, elapsed: Duration, delta: Duration, previousSourceBounds: CellRect?
  ) {
    self.geometry = geometry
    self.elapsed = elapsed
    self.delta = delta
    self.previousSourceBounds = previousSourceBounds
  }
}

/// Produces one immutable shader from the progress and source of a logical sample.
public protocol CellPreparedLayerKernel: Equatable, Sendable {
  associatedtype State: Sendable
  nonisolated func makeState() -> State
  nonisolated func prepare(
    _ state: inout State, source: CellLayer, context: CellPreparationContext
  ) -> CellLayerShader
}

/// Two layout targets for one mounted view, expressed in its parent's cell coordinates.
public struct CellPlacementContext: Equatable, Sendable {
  public let previousFrame: CellRect
  public let currentFrame: CellRect
  public let progress: Double
  public init(previousFrame: CellRect, currentFrame: CellRect, progress: Double) {
    self.previousFrame = previousFrame
    self.currentFrame = currentFrame
    self.progress = progress
  }
}

/// Retained samplers keep their own attempt's uniform even after a newer frame advances.
package final class CellPreparationFrame: Sendable {
  package let instant: MonotonicInstant
  private let shaders = Mutex<[ObjectIdentifier: CellLayerShader]>([:])
  package init(at instant: MonotonicInstant) { self.instant = instant }

  func cached(for run: AnyObject) -> CellLayerShader? {
    shaders.withLock { $0[ObjectIdentifier(run)] }
  }

  func transfer(_ run: AnyObject, to destination: CellPreparationFrame) {
    if let shader = cached(for: run) {
      destination.shaders.withLock { $0[ObjectIdentifier(run)] = shader }
    }
  }

  func sample(for run: AnyObject, _ compute: () -> CellLayerShader) -> CellLayerShader {
    let key = ObjectIdentifier(run)
    if let cached = shaders.withLock({ $0[key] }) { return cached }
    let prepared = compute()
    shaders.withLock { $0[key] = prepared }
    return prepared
  }
}

/// Resolve reserves this position even when the modifier is disabled.
package struct CellPreparationSite: Hashable, Sendable {
  package let identity: Identity
  let position: Int
  package init(identity: Identity, position: Int) {
    self.identity = identity
    self.position = position
  }
}

package protocol CellPreparationBinding: Sendable {
  var site: CellPreparationSite { get }
  func callAsFunction(
    _ source: CellLayer, _ geometry: CellEffectContext, _ frame: CellPreparationFrame
  ) -> CellLayerShader
  func cached(in frame: CellPreparationFrame) -> CellLayerShader?
  func transfer(from: CellPreparationFrame, to: CellPreparationFrame)
  func continuing(_ older: any CellPreparationBinding) -> CellLayerShader?
}

struct MountedCellPreparation<K: CellPreparedLayerKernel>: CellPreparationBinding {
  let kernel: K
  let run: CellPreparationRun<K>
  var site: CellPreparationSite { run.site }

  func callAsFunction(
    _ source: CellLayer, _ geometry: CellEffectContext, _ frame: CellPreparationFrame
  ) -> CellLayerShader {
    run.shader(for: kernel, source: source, geometry: geometry, frame: frame)
  }

  func cached(in frame: CellPreparationFrame) -> CellLayerShader? { frame.cached(for: run) }
  func transfer(from: CellPreparationFrame, to: CellPreparationFrame) {
    from.transfer(run, to: to)
  }

  func continuing(_ older: any CellPreparationBinding) -> CellLayerShader? {
    guard let original = older as? Self else { return nil }
    return .init(preparing: kernel, run: original.run)
  }
}

/// A run belongs to the modifier's mounted site. A removal snapshot holds the
/// same run until it finishes, independently of a replacement at the same path.
package final class CellPreparationRun<K: CellPreparedLayerKernel>: Sendable {
  private struct Storage: Sendable {
    var author: K.State
    let start: MonotonicInstant
    var timestamp: MonotonicInstant
    var bounds: CellRect
    var shader: CellLayerShader
  }
  private let storage = Mutex<Storage?>(nil)
  let site: CellPreparationSite
  package init(at site: CellPreparationSite) { self.site = site }

  func shader(
    for kernel: K, source: CellLayer, geometry: CellEffectContext, frame: CellPreparationFrame
  ) -> CellLayerShader {
    frame.sample(for: self) {
      storage.withLock { stored in
        if let previous = stored, frame.instant <= previous.timestamp { return previous.shader }
        let start = stored?.start ?? frame.instant
        let previous = stored?.timestamp ?? frame.instant
        var state = stored?.author ?? kernel.makeState()
        let shader = kernel.prepare(
          &state, source: source,
          context: .init(
            geometry: geometry, elapsed: start.duration(to: frame.instant),
            delta: previous.duration(to: frame.instant), previousSourceBounds: stored?.bounds))
        stored = .init(
          author: state, start: start, timestamp: frame.instant,
          bounds: geometry.sourceBounds, shader: shader)
        return shader
      }
    }
  }
}
