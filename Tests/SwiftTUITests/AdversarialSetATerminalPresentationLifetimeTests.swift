#if canImport(Darwin) || canImport(Glibc)
  import Foundation
  import Synchronization
  import Testing
  @_spi(Testing) import SwiftTUITestSupport
  @testable import SwiftTUICore
  @_spi(Runners) @testable import SwiftTUIRuntime
  #if canImport(Darwin)
    import Darwin
  #else
    import Glibc
  #endif

  @MainActor
  @Suite(.serialized, .timeLimit(.minutes(1)))
  struct AdversarialSetATerminalPresentationLifetimeTests {
    @Test func setA1026PartialExplicitWriteFailureMakesTheRetainedScreenUnknown() throws {
      // Hypothesis: invalidation after a successful write misses a prefix that
      // reached the terminal before the controller reported a failure.
      let controller = SetAPresentationController()
      let host = host(controller)
      let original = surface("AAAA")
      try presentAndDrain(original, host)
      controller.enqueue(.init(failure: .terminal(EIO), prefixCount: 9))
      #expect(throws: TerminalHostError.failedToWrite(errno: EIO)) {
        try host.write("\u{1B}[1;1HXXXX")
      }
      #expect(controller.writes.last == "\u{1B}[1;1HXXX")
      let recovered = try host.present(original, damage: .init(dirtyRows: []))
      try host.drainPendingPresentation()
      withKnownIssue("STUI-1031: partial explicit write failure leaves the retained screen trusted")
      {
        #expect(recovered.usedFullRepaint)
        #expect(controller.writes.last == "\u{1B}[2J\u{1B}[1;1HAAAA")
      }
    }

    @Test func setA1027CursorFocusErrorConsumptionCannotTrustAFailedContentFrame() throws {
      // Hypothesis: the cursor-focus entry point consumes the writer error but
      // omits the baseline invalidation performed by ordinary presentation.
      let controller = SetAPresentationController()
      let host = host(controller)
      try presentAndDrain(surface("AAAA"), host)
      controller.enqueue(.init(failure: .terminal(ENOSPC), prefixCount: 7))
      _ = try host.present(surface("BBBB"))
      try drainWriterKeepingError(host)
      #expect(throws: TerminalHostError.failedToWrite(errno: ENOSPC)) {
        try host.presentAccessibilityCursorFocus(at: .init(x: 0, y: 0))
      }
      #expect(controller.writes.last == "\u{1B}[1;1HB")
      let recovered = try host.present(surface("BBBB"), damage: .init(dirtyRows: []))
      try host.drainPendingPresentation()
      withKnownIssue(
        "STUI-1032: cursor focus consumes a writer error without invalidating its baseline"
      ) {
        #expect(recovered.usedFullRepaint)
        #expect(controller.writes.last == "\u{1B}[2J\u{1B}[1;1HBBBB")
      }
    }

    @Test func setA1028ContentCoalescingPreservesQueuedSupplementalCursorBytes() async throws {
      // Hypothesis: replacing a pending content frame also drops independent
      // cursor-hide output, whether attached to that frame or queued alone.
      // The real run loop clears terminalCursorFocusShowsCursor after queuing
      // this hide, so subsequent frames without a caret do not submit it again.
      for attachesToContent in [false, true] {
        let controller = SetAPresentationController()
        let gate = BlockingWriteGate()
        let host = host(controller)
        defer { gate.release() }
        try presentAndDrain(surface("AAAA"), host)
        try host.presentAccessibilityCursorFocus(at: .init(x: 2, y: 0))
        try host.drainPendingPresentation()
        #expect(controller.writes.last == "\u{1B}[1;3H\u{1B}[?25h")
        let alreadyWritten = controller.writes.count
        controller.enqueue(.init(gate: gate))
        _ = try host.present(surface("BAAA"))
        try await waitForBlockedWrite(gate)
        if attachesToContent { _ = try host.present(surface("BBAA")) }
        try host.presentAccessibilityCursorFocus(at: nil)
        _ = try host.present(surface("CAAA"))
        gate.release()
        try host.drainPendingPresentation()
        let output = controller.writes.dropFirst(alreadyWritten).joined()
        #expect(output.contains("\u{1B}[1;1HC"))
        withKnownIssue("STUI-1033: content coalescing drops queued cursor-hide output") {
          #expect(
            output.contains("\u{1B}[?25l"),
            "Queued cursor hide was lost; attached to pending content: \(attachesToContent)")
        }
      }
    }

    @Test func setA1029ActiveWriteFailureDiscardsItsDependentPendingFrame() async throws {
      // Hypothesis: a queued delta survives the failed baseline it depends on,
      // reaching the terminal before recovery can establish a complete screen.
      let controller = SetAPresentationController()
      let gate = BlockingWriteGate()
      controller.enqueue(.init(gate: gate, failure: .terminal(EIO), prefixCount: 2))
      let host = host(controller)
      defer { gate.release() }
      _ = try host.present(surface("AAAA"))
      try await waitForBlockedWrite(gate)
      _ = try host.present(surface("BBBB"))
      gate.release()
      #expect(throws: TerminalHostError.failedToWrite(errno: EIO)) {
        try host.drainPendingPresentation()
      }
      #expect(controller.attempts.count == 1)
      let recovery = try host.present(surface("CCCC"), damage: .init(dirtyRows: []))
      try host.drainPendingPresentation()
      #expect(recovery.usedFullRepaint)
      #expect(controller.writes.last == "\u{1B}[2J\u{1B}[1;1HCCCC")
    }

    @Test func setA1030ForeignWriteErrorsAreReportedOnceAndDoNotStrandTheWriter() throws {
      // Hypothesis: an unexpected controller error leaves isWriting latched or
      // the error uncleared, permanently blocking later valid submissions.
      let controller = SetAPresentationController()
      controller.enqueue(.init(failure: .foreign))
      let writer = writer(controller)
      writer.submit(frame(1, "failed"))
      writer.drain()
      #expect(throws: TerminalHostError.failedToWrite(errno: EIO)) {
        try writer.consumePendingError()
      }
      try writer.consumePendingError()
      writer.submit(frame(2, "recovered"))
      writer.drain()
      try writer.consumePendingError()
      #expect(controller.writes == ["recovered"])
      #expect(writer.lastCommittedSequence() == 2)
    }

    @Test func setA1031FailedActiveSubmissionStillHasAProfilingOutcome() async throws {
      // Hypothesis: failure records the discarded pending frame but silently
      // loses the active ordinal, violating the documented total frame join.
      let controller = SetAPresentationController()
      let gate = BlockingWriteGate()
      controller.enqueue(.init(gate: gate, failure: .terminal(EIO)))
      let sink = SetAPresentationSink()
      let writer = TerminalPresentationWriter(
        controller: controller, outputFileDescriptor: 101, writeSink: sink)
      defer { gate.release() }
      writer.submit(frame(1, "active", ordinal: 701))
      try await waitForBlockedWrite(gate)
      writer.submit(frame(2, "pending", ordinal: 702))
      gate.release()
      writer.drain()
      #expect(throws: TerminalHostError.self) { try writer.consumePendingError() }
      #expect(sink.samples.filter { $0.frame == 702 }.count == 1)
      #expect(sink.samples.first { $0.frame == 702 }?.outcome == .superseded)
      withKnownIssue("STUI-1034: a failed active presentation has no profiling outcome") {
        #expect(sink.samples.filter { $0.frame == 701 }.count == 1)
      }
    }

    @Test func setA1032FinishingABlockedWriterJoinsAndDiscardsItsPendingWork() async throws {
      // Hypothesis: shutdown expires the active write but returns before its
      // dependent pending frame has been retired from the serial queue.
      let controller = SetAPresentationController()
      let backpressure = try SetAPresentationBackpressure()
      controller.enqueue(.init(backpressure: backpressure))
      let writer = writer(controller)
      defer { writer.finishWithin(.zero) }
      writer.submit(frame(1, "active"))
      await backpressure.started.wait()
      try Task.checkCancellation()
      writer.submit(frame(2, "pending"))
      let started = ContinuousClock.now
      writer.finishWithin(.milliseconds(25))
      #expect(started.duration(to: .now) < .seconds(1))
      #expect(throws: TerminalHostError.failedToWrite(errno: ETIMEDOUT)) {
        try writer.consumePendingError()
      }
      #expect(controller.attempts == ["active"])
      #expect(controller.writes.isEmpty)
      #expect(writer.lastCommittedSequence() == 1)
    }

    @Test func setA1033RepeatedFinishRequestsCannotExtendAnExpiredBudget() {
      // Hypothesis: a later teardown participant replaces an earlier deadline,
      // reviving writes after the first owner's cancellation has expired.
      let budget = TerminalWriteBudget(deadline: .now - .seconds(1))
      #expect(budget.expired)
      budget.finishWithin(.seconds(60))
      #expect(budget.expired)
      #expect(throws: TerminalHostError.failedToWrite(errno: ETIMEDOUT)) {
        try budget.check()
      }
    }

    @Test func setA1034RetiringAHostReleasesItsControllerAfterTheActiveWrite() async throws {
      // Hypothesis: the writer's queue closure either releases output ownership
      // before its write finishes or forms a cycle after completion.
      let retired = AsyncEvent()
      var controller: SetAPresentationController? = SetAPresentationController(retired: retired)
      weak let weakController = controller
      let gate = BlockingWriteGate()
      defer { gate.release() }
      controller?.enqueue(.init(gate: gate))
      var terminal: TerminalHost? = host(try #require(controller))
      _ = try terminal?.present(surface("owned"))
      try await waitForBlockedWrite(gate)
      terminal = nil
      controller = nil
      #expect(weakController != nil)
      gate.release()
      await retired.wait()
      try Task.checkCancellation()
      #expect(weakController == nil)
    }

    @Test func setA1035AFailedWriterDoesNotRetainTheRetiredHostController() throws {
      // Hypothesis: the pending error keeps a failed queue/controller cycle
      // alive even after the owner has observed the error and gone away.
      var controller: SetAPresentationController? = SetAPresentationController()
      weak let weakController = controller
      controller?.enqueue(.init(failure: .terminal(EIO)))
      var terminal: TerminalHost? = host(try #require(controller))
      _ = try terminal?.present(surface("failed"))
      #expect(throws: TerminalHostError.self) { try terminal?.drainPendingPresentation() }
      terminal = nil
      controller = nil
      #expect(weakController == nil)
    }

    @Test func setA1036ExplicitHostWritesFollowAllAlreadyQueuedPresentationBytes() async throws {
      // Hypothesis: a synchronous terminal command bypasses the writer queue
      // and interleaves its bytes ahead of an already submitted content frame.
      let controller = SetAPresentationController()
      let gate = BlockingWriteGate()
      controller.enqueue(.init(gate: gate))
      let host = host(controller)
      defer { gate.release() }
      _ = try host.present(surface("AAAA"))
      try await waitForBlockedWrite(gate)
      _ = try host.present(surface("BBBB"))
      gate.release()
      try host.write("DIRECT")
      #expect(
        controller.writes == [
          "\u{1B}[2J\u{1B}[1;1HAAAA", "\u{1B}[1;1HBBBB", "DIRECT",
        ])
    }

    @Test func setA1037OneHostsWriteErrorCannotInvalidateAnotherHostsBaseline() throws {
      // Hypothesis: error or retained-surface bookkeeping is inadvertently
      // shared between independently constructed terminal presentations.
      let failedController = SetAPresentationController()
      let goodController = SetAPresentationController()
      let failed = host(failedController)
      let good = host(goodController)
      try presentAndDrain(surface("AAAA"), good)
      failedController.enqueue(.init(failure: .terminal(EIO)))
      _ = try failed.present(surface("bad!"))
      #expect(throws: TerminalHostError.self) { try failed.drainPendingPresentation() }
      let metrics = try good.present(surface("AAZA"))
      try good.drainPendingPresentation()
      #expect(metrics.strategy == .incremental)
      #expect(goodController.writes.last == "\u{1B}[1;3HZ")
    }

    @Test func setA1038ProductionHostPresentsOnlyToItsOwnedOutputPipe() throws {
      // Hypothesis: the asynchronous host path accidentally writes to stdout
      // or its input descriptor instead of the supplied output descriptor.
      let input = try SetAPresentationPipe()
      let output = try SetAPresentationPipe()
      let host = TerminalHost(
        inputFileDescriptor: input.readFD, outputFileDescriptor: output.writeFD,
        fallbackSize: .init(width: 4, height: 1), capabilityProfile: .previewUnicode,
        environment: [:], usesTerminalEditOperations: false)
      try presentAndDrain(surface("ABCD"), host)
      try presentAndDrain(surface("ABZD"), host)
      #expect(try output.readAvailable() == "\u{1B}[2J\u{1B}[1;1HABCD\u{1B}[1;3HZ")
      #expect(try input.readAvailable().isEmpty)
    }

    @Test func setA1039QueuedResizePlansAgainstTheActuallyDequeuedDimensions() async throws {
      // Hypothesis: a dropped intermediate size is adopted as the baseline,
      // making the final dimensions look unchanged and skipping a full clear.
      let controller = SetAPresentationController()
      let gate = BlockingWriteGate()
      controller.enqueue(.init(gate: gate))
      let host = host(controller)
      defer { gate.release() }
      _ = try host.present(surface("AAAA"))
      try await waitForBlockedWrite(gate)
      _ = try host.present(surface("BB"))
      let metrics = try host.present(surface("CC"))
      gate.release()
      try host.drainPendingPresentation()
      #expect(metrics.usedFullRepaint)
      #expect(
        controller.writes == [
          "\u{1B}[2J\u{1B}[1;1HAAAA", "\u{1B}[2J\u{1B}[1;1HCC",
        ])
    }

    @Test func setA1040TransientSizeQueryFailureDoesNotPoisonFutureHostGeometry() {
      // Hypothesis: one failed size query permanently caches fallback geometry
      // instead of observing the terminal again when it becomes available.
      let controller = SetAPresentationController()
      let host = host(controller)
      controller.size = .init(width: 17, height: 5)
      #expect(host.surfaceSize == .init(width: 17, height: 5))
      controller.size = nil
      #expect(host.surfaceSize == .init(width: 20, height: 8))
      controller.size = .init(width: 11, height: 3)
      #expect(host.surfaceSize == .init(width: 11, height: 3))
      #expect(controller.sizeDescriptors == [101, 101, 101])
    }

    @Test func setA1041RevertingToTheActiveFrameRetiresPendingContentWithoutWritingIt() async throws
    {
      // Hypothesis: a zero-byte recovery frame leaves the obsolete queued
      // content alive, or promotes it to the next delta's baseline.
      let controller = SetAPresentationController()
      let gate = BlockingWriteGate()
      controller.enqueue(.init(gate: gate))
      let host = host(controller)
      defer { gate.release() }
      _ = try host.present(surface("AAAA"))
      try await waitForBlockedWrite(gate)
      _ = try host.present(surface("BBBB"))
      let reverted = try host.present(surface("AAAA"))
      #expect(reverted.bytesWritten == 0)
      gate.release()
      try host.drainPendingPresentation()
      #expect(controller.writes.count == 1)
      try presentAndDrain(surface("AAZA"), host)
      #expect(controller.writes.last == "\u{1B}[1;3HZ")
    }

    @Test func setA1042EmptyTextDamageCannotSuppressChangedImageOwnership() throws {
      // Hypothesis: the text damage fast path hides a new image source at the
      // same bounds, leaving the old placement visible indefinitely.
      let controller = SetAPresentationController()
      let host = kittyHost(controller)
      try presentAndDrain(imageSurface([try attachment(1)]), host)
      let firstID = try #require(transmittedIDs(controller.writes.last ?? "").first)
      let metrics = try host.present(
        imageSurface([try attachment(2)]), damage: .init(dirtyRows: []))
      try host.drainPendingPresentation()
      let output = try #require(controller.writes.last)
      #expect(metrics.cellsChanged == 0)
      #expect(metrics.graphicsReplayScope == .full)
      #expect(transmittedIDs(output).count == 1)
      #expect(!transmittedIDs(output).contains(firstID))
      #expect(freedIDs(output).contains(firstID))
    }

    @Test func setA1043DroppedSynchronizedFramesCannotLeaveAnUnbalancedModeEnvelope() async throws {
      // Hypothesis: synchronization is queued separately from frame payloads,
      // so coalescing drops a closing sequence while retaining its opening.
      let controller = SetAPresentationController()
      let gate = BlockingWriteGate()
      controller.enqueue(.init(gate: gate))
      var profile = TerminalCapabilityProfile.previewUnicode
      profile.supportsSynchronizedOutput = true
      let host = host(controller, profile: profile)
      defer { gate.release() }
      // Incremental synchronization is promised for at least two dirty rows;
      // a single-row delta intentionally has no synchronized-output envelope.
      let initial = RasterSurface(size: .init(width: 4, height: 2), lines: ["AAAA", "aaaa"])
      let pending = RasterSurface(size: .init(width: 4, height: 2), lines: ["BBBB", "bbbb"])
      let latest = RasterSurface(size: .init(width: 4, height: 2), lines: ["CCCC", "cccc"])
      let firstMetrics = try host.present(initial)
      #expect(firstMetrics.usedSynchronizedOutput)
      try await waitForBlockedWrite(gate)
      _ = try host.present(pending)
      let latestMetrics = try host.present(latest)
      #expect(latestMetrics.usedSynchronizedOutput)
      gate.release()
      try host.drainPendingPresentation()
      #expect(controller.writes.count == 2)
      for output in controller.writes {
        #expect(output.hasPrefix("\u{1B}[?2026h"))
        #expect(output.hasSuffix("\u{1B}[?2026l"))
        #expect(output.components(separatedBy: "\u{1B}[?2026h").count == 2)
        #expect(output.components(separatedBy: "\u{1B}[?2026l").count == 2)
      }
      #expect(!controller.writes.joined().contains("BBBB"))
    }

    @Test func setA1044CoalescingKeepsOrdinalAndUTF8MetricsWithTheirOwnSubmission() async throws {
      // Hypothesis: supplemental bytes or replacement frames overwrite the
      // pending frame's ordinal/byte accounting and misattribute latency.
      let controller = SetAPresentationController()
      let gate = BlockingWriteGate()
      controller.enqueue(.init(gate: gate))
      let sink = SetAPresentationSink()
      let writer = TerminalPresentationWriter(
        controller: controller, outputFileDescriptor: 101, writeSink: sink)
      defer { gate.release() }
      writer.submit(frame(1, "one", ordinal: 90))
      try await waitForBlockedWrite(gate)
      writer.submit(frame(2, "é", ordinal: 120))
      writer.submitSupplementalOutput("focus")
      writer.submit(frame(3, "界", ordinal: 180))
      gate.release()
      writer.drain()
      let records = sink.samples
      #expect(records.count == 3)
      #expect(records.first { $0.frame == 120 }?.outcome == .superseded)
      #expect(records.first { $0.frame == 120 }?.bytes == "éfocus".utf8.count)
      #expect(records.first { $0.frame == 180 }?.bytes == "界".utf8.count)
      #expect(records.first { $0.frame == 180 }?.outcome == .written)
      #expect(Set(records.map(\.frame)) == [90, 120, 180])
    }

    @Test func setA1045ImageChurnKeepsTerminalResidentPixelDataBounded() throws {
      // Hypothesis: changing content under one image owner deletes placements
      // but leaks each prior image's pixel buffer in the actual terminal store.
      let controller = SetAPresentationController()
      let host = kittyHost(controller)
      var resident: Set<UInt32> = []
      var allUploaded: Set<UInt32> = []
      for value in UInt8(1)...32 {
        try presentAndDrain(imageSurface([try attachment(value)]), host)
        let output = try #require(controller.writes.last)
        let uploaded = transmittedIDs(output)
        try #require(uploaded.count == 1)
        allUploaded.formUnion(uploaded)
        resident.formUnion(uploaded)
        resident.subtract(freedIDs(output))
        #expect(resident == uploaded, "resident image IDs after revision \(value): \(resident)")
      }
      #expect(allUploaded.count == 32)
      try presentAndDrain(imageSurface([]), host)
      resident.subtract(freedIDs(controller.writes.last ?? ""))
      #expect(resident.isEmpty)
    }

    @Test func setA1046SharedPixelsRemainResidentWhileAnotherPlacementNeedsThem() throws {
      // Hypothesis: removing one identity frees content-addressed image data
      // still referenced by another independently positioned attachment.
      let controller = SetAPresentationController()
      let host = kittyHost(controller)
      let first = try attachment(7, x: 0, name: "first")
      let second = try attachment(7, x: 2, name: "second")
      try presentAndDrain(imageSurface([first, second]), host)
      let shared = try #require(transmittedIDs(controller.writes.last ?? "").first)
      try presentAndDrain(imageSurface([second]), host)
      let output = try #require(controller.writes.last)
      #expect(!freedIDs(output).contains(shared))
      #expect(output.contains("_Ga=p"))
      #expect(transmittedIDs(output).isEmpty)
      try presentAndDrain(imageSurface([]), host)
      #expect(freedIDs(controller.writes.last ?? "") == [shared])
    }

    @Test func setA1047FailedImageUploadCannotRecoverWithAPlacementOnlyCommand() throws {
      // Hypothesis: the eager transmit-ID cache survives a partial failure,
      // making recovery refer to pixel data the terminal never received.
      let controller = SetAPresentationController()
      let host = kittyHost(controller)
      let raster = imageSurface([try attachment(13)])
      controller.enqueue(.init(failure: .terminal(EIO), prefixCount: 5))
      _ = try host.present(raster)
      #expect(throws: TerminalHostError.self) { try host.drainPendingPresentation() }
      let recovered = try host.present(raster)
      try host.drainPendingPresentation()
      #expect(recovered.usedFullRepaint)
      #expect(transmittedIDs(controller.writes.last ?? "").count == 1)
      #expect(!(controller.writes.last ?? "").contains("_Ga=p"))
    }

    @Test func setA1048RawScreenInvalidationPreservesDataNeededForTheNextImageSweep() throws {
      // Hypothesis: clearing the cell baseline also forgets resident Kitty
      // data, so a later image-free repaint can no longer reclaim its buffer.
      let controller = SetAPresentationController()
      let host = kittyHost(controller)
      try presentAndDrain(imageSurface([try attachment(19)]), host)
      let old = try #require(transmittedIDs(controller.writes.last ?? "").first)
      try host.clearScreen()
      try presentAndDrain(imageSurface([]), host)
      #expect(freedIDs(controller.writes.last ?? "") == [old])
    }

    @Test func setA1049DroppingAnImageDeletionRestoresItsResidentDataBookkeeping() async throws {
      // Hypothesis: a queued deletion is treated as having freed data even
      // when coalescing drops it, causing reappearance to retransmit or leak it.
      let controller = SetAPresentationController()
      let host = kittyHost(controller)
      let image = try attachment(23)
      try presentAndDrain(imageSurface([image]), host)
      let originalID = try #require(transmittedIDs(controller.writes.last ?? "").first)
      let gate = BlockingWriteGate()
      controller.enqueue(.init(gate: gate))
      defer { gate.release() }
      _ = try host.present(imageSurface([image], text: "A   "))
      try await waitForBlockedWrite(gate)
      _ = try host.present(imageSurface([], text: "A   "))
      _ = try host.present(imageSurface([image], text: "B   "))
      gate.release()
      try host.drainPendingPresentation()
      let output = try #require(controller.writes.last)
      #expect(transmittedIDs(output).isEmpty)
      #expect(!freedIDs(output).contains(originalID))
      try presentAndDrain(imageSurface([]), host)
      #expect(freedIDs(controller.writes.last ?? "") == [originalID])
    }

    @Test func setA1050FinishingOneWriterCannotCancelAnIndependentWriter() async throws {
      // Hypothesis: a shared cancellation budget lets shutdown of one terminal
      // expire an unrelated writer that is still accepting presentation work.
      let firstController = SetAPresentationController()
      let secondController = SetAPresentationController()
      let firstBackpressure = try SetAPresentationBackpressure()
      let secondGate = BlockingWriteGate()
      firstController.enqueue(.init(backpressure: firstBackpressure))
      secondController.enqueue(.init(gate: secondGate))
      let first = writer(firstController)
      let second = writer(secondController)
      defer {
        first.finishWithin(.zero)
        secondGate.release()
        second.drain()
      }
      first.submit(frame(1, "cancel"))
      second.submit(frame(1, "keep"))
      await firstBackpressure.started.wait()
      try Task.checkCancellation()
      try await waitForBlockedWrite(secondGate)
      first.finishWithin(.zero)
      #expect(throws: TerminalHostError.self) { try first.consumePendingError() }
      secondGate.release()
      second.drain()
      try second.consumePendingError()
      second.submit(frame(2, "working"))
      second.drain()
      #expect(secondController.writes == ["keep", "working"])
    }

    private func host(
      _ controller: SetAPresentationController,
      profile: TerminalCapabilityProfile = .previewUnicode
    ) -> TerminalHost {
      TerminalHost(
        inputFileDescriptor: 100, outputFileDescriptor: 101,
        fallbackSize: .init(width: 20, height: 8), controller: controller,
        capabilityProfile: profile, environment: [:], usesTerminalEditOperations: false)
    }

    private func kittyHost(_ controller: SetAPresentationController) -> TerminalHost {
      let terminal = host(controller, profile: .trueColor)
      terminal.capabilityProbe.cachedGraphicsCapabilities = .init(
        supportedProtocols: [.kitty], preferredProtocol: .kitty,
        cellPixelSize: .init(width: 8, height: 16))
      terminal.capabilityProbe.hasProbedGraphicsCapabilities = true
      return terminal
    }

    private func writer(_ controller: SetAPresentationController) -> TerminalPresentationWriter {
      TerminalPresentationWriter(controller: controller, outputFileDescriptor: 101)
    }

    private func frame(_ sequence: UInt64, _ output: String, ordinal: Int? = nil)
      -> TerminalPresentationFrame
    {
      .init(sequence: sequence, output: output, frameOrdinal: ordinal, submittedAt: .now())
    }

    private func surface(_ text: String) -> RasterSurface {
      .init(size: .init(width: text.count, height: 1), lines: [text])
    }

    private func presentAndDrain(_ surface: RasterSurface, _ host: TerminalHost) throws {
      _ = try host.present(surface)
      try host.drainPendingPresentation()
    }

    private func waitForBlockedWrite(_ gate: BlockingWriteGate) async throws {
      await withTaskCancellationHandler {
        await gate.waitUntilBlocked()
      } onCancel: {
        gate.release()
      }
      try Task.checkCancellation()
    }

    private func drainWriterKeepingError(_ host: TerminalHost) throws {
      // Public drain reconciles and consumes the pending error, defeating 1027.
      // Inspect only the host-owned writer so its actual serial queue provides
      // the completion barrier without changing the state under investigation.
      let session = try #require(
        Mirror(reflecting: host).descendant("presentationSession") as? TerminalPresentationSession,
        "TerminalHost's private presentationSession fixture lookup changed")
      let writer = try #require(session.writer, "The initial presentation must create a writer")
      writer.drain()
    }

    private func imageSurface(_ attachments: [RasterImageAttachment], text: String = "    ")
      -> RasterSurface
    {
      .init(size: .init(width: 4, height: 1), lines: [text], imageAttachments: attachments)
    }

    private func attachment(_ value: UInt8, x: Int = 0, name: String = "image") throws
      -> RasterImageAttachment
    {
      let bytes = try makePNGBytes(
        width: 1, height: 1,
        pixels: [rgbaPixel(red: value, green: 170, blue: 210)])
      return makeRasterImageAttachment(
        pngBytes: bytes, pixelSize: .init(width: 1, height: 1),
        bounds: .init(origin: .init(x: x, y: 0), size: .init(width: 1, height: 1)),
        identity: testIdentity("setA-terminal-lifetime", name))
    }

    // Parse protocol operations independently of the host's retained cache;
    // these sets model what the terminal receives, not implementation storage.
    private func transmittedIDs(_ output: String) -> Set<UInt32> {
      imageIDs(output, matching: "a=T")
    }

    private func freedIDs(_ output: String) -> Set<UInt32> {
      imageIDs(output, matching: "d=I")
    }

    private func imageIDs(_ output: String, matching field: String) -> Set<UInt32> {
      Set(
        output.components(separatedBy: "\u{1B}_G").dropFirst().compactMap { suffix in
          let header = suffix.prefix { $0 != ";" && $0 != "\u{1B}" }
          let fields = header.split(separator: ",")
          guard fields.contains(Substring(field)),
            let identifier = fields.first(where: { $0.hasPrefix("i=") })
          else { return nil }
          return UInt32(identifier.dropFirst(2))
        })
    }
  }

  private enum SetAPresentationFailure: Sendable {
    case terminal(Int32)
    case foreign
  }
  private enum SetAPresentationFixtureError: Error {
    case foreign
    case pipeFailure(Int32)
  }

  /// Exercises the production write-budget checks against real kernel
  /// backpressure. Readiness is an event; no test-side loop emulates a deadline.
  private final class SetAPresentationBackpressure: Sendable {
    let started = AsyncEvent()
    private let pipe: SetAPresentationPipe

    init() throws {
      pipe = try SetAPresentationPipe()
      try pipe.fillForBackpressure()
    }

    func write(_ output: String, budget: TerminalWriteBudget) throws {
      let pipe = self.pipe
      // If production stops checking its shutdown deadline, relieve the owned
      // pipe so queue.join cannot hang the suite. This only bounds that failure;
      // the ordinary timeout/error assertions still fail when the backstop runs.
      let backstop = Task {
        await AsyncEvent.firing(after: .seconds(3)).wait()
        guard !Task.isCancelled else { return }
        _ = try? pipe.readAvailable()
      }
      defer { backstop.cancel() }
      started.fire()
      try POSIXTerminalController().write(output, to: pipe.writeFD, budget: budget)
    }
  }

  private final class SetAPresentationController: TerminalControlling {
    struct Step: Sendable {
      var gate: BlockingWriteGate? = nil
      var backpressure: SetAPresentationBackpressure? = nil
      var failure: SetAPresentationFailure? = nil
      var prefixCount = 0
    }
    private struct State: Sendable {
      var steps: [Step] = []
      var attempts: [String] = []
      var writes: [String] = []
      var size: CellSize? = .init(width: 20, height: 8)
      var sizeDescriptors: [Int32] = []
    }
    private let storage = Mutex(State())
    private let retired: AsyncEvent?
    init(retired: AsyncEvent? = nil) { self.retired = retired }
    deinit { retired?.fire() }
    var writes: [String] { storage.withLock { $0.writes } }
    var attempts: [String] { storage.withLock { $0.attempts } }
    var sizeDescriptors: [Int32] { storage.withLock { $0.sizeDescriptors } }
    var size: CellSize? {
      get { storage.withLock { $0.size } }
      set { storage.withLock { $0.size = newValue } }
    }
    func enqueue(_ step: Step) { storage.withLock { $0.steps.append(step) } }
    func isATTY(_: Int32) -> Bool { false }
    func enterRawMode(input _: Int32, output _: Int32) throws -> TerminalModeSnapshot { .init() }
    func restore(_: TerminalModeSnapshot, input _: Int32, output _: Int32) throws {}
    func windowSize(of descriptor: Int32) throws -> CellSize {
      let size = storage.withLock { state in
        state.sizeDescriptors.append(descriptor)
        return state.size
      }
      guard let size else { throw TerminalHostError.failedToReadWindowSize(errno: EIO) }
      return size
    }
    func read(from _: Int32, maxBytes _: Int, timeoutMilliseconds _: Int) throws -> [UInt8] { [] }
    func write(_ output: String, to descriptor: Int32) throws {
      try write(output, to: descriptor, budget: TerminalWriteBudget(deadline: .now + .seconds(2)))
    }
    func write(_ output: String, to _: Int32, budget: TerminalWriteBudget) throws {
      let step = storage.withLock { state in
        state.attempts.append(output)
        return state.steps.isEmpty ? Step() : state.steps.removeFirst()
      }
      step.gate?.enterBlockingSection()
      try step.backpressure?.write(output, budget: budget)
      try budget.check()
      if let failure = step.failure {
        if step.prefixCount > 0 {
          storage.withLock { $0.writes.append(String(output.prefix(step.prefixCount))) }
        }
        switch failure {
        case .terminal(let code): throw TerminalHostError.failedToWrite(errno: code)
        case .foreign: throw SetAPresentationFixtureError.foreign
        }
      }
      storage.withLock { $0.writes.append(output) }
    }
  }

  private final class SetAPresentationSink: PresentationWriteSink {
    private let storage = Mutex<[PresentationWriteSample]>([])
    var samples: [PresentationWriteSample] { storage.withLock { $0 } }
    func record(_ sample: PresentationWriteSample) { storage.withLock { $0.append(sample) } }
  }

  private final class SetAPresentationPipe: Sendable {
    let readFD: Int32
    let writeFD: Int32
    init() throws {
      var descriptors: [Int32] = [-1, -1]
      guard unsafe pipe(&descriptors) == 0 else {
        throw SetAPresentationFixtureError.pipeFailure(errno)
      }
      readFD = descriptors[0]
      writeFD = descriptors[1]
      guard fcntl(readFD, F_SETFL, O_NONBLOCK) == 0 else {
        _ = close(readFD)
        _ = close(writeFD)
        throw SetAPresentationFixtureError.pipeFailure(errno)
      }
    }
    deinit {
      _ = close(readFD)
      _ = close(writeFD)
    }

    func fillForBackpressure() throws {
      let flags = fcntl(writeFD, F_GETFL)
      guard flags >= 0, fcntl(writeFD, F_SETFL, flags | O_NONBLOCK) == 0 else {
        throw SetAPresentationFixtureError.pipeFailure(errno)
      }
      var buffer = [UInt8](repeating: 0x61, count: 4096)
      while true {
        let count = unsafe write(writeFD, &buffer, buffer.count)
        if count > 0 { continue }
        if count < 0, errno == EAGAIN || errno == EWOULDBLOCK { return }
        if count < 0, errno == EINTR { continue }
        throw SetAPresentationFixtureError.pipeFailure(count == 0 ? EIO : errno)
      }
    }

    func readAvailable() throws -> String {
      var bytes: [UInt8] = []
      var buffer = [UInt8](repeating: 0, count: 1024)
      while true {
        let count = unsafe read(readFD, &buffer, buffer.count)
        if count > 0 {
          bytes.append(contentsOf: buffer.prefix(count))
          continue
        }
        if count == 0 || errno == EAGAIN || errno == EWOULDBLOCK { break }
        if errno == EINTR { continue }
        throw SetAPresentationFixtureError.pipeFailure(errno)
      }
      return String(decoding: bytes, as: UTF8.self)
    }
  }
#endif
