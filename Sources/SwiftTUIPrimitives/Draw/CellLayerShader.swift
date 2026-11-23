import Synchronization

/// A reusable cell program whose configuration participates in draw equality.
public protocol CellLayerKernel: Equatable, Sendable {
  nonisolated func shade(
    at destination: CellPoint, in source: CellLayer, context: CellEffectContext
  ) -> CellSample
}

/// How an ordered shader changes the destination at the current paint position.
public enum CellCompositeResult: Equatable, Sendable {
  case keepDestination
  case replace(CellSample)
}

/// Reads the subject and the lower paint in the same coordinate system.
public protocol CellCompositingKernel: Equatable, Sendable {
  nonisolated func composite(
    at destination: CellPoint, source: CellLayer, backdrop: CellLayer, context: CellEffectContext
  ) -> CellCompositeResult
}

/// Mutates one bounded output buffer in the author's traversal order.
public protocol CellRegionKernel: Equatable, Sendable {
  nonisolated func apply(
    source: CellLayer, to buffer: inout CellEffectBuffer, context: CellEffectContext)
}

private protocol ShaderKey: AnyObject, Sendable {
  func matches(_ other: any ShaderKey) -> Bool
}

private final class ClosureKey: ShaderKey {
  func matches(_ other: any ShaderKey) -> Bool { self === other }
}

private final class KernelKey<K: Equatable & Sendable>: ShaderKey {
  let value: K
  init(_ value: K) { self.value = value }
  func matches(_ other: any ShaderKey) -> Bool {
    guard let other = other as? KernelKey<K> else { return false }
    return value == other.value
  }
}

/// An immutable cell program. Copies of a closure shader share its identity.
public struct CellLayerShader: Equatable, Sendable {
  public typealias Function = @Sendable (CellPoint, CellLayer, CellEffectContext) -> CellSample
  public typealias CompositingFunction =
    @Sendable (
      CellPoint, CellLayer, CellLayer, CellEffectContext
    ) -> CellCompositeResult
  public typealias RegionFunction =
    @Sendable (CellLayer, inout CellEffectBuffer, CellEffectContext) -> Void

  package enum Program: Sendable {
    case source(Function)
    case composite(CompositingFunction)
    case ordered(RegionFunction)
  }
  private let key: any ShaderKey
  package let program: Program
  package private(set) var region: CellDrawingRegion = .source
  package var readsBackdrop: Bool {
    if case .composite = program { return true }
    return false
  }

  private init(key: any ShaderKey, program: Program) {
    self.key = key
    self.program = program
  }

  public init<K: CellLayerKernel>(_ kernel: K) {
    self.init(key: KernelKey(kernel), program: .source(kernel.shade))
  }

  public init(_ shade: @escaping Function) {
    self.init(key: ClosureKey(), program: .source(shade))
  }

  /// Composites the source against the current lower paint.
  public static func compositing<K: CellCompositingKernel>(_ kernel: K) -> Self {
    Self(key: KernelKey(kernel), program: .composite(kernel.composite))
  }

  public static func compositing(_ composite: @escaping CompositingFunction) -> Self {
    Self(key: ClosureKey(), program: .composite(composite))
  }

  /// Runs an ordered program with a stable input and a writable output.
  public static func region<K: CellRegionKernel>(_ kernel: K) -> Self {
    Self(key: KernelKey(kernel), program: .ordered(kernel.apply))
  }

  public static func region(_ apply: @escaping RegionFunction) -> Self {
    Self(key: ClosureKey(), program: .ordered(apply))
  }

  /// Selects where this shader may write. It uses the source bounds by default.
  public func drawing(in region: CellDrawingRegion) -> Self {
    var copy = self
    copy.region = region
    return copy
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    guard lhs.key.matches(rhs.key), lhs.region == rhs.region else { return false }
    switch (lhs.program, rhs.program) {
    case (.source, .source), (.composite, .composite), (.ordered, .ordered): return true
    default: return false
    }
  }
}

/// Heap storage keeps the ordered draw descriptor compact on the raster worker stack.
package final class CellEffectPass: Equatable, Sendable {
  package let shader: CellLayerShader
  #if DEBUG
    private let didReport = Mutex(false)
  #endif

  package func reportInvalidRead() {
    #if DEBUG
      let first = didReport.withLock { reported in
        if reported { return false }
        reported = true
        return true
      }
      if first {
        DebugLogRouter.emit(
          "SwiftTUI cell effect: a negative distance or a read beyond maxSampleOffset.\n",
          toFileAt: DebugLogRouter.resolvedFilePath(
            override: nil, bundleFileName: "cell-effects.log"),
          fallback: .safeStandardError)
      }
    #endif
  }

  package let offset: CellSampleOffset

  package let targetsBackdrop: Bool

  package init(_ shader: CellLayerShader, offset: CellSampleOffset, targetsBackdrop: Bool = false) {
    self.targetsBackdrop = targetsBackdrop
    self.shader = shader
    self.offset = offset
    #if DEBUG
      if case .cells(let x, let y) = offset, x < 0 || y < 0 { reportInvalidRead() }
      if case .outset(let x, let y) = shader.region, x < 0 || y < 0 { reportInvalidRead() }
    #endif
  }

  package static func == (lhs: CellEffectPass, rhs: CellEffectPass) -> Bool {
    lhs === rhs
      || (lhs.shader == rhs.shader && lhs.offset == rhs.offset
        && lhs.targetsBackdrop == rhs.targetsBackdrop)
  }
}
