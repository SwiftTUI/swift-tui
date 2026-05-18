import SwiftTUICore

#if !canImport(WASILibc)
  struct TerminalHostCapabilityProbeState {
    var hasProbedAppearance = false
    var hasProbedGraphicsCapabilities = false
    var cachedGraphicsCapabilities: TerminalGraphicsCapabilities?
    var hasProbedSGRPixelsMode = false
    var cachedSGRPixelsModeSupport: Bool?
  }

  extension TerminalHost {
    func resolvedGraphicsCapabilities(
      probingProtocols: Bool
    ) -> TerminalGraphicsCapabilities {
      if probingProtocols {
        return probeGraphicsCapabilitiesIfNeeded()
      }
      return baselineGraphicsCapabilities()
    }

    func resolvedMouseCoordinateMode() -> MouseCoordinateMode {
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

    var resolvedPointerInputCapabilities: PointerInputCapabilities {
      var capabilities = activeMouseCoordinateMode.pointerInputCapabilities
      capabilities.supportsHover = activeMouseCoordinateMode.reportsMouseInput
      return capabilities
    }

    private func baselineGraphicsCapabilities() -> TerminalGraphicsCapabilities {
      var capabilities = capabilityProbe.cachedGraphicsCapabilities ?? .none
      // Always attempt a fresh ioctl read. The syscall is cheap and its result
      // is authoritative when the kernel reports pixel dimensions. Fall back to
      // the cached value only when the fresh read returns nil; this preserves
      // previously probed escape-sequence values across frames.
      if let fresh = try? controller.cellPixelSize(of: outputFileDescriptor) {
        capabilities.cellPixelSize = fresh
      }
      capabilityProbe.cachedGraphicsCapabilities = capabilities
      return capabilities
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
      try controller.write(query.request, to: outputFileDescriptor)
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
      try controller.write(query.request, to: outputFileDescriptor)
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
      var kittyProbeSawPrimaryDeviceAttributes = false
      var kittyProbeEmptyReadsAfterPrimaryDeviceAttributes = 0
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
          if kittyProbeSawPrimaryDeviceAttributes {
            kittyProbeEmptyReadsAfterPrimaryDeviceAttributes += 1
            if kittyProbeEmptyReadsAfterPrimaryDeviceAttributes >= 2 {
              return buffer
            }
          }
          continue
        }
        buffer.append(contentsOf: bytes)

        switch query {
        case .kittySupport(let id):
          // The kitty probe request piggybacks a `\e[c` primary-device-
          // attributes query after the kitty query so non-kitty terminals
          // still produce a response we can synchronize on. We wait for the
          // Kitty response itself when it exists; some terminals deliver the
          // DA reply before the Kitty OK, and returning on DA alone caches a
          // false "no Kitty" result for the entire session.
          if parseKittySupportResponse(in: buffer, id: id) == true {
            return buffer
          }
          if parsePrimaryDeviceAttributes(from: buffer) != nil {
            kittyProbeSawPrimaryDeviceAttributes = true
            kittyProbeEmptyReadsAfterPrimaryDeviceAttributes = 0
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
  }
#endif
