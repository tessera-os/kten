import Foundation

/// Encodes any `Encodable` value as a Kten binary document.
///
/// Kten implements Swift's `Encoder` protocol directly. A model therefore keeps
/// its ordinary `Codable` conformance and does not need a JSON representation
/// as an intermediate step.
public struct KtenEncoder {
  /// Creates an encoder with the default Kten binary format.
  public init() {}

  /// Encodes a value into one versioned Kten binary document.
  ///
  /// - Parameter value: The value to encode.
  /// - Returns: A deterministic Kten document.
  /// - Throws: An encoding error or `KtenError` for an unsupported value tree.
  public func encode<T: Encodable>(_ value: T) throws -> Data {
    try KtenBinaryCodec.encode(encodeValue(value))
  }

  /// Encodes a value into its in-memory typed representation.
  ///
  /// This form is useful when mapping typed application values to an existing
  /// structured store without passing through bytes.
  public func encodeValue<T: Encodable>(_ value: T) throws -> KtenValue {
    try _KtenEncoder.encoded(value, codingPath: [], userInfo: [:])
  }
}

private final class _KtenValueBox {
  var onChange: ((KtenValue) -> Void)?
  private var storage: KtenValue = .null

  /// The value so far; setting it tells the parent container.
  var value: KtenValue {
    get { storage }
    set {
      storage = newValue
      onChange?(newValue)
    }
  }

  init(onChange: ((KtenValue) -> Void)? = nil) {
    self.onChange = onChange
  }

  /// Changes the array held here in place. The box lets go of it first so
  /// the array is uniquely referenced and appending does not copy it.
  func mutateArray(_ body: (inout [KtenValue]) -> Void) {
    guard case .array(var values) = storage else { return }
    storage = .null
    body(&values)
    value = .array(values)
  }

  /// Changes the object held here in place, without copying its fields.
  func mutateObject(_ body: (inout [String: KtenValue]) -> Void) {
    guard case .object(var fields) = storage else { return }
    storage = .null
    body(&fields)
    value = .object(fields)
  }
}

private struct _KtenEncoder: Encoder {
  /// Encodes one value as a child of `codingPath`. Bytes (`Data` and
  /// `[UInt8]`) become one `bytes` value rather than an array with a value
  /// per byte, which would take minutes and a great deal of memory for a
  /// file of a few megabytes.
  static func encoded<T: Encodable>(
    _ value: T, codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: Any]
  ) throws -> KtenValue {
    if let data = value as? Data { return .bytes(Array(data)) }
    if let bytes = value as? [UInt8] { return .bytes(bytes) }
    let encoder = _KtenEncoder(codingPath: codingPath, userInfo: userInfo)
    try value.encode(to: encoder)
    return encoder.box.value
  }

  let box: _KtenValueBox
  var codingPath: [any CodingKey]
  var userInfo: [CodingUserInfoKey: Any]

  init(
    box: _KtenValueBox = _KtenValueBox(),
    codingPath: [any CodingKey],
    userInfo: [CodingUserInfoKey: Any]
  ) {
    self.box = box
    self.codingPath = codingPath
    self.userInfo = userInfo
  }

  func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
    if case .object = box.value {} else { box.value = .object([:]) }
    return KeyedEncodingContainer(
      _KtenKeyedEncodingContainer<Key>(box: box, codingPath: codingPath, userInfo: userInfo)
    )
  }

  func unkeyedContainer() -> any UnkeyedEncodingContainer {
    if case .array = box.value {} else { box.value = .array([]) }
    return _KtenUnkeyedEncodingContainer(box: box, codingPath: codingPath, userInfo: userInfo)
  }

  func singleValueContainer() -> any SingleValueEncodingContainer {
    _KtenSingleValueEncodingContainer(box: box, codingPath: codingPath)
  }
}

private struct _KtenKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
  let box: _KtenValueBox
  var codingPath: [any CodingKey]
  let userInfo: [CodingUserInfoKey: Any]

  mutating func encodeNil(forKey key: Key) throws {
    set(.null, forKey: key)
  }

  mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
    set(try _KtenEncoder.encoded(value, codingPath: codingPath + [key], userInfo: userInfo), forKey: key)
  }

  mutating func nestedContainer<NestedKey: CodingKey>(
    keyedBy keyType: NestedKey.Type,
    forKey key: Key
  ) -> KeyedEncodingContainer<NestedKey> {
    let parent = box
    let fieldName = key.stringValue
    let childBox = _KtenValueBox { value in
      Self.replace(value, in: parent, at: fieldName)
    }
    childBox.value = .object([:])
    return KeyedEncodingContainer(
      _KtenKeyedEncodingContainer<NestedKey>(
        box: childBox,
        codingPath: codingPath + [key],
        userInfo: userInfo
      )
    )
  }

  mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
    let parent = box
    let fieldName = key.stringValue
    let childBox = _KtenValueBox { value in
      Self.replace(value, in: parent, at: fieldName)
    }
    childBox.value = .array([])
    return _KtenUnkeyedEncodingContainer(
      box: childBox,
      codingPath: codingPath + [key],
      userInfo: userInfo
    )
  }

  mutating func superEncoder() -> any Encoder {
    let key = _KtenStringCodingKey("super")
    let parent = box
    let childBox = _KtenValueBox { value in
      Self.replace(value, in: parent, at: key.stringValue)
    }
    childBox.value = .null
    return _KtenEncoder(box: childBox, codingPath: codingPath + [key], userInfo: userInfo)
  }

  mutating func superEncoder(forKey key: Key) -> any Encoder {
    let parent = box
    let fieldName = key.stringValue
    let childBox = _KtenValueBox { value in
      Self.replace(value, in: parent, at: fieldName)
    }
    childBox.value = .null
    return _KtenEncoder(box: childBox, codingPath: codingPath + [key], userInfo: userInfo)
  }

  private mutating func set(_ value: KtenValue, forKey key: Key) {
    Self.replace(value, in: box, at: key.stringValue)
  }

  private static func replace(_ value: KtenValue, in box: _KtenValueBox, at key: String) {
    box.mutateObject { $0[key] = value }
  }
}

