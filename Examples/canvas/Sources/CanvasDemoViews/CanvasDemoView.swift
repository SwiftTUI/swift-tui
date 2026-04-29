import TerminalUI

public struct CanvasSketchPoint: Equatable, Hashable, Sendable {
  public var x: Int
  public var y: Int

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }
}

public enum CanvasSketchTool: Equatable, Hashable, Sendable {
  case draw
  case erase

  public var label: String {
    switch self {
    case .draw:
      "draw"
    case .erase:
      "erase"
    }
  }

  fileprivate var writesOn: Bool {
    switch self {
    case .draw:
      true
    case .erase:
      false
    }
  }
}

public enum CanvasDemoCanvasType: String, CaseIterable, Hashable, Sendable {
  case subcell
  case fullCell
  case halfBlock

  public var title: String {
    switch self {
    case .subcell:
      "Subcell"
    case .fullCell:
      "Full Cell"
    case .halfBlock:
      "Half Block"
    }
  }
}

private func forEachLinePoint(
  from start: CanvasSketchPoint,
  to end: CanvasSketchPoint,
  _ body: (CanvasSketchPoint) -> Void
) {
  var current = start
  let dx = abs(end.x - current.x)
  let dy = abs(end.y - current.y)
  let stepX = current.x < end.x ? 1 : -1
  let stepY = current.y < end.y ? 1 : -1
  var error = dx - dy

  while true {
    body(current)
    if current == end {
      break
    }
    let doubledError = error * 2
    if doubledError > -dy {
      error -= dy
      current.x += stepX
    }
    if doubledError < dx {
      error += dx
      current.y += stepY
    }
  }
}

public struct CanvasSketchDocument: Equatable, Sendable {
  private static let grid = CanvasGrid.braille2x4

  public var cellSize: CellSize
  public private(set) var cursor: CanvasSketchPoint

  private var pixels: [Bool]

  public init(
    cellSize: CellSize = CellSize(width: 36, height: 12),
    cursor: CanvasSketchPoint = CanvasSketchPoint(x: 0, y: 0)
  ) {
    let safeCellSize = CellSize(
      width: max(0, cellSize.width),
      height: max(0, cellSize.height)
    )
    self.cellSize = safeCellSize
    self.cursor = CanvasSketchDocument.clamped(cursor, in: safeCellSize)
    self.pixels = [Bool](
      repeating: false,
      count: safeCellSize.width * Self.grid.subdivisionsX * safeCellSize.height
        * Self.grid.subdivisionsY
    )
  }

