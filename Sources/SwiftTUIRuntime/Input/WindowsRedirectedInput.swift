#if canImport(ucrt)
  import WinSDK

  /// Reads redirected UTF-8 bytes without CRT text-mode translation. The
  /// reader is the sole consumer of this handle; peeking before a pipe read
  /// keeps an idle pipe cancellable without a blocking ReadFile call.
  func readWindowsRedirectedInputChunk(
    from fileDescriptor: Int32,
    maxBytes: Int
  ) -> TerminalInputReadResult {
    guard let handle = unsafe win32Handle(for: fileDescriptor) else {
      return .failure(errno: Int32(ERROR_INVALID_HANDLE))
    }
    let type = unsafe GetFileType(handle)
    var count = maxBytes
    if type == DWORD(FILE_TYPE_PIPE) {
      var available: DWORD = 0
      guard unsafe PeekNamedPipe(handle, nil, 0, nil, &available, nil) else {
        return windowsReadFailure(GetLastError())
      }
      guard available > 0 else { return .wouldBlock }
      count = min(count, Int(available))
    } else if type != DWORD(FILE_TYPE_DISK) {
      return .failure(errno: Int32(ERROR_INVALID_HANDLE))
    }
    var bytesRead: DWORD = 0
    var failure: DWORD = 0
    let bytes = unsafe [UInt8](unsafeUninitializedCapacity: count) { buffer, initialized in
      let ok = unsafe ReadFile(handle, buffer.baseAddress, DWORD(count), &bytesRead, nil)
      if !ok { failure = GetLastError() }
      initialized = Int(bytesRead)
    }
    if !bytes.isEmpty { return .bytes(bytes) }
    if failure != 0 { return windowsReadFailure(failure) }
    return .endOfFile
  }

  private func windowsReadFailure(_ error: DWORD) -> TerminalInputReadResult {
    if error == DWORD(ERROR_BROKEN_PIPE) || error == DWORD(ERROR_HANDLE_EOF) {
      return .endOfFile
    }
    return .failure(errno: Int32(bitPattern: error))
  }
#endif
