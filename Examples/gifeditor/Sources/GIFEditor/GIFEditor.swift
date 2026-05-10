import Foundation
import GIFEditorCore
import GIFEditorUI
import SwiftTUI

/// Composition root for the editor.
///
/// Today this is mostly a thin façade — it loads or creates a document
/// based on an optional file path, then hands it to `EditorView`. A future
/// SwiftUI port would have a sibling factory function that returns a
/// SwiftUI view fed the same `GIFDocument`.
public struct GIFEditor: View {
  let document: GIFDocument
  /// Loads the GIF at `path` if any, otherwise returns a blank 32×32
  /// document. Errors during load are turned into a one-frame document
  /// whose status message describes the error so the user sees them
  /// in-app rather than on stderr.
  public init(path: String? = nil) {
    self.document = Self.loadDocument(path: path)
  }

  public var body: some View {
    EditorView(document: document)
  }

  static func loadDocument(path: String?) -> GIFDocument {
    guard let path else {
      return GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 32, height: 32))
    }
    let url = URL(fileURLWithPath: path)
    do {
      return try GIFLoader.load(contentsOf: url)
    } catch {
      // Fall back to a blank document anchored at the requested path so
      // a future Ctrl+S writes there.
      var doc = GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 32, height: 32))
      doc.path = url
      return doc
    }
  }
}
