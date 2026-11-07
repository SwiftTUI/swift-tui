#if !canImport(WASILibc) && !canImport(ucrt)
  @unsafe @preconcurrency package import Dispatch
  import Synchronization
  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #elseif canImport(Android)
    import Android
  #elseif canImport(Musl)
    import Musl
  #endif

  /// Poll-backed readiness for toolchains whose libdispatch epoll HUP teardown
  /// races its manager thread (swift-corelibs-libdispatch #949). The dispatch
  /// source carries only user data; it never registers the watched descriptor.
  /// At most one event is queued. Cancellation retires the poller before the
  /// cancel handler may close or recycle the descriptor.
  package final class POSIXReadinessSource: Sendable {
    private struct State {
      var started = false
      var cancelled = false
      var suspensionDepth = 1
    }
    private let state = Mutex(State())
    private let source: Mutex<any DispatchSourceUserDataAdd>
    private let acknowledgement = DispatchSemaphore(value: 0)
    private let lifecycleChange = DispatchSemaphore(value: 0)
    private let descriptor: Int32
    private let events: Int16

    package init(fileDescriptor: Int32, writable: Bool = false, queue: DispatchQueue) {
      descriptor = fileDescriptor
      events = Int16(writable ? POLLOUT : POLLIN)
      source = Mutex(DispatchSource.makeUserDataAddSource(queue: queue))
    }

    package func setEventHandler(handler: @escaping () -> Void) {
      source.withLock { source in
        source.setEventHandler { [acknowledgement] in
          handler()
          acknowledgement.signal()
        }
      }
    }

    package func setCancelHandler(handler: @escaping () -> Void) {
      source.withLock { $0.setCancelHandler(handler: handler) }
    }

    package func resume() {
      let start = state.withLock { state in
        precondition(state.suspensionDepth > 0)
        state.suspensionDepth -= 1
        if state.started { return false }
        state.started = true
        return true
      }
      source.withLock { $0.resume() }
      lifecycleChange.signal()
      if start { startPolling() }
    }

    package func suspend() {
      state.withLock { $0.suspensionDepth += 1 }
      source.withLock { $0.suspend() }
    }

    package func cancel() {
      state.withLock { $0.cancelled = true }
      lifecycleChange.signal()
    }

    private func startPolling() {
      // Keep the syscall facade Foundation-free. The detached thread owns this
      // retain until run() retires; cancel acknowledgement follows retirement.
      let context = unsafe Unmanaged.passRetained(self).toOpaque()
      #if canImport(Darwin)
        var thread: pthread_t?
      #else
        var thread = pthread_t()
      #endif
      let result = unsafe pthread_create(
        &thread, nil,
        { context in
          #if canImport(Darwin)
            let owner = unsafe Unmanaged<POSIXReadinessSource>.fromOpaque(context)
              .takeRetainedValue()
          #else
            let owner = unsafe Unmanaged<POSIXReadinessSource>.fromOpaque(context!)
              .takeRetainedValue()
          #endif
          owner.run()
          return nil
        }, context)
      if result != 0 {
        unsafe Unmanaged<POSIXReadinessSource>.fromOpaque(context).release()
        preconditionFailure("could not create descriptor readiness thread: \(result)")
      }
      #if canImport(Darwin)
        unsafe pthread_detach(thread!)
      #else
        pthread_detach(thread)
      #endif
    }

    private func run() {
      while !state.withLock({ $0.cancelled }) {
        if state.withLock({ $0.suspensionDepth > 0 }) {
          lifecycleChange.wait()
          continue
        }
        var readiness = pollfd(fd: descriptor, events: events, revents: 0)
        let result = unsafe poll(&readiness, 1, 20)
        if result == 0 || (result < 0 && errno == EINTR) { continue }
        if state.withLock({ $0.cancelled }) { break }
        // POLLHUP/POLLERR/POLLNVAL all wake the owner, which performs the
        // actual read/write and applies its existing EOF/error policy.
        source.withLock { $0.add(data: 1) }
        while acknowledgement.wait(timeout: .now() + .milliseconds(20)) != .success {
          if state.withLock({ $0.cancelled }) { break }
        }
      }
      source.withLock { $0.cancel() }
    }
  }
#endif
