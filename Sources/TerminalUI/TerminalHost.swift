import Core
import Synchronization

#if canImport(Dispatch)
  @unsafe @preconcurrency import Dispatch
#endif

#if canImport(Darwin)
  package import Darwin
#elseif canImport(Glibc)
  package import Glibc
#elseif canImport(Android)
  package import Android
#elseif canImport(WASILibc)
  import WASILibc
#endif

#if canImport(Darwin)
  private func platformWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Darwin.write(fileDescriptor, buffer, count)
  }

  private func platformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Darwin.read(fileDescriptor, buffer, count)
  }

  private func platformPoll(
    _ descriptors: UnsafeMutablePointer<pollfd>?,
    _ count: nfds_t,
    _ timeoutMilliseconds: Int32
  ) -> Int32 {
    unsafe Darwin.poll(descriptors, count, timeoutMilliseconds)
  }
#elseif canImport(Glibc)
  private func platformWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Glibc.write(fileDescriptor, buffer, count)
  }

  private func platformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Glibc.read(fileDescriptor, buffer, count)
  }

  private func platformPoll(
    _ descriptors: UnsafeMutablePointer<pollfd>?,
    _ count: nfds_t,
    _ timeoutMilliseconds: Int32
  ) -> Int32 {
    unsafe Glibc.poll(descriptors, count, timeoutMilliseconds)
  }
#elseif canImport(Android)
  private func platformWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Android.write(fileDescriptor, buffer, count)
  }

  private func platformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Android.read(fileDescriptor, buffer, count)
  }

  private func platformPoll(
    _ descriptors: UnsafeMutablePointer<pollfd>?,
    _ count: nfds_t,
    _ timeoutMilliseconds: Int32
  ) -> Int32 {
    unsafe Android.poll(descriptors, count, timeoutMilliseconds)
  }
#elseif canImport(WASILibc)
  private func platformWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    Int(unsafe WASILibc.write(fileDescriptor, buffer, count))
  }
#endif

#if !canImport(WASILibc)
  package struct TerminalProcessExitResetAction: Sendable {
    package let inputFileDescriptor: Int32
    package let outputFileDescriptor: Int32
    package let inputFileStatusFlags: Int32
    package let savedAttributes: termios
    package let resetBytes: [UInt8]

    package func perform() {
      if !resetBytes.isEmpty {
        unsafe resetBytes.withUnsafeBytes { bytes in
          guard let baseAddress = bytes.baseAddress else {
            return
          }

          var offset = 0
          while offset < bytes.count {
            let written = unsafe platformWrite(
              outputFileDescriptor,
              unsafe baseAddress.advanced(by: offset),
              bytes.count - offset
            )
            guard written > 0 else {
              break
            }
            offset += written
          }
        }
      }

      _ = fcntl(inputFileDescriptor, F_SETFL, inputFileStatusFlags)
      var attributes = savedAttributes
      _ = unsafe tcsetattr(inputFileDescriptor, TCSAFLUSH, &attributes)
    }
  }

  package enum TerminalProcessExitCleanupRegistry {
    private struct State {
      var didInstallHandler = false
      var nextToken: UInt64 = 0
      var actions: [(token: UInt64, action: TerminalProcessExitResetAction)] = []
    }

    private static let state = Mutex(State())

    package static func register(
      _ action: TerminalProcessExitResetAction
    ) -> UInt64? {
      state.withLock { state in
        if !state.didInstallHandler {
          guard atexit(runTerminalProcessExitCleanup) == 0 else {
            return nil
          }
          state.didInstallHandler = true
        }

        let token = state.nextToken
        state.nextToken += 1
        state.actions.append((token: token, action: action))
        return token
      }
    }

    package static func unregister(
      _ token: UInt64?
    ) {
      guard let token else {
        return
      }

      state.withLock { state in
        state.actions.removeAll { $0.token == token }
      }
    }

    package static func runForTesting() {
      let actions = state.withLock { state in
        let actions = state.actions
          .sorted { lhs, rhs in lhs.token > rhs.token }
          .map(\.action)
        state.actions.removeAll()
        return actions
      }

      for action in actions {
        action.perform()
      }
    }
  }

  private func runTerminalProcessExitCleanup() {
    TerminalProcessExitCleanupRegistry.runForTesting()
  }
#endif

/// Errors thrown while configuring or writing to a terminal-backed host.
public enum TerminalHostError: Error {
  case notATTY(fileDescriptor: Int32)
  case failedToReadAttributes(errno: Int32)
  case failedToSetAttributes(errno: Int32)
  case failedToReadWindowSize(errno: Int32)
  case failedToReadFileStatusFlags(errno: Int32)
  case failedToSetFileStatusFlags(errno: Int32)
  case failedToWrite(errno: Int32)
}

/// Metrics describing how a frame was presented to the terminal.
public struct TerminalPresentationMetrics: Equatable, Sendable {
  /// The presentation strategy used for a frame commit.
  public enum Strategy: String, Equatable, Sendable {
    case fullRepaint
    case incremental
  }

  public enum GraphicsReplayScope: String, Equatable, Sendable {
    case none
    case targeted
    case full
  }

  public enum EditOperationLowering: String, Equatable, Sendable {
    case none
    case eraseToEndOfLine
  }

  public var bytesWritten: Int
  public var linesTouched: Int
  public var cellsChanged: Int
  public var strategy: Strategy
  public var usedSynchronizedOutput: Bool
  public var graphicsReplayScope: GraphicsReplayScope
  public var graphicsAttachmentsReplayed: Int
  public var editOperationLowering: EditOperationLowering
  public var editOperationCount: Int

  public init(
    bytesWritten: Int = 0,
    linesTouched: Int = 0,
    cellsChanged: Int = 0,
    strategy: Strategy = .fullRepaint,
    usedSynchronizedOutput: Bool = false,
    graphicsReplayScope: GraphicsReplayScope = .none,
    graphicsAttachmentsReplayed: Int = 0,
    editOperationLowering: EditOperationLowering = .none,
    editOperationCount: Int = 0
  ) {
    self.bytesWritten = max(0, bytesWritten)
    self.linesTouched = max(0, linesTouched)
    self.cellsChanged = max(0, cellsChanged)
    self.strategy = strategy
    self.usedSynchronizedOutput = usedSynchronizedOutput
    self.graphicsReplayScope = graphicsReplayScope
    self.graphicsAttachmentsReplayed = max(0, graphicsAttachmentsReplayed)
    self.editOperationLowering = editOperationLowering
    self.editOperationCount = max(0, editOperationCount)
  }

