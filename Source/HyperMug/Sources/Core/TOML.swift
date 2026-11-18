import Foundation
import CoreFoundation

// The configuration file is TOML. It parses to a value tree that is checked against the bundled schema (a
// JSON Schema, because that is what TOML editors read) and then decoded into the model. The serializer is
// generic over the tree: a new model key needs no TOML-specific code.

// MARK: - Value tree

/// Configuration values: what a TOML configuration document parses to.
public indirect enum ConfigValue: Equatable {
    case string(String)
    case integer(Int64)
    case float(Double)
    case boolean(Bool)
    case array([ConfigValue])
    case table([String: ConfigValue])

    /// Foundation object tree, for the schema check and the model's Codable bridge.
    var jsonObject: Any {
        switch self {
        case .string(let s): return s
        case .integer(let i): return NSNumber(value: i)
        case .float(let d): return NSNumber(value: d)
        case .boolean(let b): return NSNumber(value: b)
        case .array(let a): return a.map(\.jsonObject)
        case .table(let t): return t.mapValues(\.jsonObject)
        }
    }

    /// The model's Codable encoding. `null` has no TOML form.
    init(jsonObject: Any, path: String) throws {
        switch jsonObject {
        case let s as String: self = .string(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .boolean(n.boolValue) }
            else if CFNumberIsFloatType(n) { self = .float(n.doubleValue) }
            else { self = .integer(n.int64Value) }
        case let a as [Any]:
            self = .array(try a.enumerated().map { try ConfigValue(jsonObject: $1, path: "\(path)[\($0)]") })
        case let t as [String: Any]:
            self = .table(try t.reduce(into: [:]) { out, entry in
                out[entry.key] = try ConfigValue(jsonObject: entry.value, path: path.isEmpty ? entry.key : "\(path).\(entry.key)")
            })
        default:
            throw ConfigError(reason: "\(path.isEmpty ? "config" : path): null has no TOML equivalent")
        }
    }

    /// TOML arrays hold one value type.
    fileprivate var kind: String {
        switch self {
        case .string: return "string"
        case .integer: return "integer"
        case .float: return "float"
        case .boolean: return "boolean"
        case .array: return "array"
        case .table: return "table"
        }
    }
}

// MARK: - Public entry points

/// Parse a TOML configuration document to its root table. Errors name the line and column.
public func parseConfigTOML(_ data: Data) -> Result<[String: ConfigValue], ConfigError> {
    parseTOMLDocument(data).map(\.table)
}

/// Schema rules, then model checks. Errors name the setting.
public func validateConfigTOML(_ data: Data) -> Result<DecodedConfig, ConfigError> {
    parseConfigTOML(data).flatMap(validateConfigTable)
}

/// The model written as canonical TOML. The model's encoding holds tables, arrays, strings, numbers and
/// booleans, never `null`, so this cannot fail.
public func encodeConfigTOML(_ config: AppConfig, schemaURL: URL? = nil, includeEmptyKeys: Bool = false) -> Data {
    let object = try! JSONSerialization.jsonObject(with: encodeConfig(config, schemaURL: schemaURL, includeEmptyKeys: includeEmptyKeys))
    guard case .table(let table) = try! ConfigValue(jsonObject: object, path: "") else { preconditionFailure("the model encodes a table") }
    return renderConfigTOML(table)
}

/// Canonical TOML: sorted keys, a `#:schema` directive for TOML editors, single-key tables as dotted keys
/// (`back.helper = "next"`), other tables as `[sections]`, empty tables as `{}`. Deterministic.
public func renderConfigTOML(_ table: [String: ConfigValue]) -> Data {
    var lines: [String] = []
    var rest = table
    if let schema = rest.removeValue(forKey: "$schema") {
        if case .string(let url) = schema, !url.unicodeScalars.contains(where: isControl) { lines.append("#:schema \(url)") }
        lines.append("\(renderKey("$schema")) = \(renderValue(schema))")
    }
    renderSection(rest, path: [], into: &lines)
    return Data((lines.joined(separator: "\n") + "\n").utf8)
}

