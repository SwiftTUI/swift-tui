import PNG
import Testing

@testable import Core
@testable import TerminalUI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@Suite
struct TerminalGraphicsProtocolTests {
  @Test("terminal host emits Kitty direct RGBA payloads when Kitty graphics are available", .disabled())
  func terminalHostEmitsKittyPayloads() throws {
    let kittyQueryID = stableIdentifier(from: Array("stui-kitty-query".utf8))
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [
        Array("\u{001B}_Gi=\(kittyQueryID);OK\u{001B}\\".utf8),
        [],
      ],
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 20, height: 5),
      controller: controller,
      capabilityProfile: .trueColor
    )

    let pngBytes = try makePNGBytes(
      width: 2,
      height: 2,
      pixels: [
        rgbaPixel(red: 255, green: 0, blue: 0),
        rgbaPixel(red: 255, green: 0, blue: 0),
        rgbaPixel(red: 0, green: 0, blue: 255),
        rgbaPixel(red: 0, green: 0, blue: 255),
      ]
    )
    let surface = RasterSurface(
      size: .init(width: 2, height: 1),
      lines: ["  "],
      imageAttachments: [
        makeRasterImageAttachment(
          pngBytes: pngBytes,
          pixelSize: .init(width: 2, height: 2),
          bounds: .init(origin: .zero, size: .init(width: 1, height: 1))
        )
      ]
    )

    _ = try host.present(surface)

    let kittyWrite = try #require(
      controller.writes.first { write in
        write.contains("_Ga=T")
      }
    )

    #expect(
      kittyWrite.contains("_Ga=T,q=2,t=d,f=32,C=1")
    )
    #expect(
      kittyWrite.contains(",s=8,v=16,S=512,")
    )
    #expect(
      !kittyWrite.contains("z=-1")
    )
    #expect(
      !kittyWrite.contains(",p=")
    )
    #expect(
      !kittyWrite.contains(",c=")
    )
    #expect(
      !kittyWrite.contains(",r=")
    )
    #expect(
      !controller.writes.contains { write in
        write.contains("\u{001B}P0;1;0q")
      }
    )
  }

  @Test("terminal host chunks larger Kitty payloads for scaled image placements", .disabled())
  func terminalHostChunksLargeScaledKittyPayloads() throws {
    let kittyQueryID = stableIdentifier(from: Array("stui-kitty-query".utf8))
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [
        Array("\u{001B}_Gi=\(kittyQueryID);OK\u{001B}\\".utf8),
        [],
      ],
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .trueColor
    )

    var pixels: [PNG.RGBA<UInt8>] = []
    pixels.reserveCapacity(128 * 128)
    for y in 0..<128 {
      for x in 0..<128 {
        pixels.append(
          rgbaPixel(
            red: UInt8((x * 17 + y * 31) % 256),
            green: UInt8((x * 43 + y * 29) % 256),
            blue: UInt8((x * 61 + y * 47) % 256),
            alpha: 255
          )
        )
      }
    }

    let pngBytes = try makePNGBytes(
      width: 128,
      height: 128,
      pixels: pixels
    )
    let surface = RasterSurface(
      size: .init(width: 40, height: 20),
      lines: Array(repeating: String(repeating: " ", count: 40), count: 20),
      imageAttachments: [
        makeRasterImageAttachment(
          pngBytes: pngBytes,
          pixelSize: .init(width: 128, height: 128),
          bounds: .init(origin: .zero, size: .init(width: 40, height: 20))
        )
      ]
    )

    _ = try host.present(surface)

    let kittyWrites = controller.writes.filter { write in
      write.contains("\u{001B}_G")
    }

    #expect(
      kittyWrites.contains { write in
        write.contains("_Ga=T,q=2,t=d,f=32,C=1,s=320,v=320,S=409600")
          && write.contains(",m=1;")
      }
    )
    #expect(
      kittyWrites.contains { write in
        write.contains("\u{001B}_Gm=0;")
      }
    )
  }

  @Test("terminal host emits Sixel payloads when Kitty is unavailable but Sixel is supported")
  func terminalHostEmitsSixelPayloads() throws {
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [
        [],
        Array("\u{001B}[?4;1c".utf8),
        Array("\u{001B}[?1;0;16S".utf8),
        Array("\u{001B}[?2;0;640;480S".utf8),
      ],
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 20, height: 5),
      controller: controller,
      capabilityProfile: .ansi256
    )

    let pngBytes = try makePNGBytes(
      width: 2,
      height: 2,
      pixels: [
        rgbaPixel(red: 255, green: 0, blue: 0),
        rgbaPixel(red: 0, green: 255, blue: 0),
        rgbaPixel(red: 0, green: 0, blue: 255),
        rgbaPixel(red: 255, green: 255, blue: 255),
      ]
    )
    let surface = RasterSurface(
      size: .init(width: 2, height: 1),
      imageAttachments: [
        makeRasterImageAttachment(
          pngBytes: pngBytes,
          pixelSize: .init(width: 2, height: 2),
          bounds: .init(origin: .zero, size: .init(width: 1, height: 1))
        )
      ]
    )

    _ = try host.present(surface)

    #expect(
      controller.writes.contains { write in
        write.contains("\u{001B}P0;1;0q")
      }
    )
  }

  @Test(
    "ANSI fallback compositor uses half block cells and terminal colors when graphics protocols are unavailable"
  )
  func ansiFallbackCompositorUsesHalfBlocks() throws {
    let controller = GraphicsProtocolMockTerminalController(isTTY: false)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 10, height: 4),
      controller: controller,
      capabilityProfile: .ansi16
    )

    let pngBytes = try makePNGBytes(
      width: 1,
      height: 2,
      pixels: [
        rgbaPixel(red: 255, green: 0, blue: 0),
        rgbaPixel(red: 0, green: 0, blue: 255),
      ]
    )
    let surface = RasterSurface(
      size: .init(width: 1, height: 1),
      imageAttachments: [
        makeRasterImageAttachment(
          pngBytes: pngBytes,
          pixelSize: .init(width: 1, height: 2),
          bounds: .init(origin: .zero, size: .init(width: 1, height: 1))
        )
      ]
    )

    _ = try host.present(surface)

    #expect(
      controller.writes == [
        "\u{001B}[2J\u{001B}[1;1H\u{001B}[91;104m▀\u{001B}[0m"
      ]
    )
  }

  @Test("stable image attachments preserve incremental text updates")
  func stableImageAttachmentsPreserveIncrementalTextUpdates() throws {
    let kittyQueryID = stableIdentifier(from: Array("stui-kitty-query".utf8))
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [
        Array("\u{001B}_Gi=\(kittyQueryID);OK\u{001B}\\".utf8),
        [],
      ],
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 10, height: 4),
      controller: controller,
      capabilityProfile: .trueColor
    )

    let pngBytes = try makePNGBytes(
      width: 2,
      height: 2,
      pixels: [
        rgbaPixel(red: 255, green: 255, blue: 255),
        rgbaPixel(red: 255, green: 255, blue: 255),
        rgbaPixel(red: 255, green: 255, blue: 255),
        rgbaPixel(red: 255, green: 255, blue: 255),
      ]
    )
    let attachment = makeRasterImageAttachment(
      pngBytes: pngBytes,
      pixelSize: .init(width: 2, height: 2),
      bounds: .init(origin: .init(x: 3, y: 0), size: .init(width: 1, height: 1))
    )
    let initialSurface = RasterSurface(
      size: .init(width: 4, height: 1),
      lines: ["foo "],
      imageAttachments: [attachment]
    )
    let updatedSurface = RasterSurface(
      size: .init(width: 4, height: 1),
      lines: ["fOo "],
      imageAttachments: [attachment]
    )

    _ = try host.present(initialSurface)
    let writesBeforeIncrementalUpdate = controller.writes.count

    let metrics = try host.present(updatedSurface)
    let incrementalWrites = Array(controller.writes.dropFirst(writesBeforeIncrementalUpdate))

    #expect(
      incrementalWrites == [
        "\u{001B}[1;2HO"
      ]
    )
    #expect(metrics.strategy == .incremental)
    #expect(metrics.cellsChanged == 1)
    #expect(
      !incrementalWrites.contains { write in
        write.contains("_Ga=") || write.contains("\u{001B}P0;1;0q")
      }
    )
  }

  @Test("Kitty protocol clears background colors in image area cells")
  func kittyProtocolClearsBackgroundColorsInImageArea() throws {
    let kittyQueryID = stableIdentifier(from: Array("stui-kitty-query".utf8))
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [
        Array("\u{001B}_Gi=\(kittyQueryID);OK\u{001B}\\".utf8),
        [],
      ],
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 10, height: 3),
      controller: controller,
      capabilityProfile: .trueColor
    )

    let pngBytes = try makePNGBytes(
      width: 2,
      height: 2,
      pixels: [
        rgbaPixel(red: 255, green: 0, blue: 0),
        rgbaPixel(red: 255, green: 0, blue: 0),
        rgbaPixel(red: 0, green: 0, blue: 255),
        rgbaPixel(red: 0, green: 0, blue: 255),
      ]
    )

    // Build a surface where image area cells have background colors,
    // mimicking ZStack { RoundedRectangle.fill(); Image() }
    let bgStyle = ResolvedTextStyle(
      backgroundColor: .init(red: 40, green: 40, blue: 40)
    )
    var cells: [[RasterCell]] = []
    for _ in 0..<3 {
      var row: [RasterCell] = []
      for _ in 0..<10 {
        row.append(RasterCell(character: " ", style: bgStyle))
      }
      cells.append(row)
    }

    let surface = RasterSurface(
      size: .init(width: 10, height: 3),
      cells: cells,
      imageAttachments: [
        makeRasterImageAttachment(
          pngBytes: pngBytes,
          pixelSize: .init(width: 2, height: 2),
          bounds: .init(
            origin: .init(x: 2, y: 0),
            size: .init(width: 6, height: 3)
          )
        )
      ]
    )

    _ = try host.present(surface)

    // Kitty image commands should be emitted
    #expect(
      controller.writes.contains { $0.contains("_Ga=T") }
    )

    // Text writes for cells OUTSIDE the image bounds should contain
    // background color escape codes (48;2;40;40;40)
    let textWrites = controller.writes.filter { write in
      write.contains("48;2;40;40;40")
    }
    #expect(!textWrites.isEmpty)

    // The image area cells should NOT produce background color codes
    // spanning the full row width — styles should be cleared inside
    // the image bounds.
    let fullRowBg = String(repeating: " ", count: 10)
    let fullRowBgWrites = controller.writes.filter { write in
      write.contains("48;2;40;40;40") && write.contains(fullRowBg)
    }
    #expect(fullRowBgWrites.isEmpty)
  }
}

private final class GraphicsProtocolMockTerminalController: TerminalControlling {
  private let isTTYValue: Bool
  private let cellPixelSizeValue: Size?
  private var queuedReadResponses: [[UInt8]]

  private(set) var writes: [String] = []

  init(
    isTTY: Bool,
    readResponses: [[UInt8]] = [],
    cellPixelSize: Size? = nil
  ) {
    isTTYValue = isTTY
    queuedReadResponses = readResponses
    cellPixelSizeValue = cellPixelSize
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

  func cellPixelSize(of _: Int32) throws -> Size? {
    cellPixelSizeValue
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
    guard !queuedReadResponses.isEmpty else {
      return []
    }
    return queuedReadResponses.removeFirst()
  }
}
