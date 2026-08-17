// The Windows arm of the SwiftTUIPlatformIO syscall facade. It mirrors only
// the path/fd file-I/O subset of PlatformPOSIX.swift: the socket and
// directory-enumeration functions have no consumer outside the POSIX-only
// attach subsystem, so they deliberately have no Windows spelling yet
// (Stage 6 of the Windows plan owns the AF_UNIX-vs-named-pipe decision).
#if canImport(ucrt)
  import CRT

  package func sceneConfigureNoSigPipe(
    _ fileDescriptor: Int32
  ) {
    // SIGPIPE does not exist on Windows; writes to a closed peer fail with
    // an error return instead of a signal.
  }

  package func sceneOpen(
    _ path: String,
    _ flags: Int32
  ) -> Int32 {
    // `open`/`_open` are variadic in ucrt and un-importable; `_sopen_s` is
    // the non-variadic form. `_O_BINARY` keeps the byte stream faithful —
    // the CRT's default text mode rewrites "\n" as "\r\n".
    var descriptor: CInt = -1
    let openError = unsafe path.withCString { cPath in
      unsafe _sopen_s(&descriptor, cPath, flags | _O_BINARY, _SH_DENYNO, _S_IREAD | _S_IWRITE)
    }
    return openError == 0 ? descriptor : -1
  }

  package func sceneClose(
    _ fileDescriptor: Int32
  ) {
    _ = _close(fileDescriptor)
  }

  package func sceneRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    Int(unsafe _read(fileDescriptor, buffer, UInt32(count)))
  }

  package func sceneWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    Int(unsafe _write(fileDescriptor, buffer, UInt32(count)))
  }

  package func sceneUnlink(
    _ path: String
  ) -> Int32 {
    unsafe path.withCString { cPath in
      unsafe _unlink(cPath)
    }
  }

  package func sceneAccess(
    _ path: String,
    _ mode: Int32
  ) -> Int32 {
    unsafe path.withCString { cPath in
      unsafe _access(cPath, mode)
    }
  }
#endif
