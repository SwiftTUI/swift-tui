import Foundation
import GIF

public enum GIFLoaderError: Error, Equatable {
  case unreadable(URL)
  case decode(String)
  case empty
}

/// Reads GIF bytes off disk and adapts the vendored `swift-gif` decoder
/// into a `GIFDocument` the editor can edit.
///
/// The loader's job is to flatten the decoder's compositing semantics
/// (per-frame palettes, transparency, KEEP/BACKGROUND/PREVIOUS disposal)
/// into the editor's flatter "shared global palette + one editable
/// layer per imported frame" model. The original frames stay
/// pixel-faithful when the GIF uses ≤256 distinct colors total; beyond
/// that we nearest-color quantize.
public enum GIFLoader {

  public static func load(contentsOf url: URL) throws -> GIFDocument {
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      throw GIFLoaderError.unreadable(url)
    }
    return try load(data: data, sourcePath: url)
  }

  public static func load(data: Data, sourcePath: URL? = nil) throws -> GIFDocument {
    var source = ByteSource(data: data)
    let image: GIF.Image
    do {
      image = try GIF.Image.decompress(stream: &source)
    } catch {
      throw GIFLoaderError.decode(String(describing: error))
    }
    if image.frames.isEmpty {
      throw GIFLoaderError.empty
    }

    let size = PixelSize(width: image.size.x, height: image.size.y)

    // Pull every distinct opaque color out of every frame so we can
    // build a single shared palette. We add transparent in slot 0 and
    // append the rest in stable order.
    var seen: [EditorColor: PaletteIndex] = [:]
    var entries: [EditorColor] = [.transparent]
    seen[.transparent] = 0

    func intern(_ color: EditorColor) -> PaletteIndex {
      if let idx = seen[color] { return idx }
      let idx = PaletteIndex(min(255, entries.count))
      seen[color] = idx
      if entries.count < 256 {
        entries.append(color)
      }
      return idx
    }

    // First pass: collect colors via the composited frames so we honor
    // disposal modes — each frame as the user "sees" it during playback
    // becomes one editable frame. This loses the original disposal
    // metadata (which is fine — we re-export with `.background`).
    var compositedFrames: [[GIF.RGBA<UInt8>]] = []
    for frameIndex in 0..<image.frames.count {
      let pixels = image.composited(frameIndex: frameIndex, as: GIF.RGBA<UInt8>.self)
      compositedFrames.append(pixels)
      for px in pixels where px.a > 0 {
        _ = intern(EditorColor(red: px.r, green: px.g, blue: px.b, alpha: 255))
        if entries.count >= 256 { break }
      }
      if entries.count >= 256 { break }
    }

    // Pad to 256 so ColorPalette stays well-formed.
    let palette = ColorPalette(colors: entries)

    let editorFrames: [EditorFrame] = compositedFrames.enumerated().map { index, pixels in
      var buffer = PixelBuffer(size: size)
      for (i, px) in pixels.enumerated() {
        if px.a == 0 {
          buffer.pixels[i] = nil
        } else {
          let color = EditorColor(red: px.r, green: px.g, blue: px.b)
          let idx = seen[color] ?? palette.nearestIndex(to: color)
          buffer.pixels[i] = idx
        }
      }
      let layer = EditorLayer(name: "Imported", pixels: buffer)
      let delay = max(1, image.frames[index].delayCentiseconds)
      return EditorFrame(layers: [layer], delayCentiseconds: delay)
    }

    return GIFDocument(
      size: size,
      palette: palette,
      frames: editorFrames,
      path: sourcePath
    )
  }

  /// Adapter that drains a `Data` blob into the `GIF.BytestreamSource`
  /// the decoder expects. The decoder reads in 4 KiB chunks, so we just
  /// hand each call a bounded slice.
  private struct ByteSource: GIF.BytestreamSource {
    var bytes: [UInt8]
    var offset: Int

    init(data: Data) {
      self.bytes = Array(data)
      self.offset = 0
    }

    mutating func read(count: Int) -> [UInt8]? {
      guard offset < bytes.count else { return nil }
      let end = min(offset + count, bytes.count)
      let chunk = Array(bytes[offset..<end])
      offset = end
      return chunk
    }
  }
}