  public var usedFullRepaint: Bool {
    strategy == .fullRepaint
  }

  static func fullRepaint(
    for surface: RasterSurface,
    capabilityProfile: TerminalCapabilityProfile,
    origin: Point = .zero
  ) -> Self {
    let cellCount = max(0, surface.size.width) * max(0, surface.size.height)
    let writeSteps = fullRepaintWriteSteps(
      for: surface,
      capabilityProfile: capabilityProfile
    )
    var bytesWritten = fullRepaintBytesWritten(
      writeSteps: writeSteps,
      origin: origin
    )
    if capabilityProfile.supportsSynchronizedOutput, bytesWritten > 0 {
      bytesWritten += "\u{001B}[?2026h".utf8.count
      bytesWritten += "\u{001B}[?2026l".utf8.count
    }

    return Self(
      bytesWritten: bytesWritten,
      linesTouched: max(0, surface.size.height),
      cellsChanged: cellCount,
      strategy: .fullRepaint,
      usedSynchronizedOutput: capabilityProfile.supportsSynchronizedOutput,
      graphicsReplayScope: surface.imageAttachments.isEmpty ? .none : .full,
      graphicsAttachmentsReplayed: surface.imageAttachments.count
    )
  }
}

/// Abstraction over a terminal device used by `RunLoop`.
public protocol TerminalHosting: AnyObject {
  var surfaceSize: Size { get }
  var capabilityProfile: TerminalCapabilityProfile { get }
  var appearance: TerminalAppearance { get }
  var theme: Theme? { get }
  var graphicsCapabilities: TerminalGraphicsCapabilities { get }

  func enableRawMode() throws
  func disableRawMode() throws
  func write(_ output: String) throws
  func clearScreen() throws
  func moveCursor(to point: Point) throws
  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics
}

package protocol DamageAwareTerminalHosting: TerminalHosting {
  @discardableResult
  func present(
    _ surface: RasterSurface,
    damage: PresentationDamage?
  ) throws -> TerminalPresentationMetrics
}

extension TerminalHosting {
  public var theme: Theme? {
    nil
  }

  public var graphicsCapabilities: TerminalGraphicsCapabilities {
    .none
  }

  @discardableResult
  public func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let origin = Point.zero
    let writeSteps = fullRepaintWriteSteps(
      for: surface,
      capabilityProfile: capabilityProfile
    )
    let metrics = TerminalPresentationMetrics(
      bytesWritten: fullRepaintBytesWritten(
        writeSteps: writeSteps,
        origin: origin
      ),
      linesTouched: max(0, surface.size.height),
      cellsChanged: max(0, surface.size.width) * max(0, surface.size.height),
      strategy: .fullRepaint
    )

    try clearScreen()
    try moveCursor(to: origin)

    for writeStep in writeSteps {
      try write(writeStep)
    }
    return metrics
  }
}

