import Testing
import Foundation
@testable import AirStrings

@Suite("ExperimentSelection")
struct ExperimentSelectionTests {

  @Test func bucketVectors() {
    #expect(ExperimentSelection.bucket(experimentId: "exp_checkout_cta", assignmentId: "user_1") == 78)
    #expect(ExperimentSelection.bucket(experimentId: "exp_checkout_cta", assignmentId: "user_2") == 19)
    #expect(ExperimentSelection.bucket(experimentId: "exp_paywall_title", assignmentId: "user_2") == 50)
    #expect(ExperimentSelection.bucket(experimentId: "exp_paywall_title", assignmentId: "device-9f8e7d") == 78)
    #expect(ExperimentSelection.bucket(experimentId: "exp_unicode", assignmentId: "ユーザー_1") == 97)
    #expect(ExperimentSelection.bucket(experimentId: "exp_edge", assignmentId: "u") == 15)
  }

  @Test func selectionVectors() {
    struct Vector {
      let id: String
      let assignmentId: String
      let allocation: [String: Int]
      let expected: ExperimentSelection.Selection
    }

    let value = "V"
    let vectors: [Vector] = [
      Vector(
        id: "exp_checkout_cta", assignmentId: "user_1",
        allocation: ["control": 50, "variant_a": 50],
        expected: .variant(experimentId: "exp_checkout_cta", name: "variant_a", value: value)
      ),
      Vector(
        id: "exp_checkout_cta", assignmentId: "user_2",
        allocation: ["control": 50, "variant_a": 50],
        expected: .control(experimentId: "exp_checkout_cta")
      ),
      Vector(
        id: "exp_paywall_title", assignmentId: "user_2",
        allocation: ["control": 34, "variant_a": 33, "variant_b": 33],
        expected: .variant(experimentId: "exp_paywall_title", name: "variant_a", value: value)
      ),
      Vector(
        id: "exp_paywall_title", assignmentId: "device-9f8e7d",
        allocation: ["control": 34, "variant_a": 33, "variant_b": 33],
        expected: .variant(experimentId: "exp_paywall_title", name: "variant_b", value: value)
      ),
      Vector(
        id: "exp_unicode", assignmentId: "ユーザー_1",
        allocation: ["control": 50, "variant_a": 50],
        expected: .variant(experimentId: "exp_unicode", name: "variant_a", value: value)
      ),
      Vector(
        id: "exp_edge", assignmentId: "u",
        allocation: ["a_variant": 10, "control": 90],
        expected: .control(experimentId: "exp_edge")
      )
    ]

    for vector in vectors {
      var variants: [String: String] = [:]
      for name in vector.allocation.keys where name != "control" {
        variants[name] = value
      }
      let entry = StringEntry(
        value: "base",
        format: .text,
        experiment: Experiment(id: vector.id, allocation: vector.allocation, variants: variants)
      )
      #expect(
        ExperimentSelection.select(entry: entry, assignmentId: vector.assignmentId) == vector.expected,
        "\(vector.id):\(vector.assignmentId)"
      )
    }
  }

  @Test func invalidSumSelectsBase() {
    let entry = StringEntry(
      value: "base",
      format: .text,
      experiment: Experiment(id: "exp", allocation: ["control": 40, "variant_a": 50], variants: ["variant_a": "V"])
    )
    #expect(ExperimentSelection.select(entry: entry, assignmentId: "user_1") == .base)
  }

  @Test func missingVariantValueSelectsBase() {
    let entry = StringEntry(
      value: "base",
      format: .text,
      experiment: Experiment(id: "exp_checkout_cta", allocation: ["control": 50, "variant_a": 50], variants: [:])
    )
    #expect(ExperimentSelection.select(entry: entry, assignmentId: "user_1") == .base)
  }

  @Test func emptyExperimentIdSelectsBase() {
    let entry = StringEntry(
      value: "base",
      format: .text,
      experiment: Experiment(id: "", allocation: ["control": 50, "variant_a": 50], variants: ["variant_a": "V"])
    )
    #expect(ExperimentSelection.select(entry: entry, assignmentId: "user_1") == .base)
  }

  @Test func negativeAllocationSelectsBase() {
    let entry = StringEntry(
      value: "base",
      format: .text,
      experiment: Experiment(id: "exp", allocation: ["control": -10, "variant_a": 110], variants: ["variant_a": "V"])
    )
    #expect(ExperimentSelection.select(entry: entry, assignmentId: "user_1") == .base)
  }

  @Test func nilAssignmentIdSelectsBase() {
    let entry = StringEntry(
      value: "base",
      format: .text,
      experiment: Experiment(id: "exp_checkout_cta", allocation: ["control": 50, "variant_a": 50], variants: ["variant_a": "V"])
    )
    #expect(ExperimentSelection.select(entry: entry, assignmentId: nil) == .base)
  }

  @Test func noExperimentSelectsBase() {
    let entry = StringEntry(value: "base", format: .text, experiment: nil)
    #expect(ExperimentSelection.select(entry: entry, assignmentId: "user_1") == .base)
  }

  @Test func malformedExperimentDecodesToNil() throws {
    let json = """
    {
      "format_version": 1,
      "project_id": "proj_test",
      "locale": "en",
      "revision": 1,
      "created_at": "2026-01-01T00:00:00Z",
      "key_id": "key_01",
      "signature": "sig",
      "experiments_signature": "esig",
      "strings": {
        "hello": {
          "value": "Hello",
          "format": "text",
          "experiment": { "id": 123, "allocation": "not-a-map" }
        }
      }
    }
    """

    let bundle = try JSONDecoder().decode(StringBundle.self, from: Data(json.utf8))

    #expect(bundle.strings["hello"]?.value == "Hello")
    #expect(bundle.strings["hello"]?.experiment == nil)
    #expect(bundle.experimentsSignature == "esig")
  }

  @Test func wellFormedExperimentDecodes() throws {
    let json = """
    {
      "format_version": 1,
      "project_id": "proj_test",
      "locale": "en",
      "revision": 1,
      "created_at": "2026-01-01T00:00:00Z",
      "key_id": "key_01",
      "signature": "sig",
      "strings": {
        "hello": {
          "value": "Hello",
          "format": "text",
          "experiment": {
            "id": "exp_1",
            "allocation": { "control": 50, "variant_a": 50 },
            "variants": { "variant_a": "Hi" }
          }
        }
      }
    }
    """

    let bundle = try JSONDecoder().decode(StringBundle.self, from: Data(json.utf8))

    #expect(bundle.experimentsSignature == nil)
    #expect(
      bundle.strings["hello"]?.experiment
        == Experiment(id: "exp_1", allocation: ["control": 50, "variant_a": 50], variants: ["variant_a": "Hi"])
    )
  }
}
