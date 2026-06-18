#if os(Android)
  @_spi(ExperimentalCustomExecutors) import _Concurrency
  import Android  // Bionic: pthread_self / pthread_equal
  import Synchronization

  /// A **host-driven Swift main-actor executor** for the Android embedding.
  ///
  /// ## Why this exists
  ///
  /// On Darwin the OS run loop (CFRunLoop) continuously drains the main-actor
  /// executor, so every `@MainActor` continuation keeps flowing: the SwiftTUI
  /// run loop's own `await`, autonomous `.task` bodies resuming after a
  /// `Task.sleep`, animation deadline wakes. In a bare JNI embedding there is no
  /// such driver — the Android `Looper` drains the *Java* main queue, not
  /// Swift's main-actor job queue. Swift 6.2 reified the main executor as a
  /// `RunLoopExecutor` the program must explicitly drive; the stock Android main
  /// executor is a `DispatchMainExecutor` whose jobs sit on libdispatch's main
  /// queue, which nothing pumps here (calling its `run()` would block the JNI
  /// thread forever and its `runUntil` traps). The result is that everything
  /// time-driven freezes, while input still works only because it is
  /// special-cased through the run loop's synchronous `directWake` bypass.
  ///
  /// ## What this does
  ///
  /// At the first JNI bring-up (`installIfNeeded()`, before any main-actor work)
  /// we replace the process main executor with ``HostMainExecutor`` via
  /// `_createExecutors(factory:)`, keeping the stock Dispatch *global* executor
  /// as the default task executor. Main-actor jobs then queue in
  /// ``HostMainExecutor`` instead of on libdispatch's undrained main queue. The
  /// Kotlin host calls ``drainReadyJobs()`` once per frame poll (~30 Hz) on the
  /// Android main thread, which runs the queued jobs and returns — a bounded,
  /// non-blocking drain rather than a thread-owning run loop.
  ///
  /// Crucially the default executor is left as Dispatch's self-driving global
  /// pool, so `Task.sleep` timers still fire on libdispatch worker threads; only
  /// the *hop back to `@MainActor`* was stranded, and that is exactly what the
  /// host drain resumes.
  public enum AndroidMainExecutorPump {
    private static let installState = Mutex(InstallState())

    private struct InstallState {
      var attempted = false
      var succeeded = false
    }

    /// Installs ``HostMainExecutor`` as the process main-actor executor.
    ///
    /// Must be called **before any main-actor work** (before the first
    /// `Task { @MainActor … }`, `MainActor.assumeIsolated`, or read of
    /// `MainActor.executor`) — installing a custom main executor after the
    /// platform default has materialized is a fatal error. The Android host
    /// calls this as the first line of `swift_tui_android_create_host`.
    /// Idempotent; safe to call more than once.
    public static func installIfNeeded() {
      let shouldInstall = installState.withLock { state -> Bool in
        guard !state.attempted else { return false }
        state.attempted = true
        return true
      }
      guard shouldInstall else { return }

      _createExecutors(factory: AndroidHostExecutorFactory.self)
      installState.withLock { $0.succeeded = true }
    }

    static var didInstall: Bool {
      installState.withLock { $0.succeeded }
    }

    /// Runs every main-actor job that is ready now, on the host main thread,
    /// then returns. Called from the Kotlin render poll loop each frame.
    /// Returns the number of jobs run (diagnostic).
    @discardableResult
    static func drainReadyJobs() -> Int32 {
      Int32(clamping: HostMainExecutor.shared.drainReadyJobs())
    }

    /// Packed diagnostic snapshot for the JNI bridge log (decoded in logcat):
    /// bit 0 = executor installed; bits 1..21 = jobs enqueued; bits 22..42 =
    /// jobs drained; bits 43..52 = jobs pending now.
    static func diagnostics() -> Int64 {
      let counters = HostMainExecutor.shared.counters()
      func sat(_ value: Int, _ bits: Int) -> Int64 {
        Int64(min(max(value, 0), (1 << bits) - 1))
      }
      var packed: Int64 = didInstall ? 1 : 0
      packed |= sat(counters.enqueued, 21) << 1
      packed |= sat(counters.drained, 21) << 22
      packed |= sat(counters.pending, 10) << 43
      return packed
    }
  }

  /// The custom `ExecutorFactory` installed on Android. The main executor is the
  /// host-driven ``HostMainExecutor``; the default (global) task executor is the
  /// stock platform one (libdispatch's global pool) so `Task.sleep` and other
  /// off-main work keep self-driving on background worker threads.
  private struct AndroidHostExecutorFactory: ExecutorFactory {
    static var mainExecutor: any MainExecutor { HostMainExecutor.shared }
    static var defaultExecutor: any TaskExecutor { PlatformExecutorFactory.defaultExecutor }
  }

  /// A minimal main-actor executor whose job queue is drained by the Android
  /// host on its render tick instead of by an OS run loop.
  ///
  /// All main-actor jobs must run on the one OS thread the host treats as
  /// "main" (the thread `installIfNeeded()` ran on). `enqueue` may be called
  /// cross-thread (a `.task` finishing on a libdispatch worker hops back to the
  /// main actor), so the queue is mutex-guarded; jobs are only ever *run* from
  /// ``drainReadyJobs()`` on the host main thread.
  final class HostMainExecutor: MainExecutor {
    static let shared = HostMainExecutor()

    struct Counters {
      var enqueued = 0
      var drained = 0
      var pending = 0
    }

    private struct State {
      var queue: [UnownedJob] = []
      var enqueued = 0
      var drained = 0
      let mainThread: pthread_t
    }

    private let state: Mutex<State>

    init() {
      state = Mutex(State(mainThread: pthread_self()))
    }

    // MARK: Executor / SerialExecutor

    func enqueue(_ job: consuming ExecutorJob) {
      let unowned = UnownedJob(job)
      state.withLock { state in
        state.queue.append(unowned)
        state.enqueued += 1
      }
    }

    func checkIsolated() {
      precondition(
        isOnHostMainThread(),
        "SwiftTUI Android main-actor work ran off the host main thread"
      )
    }

    func isIsolatingCurrentContext() -> Bool? {
      isOnHostMainThread()
    }

    var isMainExecutor: Bool { true }

    // MARK: RunLoopExecutor

    func run() throws {
      // The Android host owns its thread and drives this executor via
      // `drainReadyJobs()`; a thread-owning run loop would freeze the JNI
      // thread. Only reachable through the async-main drain path, which the
      // embedding never uses.
      preconditionFailure(
        "HostMainExecutor.run() must not be called; the Android host drives the "
          + "main executor via drainReadyJobs()."
      )
    }

    func runUntil(_ condition: () -> Bool) throws {
      // Defensive non-blocking variant (never used by the host, which calls
      // `drainReadyJobs()` directly): drain ready work and re-check, but never
      // park the UI thread waiting for a not-yet-due timer.
      while !condition() {
        let ran = drainReadyJobs()
        if ran == 0 { break }
      }
    }

    func stop() {}

    // MARK: Host drain

    /// Runs every job ready as of entry, on the host main thread, then returns.
    /// Jobs enqueued *during* the drain run on the next tick, bounding a tick to
    /// the currently-ready backlog. Returns the number of jobs run.
    @discardableResult
    func drainReadyJobs() -> Int {
      let serial = unsafe asUnownedSerialExecutor()
      let batch = state.withLock { state -> [UnownedJob] in
        defer { state.queue.removeAll(keepingCapacity: true) }
        return state.queue
      }
      for job in batch {
        unsafe job.runSynchronously(on: serial)
      }
      if !batch.isEmpty {
        state.withLock { $0.drained += batch.count }
      }
      return batch.count
    }

    func counters() -> Counters {
      state.withLock { state in
        Counters(
          enqueued: state.enqueued,
          drained: state.drained,
          pending: state.queue.count
        )
      }
    }

    private func isOnHostMainThread() -> Bool {
      let mainThread = state.withLock { $0.mainThread }
      return pthread_equal(pthread_self(), mainThread) != 0
    }
  }
#endif
