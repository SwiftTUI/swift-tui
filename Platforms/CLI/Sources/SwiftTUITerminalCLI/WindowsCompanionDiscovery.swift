#if os(Windows)
  import Foundation
  import WinSDK

  struct WindowsCompanionNotRunningError: Error, CustomStringConvertible {
    var description: String {
      "No running browser companion was found. Launch the app in a terminal, or omit --companion off."
    }
  }

  /// Same-user discovery for a live companion. A protected registry DACL is
  /// installed when the volatile per-instance key is created, before its token
  /// is written. Process creation time prevents stale records matching PID reuse.
  @MainActor
  final class WindowsCompanionRegistration {
    private static let root = "Software\\SwiftTUI\\Companions"
    private let path: String
    private var removed = false

    private struct Record: Codable {
      var app: String
      var url: String
      var pid: UInt32
      var created: UInt64
    }

    init(app: String, url: String) throws {
      guard Self.isCompanionURL(url),
        let created = Self.creationTime(processID: GetCurrentProcessId())
      else {
        throw DiscoveryError(code: 87)
      }
      path = Self.root + "\\" + UUID().uuidString
      let sid = try Self.currentUserSID()
      let descriptorText = Array("O:\(sid)D:P(A;;GA;;;\(sid))".utf16) + [0]
      var descriptor: PSECURITY_DESCRIPTOR?
      let converted = descriptorText.withUnsafeBufferPointer { buffer in
        unsafe ConvertStringSecurityDescriptorToSecurityDescriptorW(
          buffer.baseAddress, 1, &descriptor, nil)
      }
      guard converted else { throw DiscoveryError(code: GetLastError()) }
      defer { _ = unsafe LocalFree(descriptor) }
      var attributes = unsafe SECURITY_ATTRIBUTES(
        nLength: DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size),
        lpSecurityDescriptor: descriptor, bInheritHandle: false)
      var key: HKEY?
      var disposition: DWORD = 0
      let status = unsafe Self.wide(path) { name in
        unsafe RegCreateKeyExW(
          HKEY_CURRENT_USER, name, 0, nil, DWORD(REG_OPTION_VOLATILE),
          REGSAM(KEY_SET_VALUE), &attributes, &key, &disposition)
      }
      guard status == 0, let key = unsafe key else {
        throw DiscoveryError(code: UInt32(bitPattern: status))
      }
      defer { _ = unsafe RegCloseKey(key) }
      guard disposition == REG_CREATED_NEW_KEY else { throw DiscoveryError(code: 183) }
      do {
        let record = Record(app: app, url: url, pid: GetCurrentProcessId(), created: created)
        let data = try JSONEncoder().encode(record)
        let result = unsafe data.withUnsafeBytes { bytes in
          unsafe RegSetValueExW(
            key, nil, 0, DWORD(REG_BINARY),
            bytes.baseAddress?.assumingMemoryBound(to: BYTE.self), DWORD(bytes.count))
        }
        guard result == 0 else { throw DiscoveryError(code: UInt32(bitPattern: result)) }
      } catch {
        remove()
        throw error
      }
    }

    func remove() {
      guard !removed else { return }
      removed = true
      _ = unsafe Self.wide(path) { unsafe RegDeleteTreeW(HKEY_CURRENT_USER, $0) }
    }

    static func urls(app: String) throws -> [String] {
      var parent: HKEY?
      let status = unsafe wide(root) {
        unsafe RegOpenKeyExW(HKEY_CURRENT_USER, $0, 0, REGSAM(KEY_ENUMERATE_SUB_KEYS), &parent)
      }
      if status == 2 { return [] }
      guard status == 0, let parent = unsafe parent else {
        throw DiscoveryError(code: UInt32(bitPattern: status))
      }
      defer { _ = unsafe RegCloseKey(parent) }
      var index: DWORD = 0
      var results: [String] = []
      while true {
        var name = [WCHAR](repeating: 0, count: 256)
        var count = DWORD(name.count)
        let enumerated = name.withUnsafeMutableBufferPointer { buffer in
          unsafe RegEnumKeyExW(parent, index, buffer.baseAddress, &count, nil, nil, nil, nil)
        }
        if enumerated == 259 { break }
        guard enumerated == 0 else { throw DiscoveryError(code: UInt32(bitPattern: enumerated)) }
        index += 1
        let child = String(decoding: name.prefix(Int(count)), as: UTF16.self)
        var key: HKEY?
        let opened = unsafe wide(child) {
          unsafe RegOpenKeyExW(parent, $0, 0, REGSAM(KEY_QUERY_VALUE), &key)
        }
        guard opened == 0, let key = unsafe key else { continue }
        let record = unsafe readRecord(key)
        _ = unsafe RegCloseKey(key)
        guard let record, record.app == app, isCompanionURL(record.url),
          creationTime(processID: record.pid) == record.created
        else { continue }
        results.append(record.url)
      }
      return results.sorted()
    }

    private static func readRecord(_ key: HKEY) -> Record? {
      var type: DWORD = 0
      var size: DWORD = 0
      guard unsafe RegQueryValueExW(key, nil, nil, &type, nil, &size) == 0,
        type == REG_BINARY, size > 0, size <= 16_384
      else { return nil }
      var data = Data(count: Int(size))
      let result = unsafe data.withUnsafeMutableBytes { bytes in
        unsafe RegQueryValueExW(
          key, nil, nil, &type,
          bytes.baseAddress?.assumingMemoryBound(to: BYTE.self), &size)
      }
      guard result == 0, type == REG_BINARY else { return nil }
      return try? JSONDecoder().decode(Record.self, from: data.prefix(Int(size)))
    }

    private static func isCompanionURL(_ string: String) -> Bool {
      guard let url = URLComponents(string: string), url.scheme == "http",
        url.host == "127.0.0.1", let port = url.port, (1...65535).contains(port),
        url.user == nil, url.password == nil,
        url.queryItems?.contains(where: { $0.name == "token" && !($0.value?.isEmpty ?? true) })
          == true
      else { return false }
      return true
    }

    private static func creationTime(processID: DWORD) -> UInt64? {
      guard
        let process = unsafe OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, processID)
      else { return nil }
      defer { _ = unsafe CloseHandle(process) }
      var created = FILETIME()
      var exited = FILETIME()
      var kernel = FILETIME()
      var user = FILETIME()
      guard unsafe GetProcessTimes(process, &created, &exited, &kernel, &user),
        exited.dwLowDateTime == 0, exited.dwHighDateTime == 0
      else { return nil }
      return UInt64(created.dwHighDateTime) << 32 | UInt64(created.dwLowDateTime)
    }

    private static func currentUserSID() throws -> String {
      var token: HANDLE?
      guard unsafe OpenProcessToken(GetCurrentProcess(), DWORD(TOKEN_QUERY), &token),
        let token = unsafe token
      else {
        throw DiscoveryError(code: GetLastError())
      }
      defer { _ = unsafe CloseHandle(token) }
      var size: DWORD = 0
      _ = unsafe GetTokenInformation(token, TokenUser, nil, 0, &size)
      guard size > 0 else { throw DiscoveryError(code: GetLastError()) }
      var data = Data(count: Int(size))
      return unsafe try data.withUnsafeMutableBytes { bytes in
        guard unsafe GetTokenInformation(token, TokenUser, bytes.baseAddress, size, &size) else {
          throw DiscoveryError(code: GetLastError())
        }
        let user = unsafe bytes.loadUnaligned(as: TOKEN_USER.self)
        var string: LPWSTR?
        guard unsafe ConvertSidToStringSidW(user.User.Sid, &string), let string = unsafe string
        else {
          throw DiscoveryError(code: GetLastError())
        }
        defer { _ = unsafe LocalFree(string) }
        return unsafe String(decodingCString: string, as: UTF16.self)
      }
    }

    private static func wide<T>(_ string: String, _ body: (UnsafePointer<WCHAR>) throws -> T)
      rethrows -> T
    {
      let characters = Array(string.utf16) + [0]
      return try characters.withUnsafeBufferPointer { buffer in unsafe try body(buffer.baseAddress!)
      }
    }

    private struct DiscoveryError: Error, CustomStringConvertible {
      let code: UInt32
      var description: String {
        "Private companion discovery failed (Windows error \(code)). Retry or use --companion off."
      }
    }
  }
#endif
