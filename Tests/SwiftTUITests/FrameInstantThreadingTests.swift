import Foundation
import SwiftTUIViews
import Testing

@testable import SwiftTUIRuntime

// Frame-instant totality guards.
//
// A frame is *about* one instant: its triggering deadline, or the reading it
// was consumed at. Everything inside that frame's lifetime — the animation
// timestamp, deadline re-arms, superseded-batch parks, and the pre-start-cancel
// and supersession gates — reads that one value.
//
// The shape this prevents: `computeFrameHead` stamped the draft from
// `MonotonicInstant.now()`, then `injectAnimations` sampled the clock AGAIN and
// overwrote the stamp, and the G2/G4 gates asked the wall clock while the
// consume they gate asked the injectable seam. Under the real clock those
// readings differ by microseconds and nothing looks wrong; under a virtual
// clock they differ by the whole test, which is why cadence could only ever be
// tested by driving a live session under a hang bound.

@Suite
struct FrameInstantThreadingTests {
  @MainActor
  @Test("the frame head animates to the instant it was given, and injection preserves it")
  func frameHeadCarriesTheGivenInstantThroughAnimationInjection() {
    let renderer = DefaultRenderer()
    // Far from `now` in both directions, so a stray wall-clock read cannot
    // coincidentally land on either value.
    let past = MonotonicInstant.now().advanced(by: .seconds(-3600))
    let future = MonotonicInstant.now().advanced(by: .seconds(3600))

    // `prepareFrameHead` runs computeFrameHead AND injectAnimations, so this
    // asserts the instant both arrives and survives injection — the second
    // half is the overwrite regression.
    let pastDraft = renderer.prepareFrameHeadForCancellationTesting(
      Text("frame"),
      proposal: .init(width: 10, height: 1),
      frameInstant: past
    )
    #expect(pastDraft.animationTimestamp == past)

    let futureDraft = renderer.prepareFrameHeadForCancellationTesting(
      Text("frame"),
      proposal: .init(width: 10, height: 1),
      frameInstant: future
    )
    #expect(futureDraft.animationTimestamp == future)
  }

  @MainActor
  @Test("two frames at the same instant animate to the same instant")
  func repeatedFramesAtOneInstantDoNotDrift() {
    let renderer = DefaultRenderer()
    let instant = MonotonicInstant.now().advanced(by: .seconds(-1800))

    // Wall-clock time genuinely passes between these two calls. If any part of
    // the head re-read the clock, the second draft would carry a later stamp.
    let first = renderer.prepareFrameHeadForCancellationTesting(
      Text("frame"),
      proposal: .init(width: 10, height: 1),
      frameInstant: instant
    )
    let second = renderer.prepareFrameHeadForCancellationTesting(
      Text("frame"),
      proposal: .init(width: 10, height: 1),
      frameInstant: instant
    )

    #expect(first.animationTimestamp == second.animationTimestamp)
    #expect(first.animationTimestamp == instant)
  }
}

// MARK: - Structural guard

/// Files on the frame path that must never sample the wall clock while doing
/// frame work.
///
/// They may still *default* an absent frame instant — the public one-shot
/// renderers have no scheduled frame to derive one from — so the guard allows
/// `frameInstant: MonotonicInstant = .now()` and nothing else. That
/// distinction is the whole point: defaulting at an entry point is a caller
/// stating "there is no frame to be about"; sampling inside frame work is a
/// second source of truth.
@Suite
struct FrameInstantWallClockGuardTests {
  private static let frameScopedFiles = [
    "Sources/SwiftTUIRuntime/Rendering/DefaultRendererFrameHeadCoordinator.swift",
    "Sources/SwiftTUIRuntime/SwiftTUI.swift",
    "Sources/SwiftTUIRuntime/RunLoop/RunLoop+PostCommitSupport.swift",
    "Sources/SwiftTUIRuntime/RunLoop/RunLoop+ResolveContext.swift",
    // The two drivers: `RunLoop+Rendering` derives `frameInstant` and threads
    // it, `RunLoop+FrameAcquisition` gates on it. Guarding the consumers while
    // leaving the producers unguarded would cover the easy half.
    "Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift",
    "Sources/SwiftTUIRuntime/RunLoop/RunLoop+FrameAcquisition.swift",
  ]

