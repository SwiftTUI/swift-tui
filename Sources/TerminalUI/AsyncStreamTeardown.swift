package func makeManagedAsyncStream<Element: Sendable>(
  bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded,
  _ setUp:
    @escaping (
      AsyncStream<Element>.Continuation
    ) -> @Sendable (AsyncStream<Element>.Continuation.Termination) -> Void
) -> AsyncStream<Element> {
  AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
    continuation.onTermination = setUp(continuation)
  }
}

package func makeTaskBackedAsyncStream<Element: Sendable>(
  bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded,
  launch:
    @escaping @Sendable (
      @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> = { operation in
      Task {
        await operation()
      }
    },
  _ produce: @escaping @Sendable (AsyncStream<Element>.Continuation) async -> Void
) -> AsyncStream<Element> {
  makeManagedAsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
    let task = launch {
      await produce(continuation)
    }
    return { _ in
      task.cancel()
    }
  }
}
