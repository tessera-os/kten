# Kten

Kten is a Swift 6 package for typed binary values and `Codable` persistence. It
encodes Swift models directly through `Encoder` and `Decoder`; it does not use
JSON as an intermediate representation.

## Add Kten to a package

```swift
dependencies: [
  .package(path: "../kten")
],
targets: [
  .target(dependencies: [.product(name: "Kten", package: "kten")])
]
```

## Encode and decode Codable values

```swift
import Kten

struct SavedNote: Codable, Sendable {
  var title: String
  var revision: UInt64
  var labels: [String]
}

let encoder = KtenEncoder()
let bytes = try encoder.encode(SavedNote(title: "Plan", revision: 3, labels: ["swift"]))
let restored = try KtenDecoder().decode(SavedNote.self, from: bytes)
```

`KtenEncoder.encodeValue(_:)` and `KtenDecoder.decode(_:from: KtenValue)` let a
storage adapter work with the typed tree directly. The binary form adds a
versioned header, stable tags for every value kind, network-order fixed-width
numbers, and sorted object keys. A decoder rejects trailing bytes, invalid
UTF-8, duplicate object keys, unknown tags, and excessive nesting.

## Declare a typed schema

```swift
struct SearchInput: Codable, Sendable, KtenSchemaProviding {
  var query: String
  var limit: UInt16

  static let ktenSchema: KtenSchema = .object(fields: [
    KtenField("query", schema: .string),
    KtenField("limit", schema: .integer, required: false),
  ])
}
```

Schemas are a Swift enum, not text documents. Applications can validate them,
derive UI forms, or translate them at a protocol boundary without changing the
model's storage representation.

## Value model

`KtenValue` distinguishes signed and unsigned integers, floating-point values,
text, and opaque bytes. Arrays preserve element order; objects map unique names
to values. This keeps storage semantics explicit and independent of provider
wire formats.
