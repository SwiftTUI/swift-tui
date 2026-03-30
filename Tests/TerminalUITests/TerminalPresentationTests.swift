import Dispatch
import Testing

@testable import Core
@testable import TerminalUI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@MainActor
@Suite
struct TerminalPresentationTests {
  @Test("capability detection prefers true color under UTF-8 terminals")
  func capabilityDetectionPrefersTrueColor() {
    let profile = TerminalCapabilityProfile.detect(
      environment: [
        "TERM": "xterm-256color",
        "COLORTERM": "truecolor",
        "LANG": "en_US.UTF-8",
      ],
      isTTY: true
    )

    #expect(profile == .trueColor)
  }

  @Test("capability detection disables styling for no-color and non-tty outputs")
  func capabilityDetectionDisablesStylingWhenRequested() {
    let noColorProfile = TerminalCapabilityProfile.detect(
      environment: [
        "TERM": "xterm-256color",
        "NO_COLOR": "1",
        "LANG": "en_US.UTF-8",
      ],
      isTTY: true
    )
    let redirectedProfile = TerminalCapabilityProfile.detect(
      environment: [
        "TERM": "xterm-256color",
        "LANG": "C",
      ],
      isTTY: false
    )

    #expect(
      noColorProfile
        == .init(
          glyphLevel: .unicode,
          colorLevel: .none,
          emitsStyleEscapeSequences: false,
          supportsHyperlinks: true,
          supportsMouseReporting: true
        )
    )
    #expect(
      redirectedProfile
        == .init(
          glyphLevel: .ascii,
          colorLevel: .none,
          emitsStyleEscapeSequences: false
        )
    )
  }

  @Test("capability detection enables mouse reporting only for supported tty terminals")
  func capabilityDetectionTracksMouseReportingSupport() {
    let supported = TerminalCapabilityProfile.detect(
      environment: [
        "TERM": "xterm-256color",
        "LANG": "en_US.UTF-8",
      ],
      isTTY: true
    )
    let dumb = TerminalCapabilityProfile.detect(
      environment: [
        "TERM": "dumb",
        "LANG": "en_US.UTF-8",
      ],
      isTTY: true
    )
    let redirected = TerminalCapabilityProfile.detect(
      environment: [
        "TERM": "xterm-256color",
        "LANG": "en_US.UTF-8",
      ],
      isTTY: false
    )

    #expect(supported.supportsMouseReporting)
    #expect(!dumb.supportsMouseReporting)
    #expect(!redirected.supportsMouseReporting)
  }

  @Test("capability detection enables hyperlinks only for supported tty terminals")
  func capabilityDetectionTracksHyperlinkSupport() {
    let supported = TerminalCapabilityProfile.detect(
      environment: [
        "TERM": "wezterm",
        "LANG": "en_US.UTF-8",
      ],
      isTTY: true
    )
    let dumb = TerminalCapabilityProfile.detect(
      environment: [
        "TERM": "dumb",
        "LANG": "en_US.UTF-8",
      ],
      isTTY: true
    )
    let redirected = TerminalCapabilityProfile.detect(
      environment: [
        "TERM": "wezterm",
        "LANG": "en_US.UTF-8",
      ],
      isTTY: false
    )

    #expect(supported.supportsHyperlinks)
    #expect(!dumb.supportsHyperlinks)
    #expect(!redirected.supportsHyperlinks)
  }

  @Test("appearance detection derives defaults from COLORFGBG heuristics")
  func appearanceDetectionUsesEnvironmentHeuristics() {
    let appearance = TerminalAppearance.detect(
      environment: [
        "COLORFGBG": "0;15"
      ],
      capabilityProfile: .trueColor
    )

    #expect(appearance.foregroundColor == TerminalAppearance.defaultPalette[0])
    #expect(appearance.backgroundColor == TerminalAppearance.defaultPalette[15])
    #expect(appearance.tintColor == TerminalAppearance.defaultPalette[4])
    #expect(appearance.colorScheme == .light)
    #expect(appearance.source == .environmentHeuristics)
  }

  @Test("appearance detection prefers active query results over heuristics")
  func appearanceDetectionPrefersActiveQueryResults() {
    let appearance = TerminalAppearance.detect(
      environment: [
        "COLORFGBG": "15;0"
      ],
      capabilityProfile: .trueColor
    ) { query in
      switch query {
      case .foreground:
        .init(hex: 0x111213)
      case .background:
        .init(hex: 0xF8F7F6)
      case .palette(let index):
        index == 4 ? .magenta : nil
      }
    }

    #expect(appearance.foregroundColor == .init(hex: 0x111213))
    #expect(appearance.backgroundColor == .init(hex: 0xF8F7F6))
    #expect(appearance.tintColor == .magenta)
    #expect(appearance.colorScheme == .light)
    #expect(appearance.source == .activeQuery)
  }

  @Test("appearance query ignores invalid UTF-8 responses")
  func appearanceQueryIgnoresInvalidUTF8Responses() {
    let response = TerminalAppearanceQuery.foreground.extractResponse(
      from: [0x1B, 0x5D, 0x31, 0x30, 0x3B, 0xFF, 0x07]
    )

    #expect(response == nil)
  }

  @Test("ansi16 renderer lowers accent emphasis into escape sequences")
  func ansi16RendererLowersStyledRuns() {
    let rendered = TerminalSurfaceRenderer(
      capabilityProfile: .ansi16
    ).render(
      RasterSurface(
        size: .init(width: 2, height: 1),
        lines: ["Hi"],
        styleRuns: [
          .init(
            x: 0,
            y: 0,
            length: 2,
            style: ResolvedTextStyle(
              foregroundColor: .cyan,
              emphasis: .bold
            )
          )
        ]
      )
    )

    #expect(rendered == "\u{001B}[1;96mHi\u{001B}[0m")
  }

  @Test("true-color renderer lowers semantic color tokens to RGB escapes")
  func trueColorRendererLowersSemanticTokens() {
    let rendered = TerminalSurfaceRenderer(
      capabilityProfile: .trueColor
    ).render(
      RasterSurface(
        size: .init(width: 2, height: 1),
        lines: ["Hi"],
        styleRuns: [
          .init(
            x: 0,
            y: 0,
            length: 2,
            style: ResolvedTextStyle(
              foregroundColor: .cyan,
              backgroundColor: .init(hex: 0x112233)
            )
          )
        ]
      )
    )

    #expect(rendered == "\u{001B}[38;2;86;182;194;48;2;17;34;51mHi\u{001B}[0m")
  }

  @Test("ascii renderer degrades rounded borders and wide glyphs deterministically")
  func asciiRendererDegradesUnicodeDrawing() {
    let rendered = TerminalSurfaceRenderer(
      capabilityProfile: .previewASCII
    ).render(
      RasterSurface(
        size: .init(width: 4, height: 3),
        lines: [
          "╭─╮",
          "│界│",
          "╰─╯",
        ]
      )
    )

    #expect(rendered == "+-+\r\n|??|\r\n+-+")
  }

  @Test("renderer emits OSC 8 hyperlinks on full repaint and preserves style ordering")
  func rendererEmitsHyperlinksOnFullRepaint() {
    let renderer = TerminalSurfaceRenderer(
      capabilityProfile: .trueColor
    )
    let surface = RasterSurface(
      size: .init(width: 2, height: 1),
      cells: [
        [
          RasterCell(
            character: "H",
            style: .init(
              foregroundColor: .cyan,
              emphasis: .bold
            ),
            hyperlink: "https://example.com"
          ),
          RasterCell(
            character: "i",
            style: .init(
              foregroundColor: .cyan,
              emphasis: .bold
            ),
            hyperlink: "https://example.com"
          ),
        ]
      ]
    )

    #expect(
      renderer.render(surface)
        == "\u{001B}]8;;https://example.com\u{001B}\\\u{001B}[1;38;2;86;182;194mHi\u{001B}]8;;\u{001B}\\\u{001B}[0m"
    )
  }

  @Test("renderer emits self-contained hyperlink spans for incremental updates")
  func rendererEmitsSelfContainedHyperlinkSpans() {
    let renderer = TerminalSurfaceRenderer(
      capabilityProfile: .ansi16
    )
    let row = [
      RasterCell(
        character: "X",
        style: .init(foregroundColor: .cyan),
        hyperlink: "https://one.example"
      ),
      RasterCell(
        character: "Y",
        style: .init(foregroundColor: .magenta),
        hyperlink: "https://two.example"
      ),
    ]

    #expect(
      renderer.renderSpan(row, from: 0, to: 2)
        == "\u{001B}]8;;https://one.example\u{001B}\\\u{001B}[96mX\u{001B}]8;;\u{001B}\\\u{001B}]8;;https://two.example\u{001B}\\\u{001B}[0m\u{001B}[95mY\u{001B}]8;;\u{001B}\\\u{001B}[0m"
    )
  }

  @Test("renderer omits hyperlink escapes when hyperlink support is disabled")
  func rendererOmitsHyperlinksWhenUnsupported() {
    let renderer = TerminalSurfaceRenderer(
      capabilityProfile: .previewUnicode
    )
    let surface = RasterSurface(
      size: .init(width: 4, height: 1),
      cells: [
        [
          RasterCell(character: "L", hyperlink: "https://example.com"),
          RasterCell(character: "i", hyperlink: "https://example.com"),
          RasterCell(character: "n", hyperlink: "https://example.com"),
          RasterCell(character: "k", hyperlink: "https://example.com"),
        ]
      ]
    )

    #expect(renderer.render(surface) == "Link")
  }

  @Test("presentation planner falls back to full repaint when size attachments or metadata differ")
  func presentationPlannerFallsBackOnSurfaceMismatch() {
    let planner = TerminalPresentationPlanner(
      capabilityProfile: .previewUnicode
    )
    let renderer = TerminalSurfaceRenderer(
      capabilityProfile: .previewUnicode
    )
    let previousSurface = RasterSurface(
      size: .init(width: 8, height: 2),
      lines: ["alpha", "bravo"],
      attachments: ["asset-a"],
      imageAttachments: [
        .init(
          identity: testIdentity("Root", "Image"),
          bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
          source: .named("asset-a.png"),
          resolvedReference: .filePath("/tmp/asset-a.png"),
          pixelSize: .init(width: 8, height: 8),
          isResizable: false,
          scalingMode: .stretch
        )
      ],
      metadata: ["theme": "light"]
    )

    let variants: [RasterSurface] = [
      .init(
        size: .init(width: 9, height: 2),
        lines: ["alpha", "bravo"],
        attachments: ["asset-a"],
        metadata: ["theme": "light"]
      ),
      .init(
        size: .init(width: 8, height: 2),
        lines: ["alpha", "bravo"],
        attachments: ["asset-b"],
        imageAttachments: previousSurface.imageAttachments,
        metadata: ["theme": "light"]
      ),
      .init(
        size: .init(width: 8, height: 2),
        lines: ["alpha", "bravo"],
        attachments: ["asset-a"],
        imageAttachments: previousSurface.imageAttachments,
        metadata: ["theme": "dark"]
      ),
      .init(
        size: .init(width: 8, height: 2),
        lines: ["alpha", "bravo"],
        attachments: ["asset-a"],
        imageAttachments: [
          .init(
            identity: testIdentity("Root", "Image"),
            bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
            source: .named("asset-b.png"),
            resolvedReference: .filePath("/tmp/asset-b.png"),
            pixelSize: .init(width: 8, height: 8),
            isResizable: false,
            scalingMode: .stretch
          )
        ],
        metadata: ["theme": "light"]
      ),
    ]

    for surface in variants {
      let plan = planner.plan(
        previousSurface: previousSurface,
        currentSurface: surface
      )

      #expect(plan.strategy == .fullRepaint)
      #expect(plan.renderedOutput == renderer.render(surface))
      #expect(plan.spanUpdates.isEmpty)
      #expect(plan.linesTouched == surface.size.height)
      #expect(plan.cellsChanged == max(0, surface.size.width) * max(0, surface.size.height))
    }
  }

  @Test("presentation planner emits a narrow span for a mid-row edit")
  func presentationPlannerEmitsNarrowSpanForMidRowEdit() {
    let planner = TerminalPresentationPlanner(
      capabilityProfile: .previewUnicode
    )
    let previousSurface = RasterSurface(
      size: .init(width: 8, height: 2),
      lines: ["alpha", "same"]
    )
    let currentSurface = RasterSurface(
      size: .init(width: 8, height: 2),
      lines: ["alpXa", "same"]
    )

    let plan = planner.plan(
      previousSurface: previousSurface,
      currentSurface: currentSurface
    )

    #expect(plan.strategy == .incremental)
    #expect(
      plan.spanUpdates == [
        .init(row: 0, column: 3, renderedSpan: "X", cellsChanged: 1)
      ])
    #expect(plan.renderedOutput.isEmpty)
    #expect(plan.linesTouched == 1)
    #expect(plan.cellsChanged == 1)
  }

  @Test("presentation planner clears trailing text when the row shrinks")
  func presentationPlannerClearsTrailingTailWhenTextShrinks() {
    let planner = TerminalPresentationPlanner(
      capabilityProfile: .previewUnicode
    )
    let previousSurface = RasterSurface(
      size: .init(width: 8, height: 1),
      lines: ["alphabet"]
    )
    let currentSurface = RasterSurface(
      size: .init(width: 8, height: 1),
      lines: ["alph"]
    )

    let plan = planner.plan(
      previousSurface: previousSurface,
      currentSurface: currentSurface
    )

    #expect(plan.strategy == .incremental)
    #expect(
      plan.spanUpdates == [
        .init(row: 0, column: 4, renderedSpan: "    ", cellsChanged: 4)
      ])
    #expect(plan.linesTouched == 1)
    #expect(plan.cellsChanged == 4)
  }

  @Test("presentation planner widens continuation cell diffs to glyph boundaries")
  func presentationPlannerWidensContinuationCellDiffs() {
    let planner = TerminalPresentationPlanner(
      capabilityProfile: .previewUnicode
    )
    let previousSurface = RasterSurface(
      size: .init(width: 4, height: 1),
      cells: [
        [
          .init(character: "a"),
          .init(
            character: "界",
            spanWidth: 2,
            style: .init(foregroundColor: .cyan)
          ),
          .init(
            character: " ",
            spanWidth: 0,
            continuationLeadX: 1,
            style: .init(foregroundColor: .cyan)
          ),
          .init(character: "b"),
        ]
      ]
    )
    let currentSurface = RasterSurface(
      size: .init(width: 4, height: 1),
      cells: [
        [
          .init(character: "a"),
          .init(
            character: "界",
            spanWidth: 2,
            style: .init(foregroundColor: .magenta)
          ),
          .init(
            character: " ",
            spanWidth: 0,
            continuationLeadX: 1,
            style: .init(foregroundColor: .magenta)
          ),
          .init(character: "b"),
        ]
      ]
    )

    let plan = planner.plan(
      previousSurface: previousSurface,
      currentSurface: currentSurface
    )

    #expect(plan.strategy == .incremental)
    #expect(
      plan.spanUpdates == [
        .init(row: 0, column: 1, renderedSpan: "界", cellsChanged: 2)
      ])
    #expect(plan.cellsChanged == 2)
  }

  @Test("presentation planner orders multiple spans from left to right")
  func presentationPlannerOrdersMultipleSpansLeftToRight() {
    let planner = TerminalPresentationPlanner(
      capabilityProfile: .previewUnicode
    )
    let previousSurface = RasterSurface(
      size: .init(width: 8, height: 1),
      lines: ["abcd1234"]
    )
    let currentSurface = RasterSurface(
      size: .init(width: 8, height: 1),
      lines: ["abXd12Y4"]
    )

    let plan = planner.plan(
      previousSurface: previousSurface,
      currentSurface: currentSurface
    )

    #expect(plan.strategy == .incremental)
    #expect(
      plan.spanUpdates == [
        .init(row: 0, column: 2, renderedSpan: "X", cellsChanged: 1),
        .init(row: 0, column: 6, renderedSpan: "Y", cellsChanged: 1),
      ])
    #expect(plan.linesTouched == 1)
    #expect(plan.cellsChanged == 2)
  }

  @Test("terminal host presents styled surfaces through the capability-aware renderer")
  func terminalHostPresentsStyledSurfaces() throws {
    let controller = PresentationMockTerminalController(isTTY: true)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .ansi256
    )

    let surface = RasterSurface(
      size: .init(width: 5, height: 1),
      lines: ["demo"],
      styleRuns: [
        .init(
          x: 0,
          y: 0,
          length: 4,
          style: ResolvedTextStyle(
            foregroundColor: .cyan,
            emphasis: .bold
          )
        )
      ]
    )
    let metrics = try host.present(surface)

    #expect(
      controller.writes == [
        "\u{001B}[2J\u{001B}[1;1H\u{001B}[1;38;5;117mdemo\u{001B}[0m"
      ])
    #expect(metrics.bytesWritten == controller.writes.joined().utf8.count)
    #expect(metrics.linesTouched == 1)
    #expect(metrics.cellsChanged == 5)
    #expect(metrics.strategy == .fullRepaint)
    #expect(metrics.usedFullRepaint)
  }

  @Test("terminal host full repaint uses explicit row addressing after full-width rows")
  func terminalHostFullRepaintUsesExplicitRowAddressingForSubsequentRows() throws {
    let controller = PresentationMockTerminalController(isTTY: true)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .previewUnicode
    )

    let surface = RasterSurface(
      size: .init(width: 4, height: 2),
      lines: ["ABCD", "EFGH"]
    )
    let metrics = try host.present(surface)

    #expect(
      controller.writes == [
        "\u{001B}[2J\u{001B}[1;1HABCD\u{001B}[2;1HEFGH"
      ])
    #expect(metrics.bytesWritten == controller.writes.joined().utf8.count)
    #expect(metrics.strategy == .fullRepaint)
  }

  @Test("terminal host uses incremental row diffs after the first presentation")
  func terminalHostUsesIncrementalRowDiffsAfterFirstPresentation() throws {
    let controller = PresentationMockTerminalController(isTTY: true)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .previewUnicode
    )

    let initialSurface = RasterSurface(
      size: .init(width: 8, height: 2),
      lines: ["alpha", "same"]
    )
    _ = try host.present(initialSurface)

    let writesBeforeUpdate = controller.writes.count
    let updatedSurface = RasterSurface(
      size: .init(width: 8, height: 2),
      lines: ["alpXa", "same"]
    )
    let metrics = try host.present(updatedSurface)
    let incrementalWrites = Array(controller.writes.dropFirst(writesBeforeUpdate))

    #expect(
      incrementalWrites == [
        "\u{001B}[1;4HX"
      ])
    #expect(metrics.strategy == .incremental)
    #expect(metrics.linesTouched == 1)
    #expect(metrics.cellsChanged == 1)
    #expect(metrics.bytesWritten == incrementalWrites.joined().utf8.count)
  }

  @Test("POSIX terminal controller retries writes after nonblocking backpressure")
  func posixTerminalControllerRetriesWritesAfterBackpressure() throws {
    var descriptors: [Int32] = [0, 0]
    #expect(unsafe pipe(&descriptors) == 0)

    let readDescriptor = descriptors[0]
    let writeDescriptor = descriptors[1]
    var didCloseReadDescriptor = false
    var didCloseWriteDescriptor = false
    defer {
      if !didCloseReadDescriptor {
        _ = Darwin.close(readDescriptor)
      }
      if !didCloseWriteDescriptor {
        _ = Darwin.close(writeDescriptor)
      }
    }

    let currentFlags = fcntl(writeDescriptor, F_GETFL)
    #expect(currentFlags >= 0)
    #expect(fcntl(writeDescriptor, F_SETFL, currentFlags | O_NONBLOCK) >= 0)

    let fillerByte: UInt8 = 0x78
    try fillPipeUntilWouldBlock(
      writeDescriptor: writeDescriptor,
      chunk: Array(repeating: fillerByte, count: 1024)
    )

    let drainStarted = DispatchSemaphore(value: 0)
    let drainFinished = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
      drainStarted.signal()
      usleep(20_000)
      var buffer = Array(repeating: UInt8(0), count: 8192)
      _ = unsafe Darwin.read(readDescriptor, &buffer, buffer.count)
      drainFinished.signal()
    }

    #expect(drainStarted.wait(timeout: .now() + 1) == .success)

    let controller = POSIXTerminalController()
    try controller.write("ok", to: writeDescriptor)

    #expect(drainFinished.wait(timeout: .now() + 1) == .success)

    _ = Darwin.close(writeDescriptor)
    didCloseWriteDescriptor = true

    let remainingBytes = try readAllBytes(from: readDescriptor)
    _ = Darwin.close(readDescriptor)
    didCloseReadDescriptor = true

    #expect(remainingBytes.suffix(2) == Array("ok".utf8))
  }

  @Test("ansi renderer lowers italic plus typed underline and strikethrough decorations")
  func ansiRendererLowersDecorationCodes() {
    let rendered = TerminalSurfaceRenderer(
      capabilityProfile: .ansi16
    ).render(
      RasterSurface(
        size: .init(width: 2, height: 1),
        lines: ["Hi"],
        styleRuns: [
          .init(
            x: 0,
            y: 0,
            length: 2,
            style: .init(
              foregroundColor: .white,
              emphasis: .italic,
              underlineStyle: .init(pattern: .dashDot, color: .yellow),
              strikethroughStyle: .init(pattern: .dot, color: .red)
            )
          )
        ]
      )
    )

    #expect(rendered == "\u{001B}[3;4:5;9;97mHi\u{001B}[0m")
  }

  @Test("truecolor renderer lowers extended underline styles and colors")
  func trueColorRendererLowersExtendedUnderlineStylesAndColors() {
    let rendered = TerminalSurfaceRenderer(
      capabilityProfile: .trueColor
    ).render(
      RasterSurface(
        size: .init(width: 2, height: 1),
        lines: ["Hi"],
        styleRuns: [
          .init(
            x: 0,
            y: 0,
            length: 2,
            style: .init(
              foregroundColor: .white,
              underlineStyle: .init(pattern: .curly, color: .red)
            )
          )
        ]
      )
    )

    #expect(rendered == "\u{001B}[4:3;38;2;255;255;255;58;2;224;87;87mHi\u{001B}[0m")
  }

  @Test("protocol extension present falls back to a full repaint")
  func protocolExtensionPresentFallsBackToFullRepaint() throws {
    let host = FallbackPresentationHost(
      surfaceSize: .init(width: 6, height: 2),
      capabilityProfile: .previewUnicode
    )
    let surface = RasterSurface(
      size: .init(width: 6, height: 2),
      lines: ["demo", "ui"]
    )

    let metrics = try host.present(surface)

    #expect(
      host.writes == [
        "\u{001B}[2J",
        "\u{001B}[1;1H",
        "demo",
        "\u{001B}[2;1H",
        "ui",
      ])
    #expect(metrics.strategy == .fullRepaint)
    #expect(metrics.usedFullRepaint)
    #expect(metrics.bytesWritten == host.writes.joined().utf8.count)
  }
}

