import Foundation
@testable import HyperMugCore

func configValidationTests() {
    let schema = URL(fileURLWithPath: "/Applications/HyperMug.app/Contents/Resources/hypermug.schema.json")
    for config in [AppConfig(), .newFileDefaults, AppConfig(shellTimeoutSeconds: 1), AppConfig(shellTimeoutSeconds: 300)] {
        expectEqual(try? validateConfigDocument(encodeConfig(config, schemaURL: schema)).get().config, config)
    }
    for text in ["{}", #"{"capsLock":"hyper"}"#, #"{"mouse":{"invertScroll":{"vertical":true}}}"#,
                 #"{"helpers":{" spaced ":"echo ok"},"mouse":{"buttons":{"back":{"helper":" spaced "}}}}"#,
                 #"{"mouse":{"buttons":{"back":{"shortcut":["CMD","Shift","["]}}}}"#] {
        if case .success = validateConfigDocument(Data(text.utf8)) { expect(true) }
        else { expect(false, "valid sparse/native config rejected: \(text)") }
    }
    let invalid = ["{", "[]", "true", "null", #"{"extra":true}"#,
        #"{"capsLock":42}"#, #"{"capsLock":"other"}"#,
        #"{"autoUpdate":1}"#, #"{"autoUpdate":null}"#,
        #"{"shellTimeoutSeconds":true}"#, #"{"shellTimeoutSeconds":0}"#, #"{"shellTimeoutSeconds":301}"#,
        #"{"helpers":{"": "echo ok"}}"#, #"{"helpers":{"  ":"echo ok"}}"#,
        #"{"helpers":{"good":""}}"#, #"{"helpers":{"good":"  "}}"#,
        #"{"helpers":{"good":"echo hi\u0000exit 1"}}"#,
        #"{"mouse":{"buttons":{"back":{"shell":"echo hi\u0000exit 1"}}}}"#,
        #"{"mouse":{"buttons":{"back":{}}}}"#,
        #"{"mouse":{"buttons":{"back":{"shell":""}}}}"#,
        #"{"mouse":{"buttons":{"back":{"shell":" \n"}}}}"#,
        #"{"mouse":{"buttons":{"back":{"shell":"echo ok","helper":"good"}}}}"#,
        #"{"mouse":{"buttons":{"back":{"shortcut":[]}}}}"#,
        #"{"mouse":{"buttons":{"back":{"shortcut":[2]}}}}"#,
        #"{"mouse":{"buttons":{"back":{"shortcut":["notakey"]}}}}"#,
        #"{"mouse":{"buttons":{"back":{"shortcut":["cmd"]}}}}"#,
        #"{"mouse":{"buttons":{"back":{"helper":"unknown"}}}}"#,
        #"{"trackpad":{"threeFingerSwipe":{"left":"x"}}}"#]
    for text in invalid {
        if case .failure(let error) = validateConfigDocument(Data(text.utf8)) {
            expect(!error.reason.isEmpty, "schema/native failure is actionable")
        } else { expect(false, "invalid config accepted: \(text)") }
    }
}
