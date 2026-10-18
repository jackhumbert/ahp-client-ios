import AgentHostProtocol
import Foundation
import Testing
@testable import AHPApp

/// The typed field reads over a JSON object, on the wrapper and on the
/// nested dictionary it returns.
struct AnyCodableFieldsTests {
    /// A JSON object as the protocol decodes it, so the values are the native
    /// Bool, Int, Double, NSNull and nested containers the wire produces.
    private func decoded(_ json: String) throws -> AnyCodable {
        try JSONDecoder().decode(AnyCodable.self, from: Data(json.utf8))
    }

    private let json = """
    {
      "text": "hi",
      "whole": 3,
      "integral": 3.0,
      "fraction": 3.5,
      "yes": true,
      "no": false,
      "list": [1, "two"],
      "object": {"inner": 7},
      "nothing": null,
      "flag_as_int": true,
      "number_as_bool": 1,
      "text_as_int": "3"
    }
    """

    @Test func stringFieldReadsAStringOnly() throws {
        let root = try decoded(json)
        #expect(root.stringField("text") == "hi")
        #expect(root.stringField("whole") == nil)
        #expect(root.stringField("missing") == nil)
    }

    @Test func intFieldAcceptsIntegersAndIntegralDoubles() throws {
        let root = try decoded(json)
        #expect(root.intField("whole") == 3)
        #expect(root.intField("integral") == 3)
        #expect(root.intField("fraction") == nil)
    }

    @Test func intFieldRejectsBooleansAndOtherTypes() throws {
        let root = try decoded(json)
        #expect(root.intField("flag_as_int") == nil)
        #expect(root.intField("yes") == nil)
        #expect(root.intField("text_as_int") == nil)
        #expect(root.intField("list") == nil)
        #expect(root.intField("missing") == nil)
    }

    @Test func boolFieldReadsBooleansOnly() throws {
        let root = try decoded(json)
        #expect(root.boolField("yes") == true)
        #expect(root.boolField("no") == false)
        #expect(root.boolField("number_as_bool") == nil)
        #expect(root.boolField("text") == nil)
        #expect(root.boolField("missing") == nil)
    }

    @Test func dictFieldReadsAnObjectOnly() throws {
        let root = try decoded(json)
        #expect(root.dictField("object")?["inner"] as? Int == 7)
        #expect(root.dictField("list") == nil)
        #expect(root.dictField("missing") == nil)
    }

    @Test func arrayFieldReadsAnArrayOnly() throws {
        let root = try decoded(json)
        #expect(root.arrayField("list")?.count == 2)
        #expect(root.arrayField("object") == nil)
        #expect(root.arrayField("missing") == nil)
    }

    @Test func jsonNullReadsAsNilForEveryAccessor() throws {
        let root = try decoded(json)
        #expect(root.stringField("nothing") == nil)
        #expect(root.intField("nothing") == nil)
        #expect(root.boolField("nothing") == nil)
        #expect(root.dictField("nothing") == nil)
        #expect(root.arrayField("nothing") == nil)
    }

    @Test func nestedDictionaryReadsLikeTheWrapper() throws {
        let root = try decoded(json)
        let object = try #require(root.dictField("object"))
        #expect(object.intField("inner") == 7)
        #expect(object.stringField("inner") == nil)
        #expect(object.boolField("inner") == nil)
    }

    @Test func dictionaryAccessorsMatchTheWrapper() throws {
        let root = try decoded(json)
        let object = try #require(root.value as? [String: Any])
        #expect(object.stringField("text") == "hi")
        #expect(object.intField("whole") == 3)
        #expect(object.intField("integral") == 3)
        #expect(object.intField("fraction") == nil)
        #expect(object.intField("flag_as_int") == nil)
        #expect(object.boolField("yes") == true)
        #expect(object.boolField("number_as_bool") == nil)
        #expect(object.arrayField("list")?.count == 2)
        #expect(object.dictField("object")?.intField("inner") == 7)
        #expect(object.intField("nothing") == nil)
    }

    @Test func bridgedFoundationNumbersFollowTheSameRules() throws {
        // JSONSerialization produces NSNumber rather than native Swift values;
        // the same field must read the same way.
        let object = try #require(
            JSONSerialization.jsonObject(
                with: Data(#"{"yes": true, "one": 1, "three": 3.0, "fraction": 3.5}"#.utf8)
            ) as? [String: Any]
        )
        #expect(object.boolField("yes") == true)
        #expect(object.boolField("one") == nil)
        #expect(object.intField("yes") == nil)
        #expect(object.intField("one") == 1)
        #expect(object.intField("three") == 3)
        #expect(object.intField("fraction") == nil)
    }

    @Test func builtInValuesReadTheSameAsDecodedOnes() {
        let meta = AnyCodable(["count": 4, "ratio": 0.5, "ok": true] as [String: Any])
        #expect(meta.intField("count") == 4)
        #expect(meta.intField("ratio") == nil)
        #expect(meta.boolField("ok") == true)
        #expect(meta.intField("ok") == nil)
    }

    @Test func aNonObjectHasNoFields() {
        let scalar = AnyCodable(3)
        #expect(scalar.intField("anything") == nil)
        #expect(scalar.stringField("anything") == nil)
        #expect(scalar.dictField("anything") == nil)
    }
}
