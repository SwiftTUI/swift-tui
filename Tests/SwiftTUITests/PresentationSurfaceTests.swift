@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct PresentationSurfaceTests {
  @Test("dropdown presentations render content without title or close chrome")
  func dropdownPresentationsRenderContentWithoutTitleOrCloseChrome() throws {
    let artifacts = DefaultRenderer().render(
      Panel(id: "PaletteHost") {
        Text("Workspace")
      }
      .paletteSheet("Command palette", isPresented: .constant(true)),
      context: .init(identity: testIdentity("DropdownPresentationChromeRoot")),
      proposal: .init(width: 40, height: 10)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    // A contentless palette renders the framework's own body, so the presence
    // check is now its filter field rather than a caller-supplied string.
    #expect(surface.contains("Filter commands"), "palette body did not render:\n\(surface)")
    #expect(!surface.contains("Command palette"))
    #expect(!surface.contains("×"))
  }

  /// Ported from the gallery's `CommandPaletteTests` when control-style A5
  /// moved `CommandPaletteList` into the framework as `DefaultPaletteBody`:
  /// the palette's filter field must publish a focusable region, or the body
  /// renders but cannot be typed into.
  @Test("the default palette body publishes a focusable filter region")
  func defaultPaletteBodyPublishesFocusableFilterRegion() throws {
    let artifacts = DefaultRenderer().render(
      Panel(id: "PaletteHost") {
        Text("Workspace")
      }
      .paletteSheet("Command palette", isPresented: .constant(true)),
      context: .init(identity: testIdentity("DefaultPaletteFocusRoot")),
      proposal: .init(width: 44, height: 12)
    )

    let focusRegions = artifacts.semanticSnapshot.focusRegions
    #expect(!focusRegions.isEmpty, "palette published no focusable region")
    #expect(
      focusRegions.contains { $0.rect.size.width > 0 && $0.rect.size.height > 0 }
    )
  }

  @Test("a filtered default-palette command is semantic in the rendered frame")
  func filteredDefaultPaletteCommandIsSemanticInRenderedFrame() throws {
    let probe = FilteredPaletteSemanticProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("FilteredDefaultPaletteSemanticRoot"),
      size: .init(width: 44, height: 12)
    ) {
      FilteredPaletteSemanticFixture(probe: probe)
    }
    defer { harness.shutdown() }

    for character in "counter" {
      _ = try harness.pressKey(KeyPress(.character(character)))
    }

    #expect(harness.frame.contains("Counter"))
    #expect(harness.frame.contains("Switch to counter"))
    #expect(!harness.frame.contains("Images"))
    let renderedPoint = try #require(harness.point(forText: "Counter"))
    let commands = harness.runLoop.latestSemanticSnapshot.accessibilityNodes.filter {
      $0.role == .button && $0.rect.contains(renderedPoint.containingCell)
    }
    let command = try #require(commands.count == 1 ? commands[0] : nil)
    #expect(command.label == "Counter")
    #expect(
      !harness.runLoop.latestSemanticSnapshot.accessibilityNodes.contains {
        $0.label?.contains("Switch to counter") == true
      }
    )
    #expect(command.rect.size.width > 0)
    #expect(command.rect.size.height > 0)

    _ = try harness.click(renderedPoint)
    #expect(probe.selection == "Counter")
  }

  @Test("default palette arrow navigation mutates its authored selection state")
  func defaultPaletteArrowNavigationMutatesAuthoredSelectionState() throws {
    let probe = FilteredPaletteSemanticProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DefaultPaletteArrowSelectionRoot"),
      size: .init(width: 44, height: 12)
    ) {
      FilteredPaletteSemanticFixture(probe: probe)
    }
    defer { harness.shutdown() }

    #expect(harness.frame.contains("> Counter"))
    let moved = try harness.pressKey(KeyPress(.arrowDown))
    #expect(moved.contains("> Images"), "palette selection did not move:\n\(moved)")
  }

  @Test("a status infers its current text across same-identity replacement frames")
  func statusInfersCurrentTextAcrossSameIdentityReplacementFrames() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CurrentStatusSemanticRoot"),
      size: .init(width: 44, height: 8)
    ) {
      CurrentStatusSemanticFixture()
    }
    defer { harness.shutdown() }

    let initial = try #require(
      harness.runLoop.latestSemanticSnapshot.accessibilityNodes.first {
        $0.role == .status
      }
    )
    #expect(initial.label == "Clipboard: idle")

    let copiedFrame = try harness.clickText("Copy journey token")
    #expect(copiedFrame.contains("Clipboard: copied"))
    let copied = try #require(
      harness.runLoop.latestSemanticSnapshot.accessibilityNodes.first {
        $0.role == .status
      }
    )
    #expect(copied.identity == initial.identity)
    #expect(copied.viewNodeID == initial.viewNodeID)
    #expect(copied.label == "Clipboard: copied")
  }

  @Test("presentation overlays carry explicit surface composition metadata")
  func presentationOverlaysCarrySurfaceCompositionMetadata() throws {
    let contentRootIdentity = testIdentity("SurfaceCompositionRoot")
    let portalStructuralPath = StructuralPath(identity: contentRootIdentity)
    let artifacts = DefaultRenderer().render(
      Text("Workspace")
        .sheet("Command palette", isPresented: .constant(true)) {
          Text("Filter commands")
        },
      context: .init(identity: contentRootIdentity),
      proposal: .init(width: 40, height: 10)
    )

    let entries = SurfaceTopologySignature(placedRoot: artifacts.placedTree).entries
    #expect(
      entries.contains {
        $0.role == .stackingContext
          && $0.stableKey == "overlay-stack:\(portalStructuralPath)"
          && $0.invalidationScope == .fullSurfaceDiff
      }
    )
    #expect(
      entries.contains {
        $0.role == .detachedOverlayHost
          && $0.stableKey == "overlay-host:\(portalStructuralPath)/PortalHost/overlays"
          && $0.invalidationScope == .fullSurfaceDiff
      }
    )
    #expect(
      entries.contains {
        $0.role == .detachedOverlayEntry
          && $0.invalidationScope == .fullSurfaceDiff
      }
    )
    #expect(
      entries.contains {
        $0.role == .detachedOverlayEntry
          && $0.stableKey?.isEmpty == false
      }
    )

    let portalRootIdentity = testIdentity("SurfaceCompositionPortalRoot")
    let portalRoot = composePresentationPortalTree(
      baseNode: ResolvedNode(
        identity: testIdentity("SurfaceCompositionContent"),
        kind: .view("Content")
      ),
      portalState: PresentationPortalState().makeDraft(),
      in: .init(identity: portalRootIdentity)
    )
    let portalRootTopology = SurfaceTopologySignature(
      placedRoot: PlacedNode(
        identity: portalRoot.identity,
        kind: portalRoot.kind,
        bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
        surfaceComposition: portalRoot.surfaceComposition
      )
    ).entries

    #expect(
      portalRootTopology.contains {
        $0.role == .detachedOverlayRoot
          && $0.stableKey == portalRootIdentity.path
          && $0.invalidationScope == .fullSurfaceDiff
      }
    )
  }

  @Test("compositing groups carry explicit surface composition metadata")
  func compositingGroupsCarrySurfaceCompositionMetadata() {
    let rootIdentity = testIdentity("SurfaceCompositionCompositingGroupRoot")
    let artifacts = DefaultRenderer().render(
      Text("Layer")
        .compositingGroup(),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 20, height: 4)
    )

    let entries = SurfaceTopologySignature(placedRoot: artifacts.placedTree).entries
    #expect(
      entries.contains {
        $0.role == .isolatedCompositingGroup
          && $0.stableKey == rootIdentity.path
          && $0.invalidationScope == .compositedBounds
      }
    )
  }

  @Test("alert renders an overlay surface and suppresses background focus")
  func alertRendersAndSuppressesBackgroundFocus() throws {
    let artifacts = DefaultRenderer().render(
      Button("Background") {}
        .id(testIdentity("BackgroundButton"))
        .alert(
          "Delete project",
          isPresented: .constant(true),
          actions: {
            Button("Delete") {}
            Button("Cancel") {}
          },
          message: {
            Text("This cannot be undone.")
          }
        ),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 40, height: 10)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    let focusedPaths = Set(artifacts.semanticSnapshot.focusRegions.map(\.identity.path))

    #expect(surface.contains("Delete project"))
    #expect(surface.contains("This cannot be undone."))
    #expect(surface.contains("Delete"))
    #expect(!focusedPaths.contains(testIdentity("BackgroundButton").path))
    #expect(focusedPaths.count >= 2)
  }

  @Test("confirmationDialog supplies a default cancel action")
  func confirmationDialogProvidesDefaultCancelAction() {
    let artifacts = DefaultRenderer().render(
      Text("Workspace")
        .confirmationDialog(
          "Archive task",
          isPresented: .constant(true)
        ),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 40, height: 8)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(surface.contains("Archive task"))
    #expect(surface.contains("Cancel"))
  }

  @Test("confirmationDialog hoists above clipped ancestor content")
  func confirmationDialogHoistsAboveClippedAncestorContent() {
    let outsideIdentity = testIdentity("OutsideButton")
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 1) {
        Button("Outside") {}
          .id(outsideIdentity)

        HStack {
          Text("Attachment")
            .confirmationDialog(
              "Archive task",
              isPresented: .constant(true),
              actions: {
                Button("Archive") {}
              },
              message: {
                Text("Move the task out of the active list.")
              }
            )
        }
        .frame(width: 8, height: 1, alignment: .leading)
        .clipped()
      }
      .frame(width: 32, height: 8, alignment: .topLeading),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 32, height: 8)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    let focusedPaths = Set(artifacts.semanticSnapshot.focusRegions.map(\.identity.path))

    #expect(surface.contains("Archive task"))
    #expect(surface.contains("Move the task out"))
    #expect(surface.contains("Archive"))
    #expect(!focusedPaths.contains(outsideIdentity.path))
  }

  @Test("alert keeps overflow-prone content inside a short terminal surface")
  func alertKeepsOverflowProneContentInsideShortSurface() {
    let artifacts = DefaultRenderer().render(
      Text("Workspace")
        .alert(
          "Archive project",
          isPresented: .constant(true),
          actions: {
            Button("Archive") {}
            Button("Duplicate") {}
            Button("Export") {}
            Button("Cancel") {}
          },
          message: {
            VStack(alignment: .leading, spacing: 0) {
              Text("This workspace has several long notes.")
              Text("Scrolling should keep the overlay bounded.")
              Text("Nothing should spill past the viewport.")
            }
          }
        )
        .frame(width: 30, height: 6, alignment: .topLeading),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 30, height: 6)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(surface.contains("Archive project"))
    #expect(surface.contains("This workspace has"))
    #expect(surface.contains("Archive"))
    #expect(surface.contains("▐") || surface.contains("▼"))
  }

  @Test("toast and alert overlays share the first frame and use fixed family order")
  func toastAndAlertOverlaysUseFixedFamilyOrder() throws {
    let artifacts = DefaultRenderer().render(
      Text("Workspace")
        .toast(
          "Saved successfully",
          isPresented: .constant(true),
          style: .success,
          duration: nil
        )
        .alert(
          "Delete project",
          isPresented: .constant(true),
          actions: {
            Button("Delete") {}
          },
          message: {
            Text("This cannot be undone.")
          }
        )
        .frame(width: 40, height: 10, alignment: .topLeading),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 40, height: 10)
    )

    let kinds = viewKindNames(in: artifacts.resolvedTree)
    let toastIndex = try #require(kinds.firstIndex(of: "ToastPresentation"))
    let alertIndex = try #require(kinds.firstIndex(of: "AlertPresentation"))

    #expect(kinds.contains("ToastPresentation"))
    #expect(kinds.contains("AlertPresentation"))
    #expect(toastIndex < alertIndex)
  }

  @Test("sheet shell uses a single-line presentation chrome with a full-bleed surface background")
  func sheetShellUsesSingleLineChromeWithFullBleedBackground() throws {
    let proposal = ProposedSize(width: .finite(48), height: .finite(14))
    let rootIdentity = testIdentity("Root")

    let backgroundOnly = DefaultRenderer().render(
      Rectangle()
        .fill(.terminalAccent(.success))
        .frame(width: 48, height: 14, alignment: .topLeading),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )

    let artifacts = DefaultRenderer().render(
      Rectangle()
        .fill(.terminalAccent(.success))
        .sheet("Inspector", isPresented: .constant(true)) {
          Text("Sheet body")
        }
        .frame(width: 48, height: 14, alignment: .topLeading),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )

    let cells = artifacts.rasterSurface.cells

    // The chrome is a square single-line box (no half-block glyphs). Anchor on
    // the two opposite corners, then read the edges off the derived bounds.
    let topLeadingCorner = try #require(
      findCharacter("┌", in: artifacts.rasterSurface.lines)
    )
    let bottomTrailingCorner = try #require(
      findCharacter("┘", in: artifacts.rasterSurface.lines)
    )
    let minX = topLeadingCorner.x
    let maxX = bottomTrailingCorner.x
    let minY = topLeadingCorner.y
    let maxY = bottomTrailingCorner.y

    #expect(cells[minY][maxX].character == "┐")
    #expect(cells[maxY][minX].character == "└")
    #expect(cells[minY][minX + 1].character == "─")  // top edge
    #expect(cells[minY + 2][minX].character == "│")  // left edge (a body row)
    #expect(cells[minY + 2][maxX].character == "│")  // right edge (a body row)

    // None of the legacy half-block chrome glyphs survive.
    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(!surface.contains("▄"))
    #expect(!surface.contains("▌"))
    #expect(!surface.contains("▗"))
    #expect(!surface.contains("▘"))

    // Full bleed: every border cell carries the same surface fill as the
    // interior, and that fill is distinct from the backdrop behind the sheet.
    let interiorBackground = try #require(
      cells[minY + 2][minX + 2].style?.backgroundColor
    )
    let topBorderBackground = try #require(
      cells[minY][minX + 1].style?.backgroundColor
    )
    let leftBorderBackground = try #require(
      cells[minY + 2][minX].style?.backgroundColor
    )
    let rightBorderBackground = try #require(
      cells[minY + 2][maxX].style?.backgroundColor
    )
    let underlyingBackground = try #require(
      backgroundOnly.rasterSurface.cells[minY][minX + 1].style?.backgroundColor
    )

    #expect(topBorderBackground == interiorBackground)
    #expect(leftBorderBackground == interiorBackground)
    #expect(rightBorderBackground == interiorBackground)
    #expect(interiorBackground != underlyingBackground)
  }

  @Test("declarative reconciliation prunes stale overlays when the source subtree disappears")
  func declarativeReconciliationPrunesStaleSourceOverlays() {
    let renderer = DefaultRenderer()
    let rootIdentity = testIdentity("Root")

    let initial = renderer.render(
      ConditionalAlertPresentationView(showAlertSource: true),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 40, height: 8)
    )
    let updated = renderer.render(
      ConditionalAlertPresentationView(showAlertSource: false),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 40, height: 8)
    )

    let initialSurface = initial.rasterSurface.lines.joined(separator: "\n")
    let updatedSurface = updated.rasterSurface.lines.joined(separator: "\n")

    #expect(initialSurface.contains("Delete project"))
    #expect(!updatedSurface.contains("Delete project"))
  }

  @Test("render-time coordinator mutation is rejected and does not surface the presentation")
  func renderTimeCoordinatorMutationIsRejected() {
    var recordedMessage: String?
    PresentationMutationGuard.onInvalidMutation = { message in
      recordedMessage = message
    }
    defer {
      PresentationMutationGuard.onInvalidMutation = nil
    }

    let artifacts = DefaultRenderer().render(
      RenderTimePresentationMutationProbe(),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 40, height: 8)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(
      recordedMessage
        == "AlertPresentationCoordinator.present(_:) must not be called during view update.")
    #expect(surface.contains("Workspace"))
    #expect(!surface.contains("Illegal mutation"))
  }

  // SwiftUI reports "Modifying state during view update" as a runtime
  // warning, not a trap. The shipped path installs no onInvalidMutation hook.
  // STUI-1226.
  @Test("render-time coordinator mutation is a runtime warning in every configuration")
  func renderTimeCoordinatorMutationWarnsWithoutTrapping() async {
    await expectRenderTimeMutationWarnsWithoutTrapping()
  }

  @Test("a presentation refused during a view update never surfaces in a later frame")
  func refusedRenderTimeMutationStaysRefused() {
    var messages: [String] = []
    PresentationMutationGuard.onInvalidMutation = { messages.append($0) }
    defer { PresentationMutationGuard.onInvalidMutation = nil }
    _ = ImperativeRuntimeIssueQueue.drain()

    let renderer = DefaultRenderer()
    let trigger = RenderTimePresentationTrigger()
    let first = renderer.render(
      OnceRenderTimePresentationProbe(trigger: trigger),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 40, height: 8)
    )
    let second = renderer.render(
      OnceRenderTimePresentationProbe(trigger: trigger),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 40, height: 8)
    )

    #expect(trigger.presentations == 1)
    #expect(
      messages == [
        "AlertPresentationCoordinator.present(_:) must not be called during view update."
      ]
    )
    #expect(
      first.diagnostics.runtime.issues.map(\.code) == ["presentation.mutationDuringViewUpdate"])
    #expect(second.diagnostics.runtime.issues.isEmpty)
    let firstSurface = first.rasterSurface.lines.joined(separator: "\n")
    let secondSurface = second.rasterSurface.lines.joined(separator: "\n")
    #expect(firstSurface.contains("Workspace"))
    #expect(!firstSurface.contains("Refused prompt"))
    #expect(secondSurface.contains("Workspace"))
    #expect(
      !secondSurface.contains("Refused prompt"), "refused mutation surfaced:\n\(secondSurface)")
    #expect(ImperativeRuntimeIssueQueue.drain().isEmpty)
  }

  @Test("an imperative presentation outside a view update applies without a warning")
  func imperativePresentationOutsideViewUpdateApplies() throws {
    _ = ImperativeRuntimeIssueQueue.drain()
    let renderer = DefaultRenderer()
    let capture = PresentationHandleCapture()
    let first = renderer.render(
      PresentationHandleCapturingProbe(capture: capture),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 40, height: 8)
    )
    let handle = try #require(capture.handle)
    let item = try #require(capture.item)
    handle.present(item)
    #expect(ImperativeRuntimeIssueQueue.pending.isEmpty)
    let second = renderer.render(
      PresentationHandleCapturingProbe(capture: capture),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 40, height: 8)
    )

    #expect(!first.rasterSurface.lines.joined(separator: "\n").contains("Deferred prompt"))
    let secondSurface = second.rasterSurface.lines.joined(separator: "\n")
    #expect(
      secondSurface.contains("Deferred prompt"), "imperative prompt missing:\n\(secondSurface)")
    #expect(first.diagnostics.runtime.issues.isEmpty)
    #expect(second.diagnostics.runtime.issues.isEmpty)
  }

  @Test("declarative presentation reports no mutation warning")
  func declarativePresentationReportsNoMutationWarning() {
    _ = ImperativeRuntimeIssueQueue.drain()
    let artifacts = DefaultRenderer().render(
      ConditionalAlertPresentationView(showAlertSource: true),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 40, height: 8)
    )
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("Delete project"))
    #expect(
      artifacts.diagnostics.runtime.issues.filter { $0.code.hasPrefix("presentation.") }.isEmpty)
  }

  @Test("toast renders in the bottom-left corner by default")
  func toastRendersInBottomLeftCorner() {
    let artifacts = DefaultRenderer().render(
      Text("Workspace")
        .toast(
          "Action performed",
          isPresented: .constant(true),
          style: .success
        )
        .frame(width: 24, height: 8, alignment: .topLeading),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 24, height: 8)
    )

    let lines = artifacts.rasterSurface.lines
    let messageIndex = try! #require(
      lines.firstIndex(where: { $0.contains("Action performed") })
    )
    let messageLine = lines[messageIndex]

    #expect(messageIndex >= 3)
    #expect(messageLine.first != " ")
  }

  // MARK: Carried palette lifecycle (STUI-1234)

  /// Opening the palette moves focus into its filter, so the run loop commits
  /// the open and re-renders once for focus, carrying the committed lifecycle
  /// plan to the re-render's end. A dismissal that arrives while that
  /// re-render is suspended supersedes it; the carried appear and initial
  /// change handlers must still run while the palette is mounted, not after
  /// the dismissal commit has retired their owner.
  @Test("a palette appear carried past a superseded focus re-render runs while mounted")
  func paletteAppearCarriedPastSupersededRerenderRunsWhileMounted() async throws {
    let model = PaletteAppearModel()
    let probe = PaletteAppearProbe()
    let root = testIdentity("PaletteAppearCarryRoot")
    let harness = try StressRuntimeHarness(rootIdentity: root, size: .init(width: 60, height: 16)) {
      PaletteAppearFixture(model: model, probe: probe)
    }
    defer { harness.shutdown() }
    let coordinator = harness.runLoop.lifecycleCoordinator
    let appearSkips = coordinator.appearHandlerSkipCount
    let changeSkips = coordinator.changeHandlerSkipCount

    try await openAndDismissDuringFocusRerender(harness: harness, root: root, model: model) {
      probe.opens = 1
    }
    #expect(!harness.frame.contains("Probe filter"))

    probe.opens = 2
    model.isPresented = true
    #expect(try harness.renderAfterExternalMutation().contains("Probe filter"))
    model.isPresented = false
    _ = try harness.renderAfterExternalMutation()

    #expect(probe.appears == [1, 2], "an open's appear handler did not run")
    #expect(probe.appearLanded == [true, true], "an appear handler ran against a retired owner")
    #expect(probe.changeLanded.allSatisfy { $0 }, "\(probe.changeLanded)")
    #expect(probe.changeLanded.count == 2)
    #expect(probe.disappears == 2)
    #expect(coordinator.appearHandlerSkipCount == appearSkips)
    #expect(coordinator.changeHandlerSkipCount == changeSkips)
  }

  /// The default palette body under the same interleaving: no committed
  /// lifecycle callback is reported lost, and every open starts with a
  /// cleared filter and the first command selected.
  @Test("the default palette under a superseded focus re-render loses no lifecycle callback")
  func defaultPaletteUnderSupersededRerenderLosesNoLifecycleCallback() async throws {
    let model = PaletteAppearModel()
    let root = testIdentity("DefaultPaletteAppearCarryRoot")
    let harness = try StressRuntimeHarness(rootIdentity: root, size: .init(width: 60, height: 16)) {
      PaletteAppearFixture(model: model, probe: nil)
    }
    defer { harness.shutdown() }
    let coordinator = harness.runLoop.lifecycleCoordinator
    let appearSkips = coordinator.appearHandlerSkipCount
    let changeSkips = coordinator.changeHandlerSkipCount

    try await openAndDismissDuringFocusRerender(harness: harness, root: root, model: model) {}
    #expect(!harness.frame.contains("Filter commands"))
    #expect(coordinator.appearHandlerSkipCount == appearSkips)
    #expect(coordinator.changeHandlerSkipCount == changeSkips)

    model.isPresented = true
    let reopened = try harness.renderAfterExternalMutation()
    #expect(reopened.contains("Filter commands"), "\(reopened)")
    #expect(reopened.contains("> Alpha"), "\(reopened)")
    _ = try harness.paste("zz")
    #expect(harness.frame.contains("No matches."), "\(harness.frame)")
    model.isPresented = false
    _ = try harness.renderAfterExternalMutation()
    model.isPresented = true
    let reset = try harness.renderAfterExternalMutation()
    #expect(reset.contains("Filter commands"), "the reopened filter kept its query:\n\(reset)")
    #expect(reset.contains("> Alpha"), "\(reset)")
    #expect(coordinator.appearHandlerSkipCount == appearSkips)
  }

  /// Opens the palette through the async driver, holds the open's own frame
  /// tail (raster entry 1) and dismisses while it is held. The open still
  /// commits (it carries lifecycle work), moves focus into the filter and
  /// re-renders for focus; the pending dismissal supersedes that re-render
  /// before its tail starts, so the open's committed plan is carried into the
  /// dismissal's frame.
  private func openAndDismissDuringFocusRerender(
    harness: StressRuntimeHarness<PaletteAppearFixture>,
    root: Identity,
    model: PaletteAppearModel,
    beforeOpen: () -> Void
  ) async throws {
    let gate = AsyncFrameTailBlockingGate(blockingEntry: 1)
    harness.runLoop.renderer.setFrameTailRenderHooks(.init(beforeRaster: { gate.beforeRaster() }))
    defer {
      gate.release()
      harness.runLoop.renderer.setFrameTailRenderHooks(nil)
    }
    let pump = SwiftTUIRuntime.RunLoop<Int, PaletteAppearFixture>.EventPump(
      stream: AsyncStream { $0.finish() }, drainEvents: { [] }, hasPendingEvents: { false },
      cancel: {}, scheduleDeadlineWake: { _ in })
    beforeOpen()
    model.isPresented = true
    harness.runLoop.scheduler.requestInvalidation(of: [root])
    let finished = AsyncEvent()
    let renderTask = Task { @MainActor in
      var frames = 0
      _ = try await harness.runLoop.renderPendingFramesAsync(
        renderedFrames: &frames, eventPump: pump)
      finished.fire()
    }
    let blocked = await firstFrameTailSignal(blocked: gate, orFinished: finished)
    #expect(blocked, "opening the palette never reached its frame tail")
    if blocked {
      model.isPresented = false
      harness.runLoop.scheduler.requestInvalidation(of: [root])
    }
    gate.release()
    try await renderTask.value
    if !blocked {
      model.isPresented = false
      _ = try harness.renderAfterExternalMutation()
    }
  }
}