private final class PresentationMockTerminalController: TerminalControlling {
  private let isTTYValue: Bool
  private(set) var writes: [String] = []

  init(isTTY: Bool) {
    isTTYValue = isTTY
  }

  func isATTY(_: Int32) -> Bool {
    isTTYValue
  }

  func getAttributes(from _: Int32) throws -> termios {
    termios()
  }

  func setAttributes(_: termios, on _: Int32) throws {}

  func windowSize(of _: Int32) throws -> Size {
    .init(width: 80, height: 24)
  }

  func getFileStatusFlags(of _: Int32) throws -> Int32 {
    0
  }

  func setFileStatusFlags(_: Int32, on _: Int32) throws {}

  func write(_ output: String, to _: Int32) throws {
    writes.append(output)
  }

  func read(
    from _: Int32,
    maxBytes _: Int,
    timeoutMilliseconds _: Int
  ) throws -> [UInt8] {
    []
  }
}

private func fillPipeUntilWouldBlock(
  writeDescriptor: Int32,
  chunk: [UInt8]
) throws {
  try unsafe chunk.withUnsafeBytes { rawBuffer in
    guard let baseAddress = rawBuffer.baseAddress else {
      return
    }

    while true {
      let result = unsafe Darwin.write(writeDescriptor, baseAddress, chunk.count)
      if result > 0 {
        continue
      }
      if result < 0, errno == EAGAIN || errno == EWOULDBLOCK {
        return
      }
      if result < 0, errno == EINTR {
        continue
      }
      throw TerminalHostError.failedToWrite(errno: errno)
    }
  }
}

