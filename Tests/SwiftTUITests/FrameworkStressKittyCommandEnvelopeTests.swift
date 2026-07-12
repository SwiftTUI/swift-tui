import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

@Suite(.serialized)
struct FrameworkStressKittyCommandEnvelopeTests {
  @Test("stress kitty command envelope 001 single PNG chunk carries complete control data")
  func kittyCommand001SinglePNGChunkCarriesCompleteControlData() throws {
    // Hypothesis: a one-chunk transmit can be left marked as awaiting continuation.
    let command = try #require(
      kittyTransmitAndPlaceCommands(
        payload: KittyPayload(encodedChunks: ["QUJD"], format: .png),
        imageID: 17,
        cellColumns: 3,
        cellRows: 2,
        sourceRect: nil
      ).first
    )

    #expect(command.contains("_Ga=T,q=2,t=d,f=100,C=1,c=3,r=2,i=17,m=0;QUJD"))
  }

  @Test("stress kitty command envelope 002 continuation chunks carry only continuation state")
  func kittyCommand002ContinuationChunksCarryOnlyContinuationState() {
    // Hypothesis: full placement keys can leak into continuation chunks and reset the transfer.
    let commands = kittyTransmitAndPlaceCommands(
      payload: KittyPayload(encodedChunks: ["AAAA", "BBBB", "CCCC"], format: .png),
      imageID: 19,
      cellColumns: 4,
      cellRows: 5,
      sourceRect: nil
    )

    #expect(commands.count == 3)
    #expect(commands[0].contains(",m=1;AAAA"))
    #expect(commands[1] == "\u{001B}_Gm=1;BBBB\u{001B}\\")
    #expect(commands[2] == "\u{001B}_Gm=0;CCCC\u{001B}\\")
  }

  @Test("stress kitty command envelope 003 RGBA payload declares both pixel axes")
  func kittyCommand003RGBAPayloadDeclaresBothPixelAxes() throws {
    // Hypothesis: one raw-pixel dimension can be omitted after payload-format replacement.
    let command = try #require(
      kittyTransmitAndPlaceCommands(
        payload: KittyPayload(
          encodedChunks: ["AAAA"],
          format: .rgba(pixelSize: .init(width: 320, height: 180))
        ),
        imageID: 23,
        cellColumns: 8,
        cellRows: 4,
        sourceRect: nil
      ).first
    )

    #expect(command.contains("f=32"))
    #expect(command.contains("s=320,v=180"))
  }

  @Test("stress kitty command envelope 004 crop fields agree across transmit and replace")
  func kittyCommand004CropFieldsAgreeAcrossTransmitAndReplace() throws {
    // Hypothesis: re-placement can lose one crop field and display a different source region.
    let crop = KittySourceRect(x: 7, y: 11, width: 13, height: 17)
    let transmit = try #require(
      kittyTransmitAndPlaceCommands(
        payload: KittyPayload(encodedChunks: ["AAAA"], format: .png),
        imageID: 29,
        cellColumns: 2,
        cellRows: 3,
        sourceRect: crop
      ).first
    )
    let replace = kittyPlacementCommand(
      imageID: 29,
      cellColumns: 2,
      cellRows: 3,
      sourceRect: crop
    )

    #expect(transmit.contains("x=7,y=11,w=13,h=17"))
    #expect(replace.contains("x=7,y=11,w=13,h=17"))
  }

  @Test("stress kitty command envelope 005 zero columns emit no transmission")
  func kittyCommand005ZeroColumnsEmitNoTransmission() {
    // Hypothesis: invalid zero-width placements are serialized into terminal protocol state.
    let commands = kittyTransmitAndPlaceCommands(
      payload: KittyPayload(encodedChunks: ["AAAA"], format: .png),
      imageID: 31,
      cellColumns: 0,
      cellRows: 2,
      sourceRect: nil
    )

    withKnownIssue("Kitty serialization emits a transmit command with zero columns") {
      #expect(commands.isEmpty)
    }
  }

  @Test("stress kitty command envelope 006 zero rows emit no transmission")
  func kittyCommand006ZeroRowsEmitNoTransmission() {
    // Hypothesis: invalid zero-height placements are serialized into terminal protocol state.
    let commands = kittyTransmitAndPlaceCommands(
      payload: KittyPayload(encodedChunks: ["AAAA"], format: .png),
      imageID: 37,
      cellColumns: 2,
      cellRows: 0,
      sourceRect: nil
    )

    withKnownIssue("Kitty serialization emits a transmit command with zero rows") {
      #expect(commands.isEmpty)
    }
  }

  @Test("stress kitty command envelope 007 empty encoded chunks emit no transmission")
  func kittyCommand007EmptyEncodedChunksEmitNoTransmission() {
    // Hypothesis: a nonempty chunk array containing no payload can create an empty stored image.
    let commands = kittyTransmitAndPlaceCommands(
      payload: KittyPayload(encodedChunks: [""], format: .png),
      imageID: 41,
      cellColumns: 2,
      cellRows: 2,
      sourceRect: nil
    )

    withKnownIssue("Kitty serialization emits a transmit command for an empty encoded chunk") {
      #expect(commands.isEmpty)
    }
  }

  @Test("stress kitty command envelope 008 source namespaces produce distinct image ids")
  func kittyCommand008SourceNamespacesProduceDistinctImageIDs() {
    // Hypothesis: equal raw text across source families can alias one resident Kitty image.
    let named = kittyImageID(reference: .namedResource("asset"))
    let file = kittyImageID(reference: .filePath("asset"))
    let embedded = kittyImageID(reference: .embeddedImage(Array("asset".utf8)))

    #expect(named != file)
    #expect(file != embedded)
    #expect(named != embedded)
    #expect(named != 0 && file != 0 && embedded != 0)
  }
}
