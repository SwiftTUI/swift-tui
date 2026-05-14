import SwiftTUICore
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
    origin: CellPoint = .zero
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

  package static func rasterHostMetrics(
    for surface: RasterSurface,
    damage: PresentationDamage?,
    bytesWritten: Int = 0,
    graphicsReplayScope: GraphicsReplayScope? = nil,
    graphicsAttachmentsReplayed: Int? = nil
  ) -> Self {
    let defaultGraphicsScope: GraphicsReplayScope =
      if damage == nil || damage?.requiresFullGraphicsReplay == true {
        surface.imageAttachments.isEmpty ? .none : .full
      } else if damage?.graphicsInvalidation.isEmpty == false {
        .targeted
      } else {
        .none
      }
    let replayedAttachments =
      graphicsAttachmentsReplayed
      ?? (defaultGraphicsScope == .none ? 0 : surface.imageAttachments.count)

    guard let damage, !damage.requiresFullTextRepaint else {
      return Self(
        bytesWritten: bytesWritten,
        linesTouched: max(0, surface.size.height),
        cellsChanged: max(0, surface.size.width) * max(0, surface.size.height),
        strategy: .fullRepaint,
        graphicsReplayScope: graphicsReplayScope ?? defaultGraphicsScope,
        graphicsAttachmentsReplayed: replayedAttachments
      )
    }

    let cellsChanged = damage.textRows.reduce(0) { partial, row in
      if row.columnRanges.isEmpty {
        return partial + max(0, surface.size.width)
      }
      return partial
        + row.columnRanges.reduce(0) { rowPartial, range in
          rowPartial + max(0, range.upperBound - range.lowerBound)
        }
    }

    return Self(
      bytesWritten: bytesWritten,
      linesTouched: damage.textRows.count,
      cellsChanged: cellsChanged,
      strategy: .incremental,
      graphicsReplayScope: graphicsReplayScope ?? defaultGraphicsScope,
      graphicsAttachmentsReplayed: replayedAttachments
    )
  }
}

/// Host-facing name for metrics describing a committed presentation frame.
public typealias PresentationMetrics = TerminalPresentationMetrics

/// Abstraction over a presentation target used by `RunLoop`.
///
/// Conformers can be terminal devices that emit ANSI bytes (`TerminalHost`,
/// `WebTerminalHost`), web transports, or pure raster sinks that hand
/// `RasterSurface` values to a non-terminal host such as a SwiftUI canvas.
public protocol PresentationSurface: AnyObject {
  var surfaceSize: CellSize { get }
  var capabilityProfile: TerminalCapabilityProfile { get }
  var appearance: TerminalAppearance { get }
  var theme: Theme? { get }
  var graphicsCapabilities: TerminalGraphicsCapabilities { get }
  var pointerInputCapabilities: PointerInputCapabilities { get }

  func enableRawMode() throws
  func disableRawMode() throws
  func write(_ output: String) throws
  func clearScreen() throws
  func moveCursor(to point: CellPoint) throws
  func setPointerHoverEnabled(_ enabled: Bool) throws
  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics
}

package protocol DamageAwarePresentationSurface: PresentationSurface {
  @discardableResult
  func present(
    _ surface: RasterSurface,
    damage: PresentationDamage?
  ) throws -> TerminalPresentationMetrics
}

/// Capabilities requested by a surface that consumes semantic host frames.
public struct SemanticHostFrameCapabilities: OptionSet, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  /// The surface can use raster damage hints to avoid full repaint work.
  public static let rasterDamage = Self(rawValue: 1 << 0)

  /// The surface consumes the frame's accessibility tree.
  public static let accessibilityTree = Self(rawValue: 1 << 1)

  /// The surface can publish imperative accessibility announcements.
  public static let accessibilityAnnouncements = Self(rawValue: 1 << 2)

  /// The surface consumes interaction regions for host-side routing.
  public static let interactionRouting = Self(rawValue: 1 << 3)

  /// The surface consumes focus regions or focused identity.
  public static let focusRouting = Self(rawValue: 1 << 4)

  /// Default capability set for current semantic host-frame consumers.
  public static let standard: Self = [
    .rasterDamage,
    .accessibilityTree,
    .accessibilityAnnouncements,
    .interactionRouting,
    .focusRouting,
  ]
}

