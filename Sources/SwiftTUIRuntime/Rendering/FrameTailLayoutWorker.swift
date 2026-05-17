import Synchronization

#if canImport(Dispatch)
  @unsafe @preconcurrency import Dispatch
#endif

final class FrameTailLayoutWorkerBox: Sendable {
  private let storage = Mutex<FrameTailLayoutWorker?>(nil)

  func async<Value>(
    _ operation: @escaping @Sendable () -> Value
  ) async -> Value {
    let worker = storage.withLock { storage in
      if let storage {
        return storage
      }
      let worker = FrameTailLayoutWorker()
      storage = worker
      return worker
    }
    return await worker.async(operation)
  }
}

#if canImport(Dispatch)
  private final class FrameTailLayoutWorker: Sendable {
    private let queue = DispatchQueue(label: "swift-tui.frame-tail-layout")

    func async<Value>(
      _ operation: @escaping @Sendable () -> Value
    ) async -> Value {
      await withCheckedContinuation { continuation in
        queue.async {
          continuation.resume(returning: operation())
        }
      }
    }
  }
#else
  private final class FrameTailLayoutWorker: Sendable {
    func async<Value>(
      _ operation: @escaping @Sendable () -> Value
    ) async -> Value {
      // WASI currently lacks the threaded/Dispatch worker used by native
      // runtimes. ADR-0020 records the accepted synchronous fallback.
      operation()
    }
  }
#endif
