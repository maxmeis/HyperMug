import Foundation

/// The editor holds the raw document text, never a second preferences model. Refreshing cannot replace edits.
public struct ConfigDocumentDraft: Equatable {
    public var text = ""
    public private(set) var savedData: Data?
    public private(set) var isLoaded = false
    public private(set) var hasExternalChanges = false

    public init() {}
    public var isModified: Bool { isLoaded && Data(text.utf8) != (savedData ?? Data()) }

    public mutating func discardChanges() {
        text = String(decoding: savedData ?? Data(), as: UTF8.self)
        hasExternalChanges = false
    }

    public mutating func load(_ data: Data?) throws {
        guard let text = String(data: data ?? Data(), encoding: .utf8) else {
            throw ConfigError(reason: "The configuration is not UTF-8 text. Convert the file to UTF-8 before editing it here.")
        }
        self.text = text
        savedData = data
        isLoaded = true
        hasExternalChanges = false
    }

    public mutating func observe(_ data: Data?) throws {
        guard isLoaded else { try load(data); return }
        guard data != savedData else { hasExternalChanges = false; return }
        if isModified { hasExternalChanges = true }
        else { try load(data) }
    }
}