  public static func sample() -> Self {
    var document = Self(
      cellSize: CellSize(width: 36, height: 12),
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

  public var subpixelWidth: Int { cellSize.width * Self.grid.subdivisionsX }
  public var subpixelHeight: Int { cellSize.height * Self.grid.subdivisionsY }
  public var maxSubpixelX: Int { subpixelWidth - 1 }
  public var maxSubpixelY: Int { subpixelHeight - 1 }

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

  public mutating func moveCursor(to point: CanvasSketchPoint) {
    cursor = CanvasSketchDocument.clamped(point, in: cellSize)
  }

  public mutating func apply(_ tool: CanvasSketchTool, at point: CanvasSketchPoint) {
    let clampedPoint = CanvasSketchDocument.clamped(point, in: cellSize)
    setPixel(clampedPoint, isOn: tool.writesOn)
    cursor = clampedPoint
  }

  public mutating func apply(_ tool: CanvasSketchTool, atLocalCell point: Point) {
    apply(tool, at: subpixelPoint(forLocalCell: point))
  }

  public mutating func apply(
    _ tool: CanvasSketchTool, from start: CanvasSketchPoint, to end: CanvasSketchPoint
  ) {
    let start = CanvasSketchDocument.clamped(start, in: cellSize)
    let target = CanvasSketchDocument.clamped(end, in: cellSize)
    forEachLinePoint(from: start, to: target) { point in
      setPixel(point, isOn: tool.writesOn)
    }
    cursor = target
  }

  public mutating func apply(
    _ tool: CanvasSketchTool,
    fromLocalCell start: Point,
    toLocalCell end: Point
  ) {
    apply(
      tool,
      from: subpixelPoint(forLocalCell: start),
      to: subpixelPoint(forLocalCell: end)
    )
  }

  public func subpixelPoint(forLocalCell point: Point) -> CanvasSketchPoint {
    CanvasSketchDocument.subpixelPoint(forLocalCell: point, in: cellSize)
  }

  func subpixelPoint(
    forLocalCell point: Point,
    precision: PointerPrecision
  ) -> CanvasSketchPoint {
    CanvasSketchDocument.subpixelPoint(
      forLocalCell: point,
      precision: precision,
      in: cellSize
    )
  }

  public func cellLocation(for point: CanvasSketchPoint) -> Point {
    Point(
      x: (Double(point.x) + 0.5) / Double(Self.grid.subdivisionsX),
      y: (Double(point.y) + 0.5) / Double(Self.grid.subdivisionsY)
    )
  }

  public static func subpixelPoint(
    forLocalCell point: Point,
    in cellSize: CellSize
  ) -> CanvasSketchPoint {
    guard cellSize.width > 0, cellSize.height > 0 else {
      return CanvasSketchPoint(x: 0, y: 0)
    }
    return CanvasSketchPoint(
      x: gridCoordinate(
        point.x,
        subdivisions: Self.grid.subdivisionsX,
        maxIndex: cellSize.width * Self.grid.subdivisionsX - 1
      ),
      y: gridCoordinate(
        point.y,
        subdivisions: Self.grid.subdivisionsY,
        maxIndex: cellSize.height * Self.grid.subdivisionsY - 1
      )
    )
  }

  static func subpixelPoint(
    forLocalCell point: Point,
    precision: PointerPrecision,
    in cellSize: CellSize
  ) -> CanvasSketchPoint {
    subpixelPoint(
      forLocalCell: canvasPointerLocation(point, precision: precision),
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
    in cellSize: CellSize
  ) -> CanvasSketchPoint {
    let maxX = max(0, cellSize.width * Self.grid.subdivisionsX - 1)
    let maxY = max(0, cellSize.height * Self.grid.subdivisionsY - 1)
    return CanvasSketchPoint(
      x: min(max(0, point.x), maxX),
      y: min(max(0, point.y), maxY)
    )
  }

  private static func gridCoordinate(
    _ value: Double,
    subdivisions: Int,
    maxIndex: Int
  ) -> Int {
    guard maxIndex > 0 else {
      return 0
    }
    let scaled = (value * Double(subdivisions)).rounded(.down)
    guard scaled.isFinite else {
      return scaled.sign == .minus || scaled.isNaN ? 0 : maxIndex
    }
    return min(max(0, Int(scaled)), maxIndex)
  }
}

private func canvasPointerLocation(
  _ point: Point,
  precision: PointerPrecision
) -> Point {
  switch precision {
  case .cell:
    Point(point.containingCell)
  case .subCell:
    point
  }
}

private func canvasPointerTargetPath(width: Int, height: Int) -> Path {
  let width = max(0, width)
  let height = max(0, height)
  var path = Path()
  guard width > 0, height > 0 else {
    return path
  }
  path.move(to: .zero)
  path.addLine(to: Point(x: Double(width), y: 0))
  path.addLine(to: Point(x: Double(width), y: Double(height)))
  path.addLine(to: Point(x: 0, y: Double(height)))
  path.close()
  return path
}

public struct CanvasPixelSketchDocument: Equatable, Sendable {
  public var size: CellSize
  public private(set) var cursor: CanvasSketchPoint

  private var pixels: [Bool]

  public init(
    size: CellSize = CellSize(width: 24, height: 10),
    cursor: CanvasSketchPoint = CanvasSketchPoint(x: 0, y: 0)
  ) {
    let safeSize = CellSize(
      width: max(0, size.width),
      height: max(0, size.height)
    )
    self.size = safeSize
    self.cursor = CanvasPixelSketchDocument.clamped(cursor, in: safeSize)
    pixels = [Bool](repeating: false, count: safeSize.width * safeSize.height)
  }

  public static func sample(
    size: CellSize = CellSize(width: 24, height: 10),
    cursor: CanvasSketchPoint = CanvasSketchPoint(x: 8, y: 4)
  ) -> Self {
    var document = Self(size: size, cursor: cursor)
    guard document.width > 0, document.height > 0 else {
      return document
    }

    let diagonalCount = min(document.width, document.height)
    for offset in 0..<diagonalCount {
      document.setPixel(CanvasSketchPoint(x: offset, y: offset), isOn: true)
    }
    for x in 2..<min(document.width, 18) {
      document.setPixel(CanvasSketchPoint(x: x, y: min(2, document.height - 1)), isOn: true)
    }
    for y in 2..<min(document.height, 8) {
      document.setPixel(CanvasSketchPoint(x: min(18, document.width - 1), y: y), isOn: true)
    }
    return document
  }

  public var width: Int { size.width }
  public var height: Int { size.height }
  public var maxPixelX: Int { width - 1 }
  public var maxPixelY: Int { height - 1 }

  public var litPixelCount: Int {
    pixels.reduce(0) { partial, isOn in partial + (isOn ? 1 : 0) }
  }

  public func contains(_ point: CanvasSketchPoint) -> Bool {
    point.x >= 0 && point.x < width && point.y >= 0 && point.y < height
  }

  public func isPixelSet(_ point: CanvasSketchPoint) -> Bool {
    guard let index = index(of: point) else {
      return false
    }
    return pixels[index]
  }

  public func colorPixels(color: Color = .cyan) -> [Color?] {
    pixels.map { isOn in isOn ? color : nil }
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

  public mutating func clear() {
    pixels = [Bool](repeating: false, count: pixels.count)
  }

  public mutating func moveCursor(dx: Int, dy: Int) {
    cursor = CanvasPixelSketchDocument.clamped(
      CanvasSketchPoint(x: cursor.x + dx, y: cursor.y + dy),
      in: size
    )
  }

  public mutating func apply(_ tool: CanvasSketchTool, at point: CanvasSketchPoint) {
    let clampedPoint = CanvasPixelSketchDocument.clamped(point, in: size)
    setPixel(clampedPoint, isOn: tool.writesOn)
    cursor = clampedPoint
  }

  public mutating func apply(
    _ tool: CanvasSketchTool,
    atLocalCell point: Point,
    mode: CanvasPixelGridMode
  ) {
    apply(tool, at: pixelPoint(forLocalCell: point, mode: mode))
  }

  public mutating func apply(
    _ tool: CanvasSketchTool,
    from start: CanvasSketchPoint,
    to end: CanvasSketchPoint
  ) {
    let start = CanvasPixelSketchDocument.clamped(start, in: size)
    let target = CanvasPixelSketchDocument.clamped(end, in: size)
    forEachLinePoint(from: start, to: target) { point in
      setPixel(point, isOn: tool.writesOn)
    }
    cursor = target
  }

  public mutating func apply(
    _ tool: CanvasSketchTool,
    fromLocalCell start: Point,
    toLocalCell end: Point,
    mode: CanvasPixelGridMode
  ) {
    apply(
      tool,
      from: pixelPoint(forLocalCell: start, mode: mode),
      to: pixelPoint(forLocalCell: end, mode: mode)
    )
  }

  public func pixelPoint(
    forLocalCell point: Point,
    mode: CanvasPixelGridMode
  ) -> CanvasSketchPoint {
    CanvasPixelSketchDocument.pixelPoint(forLocalCell: point, mode: mode, in: size)
  }

  func pixelPoint(
    forLocalCell point: Point,
    precision: PointerPrecision,
    mode: CanvasPixelGridMode
  ) -> CanvasSketchPoint {
    CanvasPixelSketchDocument.pixelPoint(
      forLocalCell: point,
      precision: precision,
      mode: mode,
      in: size
    )
  }

  public static func pixelPoint(
    forLocalCell point: Point,
    mode: CanvasPixelGridMode,
    in size: CellSize
  ) -> CanvasSketchPoint {
    guard size.width > 0, size.height > 0 else {
      return CanvasSketchPoint(x: 0, y: 0)
    }
    let ySubdivisions =
      switch mode {
      case .fullCell: 1
      case .verticalHalfBlock: 2
      }
    return CanvasSketchPoint(
      x: gridCoordinate(point.x, subdivisions: 1, maxIndex: size.width - 1),
      y: gridCoordinate(point.y, subdivisions: ySubdivisions, maxIndex: size.height - 1)
    )
  }

  static func pixelPoint(
    forLocalCell point: Point,
    precision: PointerPrecision,
    mode: CanvasPixelGridMode,
    in size: CellSize
  ) -> CanvasSketchPoint {
    pixelPoint(
      forLocalCell: canvasPointerLocation(point, precision: precision),
      mode: mode,
      in: size
    )
  }

  private func index(of point: CanvasSketchPoint) -> Int? {
    guard contains(point) else {
      return nil
    }
    return (point.y * width) + point.x
  }

  private static func clamped(
    _ point: CanvasSketchPoint,
    in size: CellSize
  ) -> CanvasSketchPoint {
    let maxX = max(0, size.width - 1)
    let maxY = max(0, size.height - 1)
    return CanvasSketchPoint(
      x: min(max(0, point.x), maxX),
      y: min(max(0, point.y), maxY)
    )
  }

  private static func gridCoordinate(
    _ value: Double,
    subdivisions: Int,
    maxIndex: Int
  ) -> Int {
    guard maxIndex > 0 else {
      return 0
    }
    let scaled = (value * Double(subdivisions)).rounded(.down)
    guard scaled.isFinite else {
      return scaled.sign == .minus || scaled.isNaN ? 0 : maxIndex
    }
    return min(max(0, Int(scaled)), maxIndex)
  }
}

public struct CanvasHoverDrawing: CanvasDrawing, Equatable {
  public var location: Point?

  public init(location: Point?) {
    self.location = location
  }

  public func draw(into context: inout CanvasContext) {
    guard let location, context.size.width > 0, context.size.height > 0 else {
      return
    }
    let x = min(max(0, location.x), max(0, Double(context.size.width) - 0.001))
    let y = min(max(0, location.y), max(0, Double(context.size.height) - 0.001))
    context.line(
      from: Point(x: max(0, x - 0.75), y: y),
      to: Point(x: min(Double(context.size.width), x + 0.75), y: y)
    )
    context.line(
      from: Point(x: x, y: max(0, y - 0.75)),
      to: Point(x: x, y: min(Double(context.size.height), y + 0.75))
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
      context.setPixel(at: document.cellLocation(for: point))
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
      context.setPixel(
        at: Point(
          x: (Double(point.x) + 0.5) / Double(CanvasGrid.braille2x4.subdivisionsX),
          y: (Double(point.y) + 0.5) / Double(CanvasGrid.braille2x4.subdivisionsY)
        )
      )
    }
  }
}

public struct CanvasDemoSurface: View {
  @Binding private var document: CanvasSketchDocument
  public var tool: CanvasSketchTool
  @State private var lastDragPoint: CanvasSketchPoint?
  @State private var hoverLocation: Point?

  public init(
    document: Binding<CanvasSketchDocument>,
    tool: CanvasSketchTool = .draw
  ) {
    _document = document
    self.tool = tool
  }

  public init(
    document: CanvasSketchDocument,
    tool: CanvasSketchTool = .draw
  ) {
    _document = .constant(document)
    self.tool = tool
  }

  public var body: some View {
    EnvironmentReader(\.pointerInputCapabilities) { pointerInputCapabilities in
      let snapshot = document
      ZStack(alignment: .topLeading) {
        Canvas(grid: .braille2x4, CanvasSketchDrawing(document: snapshot))
          .foregroundStyle(Color.cyan)
          .frame(width: snapshot.cellSize.width, height: snapshot.cellSize.height)
        Canvas(grid: .braille2x4, CanvasCursorDrawing(cursor: snapshot.cursor))
          .foregroundStyle(Color.yellow)
          .frame(width: snapshot.cellSize.width, height: snapshot.cellSize.height)
        Canvas(grid: .braille2x4, CanvasHoverDrawing(location: hoverLocation))
          .foregroundStyle(Color.magenta)
          .frame(width: snapshot.cellSize.width, height: snapshot.cellSize.height)
      }
      .frame(width: snapshot.cellSize.width, height: snapshot.cellSize.height)
      .contentShape(
        canvasPointerTargetPath(
          width: snapshot.cellSize.width,
          height: snapshot.cellSize.height
        )
      )
      .gesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
          .onChanged { value in
            applyDragChange(value)
          }
          .onEnded { value in
            applyDragEnd(value)
          }
      )
      .onPointerHover { phase in
        updateHover(phase, precision: pointerInputCapabilities.precision)
      }
      .border(.separator)
      .focusable(true, interactions: .edit)
    }
  }

  private func applyDragChange(_ value: DragGesture.Value) {
    let start =
      lastDragPoint
      ?? document.subpixelPoint(
        forLocalCell: value.startLocation, precision: value.pointer.precision)
    let end = document.subpixelPoint(
      forLocalCell: value.location, precision: value.pointer.precision)
    document.apply(tool, from: start, to: end)
    lastDragPoint = end
  }

  private func applyDragEnd(_ value: DragGesture.Value) {
    let start =
      lastDragPoint
      ?? document.subpixelPoint(
        forLocalCell: value.startLocation, precision: value.pointer.precision)
    let end = document.subpixelPoint(
      forLocalCell: value.location, precision: value.pointer.precision)
    document.apply(tool, from: start, to: end)
    lastDragPoint = nil
  }

  private func updateHover(_ phase: HoverPhase, precision: PointerPrecision) {
    switch phase {
    case .entered(let location), .moved(let location):
      hoverLocation = canvasPointerLocation(location, precision: precision)
    case .exited:
      hoverLocation = nil
    }
  }
}

public struct CanvasPixelCursorDrawing: CanvasDrawing, Equatable {
  public var cursor: CanvasSketchPoint
  public var mode: CanvasPixelGridMode

  public init(
    cursor: CanvasSketchPoint,
    mode: CanvasPixelGridMode
  ) {
    self.cursor = cursor
    self.mode = mode
  }

  public func draw(into context: inout CanvasContext) {
    switch mode {
    case .fullCell:
      context.setCell(
        x: cursor.x,
        y: cursor.y,
        character: "█",
        foreground: .yellow
      )
    case .verticalHalfBlock:
      context.setCell(
        x: cursor.x,
        y: cursor.y / 2,
        character: cursor.y.isMultiple(of: 2) ? "▀" : "▄",
        foreground: .yellow
      )
    }
  }
}

public struct CanvasDemoPixelSurface: View {
  @Binding private var document: CanvasPixelSketchDocument
  public var mode: CanvasPixelGridMode
  public var tool: CanvasSketchTool
  @State private var lastDragPoint: CanvasSketchPoint?

  public init(
    document: Binding<CanvasPixelSketchDocument>,
    mode: CanvasPixelGridMode,
    tool: CanvasSketchTool = .draw
  ) {
    _document = document
    self.mode = mode
    self.tool = tool
  }

  public init(
    document: CanvasPixelSketchDocument,
    mode: CanvasPixelGridMode,
    tool: CanvasSketchTool = .draw
  ) {
    _document = .constant(document)
    self.mode = mode
    self.tool = tool
  }

  public var body: some View {
    let snapshot = document
    let cellHeight = mode.cellHeight(for: snapshot.height)
    return ZStack(alignment: .topLeading) {
      Canvas(
        pixelGridWidth: snapshot.width,
        height: snapshot.height,
        pixels: snapshot.colorPixels(),
        mode: mode
      )
      .frame(width: snapshot.width, height: cellHeight)
      Canvas(CanvasPixelCursorDrawing(cursor: snapshot.cursor, mode: mode))
        .frame(width: snapshot.width, height: cellHeight)
    }
    .frame(width: snapshot.width, height: cellHeight)
    .contentShape(
      canvasPointerTargetPath(
        width: snapshot.width,
        height: cellHeight
      )
    )
    .gesture(
      DragGesture(minimumDistance: 0, coordinateSpace: .local)
        .onChanged { value in
          applyDragChange(value)
        }
        .onEnded { value in
          applyDragEnd(value)
        }
    )
    .border(.separator)
    .focusable(true, interactions: .edit)
  }

  private func applyDragChange(_ value: DragGesture.Value) {
    let start =
      lastDragPoint
      ?? document.pixelPoint(
        forLocalCell: value.startLocation,
        precision: value.pointer.precision,
        mode: mode
      )
    let end = document.pixelPoint(
      forLocalCell: value.location,
      precision: value.pointer.precision,
      mode: mode
    )
    document.apply(tool, from: start, to: end)
    lastDragPoint = end
  }

  private func applyDragEnd(_ value: DragGesture.Value) {
    let start =
      lastDragPoint
      ?? document.pixelPoint(
        forLocalCell: value.startLocation,
        precision: value.pointer.precision,
        mode: mode
      )
    let end = document.pixelPoint(
      forLocalCell: value.location,
      precision: value.pointer.precision,
      mode: mode
    )
    document.apply(tool, from: start, to: end)
    lastDragPoint = nil
  }
}

public struct CanvasDemoView: View {
  @State private var document: CanvasSketchDocument
  @State private var fullCellDocument: CanvasPixelSketchDocument
  @State private var halfBlockDocument: CanvasPixelSketchDocument
  @State private var selectedCanvas: CanvasDemoCanvasType
  @State private var tool: CanvasSketchTool
  @FocusState private var focusedCanvas: CanvasDemoCanvasType?

  public init(
    document: CanvasSketchDocument = .sample(),
    fullCellDocument: CanvasPixelSketchDocument = .sample(),
    halfBlockDocument: CanvasPixelSketchDocument = .sample(
      size: CellSize(width: 24, height: 18),
      cursor: CanvasSketchPoint(x: 8, y: 8)
    ),
    selectedCanvas: CanvasDemoCanvasType = .subcell,
    tool: CanvasSketchTool = .draw
  ) {
    _document = State(initialValue: document)
    _fullCellDocument = State(initialValue: fullCellDocument)
    _halfBlockDocument = State(initialValue: halfBlockDocument)
    _selectedCanvas = State(initialValue: selectedCanvas)
    _tool = State(initialValue: tool)
  }

  public var body: some View {
    EnvironmentReader(\.pointerInputCapabilities) { pointerInputCapabilities in
      EnvironmentReader(\.cellPixelMetrics) { cellPixelMetrics in
        let snapshot = document
        let fullCellSnapshot = fullCellDocument
        let halfBlockSnapshot = halfBlockDocument
        let selectionSnapshot = selectedCanvas
        let toolSnapshot = tool
        let activeLitPixelCount =
          switch selectionSnapshot {
          case .subcell:
            snapshot.litPixelCount
          case .fullCell:
            fullCellSnapshot.litPixelCount
          case .halfBlock:
            halfBlockSnapshot.litPixelCount
          }
        VStack(alignment: .leading, spacing: 0) {
          HStack(spacing: 2) {
            Text("canvas-demo").foregroundStyle(.foreground)
            Text(selectionSnapshot.title).foregroundStyle(.muted)
            Spacer(minLength: 1)
            Text("\(activeLitPixelCount) dots").foregroundStyle(.cyan)
          }
          Divider()
          TabView(selection: $selectedCanvas) {
            Tab("Subcell", value: CanvasDemoCanvasType.subcell) {
              VStack(alignment: .leading, spacing: 0) {
                CanvasDemoSurface(document: $document, tool: toolSnapshot)
                  .focused($focusedCanvas, equals: .subcell)
                  .defaultFocus($focusedCanvas, .subcell)
                  .onKeyPress(.any) { keyPress in
                    handleSubcellKeyPress(keyPress)
                  }
                Text("Braille grid max \(snapshot.maxSubpixelX),\(snapshot.maxSubpixelY)")
                  .foregroundStyle(.muted)
              }
            }

            Tab("Full Cell", value: CanvasDemoCanvasType.fullCell) {
              VStack(alignment: .leading, spacing: 0) {
                CanvasDemoPixelSurface(
                  document: $fullCellDocument,
                  mode: .fullCell,
                  tool: toolSnapshot
                )
                .focused($focusedCanvas, equals: .fullCell)
                .defaultFocus($focusedCanvas, .fullCell)
                .onKeyPress(.any) { keyPress in
                  handleFullCellKeyPress(keyPress)
                }
                Text(
                  "full-cell pixel grid max \(fullCellSnapshot.maxPixelX),\(fullCellSnapshot.maxPixelY)"
                )
                .foregroundStyle(.muted)
              }
            }

            Tab("Half Block", value: CanvasDemoCanvasType.halfBlock) {
              VStack(alignment: .leading, spacing: 0) {
                CanvasDemoPixelSurface(
                  document: $halfBlockDocument,
                  mode: .verticalHalfBlock,
                  tool: toolSnapshot
                )
                .focused($focusedCanvas, equals: .halfBlock)
                .defaultFocus($focusedCanvas, .halfBlock)
                .onKeyPress(.any) { keyPress in
                  handleHalfBlockKeyPress(keyPress)
                }
                Text(
                  "half-block pixel grid max \(halfBlockSnapshot.maxPixelX),\(halfBlockSnapshot.maxPixelY)"
                )
                .foregroundStyle(.muted)
              }
            }
          }
          .tabViewStyle(.literalTabs)
          Divider()
          Text(
            statusLine(
              selectedCanvas: selectionSnapshot,
              subcellDocument: snapshot,
              fullCellDocument: fullCellSnapshot,
              halfBlockDocument: halfBlockSnapshot,
              tool: toolSnapshot
            )
          )
          .foregroundStyle(.muted)
          Text(
            capabilityLine(
              pointerInputCapabilities: pointerInputCapabilities,
              cellPixelMetrics: cellPixelMetrics
            )
          )
          .foregroundStyle(.muted)
          Text(
            "arrows/hjkl move  space paint  d draw  e erase  c clear  drag paints  Ctrl+C quit"
          )
          .foregroundStyle(.separator)
        }
        .padding(1)
        .panel(id: "canvas-demo")
      }
    }
  }

  private func handleSubcellKeyPress(_ keyPress: KeyPress) -> KeyPressResult {
    handleDrawingKeyPress(
      keyPress,
      moveCursor: { dx, dy in document.moveCursor(dx: dx, dy: dy) },
      paint: { document.apply(tool, at: document.cursor) },
      clear: { document.clear() }
    )
  }

  private func handleFullCellKeyPress(_ keyPress: KeyPress) -> KeyPressResult {
    handleDrawingKeyPress(
      keyPress,
      moveCursor: { dx, dy in fullCellDocument.moveCursor(dx: dx, dy: dy) },
      paint: { fullCellDocument.apply(tool, at: fullCellDocument.cursor) },
      clear: { fullCellDocument.clear() }
    )
  }

  private func handleHalfBlockKeyPress(_ keyPress: KeyPress) -> KeyPressResult {
    handleDrawingKeyPress(
      keyPress,
      moveCursor: { dx, dy in halfBlockDocument.moveCursor(dx: dx, dy: dy) },
      paint: { halfBlockDocument.apply(tool, at: halfBlockDocument.cursor) },
      clear: { halfBlockDocument.clear() }
    )
  }

  private func handleDrawingKeyPress(
    _ keyPress: KeyPress,
    moveCursor: (Int, Int) -> Void,
    paint: () -> Void,
    clear: () -> Void
  ) -> KeyPressResult {
    guard keyPress.modifiers.isEmpty else {
      return .ignored
    }

    switch keyPress.key {
    case .arrowLeft, .character("h"):
      moveCursor(-1, 0)
    case .arrowRight, .character("l"):
      moveCursor(1, 0)
    case .arrowUp, .character("k"):
      moveCursor(0, -1)
    case .arrowDown, .character("j"):
      moveCursor(0, 1)
    case .space, .return:
      paint()
    case .character("d"), .character("p"):
      tool = .draw
    case .character("e"):
      tool = .erase
    case .character("c"), .backspace:
      clear()
    default:
      return .ignored
    }

    return .handled
  }

  private func statusLine(
    selectedCanvas: CanvasDemoCanvasType,
    subcellDocument: CanvasSketchDocument,
    fullCellDocument: CanvasPixelSketchDocument,
    halfBlockDocument: CanvasPixelSketchDocument,
    tool: CanvasSketchTool
  ) -> String {
    switch selectedCanvas {
    case .subcell:
      let cursor = subcellDocument.cursor
      let maxIndex = "\(subcellDocument.maxSubpixelX),\(subcellDocument.maxSubpixelY)"
      return
        "canvas \(selectedCanvas.title)  tool \(tool.label)  "
        + "cursor \(cursor.x),\(cursor.y) of max \(maxIndex) Braille grid"
    case .fullCell:
      let cursor = fullCellDocument.cursor
      let maxIndex = "\(fullCellDocument.maxPixelX),\(fullCellDocument.maxPixelY)"
      return
        "canvas \(selectedCanvas.title)  tool \(tool.label)  "
        + "cursor \(cursor.x),\(cursor.y) of max \(maxIndex) pixels"
    case .halfBlock:
      let cursor = halfBlockDocument.cursor
      let maxIndex = "\(halfBlockDocument.maxPixelX),\(halfBlockDocument.maxPixelY)"
      return
        "canvas \(selectedCanvas.title)  tool \(tool.label)  "
        + "cursor \(cursor.x),\(cursor.y) of max \(maxIndex) pixels"
    }
  }

  private func capabilityLine(
    pointerInputCapabilities: PointerInputCapabilities,
    cellPixelMetrics: CellPixelMetrics
  ) -> String {
    "pointer \(pointerPrecisionLabel(pointerInputCapabilities.precision))  "
      + "cell \(cellPixelMetrics.width)x\(cellPixelMetrics.height) "
      + "\(cellMetricSourceLabel(cellPixelMetrics.source))"
  }

  private func pointerPrecisionLabel(_ precision: PointerPrecision) -> String {
    switch precision {
    case .cell:
      "cell fallback"
    case .subCell(let source, _):
      switch source {
      case .terminalPixels:
        "terminal pixels"
      case .nativePixels:
        "native pixels"
      case .webPixels:
        "web pixels"
      }
    }
  }

  private func cellMetricSourceLabel(_ source: CellPixelMetrics.Source) -> String {
    switch source {
    case .reported:
      "reported"
    case .estimated:
      "estimated"
    }
  }
}
