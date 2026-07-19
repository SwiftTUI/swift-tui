import Observation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

private enum TestKey: EnvironmentKey {
  static let defaultValue: Int = 42
}

/// The authoring shape the type-keyed object environment requires (F157):
/// `@MainActor @Observable` classes are implicitly `Sendable`, satisfying
/// the environment storage's `Sendable` constraint.
@MainActor
@Observable
private final class ObjectEnvironmentModel {
  var count = 0
}

@MainActor
private final class ObjectEnvironmentCapture {
  var seen: ObjectEnvironmentModel?
}

@MainActor
private struct ObjectEnvironmentProbe: View {
  @Environment(ObjectEnvironmentModel.self) var model: ObjectEnvironmentModel?
  let capture: ObjectEnvironmentCapture

  var body: some View {
    capture.seen = model
    return Text("probe")
  }
}

@MainActor
@Suite
struct EnvironmentTests {
  @Test("environment key returns default value when not set")
  func defaultEnvironmentValue() {
    let values = EnvironmentValues()
    #expect(values[TestKey.self] == 42)
  }

  @Test("environment key returns custom value when set")
  func customEnvironmentValue() {
    var values = EnvironmentValues()
    values[TestKey.self] = 99
    #expect(values[TestKey.self] == 99)
  }

  @Test("environment values are equatable")
  func environmentValuesEquatable() {
    let a = EnvironmentValues()
    let b = EnvironmentValues()
    #expect(a == b)
  }

  @Test("type-keyed observable object round-trips through EnvironmentValues (F157)")
  func observableObjectEnvironmentRoundTrips() {
    let model = ObjectEnvironmentModel()
    var values = EnvironmentValues()
    #expect(values[ObjectEnvironmentModel.self] == nil)
    values[ObjectEnvironmentModel.self] = model
    #expect(values[ObjectEnvironmentModel.self] === model)
  }

  @Test("object environment entries compare by identity, not contents")
  func observableObjectEnvironmentComparesByIdentity() {
    let model = ObjectEnvironmentModel()
    var a = EnvironmentValues()
    a[ObjectEnvironmentModel.self] = model
    let sameInstance = a
    var otherInstance = EnvironmentValues()
    otherInstance[ObjectEnvironmentModel.self] = ObjectEnvironmentModel()

    #expect(a == sameInstance)
    #expect(a != otherInstance)

    // Mutating the model's properties must NOT change environment equality:
    // reads are dependency-tracked; the environment entry is the identity.
    model.count += 1
    #expect(a == sameInstance)
  }

  @Test("@Environment(Model.self) reads the type-keyed object")
  func environmentWrapperReadsTypeKeyedObject() {
    let model = ObjectEnvironmentModel()
    var values = EnvironmentValues()
    values[ObjectEnvironmentModel.self] = model

    EnvironmentValuesStorage.binding(values) {
      @Environment(ObjectEnvironmentModel.self) var optional: ObjectEnvironmentModel?
      #expect(optional === model)
      @Environment(ObjectEnvironmentModel.self) var required: ObjectEnvironmentModel
      #expect(required === model)
    }
    EnvironmentValuesStorage.binding(EnvironmentValues()) {
      @Environment(ObjectEnvironmentModel.self) var absent: ObjectEnvironmentModel?
      #expect(absent == nil)
    }
  }

  @Test("View.environment(model) injects the object for descendants")
  func environmentModifierInjectsObject() {
    let model = ObjectEnvironmentModel()
    let capture = ObjectEnvironmentCapture()
    let view = ObjectEnvironmentProbe(capture: capture).environment(model)
    let context = ResolveContext(identity: Identity(components: ["object-env-root"]))
    _ = Resolver().resolve(AnyView(view), in: context)
    #expect(capture.seen === model)
  }

  @Test("accessibilityReduceMotion defaults to false and can be overridden")
  func accessibilityReduceMotion() {
    var values = EnvironmentValues()

    #expect(!values.accessibilityReduceMotion)

    values.accessibilityReduceMotion = true
    #expect(values.accessibilityReduceMotion)
  }
}
