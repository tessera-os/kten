import Foundation
import Kten
import Testing

@Suite("Kten bytes")
struct BytesEncodingTests {
  private struct File: Codable, Equatable {
    var name: String
    var data: Data
    var raw: [UInt8]
  }

  @Test func dataAndByteArraysEncodeAsOneBytesValue() throws {
    let value = try KtenEncoder().encodeValue(File(name: "a", data: Data([1, 2, 3]), raw: [4, 5]))
    #expect(value == .object(["name": .string("a"), "data": .bytes([1, 2, 3]), "raw": .bytes([4, 5])]))
  }

  @Test func bytesRoundTrip() throws {
    let file = File(name: "a", data: Data([0, 255, 7]), raw: [9])
    #expect(try KtenDecoder().decode(File.self, from: KtenEncoder().encode(file)) == file)
  }

  @Test func bytesStoredAsNumbersStillDecode() throws {
    let stored = KtenValue.object([
      "name": .string("a"), "data": .array([.unsigned(1), .unsigned(2)]), "raw": .array([.unsigned(3)]),
    ])
    #expect(try KtenDecoder().decode(File.self, from: stored) == File(name: "a", data: Data([1, 2]), raw: [3]))
  }

  @Test func emptyArraysStayArrays() throws {
    struct Lists: Codable, Equatable {
      var names: [String]
      var counts: [Int]
    }
    let lists = Lists(names: [], counts: [])
    #expect(try KtenEncoder().encodeValue(lists) == .object(["names": .array([]), "counts": .array([])]))
    #expect(try KtenDecoder().decode(Lists.self, from: KtenEncoder().encode(lists)) == lists)
  }

  @Test func aFewMegabytesEncodeQuickly() throws {
    let file = File(name: "photo", data: Data(repeating: 7, count: 8 << 20), raw: [])
    let start = ContinuousClock.now
    let encoded = try KtenEncoder().encode(file)
    #expect(ContinuousClock.now - start < .seconds(1))
    #expect(try KtenDecoder().decode(File.self, from: encoded) == file)
  }
}
