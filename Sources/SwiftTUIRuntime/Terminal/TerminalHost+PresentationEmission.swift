import SwiftTUICore

#if !canImport(WASILibc)
  struct TerminalHostPresentationEmissionBuilder {
    var capabilityProfile: TerminalCapabilityProfile
    var usesTerminalEditOperations: Bool
    var imageRenderer: TerminalImageRenderer
    var fallbackBackground: Color
    var terminalBackgroundColor: Color?

    func build(
      for preparedSurface: RasterSurface,
      plan: TerminalPresentationPlan,
      graphicsCapabilities: TerminalGraphicsCapabilities,
      transmittedKittyImages: inout Set<UInt32>
    ) -> TerminalPresentationEmission {
      var emission = TerminalPresentationEmission()
      switch plan.strategy {
      case .fullRepaint:
        appendFullRepaint(
          to: &emission,
          for: preparedSurface,
          graphicsCapabilities: graphicsCapabilities,
          transmittedKittyImages: &transmittedKittyImages
        )

      case .incremental:
        appendIncrementalPresentation(
          to: &emission,
          for: preparedSurface,
          plan: plan,
          graphicsCapabilities: graphicsCapabilities,
          transmittedKittyImages: &transmittedKittyImages
        )
      }

      return emission
    }

    private func appendFullRepaint(
      to emission: inout TerminalPresentationEmission,
      for preparedSurface: RasterSurface,
      graphicsCapabilities: TerminalGraphicsCapabilities,
      transmittedKittyImages: inout Set<UInt32>
    ) {
      // A terminal full repaint clears the previous screen contents. Kitty
      // image ids cannot be assumed to remain displayable after that, so
      // force the current frame to retransmit any images before placement.
      if graphicsCapabilities.preferredProtocol == .kitty {
        transmittedKittyImages.removeAll()
      }
      if !preparedSurface.imageAttachments.isEmpty {
        emission.recordGraphicsReplay(
          scope: .full,
          attachmentCount: preparedSurface.imageAttachments.count
        )
      }
      emission.append(TerminalHostEscapeSequences.clearScreen)
      emission.append(TerminalHostEscapeSequences.cursor(to: .zero))

      let writeSteps = fullRepaintWriteSteps(
        for: preparedSurface,
        capabilityProfile: capabilityProfile,
        terminalBackgroundColor: terminalBackgroundColor
      )
      for writeStep in writeSteps {
        emission.append(writeStep)
      }

      for writeStep in imageRenderer.graphicsWriteSteps(
        for: preparedSurface,
        capabilityProfile: capabilityProfile,
        graphicsCapabilities: graphicsCapabilities,
        fallbackBackground: fallbackBackground,
        transmittedKittyImages: &transmittedKittyImages
      ) {
        emission.append(writeStep)
      }
    }

    private func appendIncrementalPresentation(
      to emission: inout TerminalPresentationEmission,
      for preparedSurface: RasterSurface,
      plan: TerminalPresentationPlan,
      graphicsCapabilities: TerminalGraphicsCapabilities,
      transmittedKittyImages: inout Set<UInt32>
    ) {
      for rowBatch in plan.rowBatches {
        let rowOutput = incrementalRowOutput(
          for: rowBatch,
          surfaceWidth: preparedSurface.size.width,
          emission: &emission
        )
        emission.append(
          TerminalHostEscapeSequences.cursor(
            to: .init(x: rowBatch.anchorColumn, y: rowBatch.row)
          )
        )
        emission.append(rowOutput)
      }
      appendKittyGraphicsReplay(
        to: &emission,
        plan: plan,
        graphicsCapabilities: graphicsCapabilities,
        transmittedKittyImages: &transmittedKittyImages
      )
    }

    private func incrementalRowOutput(
      for rowBatch: TerminalPresentationPlan.RowBatch,
      surfaceWidth: Int,
      emission: inout TerminalPresentationEmission
    ) -> String {
      guard usesTerminalEditOperations,
        rowBatch.canLowerToEraseToEndOfLine(surfaceWidth: surfaceWidth)
      else {
        return rowBatch.renderedBatch
      }

      emission.recordEraseToEndOfLine()
      return TerminalHostEscapeSequences.eraseToEndOfLine
    }

    private func appendKittyGraphicsReplay(
      to emission: inout TerminalPresentationEmission,
      plan: TerminalPresentationPlan,
      graphicsCapabilities: TerminalGraphicsCapabilities,
      transmittedKittyImages: inout Set<UInt32>
    ) {
      guard graphicsCapabilities.preferredProtocol == .kitty else {
        return
      }

      switch plan.graphicsReplay.scope {
      case .none:
        break
      case .targeted:
        emission.recordGraphicsReplay(
          scope: .targeted,
          attachmentCount: plan.graphicsReplay.attachmentsToReplay.count
        )
        appendGraphicsWriteSteps(
          for: plan.graphicsReplay.attachmentsToReplay,
          to: &emission,
          graphicsCapabilities: graphicsCapabilities,
          transmittedKittyImages: &transmittedKittyImages
        )
      case .full:
        emission.recordGraphicsReplay(
          scope: .full,
          attachmentCount: plan.graphicsReplay.attachmentsToReplay.count
        )
        emission.append(TerminalHostEscapeSequences.deleteVisibleKittyPlacements)
        appendGraphicsWriteSteps(
          for: plan.graphicsReplay.attachmentsToReplay,
          to: &emission,
          graphicsCapabilities: graphicsCapabilities,
          transmittedKittyImages: &transmittedKittyImages
        )
      }
    }

    private func appendGraphicsWriteSteps(
      for attachments: [RasterImageAttachment],
      to emission: inout TerminalPresentationEmission,
      graphicsCapabilities: TerminalGraphicsCapabilities,
      transmittedKittyImages: inout Set<UInt32>
    ) {
      for writeStep in imageRenderer.graphicsWriteSteps(
        for: attachments,
        capabilityProfile: capabilityProfile,
        graphicsCapabilities: graphicsCapabilities,
        fallbackBackground: fallbackBackground,
        transmittedKittyImages: &transmittedKittyImages
      ) {
        emission.append(writeStep)
      }
    }
  }
#endif
