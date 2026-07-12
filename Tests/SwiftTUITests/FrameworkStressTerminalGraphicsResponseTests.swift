import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

@Suite(.serialized)
struct FrameworkStressTerminalGraphicsResponseTests {
  @Test("stress terminal graphics response 001 kitty selection uses the exact query id")
  func graphicsResponse001KittySelectionUsesExactQueryID() {
    // Hypothesis: a neighboring Kitty probe response can be attributed to the current query.
    let bytes = Array("\u{001B}_Gi=41;OK\u{001B}\\\u{001B}_Gi=42;OK\u{001B}\\".utf8)

    #expect(parseKittySupportResponse(in: bytes, id: 42) == true)
    #expect(parseKittySupportResponse(in: bytes, id: 43) == nil)
  }

  @Test("stress terminal graphics response 002 incomplete kitty replies remain indeterminate")
  func graphicsResponse002IncompleteKittyRepliesRemainIndeterminate() {
    // Hypothesis: a split read ending immediately after the query prefix is classified unsupported.
    let bytes = Array("\u{001B}_Gi=42;".utf8)

    withKnownIssue("An incomplete Kitty probe reply is classified as unsupported") {
      #expect(parseKittySupportResponse(in: bytes, id: 42) == nil)
    }
  }

  @Test("stress terminal graphics response 003 device attributes skip unrelated CSI traffic")
  func graphicsResponse003DeviceAttributesSkipUnrelatedCSITraffic() {
    // Hypothesis: an earlier non-DA control sequence can capture the DA parser's terminator.
    let bytes = Array("\u{001B}[31mnoise\u{001B}[?62;4;22c".utf8)

    #expect(parsePrimaryDeviceAttributes(from: bytes) == [62, 4, 22])
  }

  @Test("stress terminal graphics response 004 malformed device attributes are rejected atomically")
  func graphicsResponse004MalformedDeviceAttributesAreRejectedAtomically() {
    // Hypothesis: compacting invalid parameters can turn a corrupt DA reply into supported features.
    let bytes = Array("\u{001B}[?62;bogus;4c".utf8)

    withKnownIssue(
      "Device-attributes parsing drops malformed parameters instead of rejecting the reply"
    ) {
      #expect(parsePrimaryDeviceAttributes(from: bytes) == nil)
    }
  }

  @Test("stress terminal graphics response 005 XTSM selection uses the requested item")
  func graphicsResponse005XTSMSelectionUsesRequestedItem() {
    // Hypothesis: the first graphics response in a combined buffer can win for every query item.
    let bytes = Array("\u{001B}[?1;0;256S\u{001B}[?2;0;800;600S".utf8)
    let response = parseXTSMGraphicsResponse(from: bytes, item: 2)

    #expect(response?.status == 0)
    #expect(response?.values == [800, 600])
  }

  @Test("stress terminal graphics response 006 malformed XTSM values are rejected atomically")
  func graphicsResponse006MalformedXTSMValuesAreRejectedAtomically() {
    // Hypothesis: dropping one invalid dimension can shift the surviving XTSM value positions.
    let bytes = Array("\u{001B}[?2;0;800;bogus;600S".utf8)

    withKnownIssue("XTSM graphics parsing drops malformed values instead of rejecting the reply") {
      #expect(parseXTSMGraphicsResponse(from: bytes, item: 2) == nil)
    }
  }

  @Test("stress terminal graphics response 007 window pixels preserve height width ordering")
  func graphicsResponse007WindowPixelsPreserveHeightWidthOrdering() {
    // Hypothesis: repeated width/height extraction can transpose the terminal's row-first report.
    let bytes = Array("prefix\u{001B}[4;720;1280tsuffix".utf8)

    #expect(
      parseWindowSizeResponse(from: bytes, expectedCode: 4) == PixelSize(width: 1280, height: 720))
  }

  @Test("stress terminal graphics response 008 negative window dimensions are rejected")
  func graphicsResponse008NegativeWindowDimensionsAreRejected() {
    // Hypothesis: signed integers from a corrupt reply can become a trusted pixel geometry.
    let bytes = Array("\u{001B}[4;-720;1280t".utf8)

    withKnownIssue("Window-size parsing accepts negative terminal pixel dimensions") {
      #expect(parseWindowSizeResponse(from: bytes, expectedCode: 4) == nil)
    }
  }
}
