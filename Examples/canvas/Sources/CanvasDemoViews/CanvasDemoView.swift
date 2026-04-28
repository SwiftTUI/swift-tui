import TerminalUI

public struct CanvasSketchPoint: Equatable, Hashable, Sendable {
  public var x: Int
  public var y: Int

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }
}

public struct CanvasSketchDocument: Equatable, Sendable {
  public var cellSize: Size
  public private(set) var cursor: CanvasSketchPoint

  private var pixels: [Bool]

  public init(
    cellSize: Size = Size(width: 36, height: 12),
    cursor: CanvasSketchPoint = CanvasSketchPoint(x: 0, y: 0)
  ) {
    let safeCellSize = Size(
      width: max(0, cellSize.width),
      height: max(0, cellSize.height)
    )
    self.cellSize = safeCellSize
    self.cursor = CanvasSketchDocument.clamped(cursor, in: safeCellSize)
    self.pixels = [Bool](
      repeating: false,
      count: safeCellSize.width * 2 * safeCellSize.height * 4
    )
  }

  public static func sample() -> Self {
    var document = Self(
      cellSize: Size(width: 36, height: 12),
      cursor: CanvasSketchPoint(x: 12, y: 8)
    )
    let maxX = document.subpixelWidth - 1
    let maxY = document.subpixelHeight - 1
    guard maxX >= 0, maxY >= 0 else {
      return document
    }

    let count = min(document.subpixelWidth, document.subpixelHeight)
    for offset in 0..<count {
      document.setPixel(CanvasSketchPoint(x: offset, y: offset), isOn: true)
    }
    for x in 4..<min(document.subpixelWidth, 28) {
      document.setPixel(CanvasSketchPoint(x: x, y: 18), isOn: true)
    }
    for y in 10..<min(document.subpixelHeight, 34) {
      document.setPixel(CanvasSketchPoint(x: 30, y: y), isOn: true)
    }
    return document
  }

  public var subpixelWidth: Int { cellSize.width * 2 }
  public var subpixelHeight: Int { cellSize.height * 4 }

  public var litPixelCount: Int {
    pixels.reduce(0) { partial, isOn in partial + (isOn ? 1 : 0) }
  }

  public func contains(_ point: CanvasSketchPoint) -> Bool {
    point.x >= 0 && point.x < subpixelWidth && point.y >= 0 && point.y < subpixelHeight
  }

  public func isPixelSet(_ point: CanvasSketchPoint) -> Bool {
    guard let index = index(of: point) else {
      return false
    }
    return pixels[index]
  }

  public mutating func setPixel(
    _ point: CanvasSketchPoint,
    isOn: Bool = true
  ) {
    guard let index = index(of: point) else {
      return
    }
    pixels[index] = isOn
  }

  public mutating func drawAtCursor() {
    setPixel(cursor, isOn: true)
  }

  public mutating func eraseAtCursor() {
    setPixel(cursor, isOn: false)
  }

  public mutating func clear() {
    pixels = [Bool](repeating: false, count: pixels.count)
  }

  public mutating func moveCursor(dx: Int, dy: Int) {
    cursor = CanvasSketchDocument.clamped(
      CanvasSketchPoint(x: cursor.x + dx, y: cursor.y + dy),
      in: cellSize
    )
  }

  public func forEachLitPixel(
    _ body: (CanvasSketchPoint) -> Void
  ) {
    guard subpixelWidth > 0 else {
      return
    }
    for (index, isOn) in pixels.enumerated() where isOn {
      body(
        CanvasSketchPoint(
          x: index % subpixelWidth,
          y: index / subpixelWidth
        )
      )
    }
  }

  private func index(of point: CanvasSketchPoint) -> Int? {
    guard contains(point) else {
      return nil
    }
    return (point.y * subpixelWidth) + point.x
  }

  private static func clamped(
    _ point: CanvasSketchPoint,
    in cellSize: Size
  ) -> CanvasSketchPoint {
    let maxX = max(0, cellSize.width * 2 - 1)
    let maxY = max(0, cellSize.height * 4 - 1)
    return CanvasSketchPoint(
      x: min(max(0, point.x), maxX),
      y: min(max(0, point.y), maxY)
    )
  }
}

public struct CanvasSketchDrawing: CanvasDrawing, Equatable {
  public var document: CanvasSketchDocument

  public init(document: CanvasSketchDocument) {
    self.document = document
  }

  public func draw(into context: inout CanvasContext) {
    document.forEachLitPixel { point in
      context.setPixel(x: point.x, y: point.y)
    }
  }
}

public struct CanvasCursorDrawing: CanvasDrawing, Equatable {
  public var cursor: CanvasSketchPoint

  public init(cursor: CanvasSketchPoint) {
    self.cursor = cursor
  }

  public func draw(into context: inout CanvasContext) {
    let points = [
      cursor,
      CanvasSketchPoint(x: cursor.x - 1, y: cursor.y),
      CanvasSketchPoint(x: cursor.x + 1, y: cursor.y),
      CanvasSketchPoint(x: cursor.x, y: cursor.y - 1),
      CanvasSketchPoint(x: cursor.x, y: cursor.y + 1),
    ]
    for point in points {
      context.setPixel(x: point.x, y: point.y)
    }
  }
}

public struct CanvasDemoSurface: View {
  public var document: CanvasSketchDocument

  public init(document: CanvasSketchDocument) {
    self.document = document
  }

