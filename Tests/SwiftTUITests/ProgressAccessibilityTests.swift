import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct ProgressAccessibilityTests {
  @Test("every progress style owns one named range without actions or a focus stop")
  func progressStyles() throws {
    for style in [
      AnyProgressViewStyle.automatic, .linear, .circular, .init(DecoratedProgressStyle()),
      .init(OmittedProgressStyle()),
    ] {
      for reduceMotion in [false, true] {
        let snapshot = render(
          ProgressView("Download", value: 3, total: 4)
            .progressViewStyle(style).environment(\.accessibilityReduceMotion, reduceMotion))
        let node = try #require(snapshot.accessibilityNodes.first { $0.role == .progressBar })
        #expect(node.label == "Download")
        #expect(node.control?.value == .number(0.75))
        #expect(node.control?.minimum == 0)
        #expect(node.control?.maximum == 1)
        #expect(node.control?.actions == [])
        #expect(node.properties?.valueDescription == "3/4")
        #expect(node.liveRegion == nil)
        #expect(snapshot.focusRegions.isEmpty)
        #expect(snapshot.accessibilityNodes.compactMap(\.label) == ["Download"])
      }
    }
  }

  @Test("indeterminate progress and nested style spinners expose one stable unnamed-range item")
  func indeterminate() throws {
    for style in [
      AnyProgressViewStyle.automatic, .linear, .circular, .init(DecoratedProgressStyle()),
    ] {
      for reduceMotion in [false, true] {
        let snapshot = render(
          ProgressView().progressViewStyle(style)
            .environment(\.accessibilityReduceMotion, reduceMotion))
        let nodes = snapshot.accessibilityNodes.filter { $0.role == .progressBar }
        #expect(nodes.count == 1)
        let node = try #require(nodes.first)
        #expect(node.label == "Progress")
        #expect(node.control?.value == nil)
        #expect(node.properties?.valueDescription == nil)
        #expect(node.liveRegion == nil)
        #expect(snapshot.accessibilityNodes.compactMap(\.label) == ["Progress"])
      }
    }
  }

  @Test("generic name and value slots stay separate and deduplicate repeated style placement")
  func authoredValue() throws {
    let snapshot = render(
      ProgressView(value: 2, total: 4) {
        Text("Download")
        Text("documents")
      } currentValueLabel: {
        Text("Two")
        Text("visual").accessibilityLabel("files received")
        Text("decoration").accessibilityHidden()
      }.progressViewStyle(DecoratedProgressStyle()))
    let node = try #require(snapshot.accessibilityNodes.first { $0.role == .progressBar })
    #expect(node.label == "Download documents")
    #expect(node.properties?.valueDescription == "Two files received")
    #expect(snapshot.accessibilityNodes.compactMap(\.label) == ["Download documents"])

    let overrides = render(
      VStack {
        ProgressView("Download", value: 0.5).accessibilityLabel("Transfer")
          .accessibilityProperties(.init(valueDescription: "Half received"))
        ProgressView("Silent", value: 0.5).accessibilityLabel("")
          .accessibilityProperties(.init(valueDescription: ""))
        ProgressView("Hidden", value: 0.5).accessibilityHidden()
      })
    let nodes = overrides.accessibilityNodes.filter { $0.role == .progressBar }
    #expect(nodes.map(\.label) == ["Transfer", ""])
    #expect(nodes.map { $0.properties?.valueDescription } == ["Half received", ""])
  }

  @Test("numeric progress follows visual clamping and never exports nonfinite numbers")
  func numericEdges() throws {
    for (value, total, expected) in [
      (-2.0, 4.0, 0.0), (8, 4, 1), (1, 0, 1), (0, 0, 0), (.nan, 4, 0), (.infinity, 4, 1),
      (1, .infinity, 0),
    ] {
      let snapshot = render(ProgressView(value: value, total: total))
      let node = try #require(snapshot.accessibilityNodes.first { $0.role == .progressBar })
      #expect(node.control?.value == .number(expected))
      #expect(node.label == "Progress")
    }
  }

  @Test("every spinner preset exposes stage meaning independent of its glyph or motion policy")
  func spinnerStyles() throws {
    let styles: [GlyphSpinnerStyle] = [
      .arcOrbit, .arrowCompass, .asteriskCycle, .automatic, .barRise, .blockCorners,
      .boxCornerOrbit, .brailleBlockFill, .brailleDotFade, .brailleDotOrbit, .brailleLinePulse,
      .brailleLineSweep, .brailleLoop, .brailleLoopFilled, .brailleRamp, .brailleRing,
      .brailleRingFilled, .brailleSweep, .circleFill, .circleOrbit, .clockFace, .diamondPulse,
      .diceRoll, .dotChase, .globe, .glyphPulse, .halfCircle, .heavyArrowCompass,
      .horizontalBarFill, .lineCompass, .moonPhase, .oghamPulse, .quadrantCorners, .quadrantOrbit,
      .segmentedBar, .shadeFade, .triangleCompass, .verticalBarFill,
      .init(activeFrames: ["x", "y"], inactiveFrame: "-", finishedFrame: "+"),
    ]
    for style in styles {
      for reduceMotion in [false, true] {
        for (stage, value, description) in [
          (Spinner.Stage.inactive, AccessibilityValue.number(0), "Inactive"),
          (.active, nil, "In progress"), (.finished, .number(1), "Completed"),
        ] {
          let snapshot = render(
            Spinner(stage: stage).spinnerStyle(style)
              .environment(\.accessibilityReduceMotion, reduceMotion).accessibilityLabel("Sync"))
          let node = try #require(snapshot.accessibilityNodes.first { $0.role == .progressBar })
          #expect(node.label == "Sync")
          #expect(node.control?.value == value)
          #expect(node.control?.actions == [])
          #expect(node.properties?.valueDescription == description)
          #expect(node.liveRegion == nil)
          #expect(snapshot.focusRegions.isEmpty)
          #expect(snapshot.accessibilityNodes.compactMap(\.label) == ["Sync"])
        }
      }
    }
  }

  @Test("retained updates refresh progress, generic value content and spinner stage together")
  func retainedUpdates() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ProgressUpdates"), size: .init(width: 80, height: 20)
    ) {
      ProgressUpdateFixture()
    }
    defer { harness.shutdown() }
    for count in 1...3 {
      _ = try harness.clickText("Advance")
      let nodes = harness.runLoop.latestSemanticSnapshot.accessibilityNodes
      let progress = try #require(
        nodes.first { $0.role == .progressBar && $0.label == "Download files" })
      #expect(progress.control?.value == .number(Double(count) / 3))
      #expect(progress.properties?.valueDescription == "Received \(count)")
      let spinner = try #require(nodes.first { $0.role == .progressBar && $0.label == "Activity" })
      #expect(spinner.properties?.valueDescription == (count == 3 ? "Completed" : "In progress"))
      #expect(nodes.filter { $0.role == .progressBar }.count == 2)
      #expect(harness.runLoop.latestSemanticSnapshot.accessibilityAnnouncements.isEmpty)
    }
  }

  private func render<V: View>(_ view: V) -> SemanticSnapshot {
    DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("ProgressAccessibility"), applyEnvironmentValues: true),
      proposal: .init(width: 80, height: 30)
    ).semanticSnapshot
  }
}

private struct DecoratedProgressStyle: ProgressViewStyle {
  func makeBody(configuration: ProgressViewStyleConfiguration) -> some View {
    VStack {
      Text("style chrome")
      if let label = configuration.label { label }
      if let value = configuration.currentValueLabel { value }
      if let label = configuration.label { label }
      if let value = configuration.currentValueLabel { value }
      Spinner()
    }
  }
}

private struct OmittedProgressStyle: ProgressViewStyle {
  func makeBody(configuration: ProgressViewStyleConfiguration) -> some View { Text("chrome only") }
}

private struct ProgressUpdateFixture: View {
  @State private var received = 0
  var body: some View {
    VStack {
      Button("Advance") { received += 1 }
      ProgressView(value: Double(received), total: 3) {
        HStack {
          Text("Download")
          Text("files")
        }
      } currentValueLabel: {
        HStack {
          Text("Received")
          Text("\(received)")
        }
      }.progressViewStyle(DecoratedProgressStyle())
      Spinner(stage: received == 3 ? .finished : .active).accessibilityLabel("Activity")
    }.environment(\.accessibilityReduceMotion, true)
  }
}
