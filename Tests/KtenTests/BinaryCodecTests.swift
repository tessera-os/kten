import Foundation
import Kten
import Testing

@Suite("Kten binary codec")
struct BinaryCodecTests {
  private struct Record: Codable, Equatable {
    enum Kind: Codable, Equatable {
      case note(String)
      case count(Int, label: String?)
    }

    var name: String
    var tags: [String]
    var kind: Kind
    var bytes: Data
    var ratio: Double
    var flag: Bool
  }

  @Test func aRecordWithStringsArraysObjectsAndBytesRoundTrips() throws {
    let record = Record(
      name: "héllo", tags: ["a", "bb", ""], kind: .count(3, label: "three"), bytes: Data([0, 1, 255]), ratio: -0.25, flag: true)
    let data = try KtenEncoder().encode(record)
    #expect(try KtenDecoder().decode(Record.self, from: data) == record)
  }

  @Test func lengthsOfEveryVarintWidthRoundTrip() throws {
    for count in [0, 1, 127, 128, 300, 16_383, 16_384, 70_000] {
      let value = KtenValue.string(String(repeating: "x", count: count))
      #expect(try KtenBinaryCodec.decode(KtenBinaryCodec.encode(value)) == value)
    }
  }

  @Test func aLengthIsOneVarintByteBelow128() throws {
    let data = try KtenBinaryCodec.encode(.string("abc"))
    // Magic and version, the string tag, one length byte, three UTF-8 bytes.
    #expect(Array(data) == [0x4b, 0x54, 0x45, 0x4e, 1, 6, 3, 0x61, 0x62, 0x63])
  }
}
