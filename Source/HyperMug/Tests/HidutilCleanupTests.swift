import Foundation
@testable import HyperMugCore

private let capsToF18 = "        {\n        HIDKeyboardModifierMappingDst = 30064771181;\n        HIDKeyboardModifierMappingSrc = 30064771129;\n    }"
private let userMapping = "        {\n        HIDKeyboardModifierMappingDst = 30064771129;\n        HIDKeyboardModifierMappingSrc = 30064771300;\n    }"

func hidutilCleanupTests() {
    // Only the old Caps→F18 entry: nothing is left to set.
    expectEqual(legacyCapsRemapCleanup(hidutilOutput: "(\n\(capsToF18)\n)\n"), #"{"UserKeyMapping":[]}"#)

    // Other mappings survive, with their values intact.
    let mixed = legacyCapsRemapCleanup(hidutilOutput: "(\n\(capsToF18),\n\(userMapping)\n)\n") ?? ""
    expectEqual(mixed, #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingDst":30064771129,"HIDKeyboardModifierMappingSrc":30064771300}]}"#)
    // Order of entries does not matter.
    let reversed = legacyCapsRemapCleanup(hidutilOutput: "(\n\(userMapping),\n\(capsToF18)\n)\n") ?? ""
    expectEqual(reversed, mixed)

    // hidutil prefixes the list with its property name in some versions.
    expectEqual(legacyCapsRemapCleanup(hidutilOutput: "UserKeyMapping:(\n\(capsToF18)\n)\n"), #"{"UserKeyMapping":[]}"#)

    // Nothing to remove: the user's own mapping only, a reversed pair (Dst/Src swapped), or half of the pair.
    expect(legacyCapsRemapCleanup(hidutilOutput: "(\n\(userMapping)\n)\n") == nil, "no old mapping, nothing to do")
    let swapped = "(\n        {\n        HIDKeyboardModifierMappingDst = 30064771129;\n        HIDKeyboardModifierMappingSrc = 30064771181;\n    }\n)\n"
    expect(legacyCapsRemapCleanup(hidutilOutput: swapped) == nil, "only the exact Caps→F18 pair is removed")
    let srcOnly = "(\n        {\n        HIDKeyboardModifierMappingSrc = 30064771129;\n    }\n)\n"
    expect(legacyCapsRemapCleanup(hidutilOutput: srcOnly) == nil, "an entry without Dst is not the old mapping")

    // No usable output.
    expect(legacyCapsRemapCleanup(hidutilOutput: "(null)\n") == nil, "no mapping at all")
    expect(legacyCapsRemapCleanup(hidutilOutput: "") == nil, "empty output")
    expect(legacyCapsRemapCleanup(hidutilOutput: "no list here") == nil, "no list")
    expect(legacyCapsRemapCleanup(hidutilOutput: "(\n") == nil, "unparseable list")
    expect(legacyCapsRemapCleanup(hidutilOutput: "()\n") == nil, "empty list")

    // A non-numeric value makes the whole list untrusted: leave the user's mappings alone.
    let weird = "(\n\(capsToF18),\n        {\n        HIDKeyboardModifierMappingDst = banana;\n        HIDKeyboardModifierMappingSrc = 30064771300;\n    }\n)\n"
    expect(legacyCapsRemapCleanup(hidutilOutput: weird) == nil, "non-numeric value")
}
