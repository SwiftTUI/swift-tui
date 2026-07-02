@_spi(Testing) import SwiftTUICore
@_spi(Runners) import SwiftTUIRuntime
@_spi(Testing) import SwiftTUITestSupport
import SwiftTUIViews
import Testing

/// Regression coverage for the scroll drag-to-pan feature shadowing taps on
/// controls *inside* a scroll view.
///
/// The `ScrollView` body registers a `.down`/`.up`/`.dragged` pan handler and is
/// marked `captureOnPress`. A press that lands on an inner button bubbles up to
/// that handler via the run loop's route-fallback walk; before the fix the
/// handler claimed the `.down` (and consumed the `.up`) whenever the content
/// overflowed, so the inner button's action never fired. This only reproduces on
/// the scene (`WindowGroup`) hosting path — there the scroll handler's
/// registration route matches the fallback lookup; the direct-`RunLoop` path
/// dodged it on an `ownerNodeID` mismatch — which is why the terminal gallery
/// froze (every animation button was dead) while isolated unit tests passed.
@MainActor
struct ScrollHostedControlActivationTests {
  final class TapBox { var taps = 0 }

  /// Yields a fixed event script through the scene host's terminal-input path.
  /// Activation is synchronous on `.up`, so a `down, up, ctrl-D` script needs no
  /// timeout/hold to observe the button firing.
  private final class ScriptedSceneInputReader: InputReading, TerminalInputReading {
    private let scriptedEvents: [InputEvent]
    init(_ scriptedEvents: [InputEvent]) { self.scriptedEvents = scriptedEvents }
    func events() -> AsyncStream<KeyPress> { AsyncStream { $0.finish() } }
    func inputEvents() -> AsyncStream<InputEvent> {
      AsyncStream { continuation in
        for event in scriptedEvents { continuation.yield(event) }
        continuation.finish()
      }
    }
  }

  private final class FrameRecordingHost: PresentationSurface {
    let surfaceSize: CellSize
    let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
    let appearance: TerminalAppearance = .fallback
    init(surfaceSize: CellSize) { self.surfaceSize = surfaceSize }
    func enableRawMode() throws {}
    func disableRawMode() throws {}
    func clearScreen() throws {}
    func moveCursor(to _: CellPoint) throws {}
    @discardableResult
    func present(_: RasterSurface) throws -> TerminalPresentationMetrics { .init() }
    func write(_: String) throws {}
  }

  /// The center of the interaction region whose identity contains `idToken`,
  /// from a one-shot bare render of `content`.
  private func clickLocation<Content: View>(
    forControl idToken: String,
    in content: Content,
    surfaceSize: CellSize
  ) throws -> PointerLocation {
    var env = EnvironmentValues()
    env.terminalSize = surfaceSize
    let artifacts = DefaultRenderer().render(
      content,
      context: .init(identity: testIdentity("ScrollHostedProbe"), environmentValues: env),
      proposal: .init(width: surfaceSize.width, height: surfaceSize.height))
    let rect = try #require(
      artifacts.semanticSnapshot.interactionRegions
        .first { $0.identity.description.contains(idToken) }?.rect)
    return .cellFallback(
      CellPoint(x: rect.origin.x + rect.size.width / 2, y: rect.origin.y + rect.size.height / 2))
  }

  @Test(
    "a tap on a button inside an overflowing ScrollView activates it on the scene host",
    arguments: [false, true])
  func tapOnButtonInsideScrollViewActivates(inScrollView: Bool) async throws {
    let size = CellSize(width: 40, height: 10)
    let taps = TapBox()
    struct Fixture: View {
      let taps: TapBox
      let inScrollView: Bool
      @ViewBuilder var content: some View {
        VStack(alignment: .leading, spacing: 0) {
          Button("PRESS") { taps.taps += 1 }.id("PRESSBTN")
          ForEach(0..<30) { Text("row \($0)") }  // overflow so the body would pan
        }
      }
      var body: some View {
        Group {
          if inScrollView {
            ScrollView { content }
          } else {
            VStack(alignment: .leading, spacing: 0) {
              content
              Spacer(minLength: 0)
            }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    }
    let loc = try clickLocation(
      forControl: "PRESSBTN", in: Fixture(taps: taps, inScrollView: inScrollView), surfaceSize: size
    )

    let result = try await runTestSceneSession(
      scene: WindowGroup { Fixture(taps: taps, inScrollView: inScrollView) },
      sessionName: "ScrollHostedControlActivation",
      presentationSurface: FrameRecordingHost(surfaceSize: size),
      inputReader: ScriptedSceneInputReader([
        .mouse(.init(kind: .down(.primary), location: loc)),
        .mouse(.init(kind: .up(.primary), location: loc)),
        .key(KeyPress(.character("d"), modifiers: .ctrl)),
      ]),
      signalReader: nil)

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(
      taps.taps == 1,
      "button inside ScrollView=\(inScrollView) should activate on tap; taps=\(taps.taps)")
  }
}
