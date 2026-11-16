@testable import HyperMugCore

private func padded(_ head: [UInt8], to length: Int = HIDPP.reportLength) -> [UInt8] {
    head + [UInt8](repeating: 0, count: length - head.count)
}

func hidppTests() {
    hidppRequestTests()
    hidppParseTests()
    hidppDivertedCIDTests()
    hidppHelperTests()
    hidppCandidateTests()
}

private func hidppRequestTests() {
    // Wire vectors written out by hand (feature 0x1B04 / 0x1D4B lookups, divert and undivert of CID 0x00C3).
    expectEqual(HIDPP.getFeature(0x1B04), padded([0x11, 0xFF, 0x00, 0x0A, 0x1B, 0x04]), "getFeature(0x1B04)")
    expectEqual(HIDPP.getFeature(0x1D4B), padded([0x11, 0xFF, 0x00, 0x0A, 0x1D, 0x4B]), "getFeature(0x1D4B)")
    expectEqual(HIDPP.setCidReporting(featureIndex: 0x09, cid: 0x00C3, divert: true),
                padded([0x11, 0xFF, 0x09, 0x3A, 0x00, 0xC3, 0x03, 0x00, 0x00]), "divert: valid|value, remap kept")
    expectEqual(HIDPP.setCidReporting(featureIndex: 0x09, cid: 0x00C3, divert: false),
                padded([0x11, 0xFF, 0x09, 0x3A, 0x00, 0xC3, 0x02, 0x00, 0x00]), "undivert: valid, value 0")

    // Layout invariants: always exactly one long report; the function is a nibble; params are clipped, not wrapped.
    expectEqual(HIDPP.request(featureIndex: 0x05, function: 2, params: []).count, HIDPP.reportLength, "no params")
    expectEqual(HIDPP.request(featureIndex: 0x05, function: 0x1F, params: []), padded([0x11, 0xFF, 0x05, 0xFA]),
                "function is masked to its nibble")
    let long = HIDPP.request(featureIndex: 0x05, function: 2,
                             params: [UInt8](repeating: 0xAB, count: 40))
    expectEqual(long.count, HIDPP.reportLength, "oversized params are clipped to the report length")
    expect(long[4...] == [UInt8](repeating: 0xAB, count: HIDPP.paramLength)[...], "all 16 param bytes are filled")
}

private func hidppParseTests() {
    // Response, in each form the macOS callbacks produce.
    let responseFull = padded([0x11, 0xFF, 0x00, 0x0A, 0x09, 0x00, 0x04])
    let expectedResponse = HIDPP.Message.response(featureIndex: 0x00, function: 0,
                                                  params: padded([0x09, 0x00, 0x04], to: HIDPP.paramLength))
    expectEqual(HIDPP.parse(reportID: 0x11, bytes: responseFull), expectedResponse, "with report ID byte")
    expectEqual(HIDPP.parse(reportID: 0x11, bytes: Array(responseFull.dropFirst())), expectedResponse,
                "without report ID byte (19 bytes)")
    expectEqual(HIDPP.parse(reportID: 0, bytes: responseFull), expectedResponse, "report ID 0 with embedded ID byte")
    let noIDLong = padded([0xFF, 0x00, 0x0A, 0x09, 0x00, 0x04])      // 20 bytes, first byte is the device index
    expectEqual(HIDPP.parse(reportID: 0x11, bytes: noIDLong), expectedResponse,
                "20 bytes not starting with 0x11 are read as the ID-less form")

    // The function nibble travels with the reply.
    expectEqual(HIDPP.parse(reportID: 0x11, bytes: padded([0x11, 0xFF, 0x07, 0x3A, 0x00, 0xC3, 0x03])),
                .response(featureIndex: 0x07, function: 3, params: padded([0x00, 0xC3, 0x03], to: HIDPP.paramLength)),
                "setCidReporting echo")

    // Error reply for function 3 on feature index 0x0B, code 2.
    let errorFull = padded([0x11, 0xFF, 0xFF, 0x0B, 0x3A, 0x02])
    let expectedError = HIDPP.Message.error(featureIndex: 0x0B, function: 3, code: 0x02)
    expectEqual(HIDPP.parse(reportID: 0x11, bytes: errorFull), expectedError, "error with ID byte")
    expectEqual(HIDPP.parse(reportID: 0x11, bytes: Array(errorFull.dropFirst())), expectedError, "error without ID byte")

    // Diverted-buttons event: software ID 0.
    let eventFull = padded([0x11, 0xFF, 0x0B, 0x00, 0x00, 0xC3, 0x00])
    let expectedEvent = HIDPP.Message.event(featureIndex: 0x0B, function: 0,
                                            params: padded([0x00, 0xC3], to: HIDPP.paramLength))
    expectEqual(HIDPP.parse(reportID: 0x11, bytes: eventFull), expectedEvent, "event with ID byte")
    expectEqual(HIDPP.parse(reportID: 0x11, bytes: Array(eventFull.dropFirst())), expectedEvent, "event without ID byte")
    expectEqual(HIDPP.parse(reportID: 0x11, bytes: padded([0x11, 0xFF, 0x0B, 0x10])),
                .event(featureIndex: 0x0B, function: 1, params: padded([], to: HIDPP.paramLength)),
                "event function is the high nibble")

    // Anything else is not ours.
    expectEqual(HIDPP.parse(reportID: 0x02, bytes: [0x02, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00]), nil, "mouse report")
    expectEqual(HIDPP.parse(reportID: 0x10, bytes: padded([0x10, 0xFF, 0x00, 0x0A])), nil, "short HID++ report ID")
    expectEqual(HIDPP.parse(reportID: 0x11, bytes: [0x11, 0xFF, 0x00]), nil, "too short")
    expectEqual(HIDPP.parse(reportID: 0x11, bytes: padded([0x11, 0xFF, 0x00, 0x0A], to: 18)), nil, "one byte short of the ID-less form")
    expectEqual(HIDPP.parse(reportID: 0x11, bytes: padded([0xFF, 0x00, 0x0A, 0x09], to: 19)),
                .response(featureIndex: 0x00, function: 0, params: padded([0x09], to: HIDPP.paramLength)),
                "exactly the ID-less form parses")
    expectEqual(HIDPP.parse(reportID: 0, bytes: padded([0xFF, 0x00, 0x0A], to: 19)), nil, "report ID 0 needs the full 20 bytes")
    expectEqual(HIDPP.parse(reportID: 0, bytes: padded([0x12, 0xFF, 0x00, 0x0A])), nil, "report ID 0 needs the 0x11 prefix")
    expectEqual(HIDPP.parse(reportID: 0x11, bytes: padded([0x11, 0xFF, 0x00, 0x0B, 0x09])), nil, "foreign software ID")
    expectEqual(HIDPP.parse(reportID: 0x11, bytes: padded([0x11, 0xFF, 0x00, 0x05, 0x09])), nil, "another foreign software ID")
    expectEqual(HIDPP.parse(reportID: 0x11, bytes: padded([0x11, 0xFF, 0xFF, 0x00, 0x0B, 0x02])), nil, "error for a foreign request")
}