private struct _KtenUnkeyedEncodingContainer: UnkeyedEncodingContainer {
  let box: _KtenValueBox
  var codingPath: [any CodingKey]
  let userInfo: [CodingUserInfoKey: Any]

  var count: Int {
    guard case .array(let values) = box.value else { return 0 }
    return values.count
  }

  mutating func encodeNil() throws { append(.null) }

  mutating func encode<T: Encodable>(_ value: T) throws {
    let index = count
    append(try _KtenEncoder.encoded(value, codingPath: codingPath + [_KtenIndexCodingKey(index)], userInfo: userInfo))
  }

  mutating func nestedContainer<NestedKey: CodingKey>(
    keyedBy keyType: NestedKey.Type
  ) -> KeyedEncodingContainer<NestedKey> {
    let index = count
    let parent = box
    let childBox = _KtenValueBox { value in
      Self.replace(value, in: parent, at: index)
    }
    childBox.value = .object([:])
    append(childBox.value)
    return KeyedEncodingContainer(
      _KtenKeyedEncodingContainer<NestedKey>(
        box: childBox,
        codingPath: codingPath + [_KtenIndexCodingKey(index)],
        userInfo: userInfo
      )
    )
  }

  mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
    let index = count
    let parent = box
    let childBox = _KtenValueBox { value in
      Self.replace(value, in: parent, at: index)
    }
    childBox.value = .array([])
    append(childBox.value)
    return _KtenUnkeyedEncodingContainer(
      box: childBox,
      codingPath: codingPath + [_KtenIndexCodingKey(index)],
      userInfo: userInfo
    )
  }

  mutating func superEncoder() -> any Encoder {
    let index = count
    let parent = box
    let childBox = _KtenValueBox { value in
      Self.replace(value, in: parent, at: index)
    }
    append(childBox.value)
    return _KtenEncoder(
      box: childBox,
      codingPath: codingPath + [_KtenIndexCodingKey(index)],
      userInfo: userInfo
    )
  }

  private mutating func append(_ value: KtenValue) {
    box.mutateArray { $0.append(value) }
  }

  private static func replace(_ value: KtenValue, in box: _KtenValueBox, at index: Int) {
    box.mutateArray { values in
      guard values.indices.contains(index) else { return }
      values[index] = value
    }
  }
}

private struct _KtenSingleValueEncodingContainer: SingleValueEncodingContainer {
  let box: _KtenValueBox
  var codingPath: [any CodingKey]

  mutating func encodeNil() throws { box.value = .null }
  mutating func encode(_ value: Bool) throws { box.value = .bool(value) }
  mutating func encode(_ value: String) throws { box.value = .string(value) }
  mutating func encode(_ value: Double) throws { box.value = .floating(value) }
  mutating func encode(_ value: Float) throws { box.value = .floating(Double(value)) }
  mutating func encode(_ value: Int) throws { box.value = .signed(Int64(value)) }
  mutating func encode(_ value: Int8) throws { box.value = .signed(Int64(value)) }
  mutating func encode(_ value: Int16) throws { box.value = .signed(Int64(value)) }
  mutating func encode(_ value: Int32) throws { box.value = .signed(Int64(value)) }
  mutating func encode(_ value: Int64) throws { box.value = .signed(value) }
  mutating func encode(_ value: UInt) throws { box.value = .unsigned(UInt64(value)) }
  mutating func encode(_ value: UInt8) throws { box.value = .unsigned(UInt64(value)) }
  mutating func encode(_ value: UInt16) throws { box.value = .unsigned(UInt64(value)) }
  mutating func encode(_ value: UInt32) throws { box.value = .unsigned(UInt64(value)) }
  mutating func encode(_ value: UInt64) throws { box.value = .unsigned(value) }

  mutating func encode<T: Encodable>(_ value: T) throws {
    box.value = try _KtenEncoder.encoded(value, codingPath: codingPath, userInfo: [:])
  }
}

private struct _KtenIndexCodingKey: CodingKey {
  let intValue: Int?
  let stringValue: String

  init(_ index: Int) {
    self.intValue = index
    self.stringValue = "Index \(index)"
  }

  init?(intValue: Int) { self.init(intValue) }
  init?(stringValue: String) { return nil }
}

private struct _KtenStringCodingKey: CodingKey {
  let stringValue: String
  var intValue: Int? { nil }

  init(_ value: String) { stringValue = value }
  init?(stringValue: String) { self.init(stringValue) }
  init?(intValue: Int) { return nil }
}
