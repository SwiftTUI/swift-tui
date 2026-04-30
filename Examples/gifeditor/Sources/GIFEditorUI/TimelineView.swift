import GIFEditorCore
import TerminalUI

/// Bottom-strip timeline. Renders the navigation cluster
/// (`◀◀ ◀ ▶ ▶▶`), a horizontally-scrolling row of clickable frame
/// thumbnails (the active frame is wrapped in `[ ]` and tinted),
/// frame operations (`＋ ⎘ ✕`), and a delay readout / stepper
/// (`⊖ ⊕`) plus an `=all` equalize button.
///
/// Every visible affordance is a `.plain`-styled `Button` that calls
/// the same model method as its keyboard shortcut, so users can drive
/// the timeline entirely via mouse, entirely via keyboard, or any
/// mix.
struct TimelineView: View {
  let frames: [TimelineFrame]
  let currentFrameIndex: Int
  let model: EditorViewModel
  let refresh: @MainActor @Sendable () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 1) {
      VStack {
        Text("Frames").foregroundStyle(.muted)
        navigationCluster
      }
      ScrollView(.horizontal) {
        HStack {
          ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
            thumbnail(frame: frame, index: index)
          }
        }
      }
      .focusable(false)
      VStack {
        frameOperations
        delayCluster
      }
    }
    .padding(.horizontal, 1)
    .border(.separator, set: .single)
  }

  // MARK: - Navigation cluster (◀◀ ◀ ▶ ▶▶)

  private var navigationCluster: some View {
    HStack(spacing: 1) {
      navButton("◀◀", action: model.goToFirstFrame)
      navButton("◀", action: model.previousFrame)
      navButton("▶", action: model.nextFrame)
      navButton("▶▶", action: model.goToLastFrame)
    }
  }

  private func navButton(
    _ glyph: String,
    action: @escaping @MainActor () -> Void
  ) -> some View {
    Button {
      action()
      refresh()
    } label: {
      Text(glyph).foregroundStyle(.muted)
    }
    .buttonStyle(.plain)
  }

  // MARK: - Frame operations (＋ ⎘ ✕)

  private var frameOperations: some View {
    HStack(spacing: 1) {
      navButton("＋", action: model.insertBlankFrameAfterCurrent)
      navButton("⎘", action: model.duplicateCurrentFrame)
      navButton("✕", action: model.deleteCurrentFrame)
    }
  }

  // MARK: - Delay cluster (delay XXcs ⊖ ⊕ =all)

  private var delayCluster: some View {
    HStack(spacing: 1) {
      Text("delay").foregroundStyle(.muted)
      Text("\(currentDelay) cs").foregroundStyle(.foreground)
      navButton("-") { model.adjustCurrentFrameDelay(by: -10) }
      navButton("+") { model.adjustCurrentFrameDelay(by: 10) }
      Button {
        model.setAllFrameDelaysToCurrent()
        refresh()
      } label: {
        Text("=all").foregroundStyle(.muted)
      }
      .buttonStyle(.plain)
    }
  }

  private var currentDelay: Int {
    guard frames.indices.contains(currentFrameIndex) else { return 0 }
    return frames[currentFrameIndex].delayCentiseconds
  }

  // MARK: - Thumbnails

  private func thumbnail(frame: TimelineFrame, index: Int) -> some View {
    let active = index == currentFrameIndex
    let pixels = frame.thumbnail.pixels.map { $0?.toTerminalColor() }
    return Button {
      model.selectFrame(at: index)
      refresh()
    } label: {
      Canvas(
        pixelGridWidth: frame.thumbnail.width,
        height: frame.thumbnail.height,
        pixels: pixels,
        mode: .verticalHalfBlock
      )
      .frame(width: frame.thumbnail.width, height: frame.thumbnail.height)
      .border(active ? .tint : .separator, set: .rounded)
      .overlay(alignment: .bottomTrailing) {
        Text(active ? "[\(index + 1)]" : "\(index + 1)")
          .foregroundStyle(active ? .tint : .muted)
          .background(.clear)
      }
    }
    .buttonStyle(.plain)
  }
}

/// Pre-flattened thumbnail data passed in from the parent so this view
/// doesn't need to depend on the document/view-model directly.
public struct TimelineFrame: Equatable {
  public let thumbnail: Thumbnail
  public let delayCentiseconds: Int

  public init(thumbnail: Thumbnail, delayCentiseconds: Int) {
    self.thumbnail = thumbnail
    self.delayCentiseconds = delayCentiseconds
  }

  public struct Thumbnail: Equatable {
    public let width: Int
    public let height: Int
    public let pixels: [EditorColor?]

    public init(width: Int, height: Int, pixels: [EditorColor?]) {
      precondition(pixels.count == width * height)
      self.width = width
      self.height = height
      self.pixels = pixels
    }
  }
}
