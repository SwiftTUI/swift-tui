// The value an `Animatable` shape carries beside its geometry.
//
// A fill, a stroke or a clip keeps a shape's geometry and drops the shape. A
// shape that conforms to `Animatable` has to be evaluated again for every
// animation sample, so its modifier also records the shape's data and a way
// back from data to geometry. The animation controller interpolates the data
// and asks for the geometry of each sample.

/// An animated value that takes everything but its data from its destination.
///
/// The controller interpolates `animatableData` and writes it into a copy of
/// one end of the animation. For most values the two ends differ only in
/// their data, so the choice of end does not show. A value that also carries
/// state the data does not cover marks itself with this protocol, and the
/// sample is then a copy of the destination: what cannot interpolate changes
/// when the animation starts, as the rest of a view's value does.
package protocol DestinationStructuredAnimatable {}

/// The data of an `Animatable` shape and the geometry it draws with that data.
package protocol AnimatableShapeValue: Animatable, Equatable, DestinationStructuredAnimatable {
  /// The geometry of the shape with this value's data, in the unit rectangle.
  @MainActor var geometry: ShapeGeometry { get }
}

/// The concrete ``AnimatableShapeValue`` a shape modifier records.
///
/// Two values are equal when they come from the same shape type and hold
/// equal data. The closure does not take part: it is the shape itself, which
/// is not `Equatable`, and a shape whose other fields changed has a different
/// resolved geometry, which the node compares on its own.
package struct AnimatableShapeData<Data: VectorArithmetic>: AnimatableShapeValue {
  package var animatableData: Data
  private let shapeType: ObjectIdentifier
  private let makeGeometry: @MainActor @Sendable (Data) -> ShapeGeometry

  package init(
    data: Data,
    shapeType: ObjectIdentifier,
    geometry: @escaping @MainActor @Sendable (Data) -> ShapeGeometry
  ) {
    animatableData = data
    self.shapeType = shapeType
    makeGeometry = geometry
  }

  @MainActor package var geometry: ShapeGeometry {
    makeGeometry(animatableData)
  }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.shapeType == rhs.shapeType && lhs.animatableData == rhs.animatableData
  }
}

/// A type-erased ``AnimatableShapeValue``, stored beside a shape's geometry in
/// a draw payload or a clip. `nil` there means the shape does not conform to
/// `Animatable`, and its path morphs point by point instead.
///
/// The value sits behind one reference, so a payload that carries no provider
/// grows by a word and an unchanged provider compares by pointer.
package struct AnimatableShapeProvider: Equatable, Sendable {
  private final class Storage: Sendable {
    let value: any AnimatableShapeValue

    init(_ value: any AnimatableShapeValue) {
      self.value = value
    }
  }

  private let storage: Storage

  package init(_ value: any AnimatableShapeValue) {
    storage = Storage(value)
  }

  package var value: any AnimatableShapeValue {
    storage.value
  }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.storage === rhs.storage || isEqual(lhs.value, rhs.value)
  }

  private static func isEqual<Value: AnimatableShapeValue>(
    _ lhs: Value, _ rhs: any AnimatableShapeValue
  ) -> Bool {
    (rhs as? Value) == lhs
  }
}
