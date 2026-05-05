package import SwiftTUICore

package struct ErasedViewTypeID: Hashable, Sendable, CustomStringConvertible {
  package let identityComponent: IdentityComponent
  package let typeDiscriminator: ObjectIdentifier
  package let displayName: String

  package init<V: View>(_ type: V.Type) {
    self.init(erasing: type)
  }

  package init(erasing type: Any.Type) {
    let reflectedName = String(reflecting: type)
    displayName = reflectedName
    typeDiscriminator = ObjectIdentifier(type)
    identityComponent = .init(rawValue: "AnyViewPayload<\(reflectedName)>")
  }

  package var description: String {
    displayName
  }
}
