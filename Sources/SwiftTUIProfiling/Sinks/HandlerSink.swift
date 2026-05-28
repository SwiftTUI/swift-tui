/// In-process sink that forwards every record to a closure. This is the
/// WASI-safe path (no file I/O) and the one the hook tests drive.
@MainActor
package final class HandlerSink: ProfileSink {
  private let handler: @MainActor (ProfileRecord) -> Void

  package init(_ handler: @escaping @MainActor (ProfileRecord) -> Void) {
    self.handler = handler
  }

  package func emit(_ record: ProfileRecord) {
    handler(record)
  }
}