#if !canImport(WASILibc)
  package protocol TerminalControlling: Sendable {
    func isATTY(_ fileDescriptor: Int32) -> Bool
    func getAttributes(from fileDescriptor: Int32) throws -> termios
    func setAttributes(_ attributes: termios, on fileDescriptor: Int32) throws
    func windowSize(of fileDescriptor: Int32) throws -> Size
    func cellPixelSize(of fileDescriptor: Int32) throws -> Size?
    func getFileStatusFlags(of fileDescriptor: Int32) throws -> Int32
    func setFileStatusFlags(_ flags: Int32, on fileDescriptor: Int32) throws
    func write(_ output: String, to fileDescriptor: Int32) throws
    func read(
      from fileDescriptor: Int32,
      maxBytes: Int,
      timeoutMilliseconds: Int
    ) throws -> [UInt8]
  }

  extension TerminalControlling {
    func cellPixelSize(of _: Int32) throws -> Size? {
      nil
    }
  }

  struct POSIXTerminalController: TerminalControlling {
    func isATTY(_ fileDescriptor: Int32) -> Bool {
      isatty(fileDescriptor) == 1
    }

    func getAttributes(from fileDescriptor: Int32) throws -> termios {
      var attributes = termios()
      guard unsafe tcgetattr(fileDescriptor, &attributes) == 0 else {
        throw TerminalHostError.failedToReadAttributes(errno: errno)
      }
      return attributes
    }

    func setAttributes(_ attributes: termios, on fileDescriptor: Int32) throws {
      var attributes = attributes
      guard unsafe tcsetattr(fileDescriptor, TCSAFLUSH, &attributes) == 0 else {
        throw TerminalHostError.failedToSetAttributes(errno: errno)
      }
    }

    func windowSize(of fileDescriptor: Int32) throws -> Size {
      var windowSize = winsize()
      guard unsafe ioctl(fileDescriptor, UInt(TIOCGWINSZ), &windowSize) == 0 else {
        throw TerminalHostError.failedToReadWindowSize(errno: errno)
      }

      return Size(
        width: max(1, Int(windowSize.ws_col)),
        height: max(1, Int(windowSize.ws_row))
      )
    }

    func cellPixelSize(of fileDescriptor: Int32) throws -> Size? {
      var windowSize = winsize()
      guard unsafe ioctl(fileDescriptor, UInt(TIOCGWINSZ), &windowSize) == 0 else {
        throw TerminalHostError.failedToReadWindowSize(errno: errno)
      }
      guard
        windowSize.ws_col > 0,
        windowSize.ws_row > 0,
        windowSize.ws_xpixel > 0,
        windowSize.ws_ypixel > 0
      else {
        return nil
      }

      return .init(
        width: max(1, Int(windowSize.ws_xpixel) / Int(windowSize.ws_col)),
        height: max(1, Int(windowSize.ws_ypixel) / Int(windowSize.ws_row))
      )
    }

    func getFileStatusFlags(of fileDescriptor: Int32) throws -> Int32 {
      let flags = fcntl(fileDescriptor, F_GETFL)
      guard flags >= 0 else {
        throw TerminalHostError.failedToReadFileStatusFlags(errno: errno)
      }
      return flags
    }

    func setFileStatusFlags(_ flags: Int32, on fileDescriptor: Int32) throws {
      guard fcntl(fileDescriptor, F_SETFL, flags) >= 0 else {
        throw TerminalHostError.failedToSetFileStatusFlags(errno: errno)
      }
    }

    func write(_ output: String, to fileDescriptor: Int32) throws {
      let bytes = Array(output.utf8)
      let totalBytes = bytes.count

      try unsafe bytes.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else {
          return
        }

        var bytesWritten = 0
        while bytesWritten < totalBytes {
          let pointer = unsafe baseAddress.advanced(by: bytesWritten)
          let result = unsafe platformWrite(
            fileDescriptor,
            pointer,
            totalBytes - bytesWritten
          )

          if result > 0 {
            bytesWritten += result
            continue
          }

          if result == 0 {
            continue
          }

          switch errno {
          case EINTR:
            continue
          case EAGAIN, EWOULDBLOCK:
            try waitUntilWritable(fileDescriptor)
          default:
            throw TerminalHostError.failedToWrite(errno: errno)
          }
        }
      }
    }

    func read(
      from fileDescriptor: Int32,
      maxBytes: Int,
      timeoutMilliseconds: Int
    ) throws -> [UInt8] {
      guard maxBytes > 0 else {
        return []
      }

      var descriptor = pollfd(
        fd: fileDescriptor,
        events: Int16(POLLIN),
        revents: 0
      )
      let ready = unsafe platformPoll(
        &descriptor,
        1,
        Int32(timeoutMilliseconds)
      )

      guard ready > 0 else {
        return []
      }

      var buffer = Array(repeating: UInt8(0), count: maxBytes)
      let bytesRead = unsafe platformRead(fileDescriptor, &buffer, maxBytes)
      guard bytesRead > 0 else {
        return []
      }

      return Array(buffer.prefix(Int(bytesRead)))
    }
  }

  extension POSIXTerminalController {
    private func waitUntilWritable(
      _ fileDescriptor: Int32
    ) throws {
      var descriptor = pollfd(
        fd: fileDescriptor,
        events: Int16(POLLOUT),
        revents: 0
      )

      while true {
        let ready = unsafe platformPoll(&descriptor, 1, -1)
        if ready > 0 {
          return
        }
        if ready == 0 || errno == EINTR {
          continue
        }
        throw TerminalHostError.failedToWrite(errno: errno)
      }
    }
  }

  private struct PresentationFrame: Sendable {
    var output: String
  }

  private final class PresentationWriter: Sendable {
    private struct State: Sendable {
      var pending: PresentationFrame?
      var isWriting = false
      var didDropFrame = false
      var pendingError: TerminalHostError?
    }

    private let controller: any TerminalControlling
    private let outputFileDescriptor: Int32
    private let queue = DispatchQueue(label: "swift-terminal-ui.presentation-writer")
    private let state = Mutex(State())

    init(
      controller: any TerminalControlling,
      outputFileDescriptor: Int32
    ) {
      self.controller = controller
      self.outputFileDescriptor = outputFileDescriptor
    }

    func submit(
      _ frame: PresentationFrame
    ) {
      let shouldStart = state.withLock { state in
        guard state.pendingError == nil else {
          return false
        }
        if state.pending != nil {
          state.didDropFrame = true
        }
        state.pending = frame

        guard !state.isWriting else {
          return false
        }

        state.isWriting = true
        return true
      }

      guard shouldStart else {
        return
      }

      queue.async { [self] in
        writePendingFrames()
      }
    }

    func consumeDropFlag() -> Bool {
      state.withLock { state in
        let didDropFrame = state.didDropFrame
        state.didDropFrame = false
        return didDropFrame
      }
    }

    func hasPendingFrame() -> Bool {
      state.withLock { state in
        state.pending != nil
      }
    }

    func consumePendingError() throws {
      let pendingError = state.withLock { state in
        let pendingError = state.pendingError
        state.pendingError = nil
        return pendingError
      }

      if let pendingError {
        throw pendingError
      }
    }

    func drain() {
      queue.sync {}
    }

    private func writePendingFrames() {
      while true {
        let frame: PresentationFrame? = state.withLock { state in
          guard let frame = state.pending else {
            state.isWriting = false
            return nil
          }

          state.pending = nil
          return frame
        }

        guard let frame else {
          return
        }

        do {
          try controller.write(frame.output, to: outputFileDescriptor)
        } catch let error as TerminalHostError {
          state.withLock { state in
            state.pending = nil
            state.isWriting = false
            state.pendingError = error
          }
          return
        } catch {
          state.withLock { state in
            state.pending = nil
            state.isWriting = false
            state.pendingError = .failedToWrite(errno: EIO)
          }
          return
        }
      }
    }
  }

  /// Default terminal-backed host that owns raw mode and screen presentation.
  public final class TerminalHost: TerminalHosting, DamageAwareTerminalHosting {
    private struct CapabilityProbeState {
      var hasProbedAppearance = false
      var hasProbedGraphicsCapabilities = false
      var cachedGraphicsCapabilities: TerminalGraphicsCapabilities?
    }

    private struct PresentationSession {
      var lastSubmittedSurface: RasterSurface?
      var transmittedKittyImages: Set<UInt32> = []
      var forceFullRepaint = false
      var writer: PresentationWriter?

      mutating func reset() {
        lastSubmittedSurface = nil
        transmittedKittyImages.removeAll()
        forceFullRepaint = false
        writer = nil
      }

      mutating func invalidateRetainedState() {
        lastSubmittedSurface = nil
        transmittedKittyImages.removeAll()
        forceFullRepaint = false
      }

      mutating func markDroppedFrame() {
        forceFullRepaint = true
        transmittedKittyImages.removeAll()
      }

      var previousSurface: RasterSurface? {
        forceFullRepaint ? nil : lastSubmittedSurface
      }

      func presentationDamage(
        requested damage: PresentationDamage?
      ) -> PresentationDamage? {
        forceFullRepaint ? nil : damage
      }
    }

    public var surfaceSize: Size {
      (try? controller.windowSize(of: outputFileDescriptor)) ?? fallbackSize
    }
    public let capabilityProfile: TerminalCapabilityProfile
    public private(set) var appearance: TerminalAppearance
    public var theme: Theme? { nil }
    public var graphicsCapabilities: TerminalGraphicsCapabilities {
      resolvedGraphicsCapabilities(probingProtocols: false)
    }

    private let inputFileDescriptor: Int32
    private let outputFileDescriptor: Int32
    private let fallbackSize: Size
    private let controller: any TerminalControlling
    private let environment: [String: String]
    private let usesTerminalEditOperations: Bool
    private let imageRenderer: TerminalImageRenderer

    private var savedAttributes: termios?
    private var savedInputFileStatusFlags: Int32?
    private var processExitCleanupToken: UInt64?
    private var rawModeEnabled = false
    private var capabilityProbe = CapabilityProbeState()
    private var presentationSession = PresentationSession()

    public convenience init(
      inputFileDescriptor: Int32 = 0,
      outputFileDescriptor: Int32 = 1,
      fallbackSize: Size = .init(width: 80, height: 24),
      capabilityProfile: TerminalCapabilityProfile? = nil,
      environment: [String: String]? = nil,
      usesTerminalEditOperations: Bool? = nil
    ) {
      self.init(
        inputFileDescriptor: inputFileDescriptor,
        outputFileDescriptor: outputFileDescriptor,
        fallbackSize: fallbackSize,
        controller: POSIXTerminalController(),
        capabilityProfile: capabilityProfile,
        environment: environment ?? currentProcessEnvironment(),
        usesTerminalEditOperations: usesTerminalEditOperations
      )
    }

    package init(
      inputFileDescriptor: Int32,
      outputFileDescriptor: Int32,
      fallbackSize: Size,
      controller: any TerminalControlling,
      capabilityProfile: TerminalCapabilityProfile? = nil,
      environment: [String: String]? = nil,
      usesTerminalEditOperations: Bool? = nil
    ) {
      let environment = environment ?? currentProcessEnvironment()
      self.inputFileDescriptor = inputFileDescriptor
      self.outputFileDescriptor = outputFileDescriptor
      self.fallbackSize = fallbackSize
      self.controller = controller
      self.environment = environment
      self.usesTerminalEditOperations =
        usesTerminalEditOperations ?? controller.isATTY(outputFileDescriptor)
      imageRenderer = .init(repository: sharedImageAssetRepository)
      self.capabilityProfile =
        capabilityProfile
        ?? TerminalCapabilityProfile.detect(
          environment: environment,
          isTTY: controller.isATTY(outputFileDescriptor)
        )
      self.appearance = TerminalAppearance.detect(
        environment: environment,
        capabilityProfile: self.capabilityProfile
      )
    }

    public func enableRawMode() throws {
      guard !rawModeEnabled else {
        return
      }
      guard controller.isATTY(inputFileDescriptor) else {
        throw TerminalHostError.notATTY(fileDescriptor: inputFileDescriptor)
      }

      let currentAttributes = try controller.getAttributes(from: inputFileDescriptor)
      var rawAttributes = currentAttributes
      unsafe cfmakeraw(&rawAttributes)
      rawAttributes.c_cc.16 = 1
      rawAttributes.c_cc.17 = 0

      try controller.setAttributes(rawAttributes, on: inputFileDescriptor)
      let currentFileStatusFlags = try controller.getFileStatusFlags(of: inputFileDescriptor)
      try controller.setFileStatusFlags(
        currentFileStatusFlags | Int32(O_NONBLOCK),
        on: inputFileDescriptor
      )
      savedAttributes = currentAttributes
      savedInputFileStatusFlags = currentFileStatusFlags
      #if !canImport(WASILibc)
        processExitCleanupToken = TerminalProcessExitCleanupRegistry.register(
          .init(
            inputFileDescriptor: inputFileDescriptor,
            outputFileDescriptor: outputFileDescriptor,
            inputFileStatusFlags: currentFileStatusFlags,
            savedAttributes: currentAttributes,
            resetBytes: Array(processExitResetSequence().utf8)
          )
        )
      #endif
      rawModeEnabled = true
      presentationSession.reset()

      var shouldRestoreOnFailure = true
      defer {
        if shouldRestoreOnFailure {
          #if !canImport(WASILibc)
            TerminalProcessExitCleanupRegistry.unregister(processExitCleanupToken)
            processExitCleanupToken = nil
          #endif
          let savedInputFileStatusFlags = self.savedInputFileStatusFlags
          savedAttributes = nil
          self.savedInputFileStatusFlags = nil
          rawModeEnabled = false
          presentationSession.reset()
          if let savedInputFileStatusFlags {
            try? controller.setFileStatusFlags(savedInputFileStatusFlags, on: inputFileDescriptor)
          }
          try? controller.setAttributes(currentAttributes, on: inputFileDescriptor)
        }
      }

      refreshAppearanceIfNeeded()
      try write(enterAlternateScreenSequence())
      try write(clearScreenSequence())
      try write(cursorSequence(to: .zero))
      try write(hideCursorSequence())
      if capabilityProfile.supportsMouseReporting {
        try write(enableMouseReportingSequence())
      }
      try write("\u{001B}[?2004h")  // enable bracketed paste
      shouldRestoreOnFailure = false
    }

    public func disableRawMode() throws {
      guard rawModeEnabled else {
        return
      }

      let presentationWriter = presentationSession.writer
      let savedAttributes = self.savedAttributes
      let savedInputFileStatusFlags = self.savedInputFileStatusFlags
      #if !canImport(WASILibc)
        TerminalProcessExitCleanupRegistry.unregister(processExitCleanupToken)
        processExitCleanupToken = nil
      #endif
      self.savedAttributes = nil
      self.savedInputFileStatusFlags = nil
      rawModeEnabled = false
      presentationSession.reset()

      var attributesToRestore = savedAttributes
      var fileStatusFlagsToRestore = savedInputFileStatusFlags
      defer {
        if let fileStatusFlagsToRestore {
          try? controller.setFileStatusFlags(fileStatusFlagsToRestore, on: inputFileDescriptor)
        }
        if let attributesToRestore {
          try? controller.setAttributes(attributesToRestore, on: inputFileDescriptor)
        }
      }

      presentationWriter?.drain()
      try presentationWriter?.consumePendingError()

      try writeSynchronously(clearScreenSequence())
      try writeSynchronously(cursorSequence(to: .zero))
      if capabilityProfile.supportsMouseReporting {
        try writeSynchronously(disableMouseReportingSequence())
      }
      try writeSynchronously("\u{001B}[?2004l")  // disable bracketed paste
      try writeSynchronously(resetStyleSequence())
      try writeSynchronously(showCursorSequence())
      try writeSynchronously(exitAlternateScreenSequence())

      if let savedInputFileStatusFlags {
        try controller.setFileStatusFlags(savedInputFileStatusFlags, on: inputFileDescriptor)
        fileStatusFlagsToRestore = nil
      }
      if let savedAttributes {
        try controller.setAttributes(savedAttributes, on: inputFileDescriptor)
        attributesToRestore = nil
      }
    }

    public func write(_ output: String) throws {
      try drainPendingPresentation()
      try writeSynchronously(output)
      invalidatePresentationState()
    }

    public func clearScreen() throws {
      try write(clearScreenSequence())
    }

    public func moveCursor(to point: Point) throws {
      try write(cursorSequence(to: point))
    }

    @discardableResult
    public func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
      try present(
        surface,
        damage: nil
      )
    }

    @discardableResult
    package func present(
      _ surface: RasterSurface,
      damage: PresentationDamage?
    ) throws -> TerminalPresentationMetrics {
      try synchronizePresentationState()
      if !surface.imageAttachments.isEmpty, !capabilityProbe.hasProbedGraphicsCapabilities {
        try drainPendingPresentation()
      }

      let graphicsCapabilities = resolvedGraphicsCapabilities(
        probingProtocols: !surface.imageAttachments.isEmpty
      )
      let preparedSurface = imageRenderer.preparedSurface(
        for: surface,
        capabilityProfile: capabilityProfile,
        graphicsCapabilities: graphicsCapabilities
      )
      let plan = TerminalPresentationPlanner(
        capabilityProfile: capabilityProfile,
        graphicsCapabilities: graphicsCapabilities
      ).plan(
        previousSurface: presentationSession.previousSurface,
        currentSurface: preparedSurface,
        damage: presentationSession.presentationDamage(requested: damage)
      )
      presentationSession.forceFullRepaint = false

      var bytesWritten = 0
      let origin = Point.zero
      var bufferedOutput = String()
      var graphicsReplayScope = TerminalPresentationMetrics.GraphicsReplayScope.none
      var graphicsAttachmentsReplayed = 0
      var editOperationLowering = TerminalPresentationMetrics.EditOperationLowering.none
      var editOperationCount = 0

      func append(_ output: String) {
        bufferedOutput.append(output)
        bytesWritten += output.utf8.count
      }

      switch plan.strategy {
      case .fullRepaint:
        // A terminal full repaint clears the previous screen contents. Kitty
        // image ids cannot be assumed to remain displayable after that, so
        // force the current frame to retransmit any images before placement.
        if graphicsCapabilities.preferredProtocol == .kitty {
          presentationSession.transmittedKittyImages.removeAll()
        }
        if !preparedSurface.imageAttachments.isEmpty {
          graphicsReplayScope = .full
          graphicsAttachmentsReplayed = preparedSurface.imageAttachments.count
        }
        append(clearScreenSequence())
        append(cursorSequence(to: origin))

        let writeSteps = fullRepaintWriteSteps(
          for: preparedSurface,
          capabilityProfile: capabilityProfile
        )
        for writeStep in writeSteps {
          append(writeStep)
        }

        for writeStep in imageRenderer.graphicsWriteSteps(
          for: preparedSurface,
          capabilityProfile: capabilityProfile,
          graphicsCapabilities: graphicsCapabilities,
          transmittedKittyImages: &presentationSession.transmittedKittyImages
        ) {
          append(writeStep)
        }

      case .incremental:
        for rowBatch in plan.rowBatches {
          let rowOutput: String
          if usesTerminalEditOperations,
            rowBatch.canLowerToEraseToEndOfLine(
              surfaceWidth: preparedSurface.size.width
            )
          {
            editOperationLowering = .eraseToEndOfLine
            editOperationCount += 1
            rowOutput = eraseToEndOfLineSequence()
          } else {
            rowOutput = rowBatch.renderedBatch
          }
          append(
            cursorSequence(
              to: .init(x: rowBatch.anchorColumn, y: rowBatch.row)
            )
          )
          append(rowOutput)
        }
        if graphicsCapabilities.preferredProtocol == .kitty {
          switch plan.graphicsReplay.scope {
          case .none:
            break
          case .targeted:
            graphicsReplayScope = .targeted
            graphicsAttachmentsReplayed = plan.graphicsReplay.attachmentsToReplay.count
            for writeStep in imageRenderer.graphicsWriteSteps(
              for: plan.graphicsReplay.attachmentsToReplay,
              capabilityProfile: capabilityProfile,
              graphicsCapabilities: graphicsCapabilities,
              transmittedKittyImages: &presentationSession.transmittedKittyImages
            ) {
              append(writeStep)
            }
          case .full:
            graphicsReplayScope = .full
            graphicsAttachmentsReplayed = plan.graphicsReplay.attachmentsToReplay.count
            append(deleteVisibleKittyPlacementsSequence())
            for writeStep in imageRenderer.graphicsWriteSteps(
              for: plan.graphicsReplay.attachmentsToReplay,
              capabilityProfile: capabilityProfile,
              graphicsCapabilities: graphicsCapabilities,
              transmittedKittyImages: &presentationSession.transmittedKittyImages
            ) {
              append(writeStep)
            }
          }
        }
      }

      let usedSynchronizedOutput =
        !bufferedOutput.isEmpty
        && plan.strategy == .fullRepaint
        && capabilityProfile.supportsSynchronizedOutput
      bufferedOutput = wrappedPresentationOutput(
        bufferedOutput,
        strategy: plan.strategy
      )
      bytesWritten = bufferedOutput.utf8.count

      if !bufferedOutput.isEmpty {
        presentationWriterIfNeeded().submit(
          .init(
            output: bufferedOutput
          )
        )
      }

      presentationSession.lastSubmittedSurface = preparedSurface

      return TerminalPresentationMetrics(
        bytesWritten: bytesWritten,
        linesTouched: plan.linesTouched,
        cellsChanged: plan.cellsChanged,
        strategy: plan.strategy == TerminalPresentationPlan.Strategy.fullRepaint
          ? TerminalPresentationMetrics.Strategy.fullRepaint
          : TerminalPresentationMetrics.Strategy.incremental,
        usedSynchronizedOutput: usedSynchronizedOutput,
        graphicsReplayScope: graphicsReplayScope,
        graphicsAttachmentsReplayed: graphicsAttachmentsReplayed,
        editOperationLowering: editOperationLowering,
        editOperationCount: editOperationCount
      )
    }

    package func drainPendingPresentation() throws {
      guard let presentationWriter = presentationSession.writer else {
        return
      }

      presentationWriter.drain()
      if presentationWriter.consumeDropFlag() {
        presentationSession.markDroppedFrame()
      }
      try presentationWriter.consumePendingError()
    }

    private func synchronizePresentationState() throws {
      guard let presentationWriter = presentationSession.writer else {
        return
      }

      if presentationWriter.consumeDropFlag() {
        presentationSession.markDroppedFrame()
      }
      if presentationWriter.hasPendingFrame() {
        presentationSession.markDroppedFrame()
      }
      try presentationWriter.consumePendingError()
    }

    private func presentationWriterIfNeeded() -> PresentationWriter {
      if let presentationWriter = presentationSession.writer {
        return presentationWriter
      }

      let presentationWriter = PresentationWriter(
        controller: controller,
        outputFileDescriptor: outputFileDescriptor
      )
      presentationSession.writer = presentationWriter
      return presentationWriter
    }

    private func writeSynchronously(
      _ output: String
    ) throws {
      try controller.write(output, to: outputFileDescriptor)
    }

    private func invalidatePresentationState() {
      presentationSession.invalidateRetainedState()
    }

    private func refreshAppearanceIfNeeded() {
      guard !capabilityProbe.hasProbedAppearance else {
        return
      }
      capabilityProbe.hasProbedAppearance = true

      appearance = TerminalAppearance.detect(
        environment: environment,
        capabilityProfile: capabilityProfile,
        queryColor: { [weak self] query in
          guard let self else {
            return nil
          }
          return try self.performAppearanceQuery(query)
        }
      )
    }

    private func performAppearanceQuery(
      _ query: TerminalAppearanceQuery
    ) throws -> Color? {
      try writeSynchronously(query.request)
      var buffer: [UInt8] = []
      let timeoutMilliseconds = 40

      for _ in 0..<4 {
        let bytes = try controller.read(
          from: inputFileDescriptor,
          maxBytes: 256,
          timeoutMilliseconds: timeoutMilliseconds
        )
        guard !bytes.isEmpty else {
          break
        }
        buffer.append(contentsOf: bytes)

        if let response = query.extractResponse(from: buffer),
          let color = query.parseColor(from: response)
        {
          return color
        }
      }

      return nil
    }

    private func resolvedGraphicsCapabilities(
      probingProtocols: Bool
    ) -> TerminalGraphicsCapabilities {
      if probingProtocols {
        return probeGraphicsCapabilitiesIfNeeded()
      }
      return baselineGraphicsCapabilities()
    }

    private func baselineGraphicsCapabilities() -> TerminalGraphicsCapabilities {
      var capabilities = capabilityProbe.cachedGraphicsCapabilities ?? .none
      // Always attempt a fresh ioctl read. The syscall is cheap and its
      // result is authoritative when the kernel reports pixel dimensions.
      // We only fall back to the cached value if the fresh read returns
      // nil, which preserves previously-probed escape-sequence values
      // (CSI 16 t / CSI 14 t) across frames.
      if let fresh = try? controller.cellPixelSize(of: outputFileDescriptor) {
        capabilities.cellPixelSize = fresh
      }
      capabilityProbe.cachedGraphicsCapabilities = capabilities
      return capabilities
    }

    private func probeGraphicsCapabilitiesIfNeeded() -> TerminalGraphicsCapabilities {
      if capabilityProbe.hasProbedGraphicsCapabilities {
        return baselineGraphicsCapabilities()
      }
      capabilityProbe.hasProbedGraphicsCapabilities = true

      var capabilities = baselineGraphicsCapabilities()
      guard controller.isATTY(outputFileDescriptor) else {
        capabilityProbe.cachedGraphicsCapabilities = capabilities
        return capabilities
      }

      // Single combined probe: the kitty query escape sequence already
      // piggybacks `\e[c`, so non-kitty terminals will still respond with
      // their device attributes. We harvest kitty support and the DA
      // attributes from the same buffer instead of paying for a second
      // round trip.
      let kittyQueryID = stableIdentifier(from: Array("stui-kitty-query".utf8))
      let combinedProbeBuffer: [UInt8] =
        (try? performGraphicsQuery(.kittySupport(id: kittyQueryID))) ?? []

      if parseKittySupportResponse(in: combinedProbeBuffer, id: kittyQueryID) == true,
        !capabilities.supportedProtocols.contains(.kitty)
      {
        capabilities.supportedProtocols.append(.kitty)
      }

      if let attributes = parsePrimaryDeviceAttributes(from: combinedProbeBuffer),
        attributes.contains(4)
      {
        if !capabilities.supportedProtocols.contains(.sixel) {
          capabilities.supportedProtocols.append(.sixel)
        }

        if let registersResponse = try? performGraphicsQuery(.sixelColorRegisters),
          let registers = parseXTSMGraphicsResponse(from: registersResponse, item: 1),
          registers.status >= 0,
          let firstValue = registers.values.first
        {
          capabilities.sixelColorRegisters = firstValue
        }

        if let geometryResponse = try? performGraphicsQuery(.sixelGeometry),
          let geometry = parseXTSMGraphicsResponse(from: geometryResponse, item: 2),
          geometry.status >= 0,
          geometry.values.count >= 2
        {
          capabilities.sixelGeometry = .init(
            width: geometry.values[0],
            height: geometry.values[1]
          )
        }
      }

      if capabilities.cellPixelSize == nil {
        if let cellPixelResponse = try? performGraphicsQuery(.cellPixels),
          let cellPixelSize = parseWindowSizeResponse(from: cellPixelResponse, expectedCode: 6)
        {
          capabilities.cellPixelSize = cellPixelSize
        } else if let textAreaResponse = try? performGraphicsQuery(.textAreaPixels),
          let textAreaPixels = parseWindowSizeResponse(from: textAreaResponse, expectedCode: 4)
        {
          let size = surfaceSize
          if size.width > 0, size.height > 0 {
            capabilities.cellPixelSize = .init(
              width: max(1, textAreaPixels.width / size.width),
              height: max(1, textAreaPixels.height / size.height)
            )
          }
        }
      }

      if capabilities.supportsKitty {
        capabilities.preferredProtocol = .kitty
      } else if capabilities.supportsSixel {
        capabilities.preferredProtocol = .sixel
      }

      capabilityProbe.cachedGraphicsCapabilities = capabilities
      return capabilities
    }

    private func performGraphicsQuery(
      _ query: TerminalGraphicsQuery
    ) throws -> [UInt8] {
      try writeSynchronously(query.request)
      var buffer: [UInt8] = []
      let timeoutMilliseconds = 40

      for _ in 0..<6 {
        let bytes = try controller.read(
          from: inputFileDescriptor,
          maxBytes: 512,
          timeoutMilliseconds: timeoutMilliseconds
        )
        guard !bytes.isEmpty else {
          break
        }
        buffer.append(contentsOf: bytes)

        switch query {
        case .kittySupport:
          // The kitty probe request piggybacks a `\e[c` (primary device
          // attributes) query after the kitty query so non-kitty terminals
          // still produce a response we can synchronize on. We wait for the
          // DA response before returning so the caller can harvest both
          // the kitty result and the DA attributes from a single round trip.
          if parsePrimaryDeviceAttributes(from: buffer) != nil {
            return buffer
          }
        case .primaryDeviceAttributes:
          if parsePrimaryDeviceAttributes(from: buffer) != nil {
            return buffer
          }
        case .sixelColorRegisters:
          if parseXTSMGraphicsResponse(from: buffer, item: 1) != nil {
            return buffer
          }
        case .sixelGeometry:
          if parseXTSMGraphicsResponse(from: buffer, item: 2) != nil {
            return buffer
          }
        case .textAreaPixels:
          if parseWindowSizeResponse(from: buffer, expectedCode: 4) != nil {
            return buffer
          }
        case .cellPixels:
          if parseWindowSizeResponse(from: buffer, expectedCode: 6) != nil {
            return buffer
          }
        }
      }

      return buffer
    }

    private func clearScreenSequence() -> String {
      "\u{001B}[2J"
    }

    private func eraseToEndOfLineSequence() -> String {
      "\u{001B}[K"
    }

    private func deleteVisibleKittyPlacementsSequence() -> String {
      "\u{001B}_Ga=d,q=2\u{001B}\\"
    }

    private func beginSynchronizedOutputSequence() -> String {
      "\u{001B}[?2026h"
    }

    private func endSynchronizedOutputSequence() -> String {
      "\u{001B}[?2026l"
    }

    private func enterAlternateScreenSequence() -> String {
      "\u{001B}[?1049h"
    }

    private func exitAlternateScreenSequence() -> String {
      "\u{001B}[?1049l"
    }

    private func hideCursorSequence() -> String {
      "\u{001B}[?25l"
    }

    private func showCursorSequence() -> String {
      "\u{001B}[?25h"
    }

    private func enableMouseReportingSequence() -> String {
      "\u{001B}[?1002h\u{001B}[?1006h"
    }

    private func disableMouseReportingSequence() -> String {
      "\u{001B}[?1002l\u{001B}[?1006l"
    }

    private func processExitResetSequence() -> String {
      var reset = ""
      if capabilityProfile.supportsMouseReporting {
        reset += disableMouseReportingSequence()
      }
      reset += "\u{001B}[?2004l"  // disable bracketed paste
      reset += showCursorSequence()
      reset += resetStyleSequence()
      reset += exitAlternateScreenSequence()
      return reset
    }

    private func resetStyleSequence() -> String {
      "\u{001B}[0m"
    }

    private func cursorSequence(to point: Point) -> String {
      let row = max(1, point.y + 1)
      let column = max(1, point.x + 1)
      return "\u{001B}[\(row);\(column)H"
    }

    private func wrappedPresentationOutput(
      _ output: String,
      strategy: TerminalPresentationPlan.Strategy
    ) -> String {
      guard !output.isEmpty,
        strategy == .fullRepaint,
        capabilityProfile.supportsSynchronizedOutput
      else {
        return output
      }

      return beginSynchronizedOutputSequence()
        + output
        + endSynchronizedOutputSequence()
    }

  }
