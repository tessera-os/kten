import Foundation

/// Decodes `Decodable` values from Kten binary documents.
///
/// The decoder accepts only Kten's versioned binary format. It never guesses
/// based on file extensions or content type, and it preserves each value's
/// stored type while presenting it through Swift's `Decoder` protocol.
public struct KtenDecoder {
  /// Creates a decoder with the default Kten binary format.
  public init() {}

  /// Decodes a value of the requested type from a complete Kten document.
  ///
  /// - Parameters:
  ///   - type: The `Decodable` type to construct.
  ///   - data: A versioned Kten binary document.
  /// - Returns: A decoded value.
  /// - Throws: `KtenError` for malformed bytes and decoding errors for schema mismatches.
  public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    try decode(type, from: KtenBinaryCodec.decode(data))
  }

  /// Decodes a value directly from an in-memory Kten value tree.
  ///
  /// - Parameters:
  ///   - type: The `Decodable` type to construct.
  ///   - value: The value tree presented to the type's decoder.
  /// - Returns: A decoded value.
  /// - Throws: A decoding error when the value does not fit the requested type.
  public func decode<T: Decodable>(_ type: T.Type, from value: KtenValue) throws -> T {
    try T(from: _KtenDecoder(value: value, codingPath: [], userInfo: [:]))
  }
}

private struct _KtenDecoder: Decoder {
  let value: KtenValue
  var codingPath: [any CodingKey]
  var userInfo: [CodingUserInfoKey: Any]

  func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
    guard case .object = value else { throw mismatch(expected: "object") }
    return KeyedDecodingContainer(
      _KtenKeyedDecodingContainer<Key>(decoder: self, codingPath: codingPath)
    )
  }

  func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
    guard case .array = value else { throw mismatch(expected: "array") }
    return _KtenUnkeyedDecodingContainer(decoder: self, codingPath: codingPath)
  }

  func singleValueContainer() throws -> any SingleValueDecodingContainer {
    _KtenSingleValueDecodingContainer(decoder: self, codingPath: codingPath)
  }

  func child(_ value: KtenValue, for key: any CodingKey) -> _KtenDecoder {
    _KtenDecoder(value: value, codingPath: codingPath + [key], userInfo: userInfo)
  }

  func mismatch(expected: String) -> KtenError {
    KtenError.typeMismatch(expected: expected, actual: value.typeName)
  }
}

private struct _KtenKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
  let decoder: _KtenDecoder
  var codingPath: [any CodingKey]

  var allKeys: [Key] {
    guard case .object(let fields) = decoder.value else { return [] }
    return fields.keys.compactMap(Key.init(stringValue:)).sorted {
      $0.stringValue < $1.stringValue
    }
  }

  func contains(_ key: Key) -> Bool {
    guard case .object(let fields) = decoder.value else { return false }
    return fields[key.stringValue] != nil
  }

  func decodeNil(forKey key: Key) throws -> Bool {
    guard let value = field(for: key) else { return false }
    if case .null = value { return true }
    return false
  }

  func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
    try T(from: decoder.child(try require(key), for: key))
  }

  func nestedContainer<NestedKey: CodingKey>(
    keyedBy type: NestedKey.Type,
    forKey key: Key
  ) throws -> KeyedDecodingContainer<NestedKey> {
    try decoder.child(require(key), for: key).container(keyedBy: type)
  }

  func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
    try decoder.child(require(key), for: key).unkeyedContainer()
  }

  func superDecoder() throws -> any Decoder {
    let key = Key(stringValue: "super")!
    return decoder.child(field(for: key) ?? .null, for: key)
  }

  func superDecoder(forKey key: Key) throws -> any Decoder {
    decoder.child(try require(key), for: key)
  }

  private func field(for key: Key) -> KtenValue? {
    guard case .object(let fields) = decoder.value else { return nil }
    return fields[key.stringValue]
  }

  private func require(_ key: Key) throws -> KtenValue {
    guard let value = field(for: key) else { throw KtenError.missingKey(key.stringValue) }
    return value
  }
}

private struct _KtenUnkeyedDecodingContainer: UnkeyedDecodingContainer {
  let decoder: _KtenDecoder
  var codingPath: [any CodingKey]
  private var values: [KtenValue] {
    guard case .array(let values) = decoder.value else { return [] }
    return values
  }
  var count: Int? { values.count }
  var isAtEnd: Bool { currentIndex >= values.count }
  var currentIndex = 0

  mutating func decodeNil() throws -> Bool {
    guard !isAtEnd else { throw KtenError.truncatedInput }
    if case .null = values[currentIndex] {
      currentIndex += 1
      return true
    }
    return false
  }

  mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
    let (value, key) = try next()
    return try T(from: decoder.child(value, for: key))
  }

  mutating func nestedContainer<NestedKey: CodingKey>(
    keyedBy type: NestedKey.Type
  ) throws -> KeyedDecodingContainer<NestedKey> {
    let (value, key) = try next()
    return try decoder.child(value, for: key).container(keyedBy: type)
  }

  mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
    let (value, key) = try next()
    return try decoder.child(value, for: key).unkeyedContainer()
  }

  mutating func superDecoder() throws -> any Decoder {
    let (value, key) = try next()
    return decoder.child(value, for: key)
  }

  private mutating func next() throws -> (KtenValue, _KtenDecodingIndexKey) {
    guard !isAtEnd else { throw KtenError.truncatedInput }
    let index = currentIndex
    currentIndex += 1
    return (values[index], _KtenDecodingIndexKey(index))
  }
}

private struct _KtenSingleValueDecodingContainer: SingleValueDecodingContainer {
  let decoder: _KtenDecoder
  var codingPath: [any CodingKey]

  func decodeNil() -> Bool {
    if case .null = decoder.value { return true }
    return false
  }

  func decode<T: Decodable>(_ type: T.Type) throws -> T {
    try T(from: decoder)
  }

  func decode(_ type: Bool.Type) throws -> Bool {
    guard case .bool(let value) = decoder.value else { throw decoder.mismatch(expected: "Boolean") }
    return value
  }

  func decode(_ type: String.Type) throws -> String {
    guard case .string(let value) = decoder.value else { throw decoder.mismatch(expected: "string") }
    return value
  }

  func decode(_ type: Double.Type) throws -> Double {
    switch decoder.value {
    case .floating(let value): return value
    case .signed(let value): return Double(value)
    case .unsigned(let value): return Double(value)
    default: throw decoder.mismatch(expected: "number")
    }
  }

  func decode(_ type: Float.Type) throws -> Float { Float(try decode(Double.self)) }

  func decode(_ type: Int.Type) throws -> Int { try signedInteger().as(Int.self) }
  func decode(_ type: Int8.Type) throws -> Int8 { try signedInteger().as(Int8.self) }
  func decode(_ type: Int16.Type) throws -> Int16 { try signedInteger().as(Int16.self) }
  func decode(_ type: Int32.Type) throws -> Int32 { try signedInteger().as(Int32.self) }
  func decode(_ type: Int64.Type) throws -> Int64 { try signedInteger().as(Int64.self) }
  func decode(_ type: UInt.Type) throws -> UInt { try unsignedInteger().as(UInt.self) }
  func decode(_ type: UInt8.Type) throws -> UInt8 { try unsignedInteger().as(UInt8.self) }
  func decode(_ type: UInt16.Type) throws -> UInt16 { try unsignedInteger().as(UInt16.self) }
  func decode(_ type: UInt32.Type) throws -> UInt32 { try unsignedInteger().as(UInt32.self) }
  func decode(_ type: UInt64.Type) throws -> UInt64 { try unsignedInteger().as(UInt64.self) }

  private func signedInteger() throws -> Int64 {
    switch decoder.value {
    case .signed(let value): return value
    case .unsigned(let value) where value <= UInt64(Int64.max): return Int64(value)
    default: throw decoder.mismatch(expected: "signed integer")
    }
  }

  private func unsignedInteger() throws -> UInt64 {
    switch decoder.value {
    case .unsigned(let value): return value
    case .signed(let value) where value >= 0: return UInt64(value)
    default: throw decoder.mismatch(expected: "unsigned integer")
    }
  }
}

private extension Int64 {
  func `as`<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
    guard let value = T(exactly: self) else { throw KtenError.integerOutOfRange }
    return value
  }
}

private extension UInt64 {
  func `as`<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
    guard let value = T(exactly: self) else { throw KtenError.integerOutOfRange }
    return value
  }
}

private extension KtenValue {
  var typeName: String {
    switch self {
    case .null: "null"
    case .bool: "Boolean"
    case .signed: "signed integer"
    case .unsigned: "unsigned integer"
    case .floating: "floating-point number"
    case .string: "string"
    case .bytes: "bytes"
    case .array: "array"
    case .object: "object"
    }
  }
}

private struct _KtenDecodingIndexKey: CodingKey {
  let intValue: Int?
  let stringValue: String

  init(_ index: Int) {
    self.intValue = index
    self.stringValue = "Index \(index)"
  }

  init?(intValue: Int) { self.init(intValue) }
  init?(stringValue: String) { return nil }
}
