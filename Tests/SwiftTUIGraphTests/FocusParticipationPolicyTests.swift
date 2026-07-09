import Foundation
import Testing

@testable import SwiftTUIGraph

/// Table-driven focus-participation coverage (F99):
/// `FocusPolicy`/`AutomaticFocusPolicy`/`FocusParticipation` previously had
/// zero direct tests despite hosting the tab-switch/focus-clobber regression
/// family. The manifest below classifies every `AccessibilityRole` case and a
/// source-parsed totality lock fails when a new role is added without a
/// classification — so role growth cannot silently fall out of the focus
/// policy the way a renamed view fell out of the (legacy) name fallback.
@Suite("Focus participation policy")
struct FocusParticipationPolicyTests {
  struct RoleClassification: Sendable {
    let caseName: String
    let role: AccessibilityRole
    let isAutomaticallyFocusable: Bool
  }

  /// Every `AccessibilityRole`, classified against
  /// `AutomaticFocusPolicy.focusableAccessibilityRoles`. This is a
  /// characterization manifest: changing a role's classification here must be
  /// a deliberate focus-policy decision, not a drive-by.
  static let roleManifest: [RoleClassification] = [
    .init(caseName: "alert", role: .alert, isAutomaticallyFocusable: false),
    .init(caseName: "button", role: .button, isAutomaticallyFocusable: true),
    .init(caseName: "cell", role: .cell, isAutomaticallyFocusable: false),
    .init(caseName: "checkbox", role: .checkbox, isAutomaticallyFocusable: false),
    .init(caseName: "columnHeader", role: .columnHeader, isAutomaticallyFocusable: false),
    .init(
      caseName: "confirmationDialog", role: .confirmationDialog, isAutomaticallyFocusable: false
    ),
    .init(caseName: "custom", role: .custom("probe"), isAutomaticallyFocusable: false),
    .init(caseName: "disclosureGroup", role: .disclosureGroup, isAutomaticallyFocusable: true),
    .init(caseName: "group", role: .group, isAutomaticallyFocusable: false),
    .init(caseName: "heading", role: .heading(level: 1), isAutomaticallyFocusable: false),
    .init(caseName: "image", role: .image, isAutomaticallyFocusable: false),
    .init(caseName: "link", role: .link, isAutomaticallyFocusable: true),
    .init(caseName: "list", role: .list, isAutomaticallyFocusable: true),
    .init(caseName: "menu", role: .menu, isAutomaticallyFocusable: true),
    .init(caseName: "menuItem", role: .menuItem, isAutomaticallyFocusable: false),
    .init(caseName: "picker", role: .picker, isAutomaticallyFocusable: true),
    .init(caseName: "popover", role: .popover, isAutomaticallyFocusable: false),
    .init(caseName: "progressBar", role: .progressBar, isAutomaticallyFocusable: false),
    .init(caseName: "region", role: .region, isAutomaticallyFocusable: false),
    .init(caseName: "rowHeader", role: .rowHeader, isAutomaticallyFocusable: false),
    .init(caseName: "scrollView", role: .scrollView, isAutomaticallyFocusable: false),
    .init(
      caseName: "scrollViewWithIndicators", role: .scrollViewWithIndicators,
      isAutomaticallyFocusable: false
    ),
    .init(caseName: "section", role: .section, isAutomaticallyFocusable: false),
    .init(caseName: "secureField", role: .secureField, isAutomaticallyFocusable: true),
    .init(caseName: "separator", role: .separator, isAutomaticallyFocusable: false),
    .init(caseName: "sheet", role: .sheet, isAutomaticallyFocusable: false),
    .init(caseName: "slider", role: .slider, isAutomaticallyFocusable: true),
    .init(caseName: "status", role: .status, isAutomaticallyFocusable: false),
    .init(caseName: "stepper", role: .stepper, isAutomaticallyFocusable: true),
    .init(caseName: "tab", role: .tab, isAutomaticallyFocusable: false),
    .init(caseName: "tabPanel", role: .tabPanel, isAutomaticallyFocusable: false),
    .init(caseName: "table", role: .table, isAutomaticallyFocusable: true),
    .init(caseName: "tableRow", role: .tableRow, isAutomaticallyFocusable: false),
    .init(caseName: "tabView", role: .tabView, isAutomaticallyFocusable: true),
    .init(caseName: "textEditor", role: .textEditor, isAutomaticallyFocusable: true),
    .init(caseName: "textField", role: .textField, isAutomaticallyFocusable: true),
    .init(caseName: "timer", role: .timer, isAutomaticallyFocusable: false),
    .init(caseName: "toggle", role: .toggle, isAutomaticallyFocusable: true),
  ]

  @Test("the role manifest covers every AccessibilityRole case exactly once (totality)")
  func manifestCoversEveryRoleCase() throws {
    let source = try SourceParsingTestSupport.sourceText(
      relativePath: "Sources/SwiftTUIGraph/Semantics/SemanticRoleTypes.swift"
    )
    let body = try SourceParsingTestSupport.typeBody(
      kind: "enum",
      name: "AccessibilityRole",
      in: source
    )
    var parsedCaseNames: Set<String> = []
    for line in body.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix("case ") else { continue }
      let name = trimmed.dropFirst("case ".count)
        .prefix { $0.isLetter || $0.isNumber }
      if !name.isEmpty {
        parsedCaseNames.insert(String(name))
      }
    }
    #expect(!parsedCaseNames.isEmpty, "role-case parse must not be vacuous")

    let manifestNames = Set(Self.roleManifest.map(\.caseName))
    #expect(
      manifestNames == parsedCaseNames,
      """
      role manifest diverged from AccessibilityRole: \
      unclassified=\(parsedCaseNames.subtracting(manifestNames).sorted()) \
      stale=\(manifestNames.subtracting(parsedCaseNames).sorted())
      """
    )
    #expect(Self.roleManifest.count == manifestNames.count, "duplicate manifest entries")
  }

  @Test(
    "automatic participation matches each role's classification",
    arguments: roleManifest
  )
  func automaticParticipationMatchesClassification(_ entry: RoleClassification) {
    let metadata = SemanticMetadata(accessibilityRole: entry.role)
    #expect(
      metadata.participatesInTopLevelFocus(kind: .view("Probe"))
        == entry.isAutomaticallyFocusable,
      "\(entry.caseName): automatic focus classification changed"
    )
  }

  @Test(".included overrides a non-focusable role; .excluded overrides a focusable one")
  func explicitParticipationOverridesRole() {
    var included = SemanticMetadata(accessibilityRole: .image)
    included.isFocusable = true
    #expect(included.participatesInTopLevelFocus(kind: .view("Probe")))

    var excluded = SemanticMetadata(accessibilityRole: .button)
    excluded.isFocusable = false
    #expect(!excluded.participatesInTopLevelFocus(kind: .view("Probe")))
  }

  @Test("a role-less non-control node does not participate automatically")
  func roleLessNonControlDoesNotParticipate() {
    let metadata = SemanticMetadata()
    #expect(!metadata.participatesInTopLevelFocus(kind: .view("Text")))
    #expect(!metadata.participatesInTopLevelFocus(kind: .root))
  }
}
