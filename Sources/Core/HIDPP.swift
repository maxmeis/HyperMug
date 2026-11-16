import Foundation

// MARK: - HID++ 2.0 long-report codec (pure; no IOKit)
//
// Wire layout of a long report (20 bytes, report ID 0x11):
//   [0] 0x11  [1] device index  [2] feature index  [3] (function << 4) | softwareID  [4...19] params (16 bytes)
// Replies to our requests carry our software ID; unsolicited notifications carry software ID 0.
// Error replies: [2] == 0xFF, [3] = feature index of the failed request, [4] = (function << 4) | softwareID, [5] = error code.

public enum HIDPP {
    public static let reportID: UInt8 = 0x11
    public static let reportLength = 20
    public static let deviceIndex: UInt8 = 0xFF
    public static let softwareID: UInt8 = 0x0A               // any nonzero nibble; events use 0
    public static let reprogControlsV4: UInt16 = 0x1B04
    public static let wirelessDeviceStatus: UInt16 = 0x1D4B
    public static let thumbCID: UInt16 = 0x00C3

    /// Number of parameter bytes in a long report.
    public static let paramLength = reportLength - 4

    public static func request(featureIndex: UInt8, function: UInt8, params: [UInt8]) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: reportLength)
        report[0] = reportID
        report[1] = deviceIndex
        report[2] = featureIndex
        report[3] = ((function & 0x0F) << 4) | (softwareID & 0x0F)
        for (offset, byte) in params.prefix(paramLength).enumerated() {
            report[4 + offset] = byte
        }
        return report
    }

    /// IRoot (feature index 0) function 0: ask for the index of `featureID`.
    public static func getFeature(_ featureID: UInt16) -> [UInt8] {
        request(featureIndex: 0x00, function: 0, params: [UInt8(featureID >> 8), UInt8(featureID & 0xFF)])
    }

    /// 0x1B04 function 3 (setCidReporting): byte 2 bit1 = divert-valid, bit0 = divert value; remap 0x0000 = keep.
    public static func setCidReporting(featureIndex: UInt8, cid: UInt16, divert: Bool) -> [UInt8] {
        let flags: UInt8 = divert ? 0x03 : 0x02
        return request(featureIndex: featureIndex, function: 3,
                       params: [UInt8(cid >> 8), UInt8(cid & 0xFF), flags, 0x00, 0x00])
    }

    public enum Message: Equatable {
        case response(featureIndex: UInt8, function: UInt8, params: [UInt8])   // swid == softwareID
        case event(featureIndex: UInt8, function: UInt8, params: [UInt8])      // swid == 0
        case error(featureIndex: UInt8, function: UInt8, code: UInt8)          // byte2 == 0xFF
    }

    /// Cheap, allocation-free acceptance test shared by the input callback (which sees mouse reports at 100+ Hz)
    /// and `parse`: a long HID++ report arrives either with report ID 0x11 and at least the 19 bytes after the ID,
    /// or with report ID 0 and the full 20 bytes starting with 0x11.
    public static func isCandidateReport(reportID id: UInt32, length: Int, firstByte: UInt8) -> Bool {
        (id == UInt32(reportID) && length >= reportLength - 1)
            || (id == 0 && length >= reportLength && firstByte == reportID)
    }

    /// Parses one input report. `bytes` may or may not start with the report ID byte
    /// (macOS callbacks differ by transport), so both 20-byte (with ID) and 19-byte (without) forms are accepted.
    /// Returns nil for anything that is not a long HID++ report addressed to us (other report IDs, foreign software IDs).
    public static func parse(reportID id: UInt32, bytes: [UInt8]) -> Message? {
        guard isCandidateReport(reportID: id, length: bytes.count, firstByte: bytes.first ?? 0) else { return nil }
        // 19 bytes: device index, feature index, function|swid, 16 params
        let body = bytes.count >= reportLength && bytes[0] == reportID ? bytes[1..<reportLength] : bytes[0..<(reportLength - 1)]

        let base = body.startIndex
        let featureIndex = body[base + 1]
        if featureIndex == 0xFF {
            let fnSw = body[base + 3]
            guard fnSw & 0x0F == softwareID else { return nil }
            return .error(featureIndex: body[base + 2], function: fnSw >> 4, code: body[base + 4])
        }
        let fnSw = body[base + 2]
        let params = Array(body[(base + 3)...])
        switch fnSw & 0x0F {
        case softwareID: return .response(featureIndex: featureIndex, function: fnSw >> 4, params: params)
        case 0: return .event(featureIndex: featureIndex, function: fnSw >> 4, params: params)
        default: return nil
        }
    }

    /// 0x1B04 event 0 (divertedButtonsEvent) params: up to four big-endian CIDs currently held; zeros are padding.
    public static func divertedCIDs(_ params: [UInt8]) -> [UInt16] {
        var cids: [UInt16] = []
        var i = 0
        while i + 1 < params.count && i < 8 {
            let cid = UInt16(params[i]) << 8 | UInt16(params[i + 1])
            if cid != 0 { cids.append(cid) }
            i += 2
        }
        return cids
    }

    /// 0x1D4B event 0: params[1] == 1 means the device asks software to re-apply its configuration.
    public static func isReconfigurationRequest(_ params: [UInt8]) -> Bool {
        params.count > 1 && params[1] == 1
    }

    /// IRoot.getFeature replies do not echo the requested feature ID, so a late duplicate reply to an earlier
    /// lookup is recognised by carrying the index we already resolved for that earlier feature.
    public static func isDuplicateLookupReply(_ params: [UInt8], knownIndex: UInt8) -> Bool {
        knownIndex != 0 && params.first == knownIndex
    }
}

/// True on the press edge only: the thumb CID is held now and was not held in the previous event.
public func thumbPressed(previous: [UInt16], current: [UInt16]) -> Bool {
    current.contains(HIDPP.thumbCID) && !previous.contains(HIDPP.thumbCID)
}
