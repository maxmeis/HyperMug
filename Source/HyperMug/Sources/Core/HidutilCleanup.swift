import Foundation

// Leftover Caps→F18 mapping from older MyMug builds (exactly this Src/Dst pair).
private let legacyCapsSource: Int64 = 0x7_0000_0039   // Caps Lock
private let legacyCapsDestination: Int64 = 0x7_0000_006D   // F18

/// Given `hidutil property --get UserKeyMapping` output, returns the JSON to set so that only the old exact
/// Caps→F18 entry is gone, or nil when that entry is not present (nothing to do; other mappings stay untouched).
public func legacyCapsRemapCleanup(hidutilOutput: String) -> String? {
    guard let open = hidutilOutput.firstIndex(of: "("),
          let list = try? PropertyListSerialization.propertyList(
              from: Data(hidutilOutput[open...].utf8), options: [], format: nil) as? [[String: Any]]
    else { return nil }

    var kept: [[String: Int64]] = []
    var removed = false
    for entry in list {
        var numbers: [String: Int64] = [:]
        for (key, value) in entry {
            guard let number = Int64("\(value)") else { return nil }
            numbers[key] = number
        }
        if numbers["HIDKeyboardModifierMappingSrc"] == legacyCapsSource
            && numbers["HIDKeyboardModifierMappingDst"] == legacyCapsDestination {
            removed = true
        } else {
            kept.append(numbers)
        }
    }
    guard removed else { return nil }
    // Dictionaries of strings to integers always serialize.
    let json = try! JSONSerialization.data(withJSONObject: ["UserKeyMapping": kept], options: [.sortedKeys])
    return String(decoding: json, as: UTF8.self)
}
