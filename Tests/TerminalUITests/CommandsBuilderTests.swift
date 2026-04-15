import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct CommandsBuilderTests {
  @Test("empty buildBlock produces an empty array")
  func emptyBuildBlockProducesEmptyArray() {
    let items = CommandsBuilder.buildBlock()
    #expect(items.isEmpty)
  }

  @Test("variadic buildBlock preserves declaration order")
  func variadicBuildBlockPreservesDeclarationOrder() {
    let a = CommandItem(id: "a", title: "A") {}
    let b = CommandItem(id: "b", title: "B") {}
    let c = CommandItem(id: "c", title: "C") {}

    let items = CommandsBuilder.buildBlock(a, b, c)

    #expect(items.map(\.id) == ["a", "b", "c"])
  }

  @Test("array-form buildBlock flattens nested arrays in order")
  func arrayFormBuildBlockFlattensInOrder() {
    let first: [CommandItem] = [
      CommandItem(id: "a", title: "A") {}
    ]
    let second: [CommandItem] = [
      CommandItem(id: "b", title: "B") {},
      CommandItem(id: "c", title: "C") {},
    ]

    let items = CommandsBuilder.buildBlock(first, second)

    #expect(items.map(\.id) == ["a", "b", "c"])
  }

  @Test("buildOptional maps nil to empty and some to wrapped value")
  func buildOptionalMapsNilToEmpty() {
    let some: [CommandItem] = [
      CommandItem(id: "a", title: "A") {}
    ]
    let nilResult = CommandsBuilder.buildOptional(nil)
    let someResult = CommandsBuilder.buildOptional(some)

    #expect(nilResult.isEmpty)
    #expect(someResult.map(\.id) == ["a"])
  }

  @Test("buildEither routes first and second branches correctly")
  func buildEitherRoutesBranches() {
    let lhs = CommandsBuilder.buildEither(first: [
      CommandItem(id: "left", title: "Left") {}
    ])
    let rhs = CommandsBuilder.buildEither(second: [
      CommandItem(id: "right", title: "Right") {}
    ])

    #expect(lhs.map(\.id) == ["left"])
    #expect(rhs.map(\.id) == ["right"])
  }

  @Test("buildArray flattens for-loop blocks in order")
  func buildArrayFlattensForLoopBlocksInOrder() {
    let rows: [[CommandItem]] = [
      [CommandItem(id: "row-0", title: "Row 0") {}],
      [CommandItem(id: "row-1", title: "Row 1") {}],
      [CommandItem(id: "row-2", title: "Row 2") {}],
    ]

    let items = CommandsBuilder.buildArray(rows)

    #expect(items.map(\.id) == ["row-0", "row-1", "row-2"])
  }

  @Test("buildExpression accepts single items and array expressions")
  func buildExpressionAcceptsBothShapes() {
    let single = CommandsBuilder.buildExpression(
      CommandItem(id: "single", title: "Single") {}
    )
    let array = CommandsBuilder.buildExpression([
      CommandItem(id: "group-a", title: "Group A") {},
      CommandItem(id: "group-b", title: "Group B") {},
    ])

    #expect(single.map(\.id) == ["single"])
    #expect(array.map(\.id) == ["group-a", "group-b"])
  }

  @Test("builder end-to-end: composes single items, if-else, and for-loops")
  func builderEndToEndComposesAllFeatureCombinations() {
    // Exercise the full DSL via the `@CommandsBuilder` attribute so we
    // know the macro-generated lowering produces the same order we
    // assert on the hand-composed calls above.
    let enabled = true

    @CommandsBuilder
    func build() -> [CommandItem] {
      CommandItem(id: "quit", title: "Quit") {}
      CommandItem(id: "palette", title: "Palette") {}
      if enabled {
        CommandItem(id: "sync", title: "Sync") {}
      }
      if !enabled {
        CommandItem(id: "unreachable", title: "Unreachable") {}
      }
      for index in 0..<2 {
        CommandItem(id: "iter-\(index)", title: "Iter \(index)") {}
      }
    }

    let items = build()
    #expect(items.map(\.id) == ["quit", "palette", "sync", "iter-0", "iter-1"])
  }

  @Test("builder preserves conditional branch selection with if/else")
  func builderPreservesConditionalBranchSelection() {
    let showAdvanced = false

    @CommandsBuilder
    func build() -> [CommandItem] {
      if showAdvanced {
        CommandItem(id: "advanced", title: "Advanced") {}
      } else {
        CommandItem(id: "basic", title: "Basic") {}
      }
    }

    let items = build()
    #expect(items.map(\.id) == ["basic"])
  }
}
