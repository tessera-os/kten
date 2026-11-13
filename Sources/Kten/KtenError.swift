/// A malformed value, invalid encoding, or type mismatch reported by Kten.
public enum KtenError: Error, Sendable, Equatable {
  /// The binary input does not begin with Kten's format marker.
  case invalidHeader

  /// The input uses a binary format revision this implementation does not know.
  case unsupportedVersion(UInt8)

  /// The binary input ended before a value was complete.
  case truncatedInput

  /// The input contains a value tag that is not part of the format.
  case invalidTag(UInt8)

  /// A length or element count cannot be represented safely.
  case invalidLength

  /// A string payload is not valid UTF-8.
  case invalidUTF8

  /// The binary input contains bytes after the root value.
  case trailingBytes

  /// A value exceeds Kten's maximum nesting depth.
  case nestingLimitExceeded

  /// A value has a different structural type from the requested Codable type.
  case typeMismatch(expected: String, actual: String)

  /// A keyed value does not contain the requested member.
  case missingKey(String)

  /// A numeric value cannot be represented by the requested integer type.
  case integerOutOfRange
}
