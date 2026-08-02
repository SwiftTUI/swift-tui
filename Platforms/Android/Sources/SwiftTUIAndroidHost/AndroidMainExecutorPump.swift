#if os(Android)
  @_spi(ExperimentalCustomExecutors) import _Concurrency
  import Android  // Bionic: pthread_self / pthread_equal
  import Synchronization

  /// A **host-driven Swift main-actor executor** for the Android embedding.
  ///
  /// ## Why this exists
  ///
  /// On Darwin, the OS run loop (`CFRunLoop`) continuously drains the main-actor executor.
  /// Thus, each `@MainActor` continuation can run.
  /// These continuations include the SwiftTUI run loop's own `await`.
  /// They also include autonomous `.task` bodies after `Task.sleep` and animation deadline wakes.
  /// A bare JNI embedding has no such driver.
  /// The Android `Looper` drains the *Java* main queue, not Swift's main-actor job queue.
  /// Swift 6.2 represents the main executor as a `RunLoopExecutor`.
  /// The program must explicitly drive this executor.
  /// The stock Android main executor is a `DispatchMainExecutor`.
  /// Its jobs wait on the main queue of libdispatch, which nothing pumps here.
  /// A call to `run()` blocks the JNI thread forever, and `runUntil` traps.
  /// As a result, all time-driven work freezes.
  /// Input still works through the synchronous `directWake` bypass of the run loop.
  ///
  /// ## What this does
  ///
  /// During the first JNI setup, `installIfNeeded()` runs before all main-actor work.
  /// It replaces the process main executor with ``HostMainExecutor`` through `_createExecutors(factory:)`.
  /// It keeps the stock Dispatch *global* executor as the default task executor.
  /// Main-actor jobs then enter ``HostMainExecutor`` instead of the undrained main queue of libdispatch.
  /// The Kotlin host calls ``drainReadyJobs()`` once per frame poll (~30 Hz) on the Android main thread.
  /// The drain runs the queued jobs and returns.
  /// Thus, the drain is bounded and non-blocking, and it does not own the thread.
  ///
  /// The default executor remains the self-driving global pool of Dispatch.
  /// Thus, `Task.sleep` timers still fire on worker threads of libdispatch.
  /// Only the *hop back to `@MainActor`* was stranded.
  /// The host drain resumes this hop.
  public enum AndroidMainExecutorPump {
    private static let installState = Mutex(InstallState())

    private struct InstallState {
      var attempted = false
      var succeeded = false
    }

    /// Installs ``HostMainExecutor`` as the process main-actor executor.
    ///
    /// Call this method **before all main-actor work**.
    /// This work includes the first `Task { @MainActor … }` and `MainActor.assumeIsolated`.
    /// It also includes the first read of `MainActor.executor`.
    /// Installation after the platform default materializes causes a fatal error.
    /// The Android host calls this method first in `swift_tui_android_create_host`.
    /// Repeated calls are safe.
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
    ///
    /// - Bit 0: Executor installed.
    /// - Bits 1..21: Jobs enqueued.
    /// - Bits 22..42: Jobs drained.
    /// - Bits 43..52: Jobs pending now.
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

  /// The custom `ExecutorFactory` installed on Android.
  /// The main executor is the host-driven ``HostMainExecutor``.
  /// The default (global) task executor is the stock platform executor (the global pool of libdispatch).
  /// Thus, `Task.sleep` and other off-main work continue on background worker threads.
  private struct AndroidHostExecutorFactory: ExecutorFactory {
    static var mainExecutor: any MainExecutor { HostMainExecutor.shared }
    static var defaultExecutor: any TaskExecutor { PlatformExecutorFactory.defaultExecutor }
  }

  /// A minimal main-actor executor whose job queue is drained by the Android
  /// host on its render tick instead of by an OS run loop.
  ///
  /// All main-actor jobs must run on the one OS thread that the host treats as "main".
  /// This thread is the thread on which `installIfNeeded()` ran.
  /// Code can call `enqueue` from another thread.
  /// For example, a `.task` on a worker thread of libdispatch can return to the main actor.
  /// Thus, a mutex protects the queue.
  /// Only ``drainReadyJobs()`` runs the jobs, on the host main thread.
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
