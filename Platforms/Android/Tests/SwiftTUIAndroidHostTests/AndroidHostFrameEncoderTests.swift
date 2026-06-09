import Foundation
import SwiftTUIAndroidHost
import SwiftTUIRuntime
import Testing

@Test
func android_host_frame_encoder_writes_versioned_minimal_snapshot() throws {
  let frame = SemanticHostFrame(
    sequence: 42,
    raster: RasterSurface(
      size: CellSize(width: 4, height: 2),
      lines: [
        "Hi",
        "TUI",
      ]
    ),
    semantics: SemanticSnapshot(),
    focusedIdentity: Identity(components: ["root", "field"]),
    rasterDamage: PresentationDamage(dirtyRows: [1]),
    preferredLayoutSize: CellSize(width: 3, height: 2)
  )

  let bytes = try AndroidHostFrameEncoder.encode(frame)
  let snapshot = try JSONDecoder().decode(AndroidHostFrameSnapshot.self, from: Data(bytes))

  #expect(snapshot.schemaVersion == 1)
  #expect(snapshot.sequence == 42)
  #expect(snapshot.gridWidth == 4)
  #expect(snapshot.gridHeight == 2)
  #expect(snapshot.preferredGridWidth == 3)
  #expect(snapshot.preferredGridHeight == 2)
  #expect(snapshot.rows == ["Hi  ", "TUI "])
  #expect(snapshot.focusedIdentity == "root/field")
  #expect(snapshot.dirtyRows == [1])
  #expect(snapshot.requiresFullTextRepaint == false)
}
