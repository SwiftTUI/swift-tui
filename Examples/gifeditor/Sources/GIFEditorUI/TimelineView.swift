import GIFEditorCore
import TerminalUI

/// Horizontal frame strip with a centered cursor.
///
/// The strip shows a 5×3 thumbnail per frame — enough to convey shape
/// without overwhelming the layout. The current frame is highlighted
/// with a contrasting border.
struct TimelineView: View {
  let frames: [TimelineFrame]
  let currentFrameIndex: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(
        "Timeline — frame \(currentFrameIndex + 1)/\(frames.count) — "
          + "\(frames[currentFrameIndex].delayCentiseconds)cs"
      )
      .foregroundStyle(.muted)
      ScrollView(.horizontal) {
        HStack(spacing: 1) {
          ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
            thumbnail(frame: frame, index: index)
          }
        }
      }
      .focusable(false)
    }
    .padding(.horizontal, 1)
    .border(.separator, set: .single)
  }

  private func thumbnail(frame: TimelineFrame, index: Int) -> some View {
    let active = index == currentFrameIndex
    return VStack(spacing: 0) {
      Text("\(index + 1)")
        .foregroundStyle(active ? .tint : .muted)
      // Tiny preview: 5 rows × thumbWidth. We sample every Nth source
      // pixel for a quick approximation rather than re-flattening here.
      VStack(spacing: 0) {
        ForEach(0..<frame.thumbnail.height, id: \.self) { y in
          HStack(spacing: 0) {
            ForEach(0..<frame.thumbnail.width, id: \.self) { x in
              let color = frame.thumbnail.pixels[y * frame.thumbnail.width + x]
              Rectangle()
                .fill(color?.toTerminalColor() ?? .clear)
                .frame(width: 1, height: 1)
            }
          }
        }
      }
      .border(active ? .tint : .separator)
    }
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