/// A committed raster frame plus the semantic data needed by non-terminal hosts.
///
/// ``sequence`` is monotonically increasing for each runtime producer. Hosts
/// can use it to detect stale asynchronous work without inferring freshness
/// from callback ordering.
///
/// ``rasterDamage`` describes changed raster rows/ranges relative to the
/// previous committed raster frame. It is not a semantic-tree diff.
public struct SemanticHostFrame: Equatable, Sendable {
  public var sequence: UInt64
  public var raster: RasterSurface
  public var semantics: SemanticSnapshot
  public var focusedIdentity: Identity?
  public var rasterDamage: PresentationDamage?

  public init(
    sequence: UInt64,
    raster: RasterSurface,
    semantics: SemanticSnapshot,
    focusedIdentity: Identity?,
    rasterDamage: PresentationDamage? = nil
  ) {
    self.sequence = sequence
    self.raster = raster
    self.semantics = semantics
    self.focusedIdentity = focusedIdentity
    self.rasterDamage = rasterDamage
  }
}

@_spi(Runners)
public protocol SemanticHostFramePresentationSurface:
  PresentationSurface
{
  var semanticHostFrameCapabilities: SemanticHostFrameCapabilities { get }

  @discardableResult
  func present(_ frame: SemanticHostFrame) throws -> PresentationMetrics
}

extension SemanticHostFramePresentationSurface {
  public var semanticHostFrameCapabilities: SemanticHostFrameCapabilities {
    .standard
  }
}

extension PresentationSurface {
  public var theme: Theme? {
    nil
  }

  public var graphicsCapabilities: TerminalGraphicsCapabilities {
    .none
  }

  public var pointerInputCapabilities: PointerInputCapabilities {
    .cellOnly
  }

  public func setPointerHoverEnabled(_: Bool) throws {}

