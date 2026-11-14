// The Android link route: the runtime decides what a link activation is, and
// `swift_tui_android_copy_open_link` hands the Kotlin host each destination the
// default open-link action accepted, once and in order. A custom action, a
// disabled link and a press that leaves the link never reach that queue, and a
// client that never polls leaves the default action reporting `false`.
#if !os(Windows)

  import Foundation
  import SwiftTUIAndroidHost
  @_spi(Testing) import SwiftTUICore
  @_spi(Runners) import SwiftTUIRuntime
  import Synchronization
  import Testing

  @MainActor
  @Suite("Android host link opening", .timeLimit(.minutes(1)))
  struct AndroidHostLinkOpeningTests {
    @Test func tapOnDefaultLinkQueuesTheExactDestinationOnce() async throws {
      let fixture = try await LinkFixture.started()
      defer { fixture.destroy() }

      fixture.tap(try fixture.cell(linking: LinkFixture.defaultDestination))
      try await fixture.settle()

      #expect(fixture.drainLinks() == [LinkFixture.defaultDestination])
      #expect(fixture.pendingLinkSize() == 0)
      #expect(fixture.recorder.customDestinations.isEmpty)
    }

    @Test func inlineLinkTapQueuesItsOwnDestination() async throws {
      let fixture = try await LinkFixture.started()
      defer { fixture.destroy() }

      fixture.tap(try fixture.cell(linking: LinkFixture.inlineDestination))
      try await fixture.settle()

      #expect(fixture.drainLinks() == [LinkFixture.inlineDestination])
    }

    @Test func keyboardActivationOfTheFocusedLinkQueuesItsDestination() async throws {
      let fixture = try await LinkFixture.started()
      defer { fixture.destroy() }

      // The default link is the scene's first focusable control and holds the
      // initial focus. Return activates it without any pointer event, so only
      // the runtime route can deliver it.
      fixture.host.sendInput(Array("\r".utf8))
      try await fixture.settle()

      #expect(fixture.drainLinks() == [LinkFixture.defaultDestination])
    }

    @Test func customOpenLinkActionRunsInSwiftAndQueuesNothing() async throws {
      let fixture = try await LinkFixture.started()
      defer { fixture.destroy() }

      fixture.tap(try fixture.cell(linking: LinkFixture.customDestination))
      try await fixture.settle()

      #expect(fixture.recorder.customDestinations == [LinkFixture.customDestination])
      #expect(fixture.pendingLinkSize() == 0)
    }

    @Test func disabledLinkQueuesNothing() async throws {
      let fixture = try await LinkFixture.started()
      defer { fixture.destroy() }

      fixture.tap(try fixture.cell(linking: LinkFixture.disabledDestination))
      try await fixture.settle()

      #expect(fixture.pendingLinkSize() == 0)
      #expect(fixture.recorder.customDestinations.isEmpty)
    }

    @Test func pressThatLeavesTheLinkQueuesNothing() async throws {
      let fixture = try await LinkFixture.started()
      defer { fixture.destroy() }

      let press = try fixture.cell(linking: LinkFixture.defaultDestination)
      let release = try fixture.cell(linking: LinkFixture.disabledDestination)
      fixture.host.sendInput(
        sgr(0, press, "M") + sgr(32, CellPoint(x: press.x, y: release.y), "M")
          + sgr(0, CellPoint(x: press.x, y: release.y), "m"))
      try await fixture.settle()

      #expect(fixture.pendingLinkSize() == 0)
    }

    @Test func panThatStartsOnALinkScrollsWithoutOpeningItAndLaterTapsHitTheMovedLinks()
      async throws
    {
      let host = try AndroidHostSceneHost(app: LinkScrollFixtureApp())
      let handle = AndroidHostHandleRegistry.register(host)
      defer { swift_tui_android_destroy(handle) }
      #expect(swift_tui_android_copy_open_link(handle, nil, 0) == 0)
      swift_tui_android_start(handle)
      host.resize(columns: 40, rows: 10, cellPixelWidth: 9, cellPixelHeight: 18)
      let initial = await host.surface.waitForFrame { frame in
        frame.raster.size.width == 40 && frame.raster.lines.joined().contains("Link-00")
      }

      // Touch is direct manipulation: a press on a link that travels along the
      // scroll axis pans the content, and the link is cancelled even though it
      // is still under the finger at the release.
      let press = try linkCell(in: initial, linking: "https://example.test/row/4")
      let release = CellPoint(x: press.x, y: press.y - 3)
      host.sendInput(
        sgr(0, press, "M")
          + (1...3).flatMap { sgr(32, CellPoint(x: press.x, y: press.y - $0), "M") }
          + sgr(0, release, "m"))
      let panned = await host.surface.waitForFrame { frame in
        !frame.raster.lines.joined().contains("Link-00")
      }
      #expect(panned.raster.cells[release.y][release.x].hyperlink == "https://example.test/row/4")

      // A tap on the cell the pressed link used to occupy opens the link that
      // is there now: the activation follows the frame, not the press history.
      let moved = try #require(panned.raster.cells[press.y][press.x].hyperlink)
      #expect(moved != "https://example.test/row/4")
      host.sendInput(sgr(0, press, "M") + sgr(0, press, "m"))
      try await settle(host, in: panned)

      #expect(drainLinks(handle) == [moved])
    }

    @Test func defaultActionReportsFalseUntilAClientPolls() throws {
      let host = try AndroidHostSceneHost(app: LinkFixtureApp(recorder: LinkRecorder()))
      let handle = AndroidHostHandleRegistry.register(host)
      defer { swift_tui_android_destroy(handle) }

      // No client has polled: the pre-operation behavior, with nothing retained
      // for a client that attaches later.
      #expect(!host.surface.openLinkInHost("https://example.test/early"))
      #expect(swift_tui_android_copy_open_link(handle, nil, 0) == 0)

      #expect(host.surface.openLinkInHost("https://example.test/later"))
      #expect(swift_tui_android_copy_open_link(handle, nil, 0) == 26)
    }

    @Test func requestsDrainInOrderAndASizeQueryRemovesNothing() throws {
      let host = try AndroidHostSceneHost(app: LinkFixtureApp(recorder: LinkRecorder()))
      let handle = AndroidHostHandleRegistry.register(host)
      defer { swift_tui_android_destroy(handle) }
      #expect(swift_tui_android_copy_open_link(handle, nil, 0) == 0)

      #expect(host.surface.openLinkInHost("https://a.example"))
      #expect(host.surface.openLinkInHost("mailto:b@example.test?subject=caf\u{E9}"))

      // Neither a size query nor an undersized buffer removes the oldest entry.
      #expect(swift_tui_android_copy_open_link(handle, nil, 0) == 17)
      var small = [UInt8](repeating: 0xA5, count: 16)
      let stillNeeded = small.withUnsafeMutableBufferPointer { buffer in
        unsafe swift_tui_android_copy_open_link(handle, buffer.baseAddress, 16)
      }
      #expect(stillNeeded == 17)
      #expect(small.allSatisfy { $0 == 0xA5 })

      #expect(
        drainLinks(handle) == ["https://a.example", "mailto:b@example.test?subject=caf\u{E9}"])
      #expect(swift_tui_android_copy_open_link(handle, nil, 0) == 0)
    }

    @Test func emptyOversizedAndOverflowingRequestsAreRefused() throws {
      let host = try AndroidHostSceneHost(app: LinkFixtureApp(recorder: LinkRecorder()))
      let handle = AndroidHostHandleRegistry.register(host)
      defer { swift_tui_android_destroy(handle) }
      #expect(swift_tui_android_copy_open_link(handle, nil, 0) == 0)

      #expect(!host.surface.openLinkInHost(""))
      let atLimit = "https://example.test/" + String(repeating: "a", count: 8192 - 21)
      #expect(!host.surface.openLinkInHost(LinkDestination(atLimit + "a")))
      #expect(host.surface.openLinkInHost(LinkDestination(atLimit)))
      #expect(drainLinks(handle) == [atLimit])

      for index in 0..<16 {
        #expect(host.surface.openLinkInHost(LinkDestination("https://example.test/\(index)")))
      }
      #expect(!host.surface.openLinkInHost("https://example.test/overflow"))
      #expect(drainLinks(handle) == (0..<16).map { "https://example.test/\($0)" })
    }

    @Test func aNewSceneRunDiscardsUndeliveredRequests() async throws {
      let fixture = try await LinkFixture.started()
      defer { fixture.destroy() }

      #expect(fixture.host.surface.openLinkInHost("https://example.test/stale"))
      fixture.host.stop()
      _ = try await fixture.host.session.stopAndWait()
      for _ in 0..<8 { await Task.yield() }
      swift_tui_android_start(fixture.handle)

      #expect(fixture.pendingLinkSize() == 0)
    }

    @Test func unknownHandleReportsNothingPending() {
      #expect(swift_tui_android_copy_open_link(0, nil, 0) == 0)
      var bytes = [UInt8](repeating: 0xA5, count: 4)
      let copied = bytes.withUnsafeMutableBufferPointer { buffer in
        unsafe swift_tui_android_copy_open_link(Int64.max, buffer.baseAddress, 4)
      }
      #expect(copied == 0)
      #expect(bytes.allSatisfy { $0 == 0xA5 })
    }
  }

  private final class LinkRecorder: Sendable {
    private let destinations = Mutex<[String]>([])

    var customDestinations: [String] {
      destinations.withLock { $0 }
    }

    func record(_ destination: String) {
      destinations.withLock { $0.append(destination) }
    }
  }

  private struct LinkFixtureApp: App {
    let recorder: LinkRecorder

    init() {
      recorder = LinkRecorder()
    }

    init(recorder: LinkRecorder) {
      self.recorder = recorder
    }

    var body: some Scene {
      WindowGroup("Android Links") {
        LinkFixtureView(recorder: recorder)
      }
    }
  }

  private struct LinkFixtureView: View {
    let recorder: LinkRecorder
    @State private var marks = 0

    var body: some View {
      VStack(alignment: .leading) {
        Link("Default", destination: LinkDestination(LinkFixture.defaultDestination))
        Text("See \(Link("inline", destination: LinkDestination(LinkFixture.inlineDestination)))")
        Link("Custom", destination: LinkDestination(LinkFixture.customDestination))
          .openLinkAction(
            OpenLinkAction { [recorder] destination in
              recorder.record(destination.rawValue)
              return true
            })
        Link("Disabled", destination: LinkDestination(LinkFixture.disabledDestination))
          .disabled(true)
        Button("Mark") { marks += 1 }
        Text("marks \(marks)")
      }
    }
  }

  @MainActor
  private struct LinkFixture {
    static let defaultDestination = "https://example.test/docs?q=1&lang=sv#frag"
    static let inlineDestination = "mailto:someone@example.test"
    static let customDestination = "https://example.test/custom"
    static let disabledDestination = "https://example.test/disabled"

    let host: AndroidHostSceneHost
    let handle: Int64
    let recorder: LinkRecorder
    let frame: SemanticHostFrame

    /// A started host whose client has registered as the link dispatcher.
    static func started() async throws -> LinkFixture {
      let recorder = LinkRecorder()
      let host = try AndroidHostSceneHost(app: LinkFixtureApp(recorder: recorder))
      let handle = AndroidHostHandleRegistry.register(host)
      #expect(swift_tui_android_copy_open_link(handle, nil, 0) == 0)
      swift_tui_android_start(handle)
      host.resize(columns: 60, rows: 12, cellPixelWidth: 9, cellPixelHeight: 18)
      let frame = await host.surface.waitForFrame { frame in
        frame.raster.size.width == 60 && frame.raster.lines.joined().contains("marks 0")
      }
      return LinkFixture(host: host, handle: handle, recorder: recorder, frame: frame)
    }

    func destroy() {
      swift_tui_android_destroy(handle)
    }

    /// A cell in the middle of the run carrying `destination`.
    func cell(linking destination: String) throws -> CellPoint {
      try linkCell(in: frame, linking: destination)
    }

    func tap(_ cell: CellPoint) {
      host.sendInput(sgr(0, cell, "M") + sgr(0, cell, "m"))
    }

    func settle() async throws {
      try await SwiftTUIAndroidHostTests.settle(host, in: frame)
    }

    func pendingLinkSize() -> Int32 {
      swift_tui_android_copy_open_link(handle, nil, 0)
    }

    func drainLinks() -> [String] {
      SwiftTUIAndroidHostTests.drainLinks(handle)
    }
  }

  private enum LinkFixtureError: Error {
    case missingLink
  }

  /// Forty links in a six-row scroll view, under the button `settle` presses.
  private struct LinkScrollFixtureApp: App {
    var body: some Scene {
      WindowGroup("Android Link Scroll") {
        LinkScrollFixtureView()
      }
    }
  }

  private struct LinkScrollFixtureView: View {
    @State private var marks = 0

    var body: some View {
      VStack(alignment: .leading) {
        Button("Mark") { marks += 1 }
        Text("marks \(marks)")
        ScrollView {
          VStack(alignment: .leading) {
            ForEach(0..<40, id: \.self) { index in
              Link(
                index < 10 ? "Link-0\(index)" : "Link-\(index)",
                destination: LinkDestination("https://example.test/row/\(index)"))
            }
          }
        }
        .frame(height: 6)
      }
    }
  }

  /// A cell in the middle of the run carrying `destination` in `frame`.
  private func linkCell(
    in frame: SemanticHostFrame,
    linking destination: String
  ) throws -> CellPoint {
    for (y, row) in frame.raster.cells.enumerated() {
      let columns = row.indices.filter { row[$0].hyperlink == destination }
      if let first = columns.first, let last = columns.last {
        return CellPoint(x: (first + last) / 2, y: y)
      }
    }
    Issue.record(
      "no cell links to \(destination):\n\(frame.raster.lines.joined(separator: "\n"))")
    throw LinkFixtureError.missingLink
  }

  /// Presses the scene's Mark button, located in `frame`, and waits for its
  /// count. Input is handled in order, so the frame that shows this later
  /// press proves every earlier event has been dispatched.
  @MainActor
  private func settle(
    _ host: AndroidHostSceneHost,
    in frame: SemanticHostFrame
  ) async throws {
    let lines = frame.raster.lines
    let row = try #require(lines.firstIndex { $0.contains("Mark") })
    let column = try #require(lines[row].range(of: "Mark")).lowerBound
    let cell = CellPoint(
      x: lines[row].distance(from: lines[row].startIndex, to: column) + 1, y: row)
    host.sendInput(sgr(0, cell, "M") + sgr(0, cell, "m"))
    _ = await host.surface.waitForFrame { frame in
      frame.raster.lines.joined().contains("marks 1")
    }
  }

  /// The client's size-then-copy loop: one destination per successful copy.
  private func drainLinks(_ handle: Int64) -> [String] {
    var destinations: [String] = []
    while true {
      let required = swift_tui_android_copy_open_link(handle, nil, 0)
      guard required > 0 else { return destinations }
      var bytes = [UInt8](repeating: 0, count: Int(required))
      let copied = bytes.withUnsafeMutableBufferPointer { buffer in
        unsafe swift_tui_android_copy_open_link(handle, buffer.baseAddress, required)
      }
      guard copied == required else { return destinations }
      destinations.append(String(decoding: bytes, as: UTF8.self))
    }
  }

  private func sgr(_ button: Int, _ cell: CellPoint, _ terminator: String) -> [UInt8] {
    Array("\u{1B}[<\(button);\(cell.x + 1);\(cell.y + 1)\(terminator)".utf8)
  }

#endif
