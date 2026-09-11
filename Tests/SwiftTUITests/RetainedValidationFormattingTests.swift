import SwiftTUICore
import Testing

@testable import SwiftTUIRuntime

struct RetainedValidationFormattingTests {
  @Test("TSV distinguishes disabled collection from recorded zero and preserves every counter")
  func formatsValidationCounters() {
    var record = FrameDiagnosticRecord(frameNumber: 1, causeSummary: "test")
    let header = FrameDiagnosticsTSVFormatting.headerFields
    let indices = header.indices.filter { header[$0].hasPrefix("validation_") }
    #expect(indices.count == 11)
    let disabled = FrameDiagnosticsTSVFormatting.fields(for: record)
    #expect(disabled.count == header.count)
    #expect(indices.allSatisfy { disabled[$0] == "-" })
    record.retainedValidation = .init()
    let zero = FrameDiagnosticsTSVFormatting.fields(for: record)
    #expect(indices.allSatisfy { zero[$0] == "0" })
    record.retainedValidation?.comparison.measurementNodes = 1
    record.retainedValidation?.comparison.placementNodes = 2
    record.retainedValidation?.comparison.environmentSnapshots = 3
    record.retainedValidation?.comparison.environmentSharedStorage = 4
    record.retainedValidation?.comparison.environmentValues = 5
    record.retainedValidation?.identityNodesChecked = 6
    record.retainedValidation?.measuredNodesRestamped = 7
    record.retainedValidation?.allocationIdentitiesRestamped = 8
    record.retainedValidation?.placedNodesRestamped = 9
    record.retainedValidation?.measuredEqualityNodes = 10
    record.retainedValidation?.viewportComparisonNodes = 11
    let counted = FrameDiagnosticsTSVFormatting.fields(for: record)
    #expect(indices.map { counted[$0] } == (1...11).map(String.init))
  }
}
