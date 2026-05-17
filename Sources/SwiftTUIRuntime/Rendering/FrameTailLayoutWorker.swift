import Synchronization

#if canImport(Darwin)
  import Darwin
#endif

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

#if canImport(Darwin) && canImport(Dispatch)
  private final class FrameTailLayoutWorkerState: Sendable {
    struct Job: Sendable {
      var operation: @Sendable () -> Void
    }

    private enum NextJob {
      case job(Job)
      case idle
      case stop
    }

    private struct State: Sendable {
      var jobs: [Job] = []
      var isStopping = false
    }

    private let state = Mutex(State())
    private let semaphore = DispatchSemaphore(value: 0)

    func enqueue(_ job: Job) {
      state.withLock { state in
        state.jobs.append(job)
      }
      semaphore.signal()
    }

    func stop() {
      state.withLock { state in
        state.isStopping = true
      }
      semaphore.signal()
    }

    func runLoop() {
      unsafe pthread_setname_np("swift-tui.frame-tail-layout")

      while true {
        semaphore.wait()

        drainJobs: while true {
          switch nextJob() {
          case .job(let job):
            job.operation()
          case .idle:
            break drainJobs
          case .stop:
            return
          }
        }
      }
    }

    private func nextJob() -> NextJob {
      state.withLock { state in
        if !state.jobs.isEmpty {
          return .job(state.jobs.removeFirst())
        }
        if state.isStopping {
          return .stop
        }
        return .idle
      }
    }
  }

  private final class FrameTailLayoutWorker: Sendable {
    private static let stackSize = 8 * 1024 * 1024

    private let state: FrameTailLayoutWorkerState
    private let thread: UInt?
    private let fallbackQueue = DispatchQueue(label: "swift-tui.frame-tail-layout-fallback")

    init() {
      let state = FrameTailLayoutWorkerState()
      self.state = state
      thread = Self.startThread(state: state)
    }

    deinit {
      stopThread()
    }

    func async<Value>(
      _ operation: @escaping @Sendable () -> Value
    ) async -> Value {
      await withCheckedContinuation { continuation in
        enqueue(
          FrameTailLayoutWorkerState.Job {
            continuation.resume(returning: operation())
          }
        )
      }
    }

    private static func startThread(
      state: FrameTailLayoutWorkerState
    ) -> UInt? {
      var attributes = pthread_attr_t()
      guard unsafe pthread_attr_init(&attributes) == 0 else {
        return nil
      }
      defer {
        unsafe pthread_attr_destroy(&attributes)
      }

      _ = unsafe pthread_attr_setstacksize(&attributes, Self.stackSize)

      var createdThread: pthread_t?
      let retainedState = unsafe Unmanaged.passRetained(state)
      let result = unsafe pthread_create(
        &createdThread,
        &attributes,
        { pointer in
          let state = unsafe Unmanaged<FrameTailLayoutWorkerState>
            .fromOpaque(pointer)
            .takeRetainedValue()
          state.runLoop()
          return nil
        },
        unsafe retainedState.toOpaque()
      )

      guard result == 0 else {
        unsafe retainedState.release()
        return nil
      }
      guard unsafe createdThread != nil else {
        unsafe retainedState.release()
        return nil
      }
      return UInt(bitPattern: unsafe createdThread!)
    }

    private func stopThread() {
      guard
        let thread,
        let currentThread = unsafe pthread_t(bitPattern: thread)
      else {
        return
      }
      guard unsafe pthread_equal(pthread_self(), currentThread) == 0 else {
        return
      }

      state.stop()
      unsafe pthread_join(currentThread, nil)
    }

    private func enqueue(_ job: FrameTailLayoutWorkerState.Job) {
      guard thread != nil else {
        fallbackQueue.async {
          job.operation()
        }
        return
      }

      state.enqueue(job)
    }
  }
#elseif canImport(Dispatch)
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
