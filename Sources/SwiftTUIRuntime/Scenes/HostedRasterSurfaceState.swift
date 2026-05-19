import SwiftTUICore

package struct HostedFrameWaiter: Sendable {
  var predicate: @Sendable (SemanticHostFrame) -> Bool
  var continuation: CheckedContinuation<SemanticHostFrame, Never>
}

package struct HostedFrameSequenceWaiter: Sendable {
  var predicate: @Sendable ([SemanticHostFrame]) -> Bool
  var continuation: CheckedContinuation<[SemanticHostFrame], Never>
}

package struct HostedRasterSurfaceState: Sendable {
  var surfaceSize: CellSize
  var renderStyle: TerminalRenderStyle
  var graphicsCapabilities: TerminalGraphicsCapabilities
  var pointerInputCapabilities: PointerInputCapabilities
  var nextFrameSequence: UInt64
  var frames: [SemanticHostFrame] = []
  var frameWaiters: [HostedFrameWaiter] = []
  var frameSequenceWaiters: [HostedFrameSequenceWaiter] = []
}