/// Updates only schema metadata (the `#:schema` directive and the `"$schema"` key) in the user's text, so
/// comments and layout survive. Callers compare disk bytes again before atomically replacing the file.
public func tomlConfigDataLinkingSchema(_ data: Data, schemaURL: URL) throws -> Data {
    let parsed = try parseTOMLDocument(data).get()
    let url = schemaURL.absoluteString
    var body = parsed.scalars
    if let range = parsed.schemaRange { body.replaceSubrange(range, with: renderString(url).unicodeScalars) }
    if body.first == "\u{FEFF}" { body.removeFirst() }
    if body.starts(with: "#:schema".unicodeScalars) {
        body.removeSubrange(..<(body.firstIndex(of: "\n").map { $0 + 1 } ?? body.count))
    }
    var prefix = "#:schema \(url)\n"
    if parsed.schemaRange == nil { prefix += "\(renderKey("$schema")) = \(renderString(url))\n" }
    return Data((prefix + String(String.UnicodeScalarView(body))).utf8)
}

// MARK: - Serializer

private func renderSection(_ table: [String: ConfigValue], path: [String], into lines: inout [String]) {
    var entries: [String] = []
    var sections: [([String], [String: ConfigValue])] = []
    for key in table.keys.sorted() {
        var keys = [key]
        var value = table[key]!
        while case .table(let child) = value, child.count == 1, let only = child.first {
            keys.append(only.key)
            value = only.value
        }
        if case .table(let child) = value, !child.isEmpty {
            sections.append((path + keys, child))
        } else {
            entries.append("\(keys.map(renderKey).joined(separator: ".")) = \(renderValue(value))")
        }
    }
    if !entries.isEmpty {
        if !lines.isEmpty { lines.append("") }
        if !path.isEmpty { lines.append("[\(path.map(renderKey).joined(separator: "."))]") }
        lines += entries
    }
    for (sectionPath, child) in sections { renderSection(child, path: sectionPath, into: &lines) }
}

private func renderValue(_ value: ConfigValue) -> String {
    switch value {
    case .string(let s): return renderString(s)
    case .integer(let i): return String(i)
    case .float(let d): return "\(d)"
    case .boolean(let b): return b ? "true" : "false"
    case .array(let a): return "[" + a.map(renderValue).joined(separator: ", ") + "]"
    case .table(let t):
        if t.isEmpty { return "{}" }
        return "{ " + t.keys.sorted().map { "\(renderKey($0)) = \(renderValue(t[$0]!))" }.joined(separator: ", ") + " }"
    }
}

private func isBareKeyScalar(_ c: Unicode.Scalar) -> Bool {
    ("a"..."z").contains(c) || ("A"..."Z").contains(c) || ("0"..."9").contains(c) || c == "_" || c == "-"
}

private func isControl(_ c: Unicode.Scalar) -> Bool { c.value < 0x20 || c.value == 0x7F }

private func renderKey(_ key: String) -> String {
    !key.isEmpty && key.unicodeScalars.allSatisfy(isBareKeyScalar) ? key : renderString(key)
}

private func renderString(_ string: String) -> String {
    var out = "\""
    for c in string.unicodeScalars {
        switch c {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\t": out += "\\t"
        case "\r": out += "\\r"
        case "\u{8}": out += "\\b"
        case "\u{C}": out += "\\f"
        default: out += isControl(c) ? String(format: "\\u%04X", c.value) : String(c)
        }
    }
    return out + "\""
}

// MARK: - Parser

struct ParsedTOML {
    let table: [String: ConfigValue]
    /// Source range of the root `"$schema"` string value, for metadata updates that keep the rest of the text.
    let schemaRange: Range<Int>?
    let scalars: [Unicode.Scalar]
}

func parseTOMLDocument(_ data: Data) -> Result<ParsedTOML, ConfigError> {
    guard let text = String(data: data, encoding: .utf8) else {
        return .failure(ConfigError(reason: "invalid TOML: the file is not UTF-8 text"))
    }
    var parser = TOMLParser(text)
    do {
        let table = try parser.parse()
        return .success(ParsedTOML(table: table, schemaRange: parser.schemaRange, scalars: parser.text))
    } catch {
        let error = error as! TOMLSyntaxError
        var line = 1
        var column = 1
        for c in parser.text[..<min(error.offset, parser.text.count)] {
            if c == "\n" { line += 1; column = 1 } else { column += 1 }
        }
        return .failure(ConfigError(reason: "invalid TOML at line \(line), column \(column): \(error.message)"))
    }
}

