import Core
import Synchronization

#if canImport(Darwin)
  package import Darwin
#elseif canImport(Glibc)
  package import Glibc
#elseif canImport(Android)
  package import Android
#elseif canImport(WASILibc)
  package import WASILibc
#endif

#if canImport(Darwin)
  private func platformWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    Darwin.write(fileDescriptor, buffer, count)
  }

  private func platformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    Darwin.read(fileDescriptor, buffer, count)
  }

  private func platformPoll(
    _ descriptors: UnsafeMutablePointer<pollfd>?,
    _ count: nfds_t,
    _ timeoutMilliseconds: Int32
  ) -> Int32 {
    Darwin.poll(descriptors, count, timeoutMilliseconds)
  }
#elseif canImport(Glibc)
  private func platformWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    Glibc.write(fileDescriptor, buffer, count)
  }

  private func platformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    Glibc.read(fileDescriptor, buffer, count)
  }

  private func platformPoll(
    _ descriptors: UnsafeMutablePointer<pollfd>?,
    _ count: nfds_t,
    _ timeoutMilliseconds: Int32
  ) -> Int32 {
    Glibc.poll(descriptors, count, timeoutMilliseconds)
  }
#elseif canImport(Android)
  private func platformWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    Android.write(fileDescriptor, buffer, count)
  }

  private func platformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    Android.read(fileDescriptor, buffer, count)
  }

  private func platformPoll(
    _ descriptors: UnsafeMutablePointer<pollfd>?,
    _ count: nfds_t,
    _ timeoutMilliseconds: Int32
  ) -> Int32 {
    Android.poll(descriptors, count, timeoutMilliseconds)
  }
#elseif canImport(WASILibc)
  private func platformWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    Int(WASILibc.write(fileDescriptor, buffer, count))
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

  public var bytesWritten: Int
  public var linesTouched: Int
  public var cellsChanged: Int
  public var strategy: Strategy

  public init(
    bytesWritten: Int = 0,
    linesTouched: Int = 0,
    cellsChanged: Int = 0,
    strategy: Strategy = .fullRepaint
  ) {
    self.bytesWritten = max(0, bytesWritten)
    self.linesTouched = max(0, linesTouched)
    self.cellsChanged = max(0, cellsChanged)
    self.strategy = strategy
  }

  public var usedFullRepaint: Bool {
    strategy == .fullRepaint
  }

  static func fullRepaint(
    for surface: RasterSurface,
    renderedOutput: String,
    origin: Point = .zero
  ) -> Self {
    let clearSequence = "\u{001B}[2J"
    let cursorSequence = "\u{001B}[\(max(1, origin.y + 1));\(max(1, origin.x + 1))H"
    let cellCount = max(0, surface.size.width) * max(0, surface.size.height)

    return Self(
      bytesWritten: clearSequence.utf8.count + cursorSequence.utf8.count
        + renderedOutput.utf8.count,
      linesTouched: max(0, surface.size.height),
      cellsChanged: cellCount,
      strategy: .fullRepaint
    )
  }
}

/// Abstraction over a terminal device used by `RunLoop`.
public protocol TerminalHosting: AnyObject {
  var surfaceSize: Size { get }
  var capabilityProfile: TerminalCapabilityProfile { get }
  var appearance: TerminalAppearance { get }
  var graphicsCapabilities: TerminalGraphicsCapabilities { get }

  func enableRawMode() throws
  func disableRawMode() throws
  func write(_ output: String) throws
  func clearScreen() throws
  func moveCursor(to point: Point) throws
  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics
}

extension TerminalHosting {
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
  package protocol TerminalControlling {
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
      guard tcgetattr(fileDescriptor, &attributes) == 0 else {
        throw TerminalHostError.failedToReadAttributes(errno: errno)
      }
      return attributes
    }