#else
  public final class WebTerminalHost: TerminalHosting, Sendable {
    private struct State {
      var surfaceSize: Size
      var renderStyle: TerminalRenderStyle
    }

    private let state: Mutex<State>
    private let outputFD: Int32
    private let writeLock = Mutex(())

    public let capabilityProfile: TerminalCapabilityProfile
    public let graphicsCapabilities: TerminalGraphicsCapabilities

    public convenience init(
      surfaceSize: Size,
      theme: Theme? = nil,
      capabilityProfile: TerminalCapabilityProfile = .trueColor,
      graphicsCapabilities: TerminalGraphicsCapabilities = .none,
      environment: [String: String]? = nil
    ) {
      self.init(
        surfaceSize: surfaceSize,
        outputFileDescriptor: STDOUT_FILENO,
        theme: theme,
        capabilityProfile: capabilityProfile,
        graphicsCapabilities: graphicsCapabilities,
        environment: environment
      )
    }

    public init(
      surfaceSize: Size,
      outputFileDescriptor: Int32,
      theme: Theme? = nil,
      capabilityProfile: TerminalCapabilityProfile = .trueColor,
      graphicsCapabilities: TerminalGraphicsCapabilities = .none,
      environment: [String: String]? = nil
    ) {
      self.outputFD = outputFileDescriptor
      self.capabilityProfile = capabilityProfile
      self.graphicsCapabilities = graphicsCapabilities
      let appearance = TerminalAppearance.detect(
        environment: environment ?? currentProcessEnvironment(),
        capabilityProfile: capabilityProfile
      )
      state = Mutex(
        State(
          surfaceSize: surfaceSize,
          renderStyle: .init(
            appearance: appearance,
            theme: theme
          )
        )
      )
    }

    public var surfaceSize: Size {
      state.withLock(\.surfaceSize)
    }

    public var appearance: TerminalAppearance {
      state.withLock(\.renderStyle.appearance)
    }

    public var theme: Theme? {
      state.withLock(\.renderStyle.theme)
    }

    public func updateSurfaceSize(_ surfaceSize: Size) {
      state.withLock { state in
        state.surfaceSize = surfaceSize
      }
    }

    public func updateTheme(
      _ theme: Theme?
    ) {
      state.withLock { state in
        state.renderStyle.theme = theme
      }
    }

    public func updateStyle(
      _ style: TerminalRenderStyle
    ) {
      state.withLock { state in
        state.renderStyle = style
      }
    }

    public func enableRawMode() throws {
      var setup = enterAlternateScreenSequence()
      setup += hideCursorSequence()
      if capabilityProfile.supportsMouseReporting {
        setup += enableMouseReportingSequence()
      }
      setup += "\u{001B}[?2004h"  // enable bracketed paste
      try write(setup)
    }

    public func disableRawMode() throws {
      var teardown = ""
      if capabilityProfile.supportsMouseReporting {
        teardown += disableMouseReportingSequence()
      }
      teardown += "\u{001B}[?2004l"  // disable bracketed paste
      teardown += showCursorSequence()
      teardown += resetStyleSequence()
      teardown += exitAlternateScreenSequence()
      try write(teardown)
    }

    public func write(_ output: String) throws {
      let bytes = Array(output.utf8)
      try writeBytes(bytes)
    }

    public func clearScreen() throws {
      try write("\u{001B}[2J")
    }

    public func moveCursor(to point: Point) throws {
      try write(cursorSequence(to: point))
    }

    private func writeBytes(_ bytes: [UInt8]) throws {
      guard !bytes.isEmpty else {
        return
      }

      try writeLock.withLock { _ in
        var written = 0
        while written < bytes.count {
          let result = unsafe bytes.withUnsafeBytes { rawBuffer in
            let baseAddress = unsafe rawBuffer.baseAddress?.advanced(by: written)
            return unsafe platformWrite(
              outputFD,
              baseAddress,
              bytes.count - written
            )
          }

          if result < 0 {
            throw TerminalHostError.failedToWrite(errno: errno)
          }

          written += result
        }
      }
    }

    private func enterAlternateScreenSequence() -> String {
      "\u{001B}[?1049h"
    }

    private func exitAlternateScreenSequence() -> String {
      "\u{001B}[?1049l"
    }

    private func hideCursorSequence() -> String {
      "\u{001B}[?25l"
    }

    private func showCursorSequence() -> String {
      "\u{001B}[?25h"
    }

    private func enableMouseReportingSequence() -> String {
      "\u{001B}[?1002h\u{001B}[?1006h"
    }

    private func disableMouseReportingSequence() -> String {
      "\u{001B}[?1002l\u{001B}[?1006l"
    }

    private func resetStyleSequence() -> String {
      "\u{001B}[0m"
    }

    private func cursorSequence(to point: Point) -> String {
      let row = max(1, point.y + 1)
      let column = max(1, point.x + 1)
      return "\u{001B}[\(row);\(column)H"
    }
  }