  /// The one real-time wait that lives on the frame path.
  ///
  /// `waitForPendingFrame` blocks for a frame that does not exist yet, so it
  /// is about the real world rather than about the frame in hand — under a
  /// frozen `frameClock` it would suspend forever. Keyed to the call, not to
  /// the file, so the rest of `RunLoop+FrameAcquisition` stays guarded.
  private static let allowedRealTimeWait = "waitForPendingFrame(at: .now())"

  @Test("frame-path files read the wall clock only to default an absent instant")
  func frameScopedFilesDoNotSampleTheWallClock() throws {
    let root = try repositoryRoot()
    var violations: [String] = []

    for relativePath in Self.frameScopedFiles {
      let contents = try String(
        contentsOf: root.appendingPathComponent(relativePath),
        encoding: .utf8
      )
      for (offset, line) in contents.split(separator: "\n", omittingEmptySubsequences: false)
        .enumerated()
      {
        guard line.contains(".now()") else {
          continue
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let isInstantDefault =
          trimmed.hasPrefix("frameInstant: MonotonicInstant = .now()")
        // Whole-line comments only: a trailing comment cannot launder a real
        // call, because such a line does not *start* with the marker. Without
        // this, prose explaining why a read is deliberate would red the guard.
        let isCommentary = trimmed.hasPrefix("//")
        let isAllowedRealTimeWait = trimmed.contains(Self.allowedRealTimeWait)
        guard !isInstantDefault, !isCommentary, !isAllowedRealTimeWait else {
          continue
        }
        violations.append("\(relativePath):\(offset + 1): \(trimmed)")
      }
    }

    #expect(
      violations.isEmpty,
      """
      Frame-path code must read the frame instant it was given, not the wall \
      clock: \(violations)
      """
    )
  }

  @Test("the guard reaches files that really do contain the allowed default")
  func guardReachesFilesItIsMeantToCover() throws {
    // A scrape whose paths have gone stale would pass the assertion above
    // forever. Every listed file must exist, and at least one must contain the
    // allowed default — otherwise the exemption is untested and the guard may
    // be matching nothing at all.
    let root = try repositoryRoot()
    var filesWithAllowedDefault = 0
    var filesWithAllowedRealTimeWait = 0
    for relativePath in Self.frameScopedFiles {
      let url = root.appendingPathComponent(relativePath)
      #expect(
        FileManager.default.fileExists(atPath: url.path),
        "frame-path guard lists a missing file: \(relativePath)"
      )
      let contents = try String(contentsOf: url, encoding: .utf8)
      if contents.contains("frameInstant: MonotonicInstant = .now()") {
        filesWithAllowedDefault += 1
      }
      if contents.contains(Self.allowedRealTimeWait) {
        filesWithAllowedRealTimeWait += 1
      }
    }
    #expect(
      filesWithAllowedDefault > 0,
      "no listed file carries the allowed default — is the guard matching anything?"
    )
    // Same reasoning for the narrower carve-out: if `waitForPendingFrame` is
    // ever renamed or moved off the frame path, this exemption silently starts
    // permitting nothing — and should be deleted rather than left as decoration.
    #expect(
      filesWithAllowedRealTimeWait > 0,
      "the real-time-wait exemption matches no listed file — delete it or fix the key"
    )
  }
}

private func repositoryRoot() throws -> URL {
  var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  while directory.path != "/" {
    if FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("Package.swift").path
    ) {
      return directory
    }
    directory.deleteLastPathComponent()
  }
  throw FrameInstantGuardError.missingPackageRoot
}

private enum FrameInstantGuardError: Error {
  case missingPackageRoot
}
