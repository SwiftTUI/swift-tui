import SwiftTUICore

// Mouse coordinate-mode resolution for the terminal host.
//
// A terminal can report pointer positions either in character cells or in
// pixels (the SGR-pixels extension, DEC private mode 1016). Pixel reporting is
// only safe to enable when we trust the terminal both supports it and knows
// its own cell pixel metrics. This file owns that decision: the trust-policy
// ladder, the live DEC-1016 probe, and the terminal-identity heuristics that
// back it. Graphics-protocol probing (Kitty/Sixel) lives separately in
// `TerminalHostCapabilities.swift`.
#if !canImport(WASILibc)
  extension TerminalHost {
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
  }
#endif
