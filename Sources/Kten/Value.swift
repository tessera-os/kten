/// A typed value used by Kten's binary format.
///
/// Kten values have no implicit coercions. Signed integers, unsigned integers,
/// and floating-point values use separate tags, object members are named, and
/// byte strings remain distinct from UTF-8 text. This makes the representation
/// suitable for persistence and service boundaries where type identity matters.
public indirect enum KtenValue: Codable, Sendable, Equatable {
  /// An explicit absence of a value.
  case null

  /// A Boolean value.
  case bool(Bool)

  /// A signed 64-bit integer.
  case signed(Int64)

  /// An unsigned 64-bit integer.
  case unsigned(UInt64)

  /// An IEEE-754 64-bit floating-point value.
  case floating(Double)

  /// UTF-8 text.
  case string(String)

  /// Opaque bytes that are not interpreted as text.
  case bytes([UInt8])

  /// An ordered sequence of typed values.
  case array([KtenValue])

  /// A collection of values addressed by unique string keys.
  case object([String: KtenValue])

  private enum CodingKeys: String, CodingKey { case kind, value }
  private enum Kind: String, Codable { case null, bool, signed, unsigned, floating, string, bytes, array, object }

  /// Decodes the tagged Codable representation of a Kten value.
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    switch try values.decode(Kind.self, forKey: .kind) {
    case .null: self = .null
    case .bool: self = .bool(try values.decode(Bool.self, forKey: .value))
    case .signed: self = .signed(try values.decode(Int64.self, forKey: .value))
    case .unsigned: self = .unsigned(try values.decode(UInt64.self, forKey: .value))
    case .floating: self = .floating(try values.decode(Double.self, forKey: .value))
    case .string: self = .string(try values.decode(String.self, forKey: .value))
    case .bytes: self = .bytes(try values.decode([UInt8].self, forKey: .value))
    case .array: self = .array(try values.decode([KtenValue].self, forKey: .value))
    case .object: self = .object(try values.decode([String: KtenValue].self, forKey: .value))
    }
  }

  /// Encodes the value with a stable tag and a type-specific payload.
  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .null:
      try values.encode(Kind.null, forKey: .kind)
    case .bool(let value):
      try values.encode(Kind.bool, forKey: .kind)
      try values.encode(value, forKey: .value)
    case .signed(let value):
      try values.encode(Kind.signed, forKey: .kind)
      try values.encode(value, forKey: .value)
    case .unsigned(let value):
      try values.encode(Kind.unsigned, forKey: .kind)
      try values.encode(value, forKey: .value)
    case .floating(let value):
      try values.encode(Kind.floating, forKey: .kind)
      try values.encode(value, forKey: .value)
    case .string(let value):
      try values.encode(Kind.string, forKey: .kind)
      try values.encode(value, forKey: .value)
    case .bytes(let value):
      try values.encode(Kind.bytes, forKey: .kind)
      try values.encode(value, forKey: .value)
    case .array(let value):
      try values.encode(Kind.array, forKey: .kind)
      try values.encode(value, forKey: .value)
    case .object(let value):
      try values.encode(Kind.object, forKey: .kind)
      try values.encode(value, forKey: .value)
    }
  }
}