@MainActor
private final class FilteredPaletteSemanticProbe {
  var selection: String?
}

@MainActor
private struct FilteredPaletteSemanticFixture: View {
  let probe: FilteredPaletteSemanticProbe

  var body: some View {
    Panel(id: "palette-source") {
      Text("Workspace")
    }
    .paletteCommand(name: "Counter", description: "Switch to counter") {
      probe.selection = "Counter"
    }
    .paletteCommand(name: "Images") {
      probe.selection = "Images"
    }
    .panel(id: "palette-host")
    .paletteSheet("Command palette", isPresented: .constant(true))
  }
}

@MainActor
private struct CurrentStatusSemanticFixture: View {
  @State private var status = "Clipboard: idle"

  var body: some View {
    VStack(alignment: .leading) {
      Button("Copy journey token") {
        status = "Clipboard: copied"
      }
      Text(status)
        .accessibilityRole(.status)
        .accessibilityLiveRegion(.polite)
    }
  }
}

private struct ConditionalAlertPresentationView: View {
  var showAlertSource: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      if showAlertSource {
        Text("Attachment")
          .alert(
            "Delete project",
            isPresented: .constant(true),
            actions: {
              Button("Delete") {}
            },
            message: {
              Text("This cannot be undone.")
            }
          )
      } else {
        Text("Attachment removed")
      }
    }
    .frame(width: 40, height: 8, alignment: .topLeading)
  }
}

