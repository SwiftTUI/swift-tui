// SwiftTUIViews is the package's public authoring product. Its API names
// value vocabulary defined in the layers below (`Color`, `AnyShapeStyle`,
// `SemanticMetadata`, geometry types), so consumers of this product must be
// able to see those declarations without importing non-product targets.
// Re-export the render layer the same way `SwiftTUIRuntime` does;
// `SwiftTUICore` in turn re-exports `SwiftTUIGraph` and `SwiftTUIPrimitives`.
@_exported import SwiftTUICore
