extension SnapshotRenderer {
  public func frameDiagnostics(_ diagnostics: FrameDiagnostics) -> String {
    var lines: [String] = []
    lines.append("proposal=\(describe(diagnostics.input.proposal))")
    lines.append(
      "invalidatedIdentities=\(describe(diagnostics.input.invalidatedIdentities))"
    )
    lines.append("resolvedNodes=\(diagnostics.counts.resolvedNodes)")
    lines.append("measuredNodes=\(diagnostics.counts.measuredNodes)")
    lines.append("placedNodes=\(diagnostics.counts.placedNodes)")
    lines.append(
      "resolvedWork=computed:\(diagnostics.work.resolvedNodesComputed) reused:\(diagnostics.work.resolvedNodesReused)"
    )
    lines.append(
      "measuredWork=computed:\(diagnostics.work.measuredNodesComputed) reused:\(diagnostics.work.measuredNodesReused)"
    )
    lines.append(
      "placedWork=computed:\(diagnostics.work.placedNodesComputed) reused:\(diagnostics.work.placedNodesReused) frameTableEntriesReused:\(diagnostics.work.placedFrameTableEntriesReused)"
    )
    lines.append(
      "layoutDependent=realized:\(diagnostics.work.layoutDependentRealizations) cacheHits:\(diagnostics.work.layoutDependentRealizationCacheHits) mainActorFallbacks:\(diagnostics.work.layoutDependentMainActorFallbacks)"
    )
    lines.append("drawNodes=\(diagnostics.counts.drawNodes)")
    lines.append("interactionRegions=\(diagnostics.counts.interactionRegions)")
    lines.append("focusRegions=\(diagnostics.counts.focusRegions)")
    lines.append("scrollRoutes=\(diagnostics.counts.scrollRoutes)")
    lines.append("selectionRoutes=\(diagnostics.counts.selectionRoutes)")
    if let phaseTimings = diagnostics.timing.phaseTimings {
      lines.append(
        "phaseTimings=resolve:\(describe(phaseTimings.resolve)) measure:\(describe(phaseTimings.measure)) place:\(describe(phaseTimings.place)) semantics:\(describe(phaseTimings.semantics)) draw:\(describe(phaseTimings.draw)) raster:\(describe(phaseTimings.raster)) commit:\(describe(phaseTimings.commit)) total:\(describe(phaseTimings.total))"
      )
    } else {
      lines.append("phaseTimings=nil")
    }

    let generations = diagnostics.timing.renderGenerations
    lines.append(
      "renderGenerations=render:\(describe(generations.render)) layoutInput:\(describe(generations.layoutInput)) layoutOutput:\(describe(generations.layoutOutput)) rasterInput:\(describe(generations.rasterInput)) rasterOutput:\(describe(generations.rasterOutput))"
    )

    if let workerTimings = diagnostics.timing.workerTimings {
      lines.append(
        "workerTimings=layoutEnqueue:\(describe(workerTimings.layoutEnqueueToStart)) layoutCompute:\(describe(workerTimings.layoutCompute)) rasterEnqueue:\(describe(workerTimings.rasterEnqueueToStart)) rasterCompute:\(describe(workerTimings.rasterCompute)) completionToCommit:\(describe(workerTimings.completionToMainCommit))"
      )
    } else {
      lines.append("workerTimings=nil")
    }

    if let mainActorTimings = diagnostics.timing.mainActorTimings {
      lines.append(
        "mainActorTimings=blocked:\(describe(mainActorTimings.blocked)) suspended:\(describe(mainActorTimings.suspended))"
      )
    } else {
      lines.append("mainActorTimings=nil")
    }

    if let cache = diagnostics.work.measurementCache {
      lines.append(
        "measurementCache=generation:\(cache.generation) entries:\(cache.entries) lookups:\(cache.lookups) hits:\(cache.hits) misses:\(cache.misses) invalidations:\(cache.invalidations) stores:\(cache.stores)"
      )
    } else {
      lines.append("measurementCache=nil")
    }
    lines.append("customLayoutFallbacks=\(diagnostics.work.customLayoutFallbackCount)")
    lines.append(
      "firstCustomLayoutFallback=\(diagnostics.work.firstCustomLayoutFallbackIdentity?.path ?? "nil")"
    )
    let geometry = diagnostics.geometryResolutionDiagnostics
    lines.append(
      "geometryResolution=anchorMisses:\(geometry.anchorResolutionMissCount) missingNamed:\(geometry.missingNamedCoordinateSpaceCount) duplicateNamed:\(geometry.duplicateNamedCoordinateSpaceCount)"
    )
    lines.append(
      "firstGeometryResolutionMiss=anchor:\(geometry.firstAnchorResolutionMissIdentity?.path ?? "nil") missingNamed:\(geometry.firstMissingNamedCoordinateSpaceName ?? "nil") duplicateNamed:\(geometry.firstDuplicateNamedCoordinateSpaceName ?? "nil")"
    )
    lines.append("runtimeIssues=\(diagnostics.runtime.issues.count)")
    for issue in diagnostics.runtime.issues {
      lines.append("  \(issue.description)")
    }

    return lines.joined(separator: "\n")
  }

  public func scheduledFrame(_ frame: ScheduledFrame) -> String {
    [
      "causes=\(frame.causes.map(\.rawValue).sorted().joined(separator: ","))",
      "invalidatedIdentities=\(frame.invalidatedIdentities.map(\.path).sorted().joined(separator: ","))",
      "signalNames=\(frame.signalNames.joined(separator: ","))",
      "externalReasons=\(frame.externalReasons.joined(separator: ","))",
      "triggeredDeadline=\(describe(frame.triggeredDeadline))",
      "nextDeadline=\(describe(frame.nextDeadline))",
    ].joined(separator: "\n")
  }

  private func describe(
    _ identities: Set<Identity>
  ) -> String {
    let paths = identities.map(\.path).sorted()
    return paths.isEmpty ? "none" : paths.joined(separator: ",")
  }

  private func describe(
    _ duration: Duration
  ) -> String {
    let components = duration.components
    let milliseconds =
      Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
    let rounded = (milliseconds * 100).rounded() / 100
    return "\(rounded)ms"
  }

  private func describe(
    _ generation: RenderGeneration
  ) -> String {
    String(generation.rawValue)
  }

  private func describe(
    _ generation: RenderGeneration?
  ) -> String {
    generation.map(describe) ?? "-"
  }

  private func describe(
    _ instant: MonotonicInstant?
  ) -> String {
    guard let instant else {
      return "nil"
    }
    let totalSeconds =
      Double(instant.offset.components.seconds)
      + (Double(instant.offset.components.attoseconds) / 1_000_000_000_000_000_000)
    let roundedMilliseconds = Int((totalSeconds * 1000).rounded())
    let wholeSeconds = roundedMilliseconds / 1000
    let fractionalMilliseconds = abs(roundedMilliseconds % 1000)
    let fractionalString = String(fractionalMilliseconds)
    let paddedFractional =
      String(repeating: "0", count: max(0, 3 - fractionalString.count))
      + fractionalString
    return "\(wholeSeconds).\(paddedFractional)"
  }
}