private func readAllBytes(
  from fileDescriptor: Int32
) throws -> [UInt8] {
  var collected: [UInt8] = []

  while true {
    var buffer = Array(repeating: UInt8(0), count: 4096)
    let bytesRead = unsafe Darwin.read(fileDescriptor, &buffer, buffer.count)
    if bytesRead > 0 {
      collected.append(contentsOf: buffer.prefix(Int(bytesRead)))
      continue
    }
    if bytesRead == 0 {
      return collected
    }
    if errno == EINTR {
      continue
    }
    throw TerminalHostError.failedToWrite(errno: errno)
  }
}

private final class FallbackPresentationHost: TerminalHosting {
  let surfaceSize: Size
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance

  private(set) var writes: [String] = []

  init(
    surfaceSize: Size,
    capabilityProfile: TerminalCapabilityProfile
  ) {
    self.surfaceSize = surfaceSize
    self.capabilityProfile = capabilityProfile
    self.appearance = TerminalAppearance.detect(
      environment: [:],
      capabilityProfile: capabilityProfile
    )
  }

  func enableRawMode() throws {}

  func disableRawMode() throws {}

  func write(_ output: String) throws {
    writes.append(output)
  }

  func clearScreen() throws {
    writes.append("\u{001B}[2J")
  }

  func moveCursor(to point: Point) throws {
    let row = max(1, point.y + 1)
    let column = max(1, point.x + 1)
    writes.append("\u{001B}[\(row);\(column)H")
  }
}
