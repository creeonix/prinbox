import Foundation
import Testing

@testable import PrinboxCore

@Suite struct JSONValueTests {
    func decode(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    @Test func decodesEveryKind() throws {
        let value = try decode(#"{"a": null, "b": true, "c": 3, "d": 1.5, "e": "x", "f": [1, "y"], "g": {"h": 2}}"#)
        #expect(value["a"] == .null)
        #expect(value["b"] == .bool(true))
        #expect(value["c"] == .number(3))
        #expect(value["d"] == .double(1.5))
        #expect(value["e"] == .string("x"))
        #expect(value["f"] == .array([.number(1), .string("y")]))
        #expect(value["g"]?["h"] == .number(2))
        #expect(value["f"]?[1] == .string("y"))
        #expect(value["f"]?[5] == nil)
        #expect(value["g"]?[0] == nil)
        #expect(value["missing"] == nil)
        #expect(value["e"]?.stringValue == "x")
        #expect(value["g"]?.objectValue?.count == 1)
    }

    @Test func intValueAcceptsWholeDoubles() throws {
        #expect(try decode("60").intValue == 60)
        #expect(try decode("60.0").intValue == 60)
        #expect(try decode("1.5").intValue == nil)
        #expect(try decode("\"60\"").intValue == nil)
        #expect(JSONValue.double(-2.0).intValue == -2)
    }

    @Test func literalsBuildValues() {
        let value: JSONValue = ["name": "prinbox", "count": 2, "on": true, "none": nil, "list": [1, "two"]]
        #expect(value["name"] == .string("prinbox"))
        #expect(value["count"] == .number(2))
        #expect(value["on"] == .bool(true))
        #expect(value["none"] == .null)
        #expect(value["list"] == .array([.number(1), .string("two")]))
        let empty: JSONValue = [:]
        #expect(empty == .object([:]))
    }

    @Test func roundTripsThroughTheEncoder() throws {
        let text = #"{"a":[1,2.5,"s",null,true],"b":{"c":"d"}}"#
        let value = try decode(text)
        let encoded = JSONRPC.encode(value)
        #expect(try decode(encoded) == value)
        #expect(!encoded.contains("\n"))
    }
}