#endif

func fullRepaintWriteSteps(
  for surface: RasterSurface,
  capabilityProfile: TerminalCapabilityProfile
) -> [String] {
  let renderer = TerminalSurfaceRenderer(
    capabilityProfile: capabilityProfile
  )
  var writeSteps: [String] = []

  for rowIndex in 0..<surface.size.height {
    let row = rowIndex < surface.cells.count ? surface.cells[rowIndex] : []
    let renderedRow = renderer.renderRow(row)
    guard !renderedRow.isEmpty else {
      continue
    }

    if rowIndex > 0 {
      writeSteps.append(
        "\u{001B}[\(max(1, rowIndex + 1));1H"
      )
    }
    writeSteps.append(renderedRow)
  }

  return writeSteps
}

func fullRepaintOutput(
  for surface: RasterSurface,
  capabilityProfile: TerminalCapabilityProfile,
  origin: Point = .zero
) -> String {
  let writeSteps = fullRepaintWriteSteps(
    for: surface,
    capabilityProfile: capabilityProfile
  )
  var output = ""
  output.reserveCapacity(
    fullRepaintBytesWritten(
      writeSteps: writeSteps,
      origin: origin
    )
  )
  output += "\u{001B}[2J"
  output += fullRepaintCursorSequence(to: origin)
  for writeStep in writeSteps {
    output += writeStep
  }
  return output
}