    func setAttributes(_ attributes: termios, on fileDescriptor: Int32) throws {
      var attributes = attributes
      guard tcsetattr(fileDescriptor, TCSAFLUSH, &attributes) == 0 else {
        throw TerminalHostError.failedToSetAttributes(errno: errno)
      }
    }

    func windowSize(of fileDescriptor: Int32) throws -> Size {
      var windowSize = winsize()
      guard ioctl(fileDescriptor, UInt(TIOCGWINSZ), &windowSize) == 0 else {
        throw TerminalHostError.failedToReadWindowSize(errno: errno)
      }

      return Size(
        width: max(1, Int(windowSize.ws_col)),
        height: max(1, Int(windowSize.ws_row))
      )
    }

    func cellPixelSize(of fileDescriptor: Int32) throws -> Size? {
      var windowSize = winsize()
      guard ioctl(fileDescriptor, UInt(TIOCGWINSZ), &windowSize) == 0 else {
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

      try bytes.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else {
          return
        }

        var bytesWritten = 0
        while bytesWritten < totalBytes {
          let pointer = baseAddress.advanced(by: bytesWritten)
          let result = platformWrite(
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
      let ready = platformPoll(
        &descriptor,
        1,
        Int32(timeoutMilliseconds)
      )

      guard ready > 0 else {
        return []
      }

      var buffer = Array(repeating: UInt8(0), count: maxBytes)
      let bytesRead = platformRead(fileDescriptor, &buffer, maxBytes)
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
        let ready = platformPoll(&descriptor, 1, -1)
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

  /// Default terminal-backed host that owns raw mode and screen presentation.
  public final class TerminalHost: TerminalHosting {
    public var surfaceSize: Size {
      (try? controller.windowSize(of: outputFileDescriptor)) ?? fallbackSize
    }
    public let capabilityProfile: TerminalCapabilityProfile
    public private(set) var appearance: TerminalAppearance
    public var graphicsCapabilities: TerminalGraphicsCapabilities {
      resolvedGraphicsCapabilities(probingProtocols: false)
    }

    private let inputFileDescriptor: Int32
    private let outputFileDescriptor: Int32
    private let fallbackSize: Size
    private let controller: any TerminalControlling
    private let environment: [String: String]
    private let imageRenderer: TerminalImageRenderer

    private var savedAttributes: termios?
    private var savedInputFileStatusFlags: Int32?
    private var rawModeEnabled = false
    private var hasProbedAppearance = false
    private var hasProbedGraphicsCapabilities = false
    private var cachedGraphicsCapabilities: TerminalGraphicsCapabilities?
    private var lastPresentedSurface: RasterSurface?
    private var transmittedKittyImages: Set<UInt32> = []

    public convenience init(
      inputFileDescriptor: Int32 = 0,
      outputFileDescriptor: Int32 = 1,
      fallbackSize: Size = .init(width: 80, height: 24),
      capabilityProfile: TerminalCapabilityProfile? = nil,
      environment: [String: String]? = nil
    ) {
      self.init(
        inputFileDescriptor: inputFileDescriptor,
        outputFileDescriptor: outputFileDescriptor,
        fallbackSize: fallbackSize,
        controller: POSIXTerminalController(),
        capabilityProfile: capabilityProfile,
        environment: environment ?? currentProcessEnvironment()
      )
    }

    package init(
      inputFileDescriptor: Int32,
      outputFileDescriptor: Int32,
      fallbackSize: Size,
      controller: any TerminalControlling,
      capabilityProfile: TerminalCapabilityProfile? = nil,
      environment: [String: String]? = nil
    ) {
      let environment = environment ?? currentProcessEnvironment()
      self.inputFileDescriptor = inputFileDescriptor
      self.outputFileDescriptor = outputFileDescriptor
      self.fallbackSize = fallbackSize
      self.controller = controller
      self.environment = environment
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
      cfmakeraw(&rawAttributes)
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
      rawModeEnabled = true
      lastPresentedSurface = nil
      transmittedKittyImages.removeAll()

      var shouldRestoreOnFailure = true
      defer {
        if shouldRestoreOnFailure {
          let savedInputFileStatusFlags = self.savedInputFileStatusFlags
          savedAttributes = nil
          self.savedInputFileStatusFlags = nil
          rawModeEnabled = false
          lastPresentedSurface = nil
          transmittedKittyImages.removeAll()
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
      shouldRestoreOnFailure = false
    }

    public func disableRawMode() throws {
      guard rawModeEnabled else {
        return
      }

      let savedAttributes = self.savedAttributes
      let savedInputFileStatusFlags = self.savedInputFileStatusFlags
      self.savedAttributes = nil
      self.savedInputFileStatusFlags = nil
      rawModeEnabled = false
      lastPresentedSurface = nil
      transmittedKittyImages.removeAll()

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

      try write(clearScreenSequence())
      try write(cursorSequence(to: .zero))
      if capabilityProfile.supportsMouseReporting {
        try write(disableMouseReportingSequence())
      }
      try write(resetStyleSequence())
      try write(showCursorSequence())
      try write(exitAlternateScreenSequence())

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
      try controller.write(output, to: outputFileDescriptor)
    }

    public func clearScreen() throws {
      try write(clearScreenSequence())
    }

    public func moveCursor(to point: Point) throws {
      try write(cursorSequence(to: point))
    }

    @discardableResult
    public func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
      let graphicsCapabilities = resolvedGraphicsCapabilities(
        probingProtocols: !surface.imageAttachments.isEmpty
      )
      let preparedSurface = imageRenderer.preparedSurface(
        for: surface,
        capabilityProfile: capabilityProfile,
        graphicsCapabilities: graphicsCapabilities
      )
      let plan = TerminalPresentationPlanner(
        capabilityProfile: capabilityProfile
      ).plan(
        previousSurface: lastPresentedSurface,
        currentSurface: preparedSurface
      )

      var bytesWritten = 0
      let origin = Point.zero
      var bufferedOutput = String()

      func append(_ output: String) {
        bufferedOutput.append(output)
        bytesWritten += output.utf8.count
      }

      switch plan.strategy {
      case .fullRepaint:
        append(clearScreenSequence())
        append(cursorSequence(to: origin))

        for writeStep in fullRepaintWriteSteps(
          for: preparedSurface,
          capabilityProfile: capabilityProfile
        ) {
          append(writeStep)
        }

        for writeStep in imageRenderer.graphicsWriteSteps(
          for: preparedSurface,
          capabilityProfile: capabilityProfile,
          graphicsCapabilities: graphicsCapabilities,
          transmittedKittyImages: &transmittedKittyImages
        ) {
          append(writeStep)
        }

      case .incremental:
        for spanUpdate in plan.spanUpdates {
          append(
            cursorSequence(
              to: .init(x: spanUpdate.column, y: spanUpdate.row)
            )
          )
          append(spanUpdate.renderedSpan)
        }
      }

      if !bufferedOutput.isEmpty {
        try write(bufferedOutput)
      }

      lastPresentedSurface = preparedSurface

      return TerminalPresentationMetrics(
        bytesWritten: bytesWritten,
        linesTouched: plan.linesTouched,
        cellsChanged: plan.cellsChanged,
        strategy: plan.strategy == .fullRepaint ? .fullRepaint : .incremental
      )
    }

    private func refreshAppearanceIfNeeded() {
      guard !hasProbedAppearance else {
        return
      }
      hasProbedAppearance = true

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
      try controller.write(query.request, to: outputFileDescriptor)
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
      var capabilities = cachedGraphicsCapabilities ?? .none
      if capabilities.cellPixelSize == nil {
        capabilities.cellPixelSize = try? controller.cellPixelSize(of: outputFileDescriptor)
      }
      cachedGraphicsCapabilities = capabilities
      return capabilities
    }

    private func probeGraphicsCapabilitiesIfNeeded() -> TerminalGraphicsCapabilities {
      if hasProbedGraphicsCapabilities {
        return baselineGraphicsCapabilities()
      }
      hasProbedGraphicsCapabilities = true

      var capabilities = baselineGraphicsCapabilities()
      guard controller.isATTY(outputFileDescriptor) else {
        cachedGraphicsCapabilities = capabilities
        return capabilities
      }

      // FIXME: Kitty image protocol support does not function.
      // let kittyQueryID = stableIdentifier(from: Array("stui-kitty-query".utf8))
      // if let kittyResponse = try? performGraphicsQuery(.kittySupport(id: kittyQueryID)),
      //   parseKittySupportResponse(in: kittyResponse, id: kittyQueryID) == true,
      //   !capabilities.supportedProtocols.contains(.kitty)
      // {
      //   capabilities.supportedProtocols.append(.kitty)
      // }

      if let deviceAttributesResponse = try? performGraphicsQuery(.primaryDeviceAttributes),
        let attributes = parsePrimaryDeviceAttributes(from: deviceAttributesResponse),
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

      cachedGraphicsCapabilities = capabilities
      return capabilities
    }

    private func performGraphicsQuery(
      _ query: TerminalGraphicsQuery
    ) throws -> [UInt8] {
      try controller.write(query.request, to: outputFileDescriptor)
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
        case .kittySupport(let id):
          if parseKittySupportResponse(in: buffer, id: id) != nil {
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
#else
  public final class WebTerminalHost: TerminalHosting, @unchecked Sendable {
    private struct State {
      var surfaceSize: Size
      var appearance: TerminalAppearance
    }

    private let state: Mutex<State>
    private let outputFD: Int32
    private let writeLock = Mutex(())

    public let capabilityProfile: TerminalCapabilityProfile
    public let graphicsCapabilities: TerminalGraphicsCapabilities

    public init(
      surfaceSize: Size,
      outputFileDescriptor: Int32 = STDOUT_FILENO,
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
          appearance: appearance
        )
      )
    }

    public var surfaceSize: Size {
      state.withLock(\.surfaceSize)
    }

    public var appearance: TerminalAppearance {
      state.withLock(\.appearance)
    }

    public func updateSurfaceSize(_ surfaceSize: Size) {
      state.withLock { state in
        state.surfaceSize = surfaceSize
      }
    }

    public func enableRawMode() throws {
      var setup = enterAlternateScreenSequence()
      setup += hideCursorSequence()
      if capabilityProfile.supportsMouseReporting {
        setup += enableMouseReportingSequence()
      }
      try write(setup)
    }

    public func disableRawMode() throws {
      var teardown = ""
      if capabilityProfile.supportsMouseReporting {
        teardown += disableMouseReportingSequence()
      }
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
          let result = bytes.withUnsafeBytes { rawBuffer in
            let baseAddress = rawBuffer.baseAddress?.advanced(by: written)
            return platformWrite(
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

private func fullRepaintWriteSteps(
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

private func fullRepaintBytesWritten(
  writeSteps: [String],
  origin: Point
) -> Int {
  let clearSequence = "\u{001B}[2J"
  let cursorSequence = "\u{001B}[\(max(1, origin.y + 1));\(max(1, origin.x + 1))H"
  return clearSequence.utf8.count
    + cursorSequence.utf8.count
    + writeSteps.reduce(0) { partial, writeStep in
      partial + writeStep.utf8.count
    }
}

private func currentProcessEnvironment() -> [String: String] {
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
    let processEnvironment = environ
    var index = 0

    while let entry = processEnvironment[index] {
      defer { index += 1 }

      guard let assignment = String(validatingCString: entry),
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
    key.withCString { cKey in
      guard let rawValue = getenv(cKey) else {
        return nil
      }
      return String(cString: rawValue)
    }
  }
#endif