private struct TOMLSyntaxError: Error {
    let offset: Int
    let message: String
}

/// TOML tables while parsing; how a table was defined decides whether it may be extended later (TOML 1.0).
private final class TableBuilder {
    enum Entry {
        case table(TableBuilder)
        case value(ConfigValue)
    }
    var entries: [String: Entry] = [:]
    var definedByHeader = false
    var definedByDotted = false

    var value: [String: ConfigValue] {
        entries.mapValues { entry in
            switch entry {
            case .table(let t): return .table(t.value)
            case .value(let v): return v
            }
        }
    }
}

private struct Key {
    let name: String
    let offset: Int
}

/// TOML 1.0 without the features the configuration has no use for: dates and times, arrays of tables,
/// arrays that mix value types, and inf/nan are rejected with a clear message.
private struct TOMLParser {
    let text: [Unicode.Scalar]
    var index = 0
    let root = TableBuilder()
    var current: TableBuilder
    var schemaRange: Range<Int>?

    init(_ source: String) {
        text = Array(source.unicodeScalars)
        current = root
        if text.first == "\u{FEFF}" { index = 1 }
    }

    // MARK: Lexing

    var peek: Unicode.Scalar? { peek(0) }

    func peek(_ ahead: Int) -> Unicode.Scalar? { index + ahead < text.count ? text[index + ahead] : nil }

    func lookingAt(_ s: String) -> Bool { s.unicodeScalars.enumerated().allSatisfy { peek($0) == $1 } }

    func fail(_ message: String, at offset: Int? = nil) -> TOMLSyntaxError {
        TOMLSyntaxError(offset: offset ?? index, message: message)
    }

    mutating func skipWhitespace() {
        while peek == " " || peek == "\t" { index += 1 }
    }

    /// One newline (`\n` or `\r\n`); false when there is none here.
    mutating func skipNewline() -> Bool {
        if peek == "\n" { index += 1; return true }
        if lookingAt("\r\n") { index += 2; return true }
        return false
    }

    mutating func skipComment() throws {
        guard peek == "#" else { return }
        while let c = peek, c != "\n", !lookingAt("\r\n") {
            if isControl(c) && c != "\t" { throw fail("control characters are not allowed in comments") }
            index += 1
        }
    }

    mutating func expectLineEnd() throws {
        skipWhitespace()
        try skipComment()
        guard peek == nil || skipNewline() else { throw fail("expected the end of the line") }
    }

    /// Whitespace, comments and newlines between array elements.
    mutating func skipBlankLines() throws {
        repeat {
            skipWhitespace()
            try skipComment()
        } while skipNewline()
    }

    // MARK: Document

    mutating func parse() throws -> [String: ConfigValue] {
        skipWhitespace()
        while let c = peek {
            if c == "[" {
                try parseHeader()
            } else if c != "#" && c != "\n" && c != "\r" {
                try parseKeyValue(into: current, atRoot: current === root)
            }
            try expectLineEnd()
            skipWhitespace()
        }
        return root.value
    }

    mutating func parseHeader() throws {
        let start = index
        index += 1
        if peek == "[" { throw fail("arrays of tables ([[...]]) are not supported in the configuration", at: start) }
        skipWhitespace()
        let keys = try parseKey()
        guard peek == "]" else { throw fail("expected ] to close the table header") }
        index += 1
        var table = root
        var name = ""
        for key in keys {
            name += (name.isEmpty ? "" : ".") + key.name
            switch table.entries[key.name] {
            case nil:
                let child = TableBuilder()
                table.entries[key.name] = .table(child)
                table = child
            case .table(let child)?:
                table = child
            case .value?:
                throw fail("\(name) is already defined as a value", at: key.offset)
            }
        }
        if table.definedByHeader || table.definedByDotted { throw fail("table [\(name)] is defined more than once", at: start) }
        table.definedByHeader = true
        current = table
    }

