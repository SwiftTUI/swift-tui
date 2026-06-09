#if DEBUG
  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #elseif canImport(Android)
    import Android
  #elseif canImport(WASILibc)
    import WASILibc
  #elseif canImport(ucrt)
    import ucrt
  #endif

  /// Debug-only evidence surface for the structural-identity migration.
  ///
  /// The snapshot walks the resolved tree's real children arrays and compares
  /// that parent relation with the parent implied by `Identity.parent`. It does
  /// not participate in commit, retained reuse, or invalidation decisions.
  package enum StructuralDivergenceDiagnostics {
    package static let emissionEnvironmentVariable = "SWIFTTUI_STRUCTURAL_DIVERGENCE_REPORT"

    package static func snapshot(
      of frame: FrameArtifacts
    ) -> StructuralDivergenceSnapshot {
      snapshot(of: frame.resolvedTree)
    }

    package static func snapshot(
      of root: ResolvedNode
    ) -> StructuralDivergenceSnapshot {
      var records: [StructuralDivergenceSnapshot.NodeRecord] = []
      walk(root, structuralParent: nil, records: &records)
      return StructuralDivergenceSnapshot(records: records)
    }

    package static func report(
      from snapshots: [StructuralDivergenceSnapshot]
    ) -> StructuralDivergenceReport {
      var pathVsStructuralParentMismatches:
        [StructuralDivergenceReport.PathParentMismatch] = []
      var duplicateRuntimeIdentities:
        [StructuralDivergenceReport.DuplicateRuntimeIdentity] = []
      var portalPlacementRoles:
        [StructuralDivergenceReport.PortalPlacementRole] = []

      for snapshot in snapshots {
        pathVsStructuralParentMismatches.append(
          contentsOf: snapshot.records.compactMap { record in
            guard record.pathParent != record.structuralParent else {
              return nil
            }
            return .init(
              node: record.runtimeIdentity,
              pathParent: record.pathParent,
              structuralParent: record.structuralParent,
              kind: record.kind
            )
          }
        )

        let recordsByIdentity = Dictionary(grouping: snapshot.records, by: \.runtimeIdentity)
        for (identity, records) in recordsByIdentity where records.count > 1 {
          duplicateRuntimeIdentities.append(
            .init(
              identity: identity,
              occurrences: records.count,
              producers: records.map(\.kind)
            )
          )
        }

        portalPlacementRoles.append(
          contentsOf: snapshot.records.compactMap { record in
            guard let surfaceRole = record.surfaceRole else {
              return nil
            }
            return .init(
              node: record.runtimeIdentity,
              structuralParent: record.structuralParent,
              role: surfaceRole,
              stableKey: record.surfaceStableKey
            )
          }
        )
      }

      return StructuralDivergenceReport(
        pathVsStructuralParentMismatches: pathVsStructuralParentMismatches,
        duplicateRuntimeIdentities: duplicateRuntimeIdentities,
        portalPlacementRoles: portalPlacementRoles,
        frameCount: snapshots.count
      )
    }

    package static func emitIfRequested(
      _ report: StructuralDivergenceReport
    ) {
      guard environmentFlagIsEnabled(processEnvironmentValue(named: emissionEnvironmentVariable)) else {
        return
      }
      writeToStandardError(report.machineReadableSummary)
    }

    package static func emitIfRequested(
      _ report: StructuralDivergenceReport,
      environment: [String: String]
    ) {
      guard environment[emissionEnvironmentVariable] == "1" else {
        return
      }
      writeToStandardError(report.machineReadableSummary)
    }

    private static func walk(
      _ node: ResolvedNode,
      structuralParent: Identity?,
      records: inout [StructuralDivergenceSnapshot.NodeRecord]
    ) {
      records.append(
        .init(
          runtimeIdentity: node.identity,
          structuralPath: node.structuralPath,
          structuralParent: structuralParent,
          pathParent: normalizedPathParent(of: node.identity),
          kind: node.kind,
          typeDiscriminator: node.typeDiscriminator.map { String(describing: $0) },
          explicitIDComponent: explicitIDComponent(from: node.identity),
          isTransient: node.isTransient,
          surfaceRole: node.surfaceComposition.role == .normal
            ? nil
            : node.surfaceComposition.role,
          surfaceStableKey: node.surfaceComposition.stableKey
        )
      )
      for child in node.children {
        walk(child, structuralParent: node.identity, records: &records)
      }
    }

    private static func explicitIDComponent(
      from identity: Identity
    ) -> String? {
      guard let lastComponent = identity.lastComponent,
        lastComponent.hasPrefix("ID[")
      else {
        return nil
      }
      return lastComponent
    }

    private static func normalizedPathParent(
      of identity: Identity
    ) -> Identity? {
      guard let parent = identity.parent else {
        return nil
      }
      return parent.components.isEmpty ? nil : parent
    }

    private static func environmentFlagIsEnabled(_ value: String?) -> Bool {
      guard let value else {
        return false
      }
      switch value.lowercased() {
      case "1", "true", "yes", "on":
        return true
      default:
        return false
      }
    }

    private static func processEnvironmentValue(named name: String) -> String? {
      unsafe name.withCString { cName in
        guard let rawValue = unsafe getenv(cName) else {
          return nil
        }
        return unsafe String(cString: rawValue)
      }
    }

    private static func writeToStandardError(_ message: String) {
      #if canImport(Darwin) || canImport(Glibc) || canImport(Android)
        var message = message
        message.withUTF8 { buffer in
          guard let base = buffer.baseAddress, buffer.count > 0 else {
            return
          }
          _ = unsafe write(STDERR_FILENO, base, buffer.count)
        }
      #elseif canImport(WASILibc) || canImport(ucrt)
        unsafe message.withCString { cMessage in
          _ = fputs(cMessage, stderr)
        }
      #endif
    }
  }

  package struct StructuralDivergenceSnapshot: Sendable {
    package struct NodeRecord: Sendable {
      package let runtimeIdentity: Identity
      package let structuralPath: StructuralPath
      package let structuralParent: Identity?
      package let pathParent: Identity?
      package let kind: NodeKind
      package let typeDiscriminator: String?
      package let explicitIDComponent: String?
      package let isTransient: Bool
      package let surfaceRole: SurfaceCompositionRole?
      package let surfaceStableKey: String?

      package init(
        runtimeIdentity: Identity,
        structuralPath: StructuralPath,
        structuralParent: Identity?,
        pathParent: Identity?,
        kind: NodeKind,
        typeDiscriminator: String?,
        explicitIDComponent: String?,
        isTransient: Bool,
        surfaceRole: SurfaceCompositionRole?,
        surfaceStableKey: String?
      ) {
        self.runtimeIdentity = runtimeIdentity
        self.structuralPath = structuralPath
        self.structuralParent = structuralParent
        self.pathParent = pathParent
        self.kind = kind
        self.typeDiscriminator = typeDiscriminator
        self.explicitIDComponent = explicitIDComponent
        self.isTransient = isTransient
        self.surfaceRole = surfaceRole
        self.surfaceStableKey = surfaceStableKey
      }
    }

    package let records: [NodeRecord]

    package init(records: [NodeRecord]) {
      self.records = records
    }
  }

  package struct StructuralDivergenceReport: Sendable {
    package struct PathParentMismatch: Sendable {
      package let node: Identity
      package let pathParent: Identity?
      package let structuralParent: Identity?
      package let kind: NodeKind
    }

    package struct DuplicateRuntimeIdentity: Sendable {
      package let identity: Identity
      package let occurrences: Int
      package let producers: [NodeKind]
    }

    package struct PortalPlacementRole: Sendable {
      package let node: Identity
      package let structuralParent: Identity?
      package let role: SurfaceCompositionRole
      package let stableKey: String?
    }

    package let pathVsStructuralParentMismatches: [PathParentMismatch]
    package let duplicateRuntimeIdentities: [DuplicateRuntimeIdentity]
    package let portalPlacementRoles: [PortalPlacementRole]
    package let frameCount: Int

    package var machineReadableSummary: String {
      var lines = ["structural_divergence\tframes\t\(frameCount)"]
      lines.append(
        "structural_divergence\tpath_parent_mismatches\t\(pathVsStructuralParentMismatches.count)"
      )
      lines.append(
        "structural_divergence\tduplicate_runtime_identities\t\(duplicateRuntimeIdentities.count)"
      )
      lines.append(
        "structural_divergence\tportal_placement_roles\t\(portalPlacementRoles.count)"
      )
      return lines.joined(separator: "\n") + "\n"
    }

    package init(
      pathVsStructuralParentMismatches: [PathParentMismatch],
      duplicateRuntimeIdentities: [DuplicateRuntimeIdentity],
      portalPlacementRoles: [PortalPlacementRole],
      frameCount: Int
    ) {
      self.pathVsStructuralParentMismatches = pathVsStructuralParentMismatches
      self.duplicateRuntimeIdentities = duplicateRuntimeIdentities
      self.portalPlacementRoles = portalPlacementRoles
      self.frameCount = frameCount
    }
  }
#endif