  public var body: some View {
    ZStack(alignment: .topLeading) {
      Canvas(CanvasSketchDrawing(document: document))
        .foregroundStyle(Color.cyan)
        .frame(width: document.cellSize.width, height: document.cellSize.height)
      Canvas(CanvasCursorDrawing(cursor: document.cursor))
        .foregroundStyle(Color.yellow)
        .frame(width: document.cellSize.width, height: document.cellSize.height)
    }
    .border(.separator)
  }
}

public struct CanvasDemoPixelPreview: View {
  public var mode: CanvasPixelGridMode

  public init(mode: CanvasPixelGridMode) {
    self.mode = mode
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("pixel grid \(modeLabel)").foregroundStyle(.muted)
      Canvas(
        pixelGridWidth: Self.width,
        height: Self.height,
        pixels: Self.pixels,
        mode: mode
      )
      .frame(width: Self.width, height: mode.cellHeight(for: Self.height))
      .border(.separator)
    }
  }

  private var modeLabel: String {
    switch mode {
    case .fullCell:
      "full-cell"
    case .verticalHalfBlock:
      "half-block"
    }
  }

  private static let width = 12
  private static let height = 6

  private static let pixels: [Color?] = {
    var output = [Color?]()
    for y in 0..<height {
      for x in 0..<width {
        if (x + y) % 5 == 0 {
          output.append(nil)
        } else if x < width / 3 {
          output.append(.red)
        } else if x < (width * 2) / 3 {
          output.append(.green)
        } else {
          output.append(y.isMultiple(of: 2) ? .blue : .yellow)
        }
      }
    }
    return output
  }()
}

public struct CanvasDemoView: View {
  @State private var document: CanvasSketchDocument
  @State private var pixelMode: CanvasPixelGridMode

  public init(
    document: CanvasSketchDocument = .sample(),
    pixelMode: CanvasPixelGridMode = .fullCell
  ) {
    _document = State(initialValue: document)
    _pixelMode = State(initialValue: pixelMode)
  }

  public var body: some View {
    let snapshot = document
    let modeSnapshot = pixelMode
    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 2) {
        Text("canvas-demo").foregroundStyle(.foreground)
        Text("Canvas verification surface").foregroundStyle(.muted)
        Spacer(minLength: 1)
        Text("\(snapshot.litPixelCount) dots").foregroundStyle(.cyan)
      }
      Divider()
      HStack(alignment: .top, spacing: 2) {
        CanvasDemoSurface(document: snapshot)
        CanvasDemoPixelPreview(mode: modeSnapshot)
      }
      Divider()
      Text(statusLine(for: snapshot, pixelMode: modeSnapshot)).foregroundStyle(.muted)
      Text(
        "Shift+arrows move  Shift+Space draw  Ctrl+E erase  Ctrl+K clear  Ctrl+M mode  Ctrl+C quit"
      )
      .foregroundStyle(.separator)
    }
    .padding(1)
    .panel(id: "canvas-demo")
    .keyCommand("Move cursor left", key: .arrowLeft, modifiers: .shift) {
      document.moveCursor(dx: -1, dy: 0)
    }
    .keyCommand("Move cursor right", key: .arrowRight, modifiers: .shift) {
      document.moveCursor(dx: 1, dy: 0)
    }
    .keyCommand("Move cursor up", key: .arrowUp, modifiers: .shift) {
      document.moveCursor(dx: 0, dy: -1)
    }
    .keyCommand("Move cursor down", key: .arrowDown, modifiers: .shift) {
      document.moveCursor(dx: 0, dy: 1)
    }
    .keyCommand("Jump cursor left", key: .arrowLeft, modifiers: .ctrl) {
      document.moveCursor(dx: -8, dy: 0)
    }
    .keyCommand("Jump cursor right", key: .arrowRight, modifiers: .ctrl) {
      document.moveCursor(dx: 8, dy: 0)
    }
    .keyCommand("Jump cursor up", key: .arrowUp, modifiers: .ctrl) {
      document.moveCursor(dx: 0, dy: -8)
    }
    .keyCommand("Jump cursor down", key: .arrowDown, modifiers: .ctrl) {
      document.moveCursor(dx: 0, dy: 8)
    }
    .keyCommand("Draw at cursor", key: .space, modifiers: .shift) {
      document.drawAtCursor()
    }
    .keyCommand("Erase at cursor", key: .character("e"), modifiers: .ctrl) {
      document.eraseAtCursor()
    }
    .keyCommand("Clear drawing", key: .character("k"), modifiers: .ctrl) {
      document.clear()
    }
    .keyCommand("Toggle pixel grid mode", key: .character("m"), modifiers: .ctrl) {
      pixelMode =
        switch pixelMode {
        case .fullCell:
          .verticalHalfBlock
        case .verticalHalfBlock:
          .fullCell
        }
    }
  }

  private func statusLine(
    for document: CanvasSketchDocument,
    pixelMode: CanvasPixelGridMode
  ) -> String {
    let cursor = document.cursor
    let modeLabel =
      switch pixelMode {
      case .fullCell:
        "full-cell"
      case .verticalHalfBlock:
        "half-block"
      }
    return
      "cursor \(cursor.x),\(cursor.y) of \(document.subpixelWidth)x\(document.subpixelHeight) Braille subpixels  pixel grid \(modeLabel)"
  }
}
