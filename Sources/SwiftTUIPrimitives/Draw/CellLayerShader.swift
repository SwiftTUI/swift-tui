/// A reusable cell program whose configuration participates in draw equality.
public protocol CellLayerKernel: Equatable, Sendable {
  nonisolated func shade(
    at destination: CellPoint, in source: CellLayer, context: CellEffectContext
  ) -> CellSample
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
  package typealias RasterFunction =
    @Sendable (
      CellPoint, CellLayer, CellLayer, CellEffectContext
    ) -> CellSample

  private let key: any ShaderKey
  package let raster: RasterFunction
  package private(set) var region: CellDrawingRegion = .source
  package private(set) var readsBackdrop = false

  public init<K: CellLayerKernel>(_ kernel: K) {
    key = KernelKey(kernel)
    raster = { point, source, _, context in kernel.shade(at: point, in: source, context: context) }
  }

  public init(_ shade: @escaping Function) {
    key = ClosureKey()
    raster = { point, source, _, context in shade(point, source, context) }
  }

  package init(readingBackdrop raster: @escaping RasterFunction) {
    key = ClosureKey()
    self.raster = raster
    readsBackdrop = true
  }

  /// Selects where this shader may write. It uses the source bounds by default.
  public func drawing(in region: CellDrawingRegion) -> Self {
    var copy = self
    copy.region = region
    return copy
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.key.matches(rhs.key) && lhs.region == rhs.region
  }
}

/// Heap storage keeps the ordered draw descriptor compact on the raster worker stack.
package final class CellEffectPass: Equatable, Sendable {
  package let shader: CellLayerShader
  package let offset: CellSampleOffset

  package init(_ shader: CellLayerShader, offset: CellSampleOffset) {
    self.shader = shader
    self.offset = offset
  }

  package static func == (lhs: CellEffectPass, rhs: CellEffectPass) -> Bool {
    lhs === rhs || (lhs.shader == rhs.shader && lhs.offset == rhs.offset)
  }
}
