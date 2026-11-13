import Foundation

/// Encodes and decodes standalone `KtenValue` trees in Kten's stable binary format.
///
/// The format starts with a five-byte marker and version, followed by one tagged
/// value. Integers and floating-point bit patterns use network byte order,
/// lengths use unsigned base-128 varints, and object keys are written in sorted
/// UTF-8 order for deterministic output.
public enum KtenBinaryCodec {
  private static let magic: [UInt8] = [0x4b, 0x54, 0x45, 0x4e]
  private static let version: UInt8 = 1
  private static let maximumDepth = 512

  /// Converts a typed value tree to a deterministic binary document.
  ///
  /// - Parameter value: The root value to encode.
  /// - Returns: A versioned binary document.
  /// - Throws: `KtenError.nestingLimitExceeded` when the tree is too deep.
  public static func encode(_ value: KtenValue) throws -> Data {
    var bytes = magic
    bytes.append(version)
    try append(value, to: &bytes, depth: 0)
    return Data(bytes)
  }

  /// Decodes one complete binary document into its typed value tree.
  ///
  /// - Parameter data: A complete Kten binary document.
  /// - Returns: The decoded root value.
  /// - Throws: `KtenError` for an invalid header, malformed payload, or trailing bytes.
  public static func decode(_ data: Data) throws -> KtenValue {
    var reader = Reader(bytes: Array(data))
    guard try reader.read(count: magic.count) == magic else { throw KtenError.invalidHeader }
    let value = try reader.readByte()
    guard value == 1 else { throw KtenError.unsupportedVersion(value) }
    let result = try reader.readValue(depth: 0)
    guard reader.isAtEnd else { throw KtenError.trailingBytes }
    return result
  }

  private static func append(_ value: KtenValue, to bytes: inout [UInt8], depth: Int) throws {
    guard depth <= maximumDepth else { throw KtenError.nestingLimitExceeded }
    switch value {
    case .null:
      bytes.append(0)
    case .bool(false):
      bytes.append(1)
    case .bool(true):
      bytes.append(2)
    case .signed(let number):
      bytes.append(3)
      append(UInt64(bitPattern: number), to: &bytes)
    case .unsigned(let number):
      bytes.append(4)
      append(number, to: &bytes)
    case .floating(let number):
      bytes.append(5)
      append(number.bitPattern, to: &bytes)
    case .string(let string):
      bytes.append(6)
      let value = Array(string.utf8)
      appendLength(value.count, to: &bytes)
      bytes.append(contentsOf: value)
    case .bytes(let value):
      bytes.append(7)
      appendLength(value.count, to: &bytes)
      bytes.append(contentsOf: value)
    case .array(let values):
      bytes.append(8)
      appendLength(values.count, to: &bytes)
      for value in values { try append(value, to: &bytes, depth: depth + 1) }
    case .object(let fields):
      bytes.append(9)
      let keys = fields.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
      appendLength(keys.count, to: &bytes)
      for key in keys {
        let encodedKey = Array(key.utf8)
        appendLength(encodedKey.count, to: &bytes)
        bytes.append(contentsOf: encodedKey)
        try append(fields[key]!, to: &bytes, depth: depth + 1)
      }
    }
  }

  /// Writes a length as an unsigned base-128 varint, low group first, as `readLength` reads it.
  private static func appendLength(_ length: Int, to bytes: inout [UInt8]) {
    var value = UInt64(length)
    while value >= 0x80 {
      bytes.append(UInt8(truncatingIfNeeded: value) | 0x80)
      value >>= 7
    }
    bytes.append(UInt8(value))
  }

  private static func append(_ value: UInt64, to bytes: inout [UInt8]) {
    for shift in stride(from: 56, through: 0, by: -8) {
      bytes.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
    }
  }

  private struct Reader {
    let bytes: [UInt8]
    var offset = 0

    var isAtEnd: Bool { offset == bytes.count }

    mutating func readByte() throws -> UInt8 {
      guard offset < bytes.count else { throw KtenError.truncatedInput }
      defer { offset += 1 }
      return bytes[offset]
    }

    mutating func read(count: Int) throws -> [UInt8] {
      guard count >= 0, count <= bytes.count - offset else { throw KtenError.truncatedInput }
      defer { offset += count }
      return Array(bytes[offset..<(offset + count)])
    }

    mutating func readUInt64() throws -> UInt64 {
      let value = try read(count: 8)
      return value.reduce(UInt64.zero) { ($0 << 8) | UInt64($1) }
    }

    mutating func readLength() throws -> Int {
      var value: UInt64 = 0
      var shift: UInt64 = 0
      for _ in 0..<10 {
        let byte = try readByte()
        let bits = UInt64(byte & 0x7f)
        guard shift < 64, bits <= (UInt64.max >> shift) else { throw KtenError.invalidLength }
        value |= bits << shift
        if byte & 0x80 == 0 {
          guard value <= UInt64(Int.max) else { throw KtenError.invalidLength }
          return Int(value)
        }
        shift += 7
      }
      throw KtenError.invalidLength
    }

    mutating func readString() throws -> String {
      let count = try readLength()
      guard let string = String(bytes: try read(count: count), encoding: .utf8) else {
        throw KtenError.invalidUTF8
      }
      return string
    }

    mutating func readValue(depth: Int) throws -> KtenValue {
      guard depth <= KtenBinaryCodec.maximumDepth else { throw KtenError.nestingLimitExceeded }
      let tag = try readByte()
      switch tag {
      case 0: return .null
      case 1: return .bool(false)
      case 2: return .bool(true)
      case 3: return .signed(Int64(bitPattern: try readUInt64()))
      case 4: return .unsigned(try readUInt64())
      case 5: return .floating(Double(bitPattern: try readUInt64()))
      case 6: return .string(try readString())
      case 7: return .bytes(try read(count: readLength()))
      case 8:
        let count = try readLength()
        guard count <= bytes.count - offset else { throw KtenError.invalidLength }
        var values: [KtenValue] = []
        values.reserveCapacity(count)
        for _ in 0..<count { values.append(try readValue(depth: depth + 1)) }
        return .array(values)
      case 9:
        let count = try readLength()
        guard count <= bytes.count - offset else { throw KtenError.invalidLength }
        var fields: [String: KtenValue] = [:]
        fields.reserveCapacity(count)
        for _ in 0..<count {
          let key = try readString()
          guard fields[key] == nil else { throw KtenError.invalidLength }
          fields[key] = try readValue(depth: depth + 1)
        }
        return .object(fields)
      default:
        throw KtenError.invalidTag(tag)
      }
    }
  }
}