private struct RenderTimePresentationMutationProbe: PrimitiveView, IterativeResolvableView {
  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    context.environmentValues.alertPresentationCoordinator.present(
      renderTimeAlertItem(title: "Illegal mutation", in: context)
    )

    return Text("Workspace").resolveElementsWork(in: context)
  }
}

@MainActor
private final class RenderTimePresentationTrigger {
  var presentations = 0
}

/// Presents during its first resolve only, so a later frame shows whether the
/// refused mutation was applied after the update pass.
private struct OnceRenderTimePresentationProbe: PrimitiveView, IterativeResolvableView {
  let trigger: RenderTimePresentationTrigger

  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    if trigger.presentations == 0 {
      trigger.presentations += 1
      context.environmentValues.alertPresentationCoordinator.present(
        renderTimeAlertItem(title: "Refused prompt", in: context)
      )
    }
    return Text("Workspace").resolveElementsWork(in: context)
  }
}

@MainActor
private final class PresentationHandleCapture {
  var handle: PresentationCoordinatorHandle<PromptPresentationItem>?
  var item: PromptPresentationItem?
}

/// Captures the live alert handle and an item during resolve without
/// presenting, so the test can present from outside any view update.
private struct PresentationHandleCapturingProbe: PrimitiveView, IterativeResolvableView {
  let capture: PresentationHandleCapture

  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    capture.handle = context.environmentValues.alertPresentationCoordinator
    if capture.item == nil {
      capture.item = renderTimeAlertItem(title: "Deferred prompt", in: context)
    }
    return Text("Workspace").resolveElementsWork(in: context)
  }
}

