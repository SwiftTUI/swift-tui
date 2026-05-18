import Synchronization

#if canImport(Dispatch)
  @unsafe @preconcurrency import Dispatch
#endif

enum FrameTailLayoutWorkerScheduling: Sendable {
  case platformDefault
  case immediate
}

final class FrameTailLayoutWorkerBox: Sendable {
  private let storage = Mutex<FrameTailLayoutWorker?>(nil)
  private let scheduling: FrameTailLayoutWorkerScheduling

  init(scheduling: FrameTailLayoutWorkerScheduling = .platformDefault) {
    self.scheduling = scheduling
  }

  func async<Value>(
    _ operation: @escaping @Sendable () -> Value
  ) async -> Value {
    let worker = storage.withLock { storage in
      if let storage {
        return storage
      }
      let worker = FrameTailLayoutWorker(scheduling: scheduling)
      storage = worker
      return worker
    }
    return await worker.async(operation)
  }
}

private enum FrameTailLayoutWorker: Sendable {
  #if canImport(Dispatch)
    case dispatch(DispatchFrameTailLayoutWorker)
  #endif
  case immediate(ImmediateFrameTailLayoutWorker)

  init(scheduling: FrameTailLayoutWorkerScheduling) {
    switch scheduling {
    case .platformDefault:
      #if canImport(Dispatch)
        self = .dispatch(DispatchFrameTailLayoutWorker())
      #else
        self = .immediate(ImmediateFrameTailLayoutWorker())
      #endif
    case .immediate:
      self = .immediate(ImmediateFrameTailLayoutWorker())
    }
  }

  func async<Value>(
    _ operation: @escaping @Sendable () -> Value
  ) async -> Value {
    switch self {
    #if canImport(Dispatch)
      case .dispatch(let worker):
        await worker.async(operation)
    #endif
    case .immediate(let worker):
      await worker.async(operation)
    }
  }
}

private struct ImmediateFrameTailLayoutWorker: Sendable {
  func async<Value>(
    _ operation: @escaping @Sendable () -> Value
  ) async -> Value {
    // WASI currently lacks the threaded/Dispatch worker used by native
    // runtimes. ADR-0020 records the accepted synchronous fallback.
    operation()
  }
}

#if canImport(Dispatch)
  private final class DispatchFrameTailLayoutWorker: Sendable {
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
#endif