  @discardableResult
  public func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let origin = CellPoint.zero
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
    func windowSize(of fileDescriptor: Int32) throws -> CellSize
    func cellPixelSize(of fileDescriptor: Int32) throws -> PixelSize?
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
    func cellPixelSize(of _: Int32) throws -> PixelSize? {
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

    func windowSize(of fileDescriptor: Int32) throws -> CellSize {
      var windowSize = winsize()
      guard unsafe ioctl(fileDescriptor, UInt(TIOCGWINSZ), &windowSize) == 0 else {
        throw TerminalHostError.failedToReadWindowSize(errno: errno)
      }

      return CellSize(
        width: max(1, Int(windowSize.ws_col)),
        height: max(1, Int(windowSize.ws_row))
      )
    }

    func cellPixelSize(of fileDescriptor: Int32) throws -> PixelSize? {
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
    private let queue = DispatchQueue(label: "swift-tui.presentation-writer")
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

    func submitSupplementalOutput(_ output: String) {
      guard !output.isEmpty else {
        return
      }

      let shouldStart = state.withLock { state in
        guard state.pendingError == nil else {
          return false
        }
        if state.pending != nil {
          state.pending?.output.append(output)
        } else {
          state.pending = .init(output: output)
        }

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
  public final class TerminalHost: PresentationSurface, DamageAwarePresentationSurface,
    ClipboardWritingPresentationSurface, ClipboardReadingPresentationSurface,
    TerminalInputCapabilityProviding,
    TerminalCursorFocusPresentationSurface
  {
    private struct CapabilityProbeState {
      var hasProbedAppearance = false
      var hasProbedGraphicsCapabilities = false
      var cachedGraphicsCapabilities: TerminalGraphicsCapabilities?
      var hasProbedSGRPixelsMode = false
      var cachedSGRPixelsModeSupport: Bool?
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

    public var surfaceSize: CellSize {
      (try? controller.windowSize(of: outputFileDescriptor)) ?? fallbackSize
    }
    public let capabilityProfile: TerminalCapabilityProfile
    public private(set) var appearance: TerminalAppearance
    public var theme: Theme? { nil }
    public var graphicsCapabilities: TerminalGraphicsCapabilities {
      resolvedGraphicsCapabilities(probingProtocols: false)
    }
    public var pointerInputCapabilities: PointerInputCapabilities {
      resolvedPointerInputCapabilities
    }
    package var resolvedInputCapabilities: ResolvedTerminalInputCapabilities {
      ResolvedTerminalInputCapabilities(
        mouseCoordinateMode: activeMouseCoordinateMode,
        pointerInputCapabilities: resolvedPointerInputCapabilities
      )
    }

    private let inputFileDescriptor: Int32
    private let outputFileDescriptor: Int32
    private let fallbackSize: CellSize
    private let controller: any TerminalControlling
    private let environment: [String: String]
    private let mouseInputResolution: TerminalMouseInputResolution
    private let usesTerminalEditOperations: Bool
    private let imageRenderer: TerminalImageRenderer

    private var savedAttributes: termios?
    private var savedInputFileStatusFlags: Int32?
    private var processExitCleanupToken: UInt64?
    private var rawModeEnabled = false
    private var activeMouseCoordinateMode = MouseCoordinateMode.cells
    private var activePointerHoverEnabled = false
    private var capabilityProbe = CapabilityProbeState()
    private var presentationSession = PresentationSession()

    public convenience init(
      inputFileDescriptor: Int32 = 0,
      outputFileDescriptor: Int32 = 1,
      fallbackSize: CellSize = .init(width: 80, height: 24),
      capabilityProfile: TerminalCapabilityProfile? = nil,
      environment: [String: String]? = nil,
      usesTerminalEditOperations: Bool? = nil,
      mouseInputResolution: TerminalMouseInputResolution = .defaultAutomatic
    ) {
      self.init(
        inputFileDescriptor: inputFileDescriptor,
        outputFileDescriptor: outputFileDescriptor,
        fallbackSize: fallbackSize,
        controller: POSIXTerminalController(),
        capabilityProfile: capabilityProfile,
        environment: environment ?? currentProcessEnvironment(),
        usesTerminalEditOperations: usesTerminalEditOperations,
        mouseInputResolution: mouseInputResolution
      )
    }

    package init(
      inputFileDescriptor: Int32,
      outputFileDescriptor: Int32,
      fallbackSize: CellSize,
      controller: any TerminalControlling,
      capabilityProfile: TerminalCapabilityProfile? = nil,
      environment: [String: String]? = nil,
      usesTerminalEditOperations: Bool? = nil,
      mouseInputResolution: TerminalMouseInputResolution = .defaultAutomatic
    ) {
      let environment = environment ?? currentProcessEnvironment()
      self.inputFileDescriptor = inputFileDescriptor
      self.outputFileDescriptor = outputFileDescriptor
      self.fallbackSize = fallbackSize
      self.controller = controller
      self.environment = environment
      self.mouseInputResolution = mouseInputResolution
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

    public convenience init(
      inputFileDescriptor: Int32 = 0,
      outputFileDescriptor: Int32 = 1,
      fallbackSize: CellSize = .init(width: 80, height: 24),
      capabilityProfile: TerminalCapabilityProfile? = nil,
      environment: [String: String]? = nil,
      usesTerminalEditOperations: Bool? = nil,
      pointerPrecisionPolicy: PointerPrecisionPolicy
    ) {
      self.init(
        inputFileDescriptor: inputFileDescriptor,
        outputFileDescriptor: outputFileDescriptor,
        fallbackSize: fallbackSize,
        capabilityProfile: capabilityProfile,
        environment: environment,
        usesTerminalEditOperations: usesTerminalEditOperations,
        mouseInputResolution: pointerPrecisionPolicy.terminalMouseInputResolution
      )
    }

    package convenience init(
      inputFileDescriptor: Int32,
      outputFileDescriptor: Int32,
      fallbackSize: CellSize,
      controller: any TerminalControlling,
      capabilityProfile: TerminalCapabilityProfile? = nil,
      environment: [String: String]? = nil,
      usesTerminalEditOperations: Bool? = nil,
      pointerPrecisionPolicy: PointerPrecisionPolicy
    ) {
      self.init(
        inputFileDescriptor: inputFileDescriptor,
        outputFileDescriptor: outputFileDescriptor,
        fallbackSize: fallbackSize,
        controller: controller,
        capabilityProfile: capabilityProfile,
        environment: environment,
        usesTerminalEditOperations: usesTerminalEditOperations,
        mouseInputResolution: pointerPrecisionPolicy.terminalMouseInputResolution
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
      activeMouseCoordinateMode = resolvedMouseCoordinateMode()
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
          activeMouseCoordinateMode = .cells
          activePointerHoverEnabled = false
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
      if activeMouseCoordinateMode.reportsMouseInput {
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
      let mouseCoordinateModeToDisable = activeMouseCoordinateMode
      let pointerHoverToDisable = activePointerHoverEnabled
      #if !canImport(WASILibc)
        TerminalProcessExitCleanupRegistry.unregister(processExitCleanupToken)
        processExitCleanupToken = nil
      #endif
      self.savedAttributes = nil
      self.savedInputFileStatusFlags = nil
      rawModeEnabled = false
      activeMouseCoordinateMode = .cells
      activePointerHoverEnabled = false
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
      if mouseCoordinateModeToDisable.reportsMouseInput {
        try writeSynchronously(
          disableMouseReportingSequence(
            for: mouseCoordinateModeToDisable,
            hoverEnabled: pointerHoverToDisable
          )
        )
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

    @discardableResult
    @MainActor
    public func writeClipboard(_ text: String) throws -> Bool {
      try write(terminalClipboardSequence(for: text))
      return true
    }

    package func readClipboard() throws -> String? {
      systemClipboardText()
    }

    public func clearScreen() throws {
      try write(clearScreenSequence())
    }

    public func moveCursor(to point: CellPoint) throws {
      try write(cursorSequence(to: point))
    }

    package func presentAccessibilityCursorFocus(at point: CellPoint?) throws {
      let presentationWriter = presentationWriterIfNeeded()
      try presentationWriter.consumePendingError()
      presentationWriter.submitSupplementalOutput(cursorFocusSequence(to: point))
    }

    public func setPointerHoverEnabled(_ enabled: Bool) throws {
      let reportsMouseInput =
        rawModeEnabled
        ? activeMouseCoordinateMode.reportsMouseInput
        : initialConfigurationAllowsMouseReporting
      guard reportsMouseInput else {
        activePointerHoverEnabled = false
        return
      }
      guard activePointerHoverEnabled != enabled else {
        return
      }

      if rawModeEnabled {
        let sequence =
          if enabled {
            enableMouseReportingSequence(hoverEnabled: true)
          } else {
            "\u{001B}[?1003l" + enableMouseReportingSequence(hoverEnabled: false)
          }
        try write(sequence)
      }
      activePointerHoverEnabled = enabled
      refreshProcessExitCleanupRegistration()
    }

    private var initialConfigurationAllowsMouseReporting: Bool {
      guard capabilityProfile.supportsMouseReporting else {
        return false
      }
      if case .preResolved(.disabled) = mouseInputResolution {
        return false
      }
      return true
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
      let origin = CellPoint.zero
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

    private func resolvedMouseCoordinateMode() -> MouseCoordinateMode {
      guard capabilityProfile.supportsMouseReporting else {
        return .disabled
      }

      switch mouseInputResolution {
      case .preResolved(let mode):
        return mouseCoordinateMode(for: mode)
      case .automatic(let policy):
        return automaticMouseCoordinateMode(policy: policy)
      }
    }

    private func mouseCoordinateMode(
      for mode: TerminalMouseInputMode
    ) -> MouseCoordinateMode {
      switch mode {
      case .disabled:
        return .disabled
      case .cell:
        return .cells
      case .sgrPixels(let metrics):
        return .pixels(metrics: metrics, source: .terminalPixels)
      }
    }

    private func automaticMouseCoordinateMode(
      policy: TerminalMouseInputTrustPolicy
    ) -> MouseCoordinateMode {
      guard let metrics = trustedCellPixelMetrics() else {
        return .cells
      }

      if policy == .assumeWhenCellMetricsKnown {
        return .pixels(metrics: metrics, source: .terminalPixels)
      }

      if let liveSupport = probeSGRPixelsModeSupport() {
        return liveSupport ? .pixels(metrics: metrics, source: .terminalPixels) : .cells
      }

      switch policy {
      case .liveProbeOnly:
        return .cells
      case .liveProbeOrDocumentedSupport:
        guard documentedMatrixSupportsSGRPixels(includingKnownCompatible: false) else {
          return .cells
        }
        return .pixels(metrics: metrics, source: .terminalPixels)
      case .liveProbeOrKnownTerminalIdentity:
        guard documentedMatrixSupportsSGRPixels(includingKnownCompatible: true) else {
          return .cells
        }
        return .pixels(metrics: metrics, source: .terminalPixels)
      case .roughTerminalIdentityHeuristics:
        guard roughTerminalIdentitySupportsSGRPixels else {
          return .cells
        }
        return .pixels(metrics: metrics, source: .terminalPixels)
      case .assumeWhenCellMetricsKnown:
        return .pixels(metrics: metrics, source: .terminalPixels)
      }
    }

    private var isInsideTerminalMultiplexer: Bool {
      if environment["TMUX"] != nil {
        return true
      }
      guard let term = environment["TERM"]?.lowercased() else {
        return false
      }
      return term.hasPrefix("screen") || term.hasPrefix("tmux")
    }

    private var resolvedPointerInputCapabilities: PointerInputCapabilities {
      var capabilities = activeMouseCoordinateMode.pointerInputCapabilities
      capabilities.supportsHover = activeMouseCoordinateMode.reportsMouseInput
      return capabilities
    }

    private func documentedMatrixSupportsSGRPixels(
      includingKnownCompatible: Bool
    ) -> Bool {
      guard !isInsideTerminalMultiplexer else {
        return false
      }
      let matrix =
        includingKnownCompatible
        ? TerminalMouseInputCompatibilityMatrix.knownCompatible
        : TerminalMouseInputCompatibilityMatrix.documentedSupport
      return matrix.supportingSGRPixels(
        environment: environment,
        includingKnownCompatible: includingKnownCompatible
      ) != nil
    }

    private var roughTerminalIdentitySupportsSGRPixels: Bool {
      if documentedMatrixSupportsSGRPixels(includingKnownCompatible: true) {
        return true
      }
      guard !isInsideTerminalMultiplexer else {
        return false
      }
      let identityValues = [
        environment["TERM"],
        environment["TERM_PROGRAM"],
        environment["LC_TERMINAL"],
        environment["COLORTERM"],
      ]
      .compactMap { $0?.lowercased() }
      let roughMarkers = [
        "ghostty",
        "alacritty",
        "rio",
        "contour",
        "xterm.js",
        "xtermjs",
      ]
      return identityValues.contains { identity in
        roughMarkers.contains { marker in
          identity.contains(marker)
        }
      }
    }

    private func trustedCellPixelMetrics() -> CellPixelMetrics? {
      guard let cellPixelSize = baselineGraphicsCapabilities().cellPixelSize else {
        return nil
      }
      return CellPixelMetrics(
        width: max(1, cellPixelSize.width),
        height: max(1, cellPixelSize.height),
        source: .reported
      )
    }

    private func probeSGRPixelsModeSupport() -> Bool? {
      if capabilityProbe.hasProbedSGRPixelsMode {
        return capabilityProbe.cachedSGRPixelsModeSupport
      }
      capabilityProbe.hasProbedSGRPixelsMode = true

      guard controller.isATTY(outputFileDescriptor) else {
        capabilityProbe.cachedSGRPixelsModeSupport = nil
        return nil
      }

      let response =
        (try? performInputCapabilityQuery(.decPrivateMode(mode: 1016))) ?? []
      guard let state = parseDECPrivateModeReport(from: response, mode: 1016) else {
        capabilityProbe.cachedSGRPixelsModeSupport = nil
        return nil
      }

      let supported = state.canEnable
      capabilityProbe.cachedSGRPixelsModeSupport = supported
      return supported
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

    private func performInputCapabilityQuery(
      _ query: TerminalInputCapabilityQuery
    ) throws -> [UInt8] {
      try writeSynchronously(query.request)
      var buffer: [UInt8] = []

      for iteration in 0..<4 {
        let timeoutMilliseconds = iteration == 0 ? 40 : 20
        let bytes = try controller.read(
          from: inputFileDescriptor,
          maxBytes: 512,
          timeoutMilliseconds: timeoutMilliseconds
        )
        if bytes.isEmpty {
          break
        }
        buffer.append(contentsOf: bytes)

        switch query {
        case .decPrivateMode(let mode):
          if parseDECPrivateModeReport(from: buffer, mode: mode) != nil {
            return buffer
          }
        }
      }

      return buffer
    }

    private func performGraphicsQuery(
      _ query: TerminalGraphicsQuery
    ) throws -> [UInt8] {
      try writeSynchronously(query.request)
      var buffer: [UInt8] = []
      // The kitty/DA combined probe is the one we cannot afford to give up
      // on early. A modern terminal usually replies in microseconds, but
      // `swift run` cold starts, system load, and PTY scheduling can push
      // the first byte well past 40ms. Quitting the read loop the moment
      // a single poll returns empty made the protocol detection
      // non-deterministic across runs of the same binary in the same
      // terminal — sometimes kitty was detected, sometimes the renderer
      // fell back to the dithered half-block path. Use a longer total
      // budget for the kitty probe and never break early on it; for the
      // narrower follow-up queries (sixel registers, cell pixels) we
      // already know the terminal is responsive, so the original
      // break-on-empty heuristic still applies.
      let initialTimeoutMilliseconds: Int
      let followUpTimeoutMilliseconds = 40
      let breaksOnEmptyRead: Bool
      let maxIterations: Int
      switch query {
      case .kittySupport:
        initialTimeoutMilliseconds = 250
        breaksOnEmptyRead = false
        maxIterations = 8
      default:
        initialTimeoutMilliseconds = 40
        breaksOnEmptyRead = true
        maxIterations = 6
      }

      for iteration in 0..<maxIterations {
        let timeoutMilliseconds =
          iteration == 0 ? initialTimeoutMilliseconds : followUpTimeoutMilliseconds
        let bytes = try controller.read(
          from: inputFileDescriptor,
          maxBytes: 512,
          timeoutMilliseconds: timeoutMilliseconds
        )
        if bytes.isEmpty {
          if breaksOnEmptyRead {
            break
          }
          continue
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
      enableMouseReportingSequence(hoverEnabled: activePointerHoverEnabled)
    }

    private func enableMouseReportingSequence(hoverEnabled: Bool) -> String {
      var sequence = "\u{001B}[?1006h"
      if activeMouseCoordinateMode.usesTerminalPixels {
        sequence += "\u{001B}[?1016h"
      }
      sequence += "\u{001B}[?1002h"
      if hoverEnabled {
        sequence += "\u{001B}[?1003h"
      }
      return sequence
    }

    private func disableMouseReportingSequence(
      for mouseCoordinateMode: MouseCoordinateMode,
      hoverEnabled: Bool
    ) -> String {
      var sequence = hoverEnabled ? "\u{001B}[?1003l" : ""
      sequence += "\u{001B}[?1002l"
      if mouseCoordinateMode.usesTerminalPixels {
        sequence += "\u{001B}[?1016l\u{001B}[?1006l"
      } else {
        sequence += "\u{001B}[?1006l"
      }
      return sequence
    }

    private func processExitResetSequence() -> String {
      var reset = ""
      if activeMouseCoordinateMode.reportsMouseInput {
        reset += disableMouseReportingSequence(
          for: activeMouseCoordinateMode,
          hoverEnabled: activePointerHoverEnabled
        )
      }
      reset += "\u{001B}[?2004l"  // disable bracketed paste
      reset += showCursorSequence()
      reset += resetStyleSequence()
      reset += exitAlternateScreenSequence()
      return reset
    }

    private func refreshProcessExitCleanupRegistration() {
      guard rawModeEnabled,
        let savedAttributes,
        let savedInputFileStatusFlags
      else {
        return
      }

      #if !canImport(WASILibc)
        TerminalProcessExitCleanupRegistry.unregister(processExitCleanupToken)
        processExitCleanupToken = TerminalProcessExitCleanupRegistry.register(
          .init(
            inputFileDescriptor: inputFileDescriptor,
            outputFileDescriptor: outputFileDescriptor,
            inputFileStatusFlags: savedInputFileStatusFlags,
            savedAttributes: savedAttributes,
            resetBytes: Array(processExitResetSequence().utf8)
          )
        )
      #endif
    }

    private func resetStyleSequence() -> String {
      "\u{001B}[0m"
    }

    private func cursorSequence(to point: CellPoint) -> String {
      let row = max(1, point.y + 1)
      let column = max(1, point.x + 1)
      return "\u{001B}[\(row);\(column)H"
    }

    private func cursorFocusSequence(to point: CellPoint?) -> String {
      guard let point else {
        return hideCursorSequence()
      }
      return cursorSequence(to: point) + showCursorSequence()
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
  public final class WebTerminalHost: PresentationSurface, ClipboardWritingPresentationSurface,
    ClipboardReadingPresentationSurface, TerminalCursorFocusPresentationSurface, Sendable
  {
    private struct State {
      var surfaceSize: CellSize
      var renderStyle: TerminalRenderStyle
    }

    private let state: Mutex<State>
    private let outputFD: Int32
    private let writeLock = Mutex(())

    public let capabilityProfile: TerminalCapabilityProfile
    public let graphicsCapabilities: TerminalGraphicsCapabilities

    public convenience init(
      surfaceSize: CellSize,
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
      surfaceSize: CellSize,
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

    public var surfaceSize: CellSize {
      state.withLock(\.surfaceSize)
    }

    public var appearance: TerminalAppearance {
      state.withLock(\.renderStyle.appearance)
    }

    public var theme: Theme? {
      state.withLock(\.renderStyle.theme)
    }

    public func updateSurfaceSize(_ surfaceSize: CellSize) {
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

    @discardableResult
    @MainActor
    public func writeClipboard(_ text: String) throws -> Bool {
      try write(terminalClipboardSequence(for: text))
      return true
    }

    package func readClipboard() throws -> String? {
      nil
    }

    public func clearScreen() throws {
      try write("\u{001B}[2J")
    }

    public func moveCursor(to point: CellPoint) throws {
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
      "\u{001B}[?1006h\u{001B}[?1002h"
    }

    private func disableMouseReportingSequence() -> String {
      "\u{001B}[?1002l\u{001B}[?1006l"
    }

    private func resetStyleSequence() -> String {
      "\u{001B}[0m"
    }

    private func cursorSequence(to point: CellPoint) -> String {
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
  origin: CellPoint = .zero
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
  origin: CellPoint
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
  to point: CellPoint
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
