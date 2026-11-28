// A synchronous view evaluation cannot move between threads. Mark its calling
// thread so nonisolated Sendable values can attribute reads during evaluation
// without assuming that every reader runs on MainActor. Task locals alone are
// insufficient: a concurrent child task can inherit them.
#if os(Windows)
  import WinSDK
#elseif canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#elseif canImport(WASILibc)
  import wasi_pthread
#endif

enum ViewEvaluationThreadScope {
  #if os(Windows)
    private static let key: DWORD = {
      let key = TlsAlloc()
      precondition(key != TLS_OUT_OF_INDEXES)
      return key
    }()
  #else
    private static let key: pthread_key_t = {
      var key = pthread_key_t()
      let result = unsafe pthread_key_create(&key, nil)
      precondition(result == 0)
      return key
    }()
  #endif

  static var isActive: Bool {
    #if os(Windows)
      unsafe TlsGetValue(key) != nil
    #else
      unsafe pthread_getspecific(key) != nil
    #endif
  }

  static func setActive(_ active: Bool) {
    // The thread-local value is a presence bit; no pointer is dereferenced.
    let value = unsafe active ? UnsafeMutableRawPointer(bitPattern: 1) : nil
    #if os(Windows)
      let result = unsafe TlsSetValue(key, value)
      precondition(result)
    #else
      let result = unsafe pthread_setspecific(key, value)
      precondition(result == 0)
    #endif
  }
}