    /// A bare, quoted or dotted key. Consumes trailing whitespace.
    mutating func parseKey() throws -> [Key] {
        var keys = [try parseSimpleKey()]
        while peek == "." {
            index += 1
            skipWhitespace()
            keys.append(try parseSimpleKey())
        }
        return keys
    }

    mutating func parseSimpleKey() throws -> Key {
        let start = index
        let name: String
        if peek == "\"" || peek == "'" {
            name = try parseString(multiline: false)
        } else {
            while let c = peek, isBareKeyScalar(c) { index += 1 }
            guard index > start else { throw fail("expected a key") }
            name = String(String.UnicodeScalarView(text[start..<index]))
        }
        skipWhitespace()
        return Key(name: name, offset: start)
    }

    mutating func parseKeyValue(into table: TableBuilder, atRoot: Bool) throws {
        let keys = try parseKey()
        guard peek == "=" else { throw fail("expected = after the key") }
        index += 1
        skipWhitespace()
        let valueStart = index
        let value = try parseValue()
        if atRoot && keys.count == 1 && keys[0].name == "$schema", case .string = value { schemaRange = valueStart..<index }

        var target = table
        var name = ""
        for key in keys.dropLast() {
            name += (name.isEmpty ? "" : ".") + key.name
            switch target.entries[key.name] {
            case nil:
                let child = TableBuilder()
                child.definedByDotted = true
                target.entries[key.name] = .table(child)
                target = child
            case .table(let child)? where child.definedByDotted:
                target = child
            default:
                throw fail("\(name) is already defined and cannot be extended with dotted keys", at: key.offset)
            }
        }
        let last = keys[keys.count - 1]
        name += (name.isEmpty ? "" : ".") + last.name
        guard target.entries[last.name] == nil else { throw fail("duplicate key \(name)", at: last.offset) }
        target.entries[last.name] = .value(value)
    }

    // MARK: Values

    mutating func parseValue() throws -> ConfigValue {
        switch peek {
        case "\""?, "'"?: return .string(try parseString(multiline: lookingAt("\"\"\"") || lookingAt("'''")))
        case "["?: return try parseArray()
        case "{"?: return try parseInlineTable()
        default: return try parseScalar()
        }
    }

    /// Basic (`"`, with escapes) and literal (`'`) strings, single- or multi-line.
    mutating func parseString(multiline: Bool) throws -> String {
        let start = index
        let quote = text[index]
        let escapes = quote == "\""
        index += multiline ? 3 : 1
        if multiline { _ = skipNewline() }   // a newline right after the opening quotes is not content
        var out = String.UnicodeScalarView()
        while let c = peek {
            if c == quote {
                guard multiline else { index += 1; return String(out) }
                var quotes = 0
                while peek(quotes) == quote { quotes += 1 }
                if quotes >= 3 {
                    // Up to two quotes may directly precede the closing delimiter.
                    guard quotes <= 5 else { throw fail("too many quotes at the end of a multi-line string") }
                    out.append(contentsOf: repeatElement(quote, count: quotes - 3))
                    index += quotes
                    return String(out)
                }
                out.append(c)
                index += 1
            } else if c == "\\" && escapes {
                try parseEscape(into: &out, multiline: multiline)
            } else if c == "\n" || lookingAt("\r\n") {
                guard multiline else { throw fail("strings cannot span lines; use triple quotes for a multi-line string") }
                _ = skipNewline()
                out.append("\n")
            } else if isControl(c) && c != "\t" {
                throw fail("control characters must be escaped in strings")
            } else {
                out.append(c)
                index += 1
            }
        }
        throw fail("unterminated string", at: start)
    }

