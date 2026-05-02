import SwiftUI

/// A `Canvas` whose drawing intentionally paints far past the canvas
/// frame, with `.clipped()` ensuring only cells inside the frame
/// reach the raster.
///
/// SwiftUI port: the original used SwiftTUI's `CanvasDrawing` /
/// `CanvasContext` types. SwiftUI's `Canvas` uses
/// `(GraphicsContext, CGSize) -> Void` and `Path` directly. The
/// drawing intent is preserved — paint a horizontal line that
/// extends well past the frame — so `.clipped()` has work to do.
public struct CanvasHonorsClipped: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Canvas honors clipped").foregroundStyle(.secondary)
      Canvas { context, size in
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height / 2))
        path.addLine(to: CGPoint(x: size.width * 3, y: size.height / 2))
        context.stroke(path, with: .color(.cyan))
      }
      .frame(width: 10, height: 4)
      .clipped()
      .border(Color.gray)
    }
    .padding(1)
  }
}
