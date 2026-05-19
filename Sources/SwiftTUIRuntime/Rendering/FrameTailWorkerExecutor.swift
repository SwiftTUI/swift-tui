#if canImport(Dispatch)
  @unsafe @preconcurrency import Dispatch
#endif

final class FrameTailWorkerExecutor: Sendable {
  private let layoutWorker = FrameTailLayoutWorkerBox()

  #if canImport(Dispatch)
    private let queue = DispatchQueue(label: "swift-tui.frame-tail-renderer")
  #endif

  func sync<Value>(
    _ operation: () -> Value
  ) -> Value {
    #if canImport(Dispatch)
      queue.sync {
        operation()
      }
    #else
      operation()
    #endif
  }

  func timedSync<Value>(
    clock: ContinuousClock?,
    _ operation: () -> Value
  ) -> FrameTailWorkerResult<Value> {
    guard let clock else {
      return .init(
        value: sync(operation),
        enqueueToStart: .zero,
        compute: .zero,
        completedAt: nil
      )
    }

    let enqueuedAt = clock.now
    return sync {
      let startedAt = clock.now
      let value = operation()
      let completedAt = clock.now
      return .init(
        value: value,
        enqueueToStart: enqueuedAt.duration(to: startedAt),
        compute: startedAt.duration(to: completedAt),
        completedAt: completedAt
      )
    }
  }

  func timedAsync<Value>(
    clock: ContinuousClock?,
    _ operation: @escaping @Sendable () -> Value
  ) async -> FrameTailWorkerResult<Value> {
    guard let clock else {
      return .init(
        value: await async(operation),
        enqueueToStart: .zero,
        compute: .zero,
        completedAt: nil
      )
    }

    let enqueuedAt = clock.now
    return await async {
      let startedAt = clock.now
      let value = operation()
      let completedAt = clock.now
      return .init(
        value: value,
        enqueueToStart: enqueuedAt.duration(to: startedAt),
        compute: startedAt.duration(to: completedAt),
        completedAt: completedAt
      )
    }
  }

  func timedLayoutAsync<Value>(
    clock: ContinuousClock?,
    cancellationToken: FrameTailJobCancellationToken?,
    _ operation: @escaping @Sendable () -> Value
  ) async -> FrameTailWorkerResult<Value?> {
    guard let clock else {
      return .init(
        value: await layoutWorker.async {
          guard cancellationToken?.markStarted() ?? true else {
            return nil
          }
          return operation()
        },
        enqueueToStart: .zero,
        compute: .zero,
        completedAt: nil
      )
    }

    let enqueuedAt = clock.now
    return await layoutWorker.async {
      let startedAt = clock.now
      guard cancellationToken?.markStarted() ?? true else {
        return .init(
          value: nil,
          enqueueToStart: enqueuedAt.duration(to: startedAt),
          compute: .zero,
          completedAt: startedAt
        )
      }
      let value = operation()
      let completedAt = clock.now
      return .init(
        value: Optional(value),
        enqueueToStart: enqueuedAt.duration(to: startedAt),
        compute: startedAt.duration(to: completedAt),
        completedAt: completedAt
      )
    }
  }

  func runLayoutWorkerJob(
    _ operation: @escaping @Sendable () -> Void
  ) async {
    _ = await layoutWorker.async(operation)
  }

  private func async<Value>(
    _ operation: @escaping @Sendable () -> Value
  ) async -> Value {
    #if canImport(Dispatch)
      await withCheckedContinuation { continuation in
        queue.async {
          continuation.resume(returning: operation())
        }
      }
    #else
      operation()
    #endif
  }
}