@MainActor
private func renderTimeAlertItem(
  title: String,
  in context: ResolveContext
) -> PromptPresentationItem {
  let spec = alertPromptPresentationSpec()
  return PromptPresentationItem(
    id: presentationAttachmentID(
      for: context.identity,
      token: spec.token
    ),
    title: title,
    surface: spec.prepareSurface(context),
    actionPayloads: portalAttachmentDeclaredBuilderChildren(
      from: Button("Dismiss") {},
      edge: nil
    ),
    messagePayloads: portalAttachmentDeclaredBuilderChildren(
      from: Text("Should never render."),
      edge: nil
    ),
    contentPayloads: [],
    dismiss: {}
  )
}

/// The shipped path installs no onInvalidMutation hook. The child process
/// turns a trap into an exit status instead of ending the test run.
private func expectRenderTimeMutationWarnsWithoutTrapping() async {
  await #expect(processExitsWith: .success) {
    await MainActor.run {
      PresentationMutationGuard.onInvalidMutation = nil
      _ = ImperativeRuntimeIssueQueue.drain()
      let artifacts = DefaultRenderer().render(
        RenderTimePresentationMutationProbe(),
        context: .init(identity: testIdentity("Root")),
        proposal: .init(width: 40, height: 8)
      )
      let warnings = artifacts.diagnostics.runtime.issues.filter {
        $0.code == "presentation.mutationDuringViewUpdate"
      }
      #expect(warnings.count == 1)
      #expect(warnings.first?.severity == .warning)
      #expect(
        warnings.first?.message.hasPrefix(
          "AlertPresentationCoordinator.present(_:) must not be called during view update.")
          == true)
      let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
      #expect(surface.contains("Workspace"))
      #expect(!surface.contains("Illegal mutation"))
    }
  }
}

