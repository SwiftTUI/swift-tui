import SwiftTUIRuntime

/// Conway's Game of Life, rendered through SwiftTUI at three zoom
/// levels and editable by tap or click-and-drag.
///
/// **Zoom modes** (most → least dense):
///   - braille (8×): 2×4 game cells per terminal cell, Unicode required
///   - half-cell (2×): 1×2 game cells per terminal cell, Unicode required
///   - square (1×): 1 game cell per pair of terminal cells (always available)
///
/// **Interactivity**:
///   - tap: toggles the cell under the pointer
///   - drag: paints every cell touched along the drag path with the
///     opposite of the starting cell's state. So starting on an alive
///     cell erases; starting on a dead cell stamps.
///
/// **Capability gating** is enforced by the `Picker` options: when a
/// host environment one day exposes a `glyphLevel` value, modes that
/// require Unicode are filtered out for ASCII-only profiles. Today the
/// demo trusts the iframe / WASI host to advertise Unicode, which the
/// browser always does.
public struct LifeTab: View {
  public init() {}

  // Game state
  @State private var grid = LifeGrid()
  @State private var didSeedDefault = false
  @State private var lastFitWidth: Int = 0
  @State private var lastFitHeight: Int = 0

  // Auto-tick state
  @State private var isRunning: Bool = true
  @State private var tickIntervalMs: Double = 110

  // Zoom & rendering
  @State private var zoom: LifeZoom = .halfCell

  // Drag-paint state. `paintMode` is `nil` while idle and latches to
  // either `true` (stamp alive) or `false` (erase) on the first touch
  // of a drag. The set tracks already-stamped game cells across the
  // drag so traversing the same cell does not re-toggle it.
  @State private var paintMode: Bool? = nil
  @State private var stampedCells: Set<Int> = []

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      gridSurface
      Divider()
      controls
    }
    .task(id: AutoTickKey(running: isRunning, intervalMs: Int(tickIntervalMs))) {
      @MainActor in
      await runAutoTick()
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(spacing: 1) {
      Text("Conway's Life").bold()
      Text("·").foregroundStyle(.separator)
      Text("\(grid.population) live").foregroundStyle(.muted)
      Text("·").foregroundStyle(.separator)
      Text("gen \(grid.generation)").foregroundStyle(.muted)
      Spacer()
      Text(zoom.label).foregroundStyle(.tint)
    }
    .padding(.horizontal, 1)
  }

  // MARK: - Grid surface

  private var gridSurface: some View {
    GeometryReader { proxy in
      let dims = zoom.gridDimensions(for: proxy.size)
      let termSize = zoom.terminalSize(forGameWidth: dims.width, gameHeight: dims.height)
      let drawing = LifeDrawing(
        cells: LifeRenderer.snapshot(of: grid, width: dims.width, height: dims.height),
        width: dims.width,
        height: dims.height,
        zoom: zoom
      )

      Canvas(grid: zoom.canvasGrid, drawing)
        .foregroundStyle(.tint)
        .frame(width: termSize.width, height: termSize.height, alignment: .topLeading)
        .contentShape(
          CellRect(
            origin: .init(x: 0, y: 0),
            size: proxy.size
          )
        )
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              handlePaint(at: value.location, gridSize: dims)
            }
            .onEnded { _ in
              paintMode = nil
              stampedCells.removeAll(keepingCapacity: true)
            }
        )
        .onAppearOnce(once: $didSeedDefault) {
          var resized = grid
          resized.resize(width: dims.width, height: dims.height)
          resized.seedDefault()
          grid = resized
          lastFitWidth = dims.width
          lastFitHeight = dims.height
        }
        .onResize(
          width: dims.width, height: dims.height, lastWidth: $lastFitWidth,
          lastHeight: $lastFitHeight
        ) {
          var resized = grid
          resized.resize(width: dims.width, height: dims.height)
          grid = resized
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Controls

  private var controls: some View {
    HStack(spacing: 2) {
      Button(isRunning ? "Pause" : "Play") {
        isRunning.toggle()
      }
      .buttonStyle(.borderedProminent)

      Button("Step") {
        var next = grid
        next.step()
        grid = next
      }
      .disabled(isRunning)

      Button("Random") {
        var next = grid
        next.randomize()
        grid = next
      }

      Button("Clear") {
        var next = grid
        next.clear()
        grid = next
      }

      Spacer()

      Picker("Zoom", selection: $zoom) {
        ForEach(LifeZoom.allCases, id: \.self) { level in
          Text(level.label).tag(level)
        }
      }
    }
    .padding(.horizontal, 1)
  }

  // MARK: - Drag painting

  private func handlePaint(at point: Point, gridSize: (width: Int, height: Int)) {
    guard let cell = zoom.gameCell(at: point, gridSize: gridSize) else { return }
    let index = cell.y * LifeGrid.maxWidth + cell.x

    if paintMode == nil {
      // First touch of this drag — latch the paint mode to the inverse
      // of the starting cell so dragging from an alive cell erases and
      // dragging from a dead cell stamps.
      paintMode = !grid.at(cell.x, cell.y)
    }

    // Skip cells already stamped during this drag.
    guard !stampedCells.contains(index) else { return }
    stampedCells.insert(index)

    if let mode = paintMode {
      var next = grid
      next.set(cell.x, cell.y, mode)
      grid = next
    }
  }

  // MARK: - Auto-tick loop

  private func runAutoTick() async {
    guard isRunning else { return }
    let intervalNs = UInt64(max(20.0, tickIntervalMs)) * 1_000_000

    while !Task.isCancelled, isRunning {
      try? await Task.sleep(nanoseconds: intervalNs)
      guard !Task.isCancelled, isRunning else { return }
      var next = grid
      next.step()
      grid = next
    }
  }
}

// MARK: - Auto-tick key

/// `.task(id:)` re-runs the body when this key changes, so flipping
/// `isRunning` or `tickIntervalMs` cleanly cancels the prior loop and
/// starts a fresh one. Sendable so it satisfies the `id`'s
/// `Equatable + Sendable` constraint under strict concurrency.
private struct AutoTickKey: Hashable, Sendable {
  let running: Bool
  let intervalMs: Int
}

// MARK: - Once-only on-appear and resize helpers

extension View {
  /// Runs `action` exactly once across this view's lifetime. The flag
  /// is held in a caller-owned `@State` so it survives re-resolves.
  fileprivate func onAppearOnce(
    once flag: Binding<Bool>,
    perform action: @escaping @MainActor @Sendable () -> Void
  ) -> some View {
    self.onAppear {
      guard !flag.wrappedValue else { return }
      flag.wrappedValue = true
      action()
    }
  }

  /// Calls `action` whenever `width`/`height` differ from the values
  /// previously persisted in `lastWidth`/`lastHeight`. Used in the
  /// `gridSurface` body to react to terminal resize without thrashing
  /// state every frame.
  fileprivate func onResize(
    width: Int,
    height: Int,
    lastWidth: Binding<Int>,
    lastHeight: Binding<Int>,
    perform action: @escaping @MainActor @Sendable () -> Void
  ) -> some View {
    self
      .onChange(of: width) { _, newValue in
        if newValue != lastWidth.wrappedValue {
          lastWidth.wrappedValue = newValue
          action()
        }
      }
      .onChange(of: height) { _, newValue in
        if newValue != lastHeight.wrappedValue {
          lastHeight.wrappedValue = newValue
          action()
        }
      }
  }
}
