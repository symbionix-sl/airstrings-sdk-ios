import CryptoKit
import Foundation

enum ExperimentSelection {
  enum Selection: Sendable, Equatable {
    case base
    case control(experimentId: String)
    case variant(experimentId: String, name: String, value: String)
  }

  static func bucket(experimentId: String, assignmentId: String) -> Int {
    let digest = SHA256.hash(data: Data((experimentId + ":" + assignmentId).utf8))
    var value: UInt32 = 0
    for byte in digest.prefix(4) {
      value = (value << 8) | UInt32(byte)
    }
    return Int(value % 100)
  }

  static func select(entry: StringEntry, assignmentId: String?) -> Selection {
    guard let experiment = entry.experiment else { return .base }
    guard let assignmentId else { return .base }
    guard !experiment.id.isEmpty else { return .base }

    let allocation = experiment.allocation
    guard allocation.values.allSatisfy({ $0 >= 0 }) else { return .base }
    guard allocation.values.reduce(0, +) == 100 else { return .base }

    let b = bucket(experimentId: experiment.id, assignmentId: assignmentId)
    let names = allocation.keys.sorted {
      $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars)
    }

    var acc = 0
    for name in names {
      acc += allocation[name]!
      guard b < acc else { continue }
      if name == "control" {
        return .control(experimentId: experiment.id)
      }
      guard let value = experiment.variants[name] else { return .base }
      return .variant(experimentId: experiment.id, name: name, value: value)
    }
    return .base
  }
}