private func hasFillCommand(
  in node: DrawNode,
  bounds: CellRect
) -> Bool {
  if node.commands.contains(where: { hasFillCommand($0, bounds: bounds) }) {
    return true
  }

  return node.children.contains(where: { hasFillCommand(in: $0, bounds: bounds) })
}

private func hasFillCommand(
  _ command: DrawCommand,
  bounds: CellRect
) -> Bool {
  switch command {
  case .group(_, let children):
    return children.contains(where: { hasFillCommand($0, bounds: bounds) })
  case .fill(let commandBounds, _, _, _, _):
    return commandBounds == bounds
  case .clip(_, let child):
    return hasFillCommand(child, bounds: bounds)
  default:
    return false
  }
}

private func viewKindNames(
  in node: ResolvedNode
) -> [String] {
  var kinds: [String] = []
  collectViewKindNames(in: node, into: &kinds)
  return kinds
}

private func collectViewKindNames(
  in node: ResolvedNode,
  into kinds: inout [String]
) {
  if case .view(let name) = node.kind {
    kinds.append(name)
  }

  for child in node.children {
    collectViewKindNames(in: child, into: &kinds)
  }
}

private func findSubstring(
  _ substring: String,
  in lines: [String]
) -> (x: Int, y: Int)? {
  let needle = Array(substring)
  guard !needle.isEmpty else {
    return nil
  }

  for (y, line) in lines.enumerated() {
    let haystack = Array(line)
    guard haystack.count >= needle.count else {
      continue
    }
    let maxStart = haystack.count - needle.count
    for start in 0...maxStart {
      let end = start + needle.count
      if Array(haystack[start..<end]) == needle {
        return (x: start, y: y)
      }
    }
  }
  return nil
}

