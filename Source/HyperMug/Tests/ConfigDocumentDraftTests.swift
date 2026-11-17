import Foundation
@testable import HyperMugCore

func configDocumentDraftTests() {
    let original = Data(#"{"capsLock":"meh"}"#.utf8)
    let external = Data(#"{"capsLock":"hyper"}"#.utf8)
    var draft = ConfigDocumentDraft()
    expect(!draft.isLoaded && !draft.isModified)
    try! draft.observe(original)
    expect(draft.isLoaded && !draft.isModified && !draft.hasExternalChanges)
    try! draft.observe(external)
    expectEqual(draft.savedData, external, "a clean editor follows external edits")
    draft.text = #"{"capsLock":"default"}"#
    try! draft.observe(original)
    expect(draft.hasExternalChanges && draft.isModified)
    expectEqual(draft.text, #"{"capsLock":"default"}"#, "background polling never replaces a draft")
    expectEqual(draft.savedData, external, "save baseline stays at the version that was edited")
    try! draft.observe(external)
    expect(!draft.hasExternalChanges, "external revert to baseline resolves the conflict")
    draft.discardChanges()
    expect(!draft.isModified && draft.savedData == external, "discard changes only the draft, not its disk baseline")
    try! draft.load(original)
    expect(!draft.isModified && !draft.hasExternalChanges, "explicit reload discards edits")
    try! draft.load(nil)
    expect(!draft.isModified && draft.savedData == nil, "absent file is a clean empty editor")
    draft.text = "{}"
    expect(draft.isModified)
    let before = draft
    do { try draft.load(Data([0xff])); expect(false) }
    catch { expectEqual(draft, before, "invalid UTF-8 does not destroy the current draft") }
}