func fullRepaintBytesWritten(
  writeSteps: [String],
  origin: Point
) -> Int {
  let clearSequence = "\u{001B}[2J"
  let cursorSequence = fullRepaintCursorSequence(to: origin)
  return clearSequence.utf8.count
    + cursorSequence.utf8.count
    + writeSteps.reduce(0) { partial, writeStep in
      partial + writeStep.utf8.count
    }
}

func fullRepaintCursorSequence(
  to point: Point
) -> String {
  "\u{001B}[\(max(1, point.y + 1));\(max(1, point.x + 1))H"
}

package func currentProcessEnvironment() -> [String: String] {
  #if canImport(WASILibc)
    var environment: [String: String] = [:]

    for key in ["TERM", "COLORTERM", "LANG", "LC_ALL", "LC_CTYPE", "COLORFGBG"] {
      if let value = environmentValue(named: key) {
        environment[key] = value
      }
    }

    return environment
  #elseif canImport(Android)
    // Android imports `environ` as shared mutable global state, which trips
    // strict concurrency checking in Swift 6. Falling back to an empty map keeps
    // cross-compilation working and preserves the terminal runtime's default
    // capability detection behavior.
    [:]
  #else
    var environment: [String: String] = [:]
    let processEnvironment = unsafe environ
    var index = 0

    while let entry = unsafe processEnvironment[index] {
      defer { index += 1 }

      guard let assignment = unsafe String(validatingCString: entry),
        let separator = assignment.firstIndex(of: "=")
      else {
        continue
      }

      let key = String(assignment[..<separator])
      let value = String(assignment[assignment.index(after: separator)...])
      environment[key] = value
    }

    return environment
  #endif
}

#if canImport(WASILibc)
  private func environmentValue(
    named key: String
  ) -> String? {
    unsafe key.withCString { cKey in
      guard let rawValue = unsafe getenv(cKey) else {
        return nil
      }
      return unsafe String(cString: rawValue)
    }
  }
#endif
