import SwiftTUICore

#if canImport(os)
  import os
#endif

extension BodyChangeSink {
  /// Inherited only within this renderer invocation. Standalone authoring
  /// consumers retain the portable sink; nested renderers preserve injection.
  @MainActor package static var nativeRuntime: BodyChangeSink {
    BodyChangeSink { record, format in
      #if canImport(os)
        if format == .json, DebugLogRouter.activeDebugDirectory() == nil {
          let logger = Logger(subsystem: "sh.swifttui", category: "Changed Body Properties")
          // The record contains only bounded framework/type/declaration metadata.
          logger.info("\(record.formatted(.json), privacy: .public)")
          return
        }
      #endif
      BodyChangeOutput.emitPortable(record, format: format)
    }
  }
}
