import SwiftTUICore
import Synchronization

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(WASILibc)
  import WASILibc
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

#if !canImport(WASILibc)
  /// Default terminal-backed host that owns raw mode and screen presentation.
  public final class TerminalHost: PresentationSurface, DamageAwarePresentationSurface,
    ClipboardWritingPresentationSurface, ClipboardReadingPresentationSurface,
    TerminalInputCapabilityProviding,
    TerminalCursorFocusPresentationSurface
  {
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

    let inputFileDescriptor: Int32
    let outputFileDescriptor: Int32
    private let fallbackSize: CellSize
    let controller: any TerminalControlling
    let environment: [String: String]
    let mouseInputResolution: TerminalMouseInputResolution
    private let usesTerminalEditOperations: Bool
    private let imageRenderer: TerminalImageRenderer

    private var rawModeSession = TerminalRawModeSession()
    var activeMouseCoordinateMode: MouseCoordinateMode {
      rawModeSession.mouseCoordinateMode
    }
    var capabilityProbe = TerminalHostCapabilityProbeState()
    private var presentationSession = TerminalPresentationSession()

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
      guard !rawModeSession.isEnabled else {
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
      rawModeSession.activate(
        savedAttributes: currentAttributes,
        inputFileStatusFlags: currentFileStatusFlags,
        mouseCoordinateMode: resolvedMouseCoordinateMode(),
        inputFileDescriptor: inputFileDescriptor,
        outputFileDescriptor: outputFileDescriptor
      )
      presentationSession.reset()

      var shouldRestoreOnFailure = true
      defer {
        if shouldRestoreOnFailure {
          let restorePlan = rawModeSession.deactivate()
          presentationSession.reset()
          if let savedInputFileStatusFlags = restorePlan.savedInputFileStatusFlags {
            try? controller.setFileStatusFlags(
              savedInputFileStatusFlags,
              on: inputFileDescriptor
            )
          }
          if let savedAttributes = restorePlan.savedAttributes {
            try? controller.setAttributes(savedAttributes, on: inputFileDescriptor)
          }
        }
      }

      refreshAppearanceIfNeeded()
      try write(TerminalHostEscapeSequences.enterAlternateScreen)
      try write(TerminalHostEscapeSequences.clearScreen)
      try write(TerminalHostEscapeSequences.cursor(to: .zero))
      try write(TerminalHostEscapeSequences.hideCursor)
      if rawModeSession.mouseCoordinateMode.reportsMouseInput {
        try write(
          TerminalHostEscapeSequences.enableMouseReporting(
            mouseCoordinateMode: rawModeSession.mouseCoordinateMode,
            hoverEnabled: rawModeSession.pointerHoverEnabled
          )
        )
      }
      try write(TerminalHostEscapeSequences.enableBracketedPaste)
      shouldRestoreOnFailure = false
    }

    public func disableRawMode() throws {
      guard rawModeSession.isEnabled else {
        return
      }

      let presentationWriter = presentationSession.writer
      let restorePlan = rawModeSession.deactivate()
      presentationSession.reset()

      var attributesToRestore = restorePlan.savedAttributes
      var fileStatusFlagsToRestore = restorePlan.savedInputFileStatusFlags
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

      try writeSynchronously(TerminalHostEscapeSequences.clearScreen)
      try writeSynchronously(TerminalHostEscapeSequences.cursor(to: .zero))
      if restorePlan.mouseCoordinateMode.reportsMouseInput {
        try writeSynchronously(
          TerminalHostEscapeSequences.disableMouseReporting(
            mouseCoordinateMode: restorePlan.mouseCoordinateMode,
            hoverEnabled: restorePlan.pointerHoverEnabled
          )
        )
      }
      try writeSynchronously(TerminalHostEscapeSequences.disableBracketedPaste)
      try writeSynchronously(TerminalHostEscapeSequences.resetStyle)
      try writeSynchronously(TerminalHostEscapeSequences.showCursor)
      try writeSynchronously(TerminalHostEscapeSequences.exitAlternateScreen)

      if let savedInputFileStatusFlags = restorePlan.savedInputFileStatusFlags {
        try controller.setFileStatusFlags(savedInputFileStatusFlags, on: inputFileDescriptor)
        fileStatusFlagsToRestore = nil
      }
      if let savedAttributes = restorePlan.savedAttributes {
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
      try write(TerminalHostEscapeSequences.clearScreen)
    }

    public func moveCursor(to point: CellPoint) throws {
      try write(TerminalHostEscapeSequences.cursor(to: point))
    }

    package func presentAccessibilityCursorFocus(at point: CellPoint?) throws {
      let presentationWriter = presentationWriterIfNeeded()
      try presentationWriter.consumePendingError()
      presentationWriter.submitSupplementalOutput(
        TerminalHostEscapeSequences.cursorFocus(to: point)
      )
    }

    public func setPointerHoverEnabled(_ enabled: Bool) throws {
      let reportsMouseInput =
        rawModeSession.isEnabled
        ? rawModeSession.mouseCoordinateMode.reportsMouseInput
        : initialConfigurationAllowsMouseReporting
      guard reportsMouseInput else {
        rawModeSession.pointerHoverEnabled = false
        return
      }
      guard rawModeSession.pointerHoverEnabled != enabled else {
        return
      }

      if rawModeSession.isEnabled {
        let sequence =
          if enabled {
            TerminalHostEscapeSequences.enableMouseReporting(
              mouseCoordinateMode: rawModeSession.mouseCoordinateMode,
              hoverEnabled: true
            )
          } else {
            TerminalHostEscapeSequences.disableAllMouseMotion
              + TerminalHostEscapeSequences.enableMouseReporting(
                mouseCoordinateMode: rawModeSession.mouseCoordinateMode,
                hoverEnabled: false
              )
          }
        try write(sequence)
      }
      rawModeSession.pointerHoverEnabled = enabled
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

      let emission = TerminalHostPresentationEmissionBuilder(
        capabilityProfile: capabilityProfile,
        usesTerminalEditOperations: usesTerminalEditOperations,
        imageRenderer: imageRenderer
      ).build(
        for: preparedSurface,
        plan: plan,
        graphicsCapabilities: graphicsCapabilities,
        transmittedKittyImages: &presentationSession.transmittedKittyImages
      )
      let usedSynchronizedOutput = TerminalHostEscapeSequences.usesSynchronizedOutput(
        for: emission.output,
        strategy: plan.strategy,
        capabilityProfile: capabilityProfile
      )
      let bufferedOutput = TerminalHostEscapeSequences.wrappedSynchronizedOutput(
        emission.output,
        strategy: plan.strategy,
        capabilityProfile: capabilityProfile
      )

      if !bufferedOutput.isEmpty {
        presentationWriterIfNeeded().submit(
          .init(
            output: bufferedOutput
          )
        )
      }

      presentationSession.lastSubmittedSurface = preparedSurface

      return emission.metrics(
        for: plan,
        output: bufferedOutput,
        usedSynchronizedOutput: usedSynchronizedOutput
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

    private func presentationWriterIfNeeded() -> TerminalPresentationWriter {
      if let presentationWriter = presentationSession.writer {
        return presentationWriter
      }

      let presentationWriter = TerminalPresentationWriter(
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

    private func refreshProcessExitCleanupRegistration() {
      rawModeSession.refreshProcessExitCleanupRegistration(
        inputFileDescriptor: inputFileDescriptor,
        outputFileDescriptor: outputFileDescriptor
      )
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
      var setup = TerminalHostEscapeSequences.enterAlternateScreen
      setup += TerminalHostEscapeSequences.hideCursor
      if capabilityProfile.supportsMouseReporting {
        setup += TerminalHostEscapeSequences.enableMouseReporting(
          mouseCoordinateMode: .cells,
          hoverEnabled: false
        )
      }
      setup += TerminalHostEscapeSequences.enableBracketedPaste
      try write(setup)
    }

    public func disableRawMode() throws {
      var teardown = ""
      if capabilityProfile.supportsMouseReporting {
        teardown += TerminalHostEscapeSequences.disableMouseReporting(
          mouseCoordinateMode: .cells,
          hoverEnabled: false
        )
      }
      teardown += TerminalHostEscapeSequences.disableBracketedPaste
      teardown += TerminalHostEscapeSequences.showCursor
      teardown += TerminalHostEscapeSequences.resetStyle
      teardown += TerminalHostEscapeSequences.exitAlternateScreen
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
      try write(TerminalHostEscapeSequences.clearScreen)
    }

    public func moveCursor(to point: CellPoint) throws {
      try write(TerminalHostEscapeSequences.cursor(to: point))
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
            return unsafe terminalPlatformWrite(
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
  output += TerminalHostEscapeSequences.clearScreen
  output += TerminalHostEscapeSequences.cursor(to: origin)
  for writeStep in writeSteps {
    output += writeStep
  }
  return output
}

func fullRepaintBytesWritten(
  writeSteps: [String],
  origin: CellPoint
) -> Int {
  let cursorSequence = TerminalHostEscapeSequences.cursor(to: origin)
  return TerminalHostEscapeSequences.clearScreen.utf8.count
    + cursorSequence.utf8.count
    + writeSteps.reduce(0) { partial, writeStep in
      partial + writeStep.utf8.count
    }
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