    mutating func parseEscape(into out: inout String.UnicodeScalarView, multiline: Bool) throws {
        let start = index
        index += 1
        if multiline {
            // A line-ending backslash removes the newline and the whitespace that follows it.
            var end = index
            while text.indices.contains(end) && (text[end] == " " || text[end] == "\t") { end += 1 }
            if end < text.count && (text[end] == "\n" || text[end] == "\r") {
                index = end
                while skipNewline() { skipWhitespace() }
                return
            }
        }
        let simple: [Unicode.Scalar: Unicode.Scalar] = ["b": "\u{8}", "t": "\t", "n": "\n", "f": "\u{C}", "r": "\r", "\"": "\"", "\\": "\\"]
        guard let e = peek else { throw fail("unterminated string", at: start) }
        index += 1
        if let scalar = simple[e] {
            out.append(scalar)
            return
        }
        guard e == "u" || e == "U" else { throw fail("invalid escape \\\(e)", at: start) }
        let count = e == "u" ? 4 : 8
        let digits = text[index..<min(index + count, text.count)]
        guard digits.count == count, digits.allSatisfy(\.properties.isASCIIHexDigit),
              let scalar = Unicode.Scalar(UInt32(String(String.UnicodeScalarView(digits)), radix: 16)!) else {
            throw fail("invalid Unicode escape", at: start)
        }
        index += count
        out.append(scalar)
    }

    mutating func parseArray() throws -> ConfigValue {
        index += 1
        var items: [ConfigValue] = []
        while true {
            try skipBlankLines()
            if peek == "]" { break }
            let itemStart = index
            let item = try parseValue()
            if let first = items.first, first.kind != item.kind {
                throw fail("arrays cannot mix value types (\(first.kind) and \(item.kind))", at: itemStart)
            }
            items.append(item)
            try skipBlankLines()
            guard peek == "," else { break }
            index += 1
        }
        guard peek == "]" else { throw fail("expected , or ] in the array") }
        index += 1
        return .array(items)
    }

    mutating func parseInlineTable() throws -> ConfigValue {
        index += 1
        let table = TableBuilder()
        skipWhitespace()
        if peek != "}" {
            while true {
                skipWhitespace()
                try parseKeyValue(into: table, atRoot: false)
                skipWhitespace()
                guard peek == "," else { break }
                index += 1
            }
        }
        guard peek == "}" else { throw fail("expected , or } in the inline table (inline tables stay on one line)") }
        index += 1
        return .table(table.value)
    }

    /// Booleans and numbers. Dates and times are recognized only to reject them clearly.
    mutating func parseScalar() throws -> ConfigValue {
        let start = index
        while let c = peek, isBareKeyScalar(c) || c == "+" || c == "." || c == ":" { index += 1 }
        let token = String(String.UnicodeScalarView(text[start..<index]))
        func matches(_ pattern: String) -> Bool { token.range(of: pattern, options: .regularExpression) != nil }
        if token == "true" { return .boolean(true) }
        if token == "false" { return .boolean(false) }
        guard !token.isEmpty else { throw fail("expected a value") }
        if matches(#"^[+-]?(inf|nan)$"#) { throw fail("inf and nan are not supported in the configuration", at: start) }
        if matches(#"^[0-9]{4}-[0-9]{2}-[0-9]{2}|^[0-9]{2}:[0-9]{2}"#) {
            throw fail("dates and times are not supported in the configuration", at: start)
        }
        let digits = token.replacingOccurrences(of: "_", with: "")
        let integers: [(prefix: String, radix: Int, pattern: String)] = [
            ("", 10, #"^[+-]?(0|[1-9](_?[0-9])*)$"#),
            ("0x", 16, #"^0x[0-9A-Fa-f](_?[0-9A-Fa-f])*$"#),
            ("0o", 8, #"^0o[0-7](_?[0-7])*$"#),
            ("0b", 2, #"^0b[01](_?[01])*$"#),
        ]
        for integer in integers where matches(integer.pattern) {
            guard let value = Int64(digits.dropFirst(integer.prefix.count), radix: integer.radix) else {
                throw fail("integer \(token) is out of range", at: start)
            }
            return .integer(value)
        }
        let digit = "[0-9](_?[0-9])*"
        if matches("^[+-]?(0|[1-9](_?[0-9])*)(\\.\(digit)([eE][+-]?\(digit))?|[eE][+-]?\(digit))$") {
            let value = Double(digits)!
            guard value.isFinite else { throw fail("number \(token) is out of range", at: start) }
            return .float(value)
        }
        throw fail("invalid value \(token)", at: start)
    }
}
