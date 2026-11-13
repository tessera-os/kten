/// A named member in an object schema.
public struct KtenField: Sendable, Equatable {
  /// The member's stable name.
  public var name: String

  /// The member's value schema.
  public var schema: KtenSchema

  /// Whether the member must be present in an encoded object.
  public var isRequired: Bool

  /// Creates one named field declaration.
  public init(_ name: String, schema: KtenSchema, required: Bool = true) {
    self.name = name
    self.schema = schema
    self.isRequired = required
  }
}

/// A typed description of values accepted by a Codable model or tool.
///
/// Schemas are ordinary Swift values, so a caller can validate data locally or
/// translate a schema at a boundary that requires another representation. The
/// Kten package itself does not depend on JSON Schema or a provider SDK.
public indirect enum KtenSchema: Sendable, Equatable {
  /// A Boolean value.
  case boolean

  /// A signed integer value.
  case integer

  /// A numeric value that may be integral or floating point.
  case number

  /// A UTF-8 string.
  case string

  /// An opaque byte sequence.
  case bytes

  /// An ordered sequence whose elements match the associated schema.
  case array(KtenSchema)

  /// An object with named fields and an explicit unknown-field policy.
  case object(fields: [KtenField], allowsAdditionalFields: Bool = false)

  /// A value restricted to a fixed list of strings.
  case enumeration([String])

  /// An optional value represented by either the wrapped type or `null`.
  case optional(KtenSchema)
}

/// Adds a reusable typed schema to a `Codable` model.
public protocol KtenSchemaProviding: Codable, Sendable {
  /// The schema corresponding to this model's encoded shape.
  static var ktenSchema: KtenSchema { get }
}
