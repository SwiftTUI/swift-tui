import SwiftTUICore

#if !canImport(WASILibc)
  struct TerminalHostCapabilityProbeState {
    var hasProbedAppearance = false
    var hasProbedGraphicsCapabilities = false
    var cachedGraphicsCapabilities: TerminalGraphicsCapabilities?
    var hasProbedSGRPixelsMode = false
    var cachedSGRPixelsModeSupport: Bool?
    var hasProbedKittyKeyboardSupport = false
    var cachedKittyKeyboardSupport = false
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

    // Visibility note: `baselineGraphicsCapabilities()` is referenced by mouse
    // coordinate-mode resolution in `TerminalMouseCoordinateResolution.swift`,
    // so it is file-internal rather than `private`.
    func baselineGraphicsCapabilities() -> TerminalGraphicsCapabilities {
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

    /// Probes once for the kitty keyboard protocol (`CSI ? u` flags query,
    /// piggybacking `CSI c` as the guaranteed terminator). Skipped inside
    /// terminal multiplexers — tmux/screen pass the push through to panes
    /// they don't own — and disabled by `SWIFTTUI_KITTY_KEYBOARD=0`.
    func probeKittyKeyboardSupportIfNeeded() -> Bool {
      if capabilityProbe.hasProbedKittyKeyboardSupport {
        return capabilityProbe.cachedKittyKeyboardSupport
      }
      capabilityProbe.hasProbedKittyKeyboardSupport = true
      capabilityProbe.cachedKittyKeyboardSupport = false

      guard environment["SWIFTTUI_KITTY_KEYBOARD"] != "0" else {
        return false
      }
      guard !isInsideTerminalMultiplexer else {
        return false
      }
      guard
        controller.isATTY(inputFileDescriptor),
        controller.isATTY(outputFileDescriptor)
      else {
        return false
      }

      let response = (try? performInputCapabilityQuery(.kittyKeyboardFlags)) ?? []
      let supported = parseKittyKeyboardFlagsReport(from: response) != nil
      capabilityProbe.cachedKittyKeyboardSupport = supported
      return supported
    }

    /// Runs `body` with the live input reader suspended, when a gate is
    /// wired. The capability replies arrive on the shared input descriptor,
    /// so an unsuspended reader races the probe for them — whoever loses the
    /// race either eats the reply (mis-detection) or burns the full timeout
    /// ladder (the historical 0.5–1 s first-image stall, F42).
    ///
    /// Visibility note: shared with `performInputCapabilityQuery` in
    /// `TerminalMouseCoordinateResolution.swift`, so file-internal rather
    /// than private.
    func withInputSuspensionGate<T>(_ body: () throws -> T) rethrows -> T {
      if let inputSuspensionGate {
        return try inputSuspensionGate.withInputSuspended(body)
      }
      return try body()
    }

    private func performGraphicsQuery(
      _ query: TerminalGraphicsQuery
    ) throws -> [UInt8] {
      try withInputSuspensionGate {
        try performGraphicsQueryOnUncontendedDescriptor(query)
      }
    }

    private func performGraphicsQueryOnUncontendedDescriptor(
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