private func hidppDivertedCIDTests() {
    expectEqual(HIDPP.divertedCIDs([]), [], "no params")
    expectEqual(HIDPP.divertedCIDs([0, 0, 0, 0, 0, 0, 0, 0]), [], "all padding")
    expectEqual(HIDPP.divertedCIDs([0x00, 0xC3, 0x00, 0x56, 0x00, 0x00, 0x00, 0x00]), [0x00C3, 0x0056], "two held, big-endian")
    expectEqual(HIDPP.divertedCIDs([0x00, 0x00, 0x00, 0xC3, 0x01, 0x02]), [0x00C3, 0x0102], "zeros are dropped anywhere")
    expectEqual(HIDPP.divertedCIDs([0x00, 0xC3, 0x01]), [0x00C3], "a trailing odd byte is ignored")
    expectEqual(HIDPP.divertedCIDs([0x00, 0x01, 0x00, 0x02, 0x00, 0x03, 0x00, 0x04, 0x00, 0x05]), [1, 2, 3, 4],
                "at most four CIDs")
}

private func hidppCandidateTests() {
    func candidate(_ id: UInt32, _ length: Int, _ first: UInt8 = 0x00) -> Bool {
        HIDPP.isCandidateReport(reportID: id, length: length, firstByte: first)
    }
    // Report ID 0x11: the 19 bytes after the ID are enough; the first byte is not looked at.
    expect(candidate(0x11, 19), "ID-less form")
    expect(candidate(0x11, 20, 0x11), "full form")
    expect(candidate(0x11, 20, 0xFF), "20 bytes starting with the device index")
    expect(candidate(0x11, 64), "longer buffers")
    expect(!candidate(0x11, 18), "one byte short")
    expect(!candidate(0x11, 0), "empty")
    // Report ID 0: the 0x11 must be embedded as the first of 20 bytes.
    expect(candidate(0, 20, 0x11), "embedded ID")
    expectEqual(HIDPP.parse(reportID: 0, bytes: []), nil, "parse of an empty report")
    expect(!candidate(0, 19, 0x11), "embedded ID but short")
    expect(!candidate(0, 20, 0x12), "embedded other ID")
    expect(!candidate(0, 20, 0x00), "no embedded ID")
    // Everything else, e.g. the mouse reports that arrive at 100+ Hz.
    expect(!candidate(0x02, 20, 0x11), "mouse report")
    expect(!candidate(0x10, 20, 0x10), "short HID++ report")
}

private func hidppHelperTests() {
    // 0x1D4B reconfiguration notification: params[1] == 1.
    expect(HIDPP.isReconfigurationRequest([0x00, 0x01, 0x00]), "params[1] == 1")
    expect(!HIDPP.isReconfigurationRequest([0x00, 0x00, 0x00]), "params[1] == 0")
    expect(!HIDPP.isReconfigurationRequest([0x00, 0x02]), "params[1] == 2")
    expect(!HIDPP.isReconfigurationRequest([0x01]), "too short")

    // A late duplicate reply to a retried lookup carries the index we already resolved.
    expect(HIDPP.isDuplicateLookupReply([0x09, 0x00, 0x04], knownIndex: 0x09), "same index again")
    expect(!HIDPP.isDuplicateLookupReply([0x0C, 0x00, 0x01], knownIndex: 0x09), "different feature")
    expect(!HIDPP.isDuplicateLookupReply([0x00, 0x00, 0x00], knownIndex: 0x09), "feature absent is a real answer")
    expect(!HIDPP.isDuplicateLookupReply([0x09], knownIndex: 0), "nothing resolved yet")
    expect(!HIDPP.isDuplicateLookupReply([], knownIndex: 0x09), "empty reply")

    // Press edge only.
    expect(thumbPressed(previous: [], current: [0x00C3]), "appears")
    expect(!thumbPressed(previous: [0x00C3], current: [0x00C3]), "held")
    expect(!thumbPressed(previous: [0x00C3], current: []), "released")
    expect(!thumbPressed(previous: [], current: []), "nothing")
    expect(!thumbPressed(previous: [], current: [0x0056]), "another button")
    expect(thumbPressed(previous: [0x0056], current: [0x0056, 0x00C3]), "pressed while another is held")
}
