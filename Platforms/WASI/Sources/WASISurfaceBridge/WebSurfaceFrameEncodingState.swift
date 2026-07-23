@_spi(Runners) package import SwiftTUIRuntime

/// The web wire's instantiation of the shared cross-frame encoding state.
/// The state shape (persistent style table, transmitted-image dedup set,
/// delta baseline) is host-neutral and lives beside `HostWireFrameModel` so
/// a second delta-capable wire can instantiate the same machinery instead
/// of re-implementing it.
package typealias WebSurfaceFrameEncodingState = HostWireEncodingState