private func findCharacter(
  _ character: Character,
  in lines: [String]
) -> (x: Int, y: Int)? {
  for (y, line) in lines.enumerated() {
    for (x, candidate) in line.enumerated() where candidate == character {
      return (x: x, y: y)
    }
  }
  return nil
}

@MainActor
final class PaletteAppearModel {
  var isPresented = false

  var binding: Binding<Bool> {
    Binding(get: { self.isPresented }, set: { self.isPresented = $0 })
  }
}

/// Records each palette lifetime's appear, initial change and disappear, and
/// whether each handler's own @State write landed on a live owner.
@MainActor
final class PaletteAppearProbe {
  var opens = 0
  private(set) var appears: [Int] = []
  private(set) var appearLanded: [Bool] = []
  private(set) var changeLanded: [Bool] = []
  var disappears = 0

  func recordAppear(open: Int, landed: Bool) {
    appears.append(open)
    appearLanded.append(landed)
  }

  func recordChange(landed: Bool) {
    changeLanded.append(landed)
  }
}

@MainActor
struct PaletteAppearFixture: View {
  let model: PaletteAppearModel
  let probe: PaletteAppearProbe?

  var body: some View {
    let host = Panel(id: "palette-appear-source") {
      Text("Workspace")
    }
    .paletteCommand(name: "Alpha") {}
    .paletteCommand(name: "Beta") {}
    .panel(id: "palette-appear-host")
    // The palette reads its style where the sheet is declared, so the style
    // goes outside the declaration.
    let sheet = host.paletteSheet("Command palette", isPresented: model.binding)
    if let probe {
      sheet.paletteStyle(AppearProbePaletteStyle(probe: probe))
    } else {
      sheet
    }
  }
}

private struct AppearProbePaletteStyle: PaletteStyle {
  let probe: PaletteAppearProbe

  @MainActor func makeBody(configuration: PaletteStyleConfiguration) -> some View {
    AppearProbePaletteBody(commandCount: configuration.commands.count, probe: probe)
  }
}

@MainActor
private struct AppearProbePaletteBody: View {
  let commandCount: Int
  let probe: PaletteAppearProbe
  @State private var query = "seed"
  @State private var mark = -1
  @FocusState private var isQueryFocused: Bool
  @Namespace private var filterScope

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      TextField("Probe filter", text: $query)
        .focused($isQueryFocused)
        .prefersDefaultFocus(in: filterScope)
      Text("commands \(commandCount)")
    }
    .focusScope(filterScope)
    .onAppear {
      query = ""
      probe.recordAppear(open: probe.opens, landed: stampLanded())
    }
    .onChange(of: commandCount, initial: true) {
      probe.recordChange(landed: stampLanded())
    }
    .onDisappear {
      probe.disappears += 1
    }
  }

  /// Writes this lifetime's open number into its own @State and reads it
  /// back: a retired owner discards the write and reads the authored seed.
  private func stampLanded() -> Bool {
    let open = probe.opens
    mark = open
    return mark == open
  }
}
