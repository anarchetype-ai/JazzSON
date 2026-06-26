import AppKit
import CoreFoundation
import Foundation
import UniformTypeIdentifiers

private enum JSONValue {
    case object([(key: String, value: JSONValue)])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null
}

private final class JSONNode {
    enum Kind {
        case object
        case array
        case value
    }

    let key: String?
    let value: JSONValue?
    let kind: Kind
    let hasTrailingComma: Bool
    let children: [JSONNode]
    lazy var closingToken = JSONClosingToken(title: closingTitle)

    init(key: String?, value: JSONValue? = nil, kind: Kind, hasTrailingComma: Bool = false, children: [JSONNode] = []) {
        self.key = key
        self.value = value
        self.kind = kind
        self.hasTrailingComma = hasTrailingComma
        self.children = children
    }

    var isExpandable: Bool {
        !children.isEmpty
    }

    func title(isExpanded: Bool) -> String {
        let comma = hasTrailingComma ? "," : ""
        let prefix = key.map { "\"\(JSONText.escapedStringContent($0))\": " } ?? ""

        switch kind {
        case .object:
            if children.isEmpty {
                return "\(prefix){}\(comma)"
            }
            return isExpanded ? "\(prefix){" : "\(prefix){ ... }\(comma)"
        case .array:
            if children.isEmpty {
                return "\(prefix)[]\(comma)"
            }
            return isExpanded ? "\(prefix)[" : "\(prefix)[ ... ]\(comma)"
        case .value:
            return "\(prefix)\(JSONText.valueDescription(value))\(comma)"
        }
    }

    var closingTitle: String {
        let comma = hasTrailingComma ? "," : ""
        switch kind {
        case .object:
            return "}\(comma)"
        case .array:
            return "]\(comma)"
        case .value:
            return ""
        }
    }

    static func root(from value: JSONValue) -> JSONNode {
        makeNode(key: nil, value: value, hasTrailingComma: false)
    }

    private static func makeNode(key: String?, value: JSONValue, hasTrailingComma: Bool) -> JSONNode {
        switch value {
        case .object(let members):
            let children = members.enumerated().map { index, member in
                makeNode(key: member.key, value: member.value, hasTrailingComma: index < members.count - 1)
            }
            return JSONNode(key: key, kind: .object, hasTrailingComma: hasTrailingComma, children: children)
        case .array(let values):
            let children = values.enumerated().map { index, value in
                makeNode(key: nil, value: value, hasTrailingComma: index < values.count - 1)
            }
            return JSONNode(key: key, kind: .array, hasTrailingComma: hasTrailingComma, children: children)
        case .string, .number, .bool, .null:
            return JSONNode(key: key, value: value, kind: .value, hasTrailingComma: hasTrailingComma)
        }
    }
}

private final class JSONClosingToken {
    let title: String

    init(title: String) {
        self.title = title
    }
}

private final class JSONRow {
    enum Kind {
        case node(JSONNode)
        case closing(JSONClosingToken)
        case message(String)
    }

    let kind: Kind
    let depth: Int

    init(kind: Kind, depth: Int = 0) {
        self.kind = kind
        self.depth = depth
    }
}

private protocol JSONTextViewToggleDelegate: AnyObject {
    func jsonTextView(_ textView: JSONTextView, toggleAtCharacterIndex characterIndex: Int) -> Bool
}

private final class JSONTextView: NSTextView {
    weak var toggleDelegate: JSONTextViewToggleDelegate?
    var toggleRanges: [NSRange] = []

    override func mouseDown(with event: NSEvent) {
        if let characterIndex = characterIndex(for: event),
           toggleDelegate?.jsonTextView(self, toggleAtCharacterIndex: characterIndex) == true {
            return
        }

        super.mouseDown(with: event)
    }

    override func copy(_ sender: Any?) {
        let source = string as NSString
        let copiedParts = selectedRanges.compactMap { value -> String? in
            let selectedRange = value.rangeValue
            guard selectedRange.length > 0 else {
                return nil
            }

            let copiedText = NSMutableString(string: source.substring(with: selectedRange))
            let rangesToRemove = toggleRanges
                .map { NSIntersectionRange($0, selectedRange) }
                .filter { $0.length > 0 }
                .sorted { $0.location > $1.location }

            for range in rangesToRemove {
                copiedText.replaceCharacters(
                    in: NSRange(location: range.location - selectedRange.location, length: range.length),
                    with: String(repeating: " ", count: range.length)
                )
            }

            return copiedText as String
        }

        guard copiedParts.isEmpty == false else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copiedParts.joined(separator: "\n"), forType: .string)
    }

    private func characterIndex(for event: NSEvent) -> Int? {
        guard let layoutManager, let textContainer, string.isEmpty == false else {
            return nil
        }

        var point = convert(event.locationInWindow, from: nil)
        point.x -= textContainerOrigin.x
        point.y -= textContainerOrigin.y

        guard point.x >= 0, point.y >= 0 else {
            return nil
        }

        layoutManager.ensureLayout(for: textContainer)
        guard layoutManager.numberOfGlyphs > 0 else {
            return nil
        }

        let characterIndex = layoutManager.characterIndex(
            for: point,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        return characterIndex < string.count ? characterIndex : nil
    }

}

private struct RenderedLine {
    let row: JSONRow
    let lineRange: NSRange
    let toggleRange: NSRange?
}

private final class JSONViewController: NSViewController, JSONTextViewToggleDelegate {
    private let scrollView = NSScrollView()
    private let textView = JSONTextView()
    private var rootNode: JSONNode?
    private var rows: [JSONRow] = [JSONRow(kind: .message("Open a JSON file or paste JSON from the clipboard."))]
    private var renderedLines: [RenderedLine] = []
    private var expandedNodeIDs = Set<ObjectIdentifier>()
    private var currentURL: URL?

    var hasLoadedJSON: Bool {
        rootNode != nil
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 650))

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        view.addSubview(scrollView)

        textView.toggleDelegate = self
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(calibratedRed: 0.70, green: 0.86, blue: 0.96, alpha: 0.95),
            .foregroundColor: NSColor.textColor
        ]
        scrollView.documentView = textView

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        renderRows()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateTextWidth()
    }

    @discardableResult
    func open(url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            let value = try JSONParser.parse(data: data)
            load(value: value, title: url.lastPathComponent, url: url, expandByDefault: true)
            return true
        } catch {
            showInvalidJSON(error, source: url.lastPathComponent)
            return false
        }
    }

    func openClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSAlert.showMessage(title: "Clipboard Is Empty", message: "The clipboard does not contain text that can be read as JSON.")
            return
        }

        do {
            guard let data = text.data(using: .utf8) else {
                NSAlert.showMessage(title: "Could Not Read Clipboard", message: "The clipboard text could not be read as UTF-8.")
                return
            }

            let value = try JSONParser.parse(data: data)
            load(value: value, title: "Clipboard JSON", url: nil, expandByDefault: true)
        } catch {
            showInvalidJSON(error, source: "Clipboard")
        }
    }

    func reload() {
        guard let currentURL else {
            return
        }
        open(url: currentURL)
    }

    func expandAll() {
        guard let rootNode else {
            return
        }

        expandedNodeIDs.removeAll()
        expandRecursively(rootNode)
        rebuildRows()
    }

    func collapseAll() {
        guard rootNode != nil else {
            return
        }

        expandedNodeIDs.removeAll()
        rebuildRows()
    }

    func performFindAction(_ action: NSTextFinder.Action) {
        view.window?.makeFirstResponder(textView)

        let item = NSMenuItem()
        item.tag = action.rawValue
        textView.performFindPanelAction(item)
    }

    private func load(value: JSONValue, title: String, url: URL?, expandByDefault: Bool) {
        let rootNode = JSONNode.root(from: value)
        self.rootNode = rootNode
        currentURL = url
        expandedNodeIDs.removeAll()
        if expandByDefault {
            expandRecursively(rootNode)
        }
        rebuildRows()
        view.window?.title = title
    }

    private func showInvalidJSON(_ error: Error, source: String) {
        rootNode = nil
        currentURL = nil
        rows = [JSONRow(kind: .message("Invalid JSON\n\n\(source) could not be read as valid JSON.\n\n\(error.localizedDescription)"))]
        renderRows()
        view.window?.title = "Invalid JSON"
        NSAlert.showInvalidJSON(error, source: source)
    }

    private func expandRecursively(_ node: JSONNode) {
        guard node.isExpandable else {
            return
        }
        expandedNodeIDs.insert(ObjectIdentifier(node))
        node.children.forEach(expandRecursively)
    }

    private func rebuildRows() {
        rows.removeAll()
        if let rootNode {
            appendRows(for: rootNode, depth: 0)
        }
        renderRows()
    }

    private func renderRows() {
        let text = NSMutableAttributedString()
        var renderedLines: [RenderedLine] = []
        let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let chevronFont = baseFont
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = 22
        paragraphStyle.maximumLineHeight = 22

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle
        ]
        let secondaryAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]
        let chevronAttributes: [NSAttributedString.Key: Any] = [
            .font: chevronFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
            .baselineOffset: 0
        ]

        for (index, row) in rows.enumerated() {
            let lineStart = text.length
            var toggleRange: NSRange?

            switch row.kind {
            case .node(let node):
                text.append(NSAttributedString(string: String(repeating: "  ", count: row.depth), attributes: baseAttributes))
                if node.isExpandable {
                    let toggleStart = text.length
                    text.append(NSAttributedString(string: isExpanded(node) ? "▾" : "▸", attributes: chevronAttributes))
                    toggleRange = NSRange(location: toggleStart, length: 1)
                    text.append(NSAttributedString(string: " ", attributes: baseAttributes))
                } else {
                    text.append(NSAttributedString(string: "  ", attributes: baseAttributes))
                }
                text.append(NSAttributedString(string: node.title(isExpanded: isExpanded(node)), attributes: baseAttributes))
            case .closing(let token):
                text.append(NSAttributedString(string: String(repeating: "  ", count: row.depth), attributes: baseAttributes))
                text.append(NSAttributedString(string: "  \(token.title)", attributes: baseAttributes))
            case .message(let message):
                text.append(NSAttributedString(string: message, attributes: secondaryAttributes))
            }

            let lineEnd = text.length
            renderedLines.append(RenderedLine(row: row, lineRange: NSRange(location: lineStart, length: lineEnd - lineStart), toggleRange: toggleRange))

            if index < rows.count - 1 {
                text.append(NSAttributedString(string: "\n", attributes: baseAttributes))
            }
        }

        self.renderedLines = renderedLines
        textView.textStorage?.setAttributedString(text)
        textView.toggleRanges = renderedLines.compactMap(\.toggleRange)
        updateTextWidth()
    }

    private func updateTextWidth() {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let contentWidth = max(scrollView.contentSize.width, ceil(usedRect.width + textView.textContainerInset.width * 2 + 24))

        var frame = textView.frame
        frame.size.width = contentWidth
        textView.frame = frame
    }

    private func appendRows(for node: JSONNode, depth: Int) {
        rows.append(JSONRow(kind: .node(node), depth: depth))
        guard node.isExpandable, isExpanded(node) else {
            return
        }

        for child in node.children {
            appendRows(for: child, depth: depth + 1)
        }

        rows.append(JSONRow(kind: .closing(node.closingToken), depth: depth))
    }

    private func isExpanded(_ node: JSONNode) -> Bool {
        expandedNodeIDs.contains(ObjectIdentifier(node))
    }

    private func setExpanded(_ expanded: Bool, for node: JSONNode) {
        let id = ObjectIdentifier(node)
        if expanded {
            expandedNodeIDs.insert(id)
        } else {
            expandedNodeIDs.remove(id)
        }
    }

    func jsonTextView(_ textView: JSONTextView, toggleAtCharacterIndex characterIndex: Int) -> Bool {
        guard let renderedLine = renderedLines.first(where: { line in
            guard let toggleRange = line.toggleRange else {
                return false
            }
            return NSLocationInRange(characterIndex, toggleRange)
        }) else {
            return false
        }

        guard case .node(let node) = renderedLine.row.kind, node.isExpandable else {
            return false
        }

        setExpanded(!isExpanded(node), for: node)
        rebuildRows()
        return true
    }
}

private final class JSONParser {
    private let characters: [Character]
    private var index = 0

    private init(text: String) {
        characters = Array(text.dropUTF8ByteOrderMark())
    }

    static func parse(data: Data) throws -> JSONValue {
        guard let text = String(data: data, encoding: .utf8) else {
            throw JSONParserError(message: "The file is not valid UTF-8 text.")
        }

        let parser = JSONParser(text: text)
        let value = try parser.parseValue()
        parser.skipWhitespace()
        guard parser.isAtEnd else {
            throw parser.error("Unexpected content after the JSON value.")
        }
        return value
    }

    private var isAtEnd: Bool {
        index >= characters.count
    }

    private var current: Character? {
        isAtEnd ? nil : characters[index]
    }

    private func advance() -> Character {
        let character = characters[index]
        index += 1
        return character
    }

    private func skipWhitespace() {
        while let character = current, Self.isJSONWhitespace(character) {
            index += 1
        }
    }

    private static func isJSONWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x20, 0x0A, 0x0D, 0x09:
                return true
            default:
                return false
            }
        }
    }

    private func parseValue() throws -> JSONValue {
        skipWhitespace()
        guard let character = current else {
            throw error("Expected a JSON value.")
        }

        switch character {
        case "{":
            return try parseObject()
        case "[":
            return try parseArray()
        case "\"":
            return .string(try parseString())
        case "t":
            try consumeLiteral("true")
            return .bool(true)
        case "f":
            try consumeLiteral("false")
            return .bool(false)
        case "n":
            try consumeLiteral("null")
            return .null
        case "-", "0"..."9":
            return .number(try parseNumber())
        default:
            throw error("Unexpected character '\(character)'.")
        }
    }

    private func parseObject() throws -> JSONValue {
        try consume("{")
        skipWhitespace()

        var members: [(key: String, value: JSONValue)] = []
        if current == "}" {
            index += 1
            return .object(members)
        }

        while true {
            skipWhitespace()
            guard current == "\"" else {
                throw error("Expected an object key.")
            }
            let key = try parseString()

            skipWhitespace()
            try consume(":")

            let value = try parseValue()
            members.append((key: key, value: value))

            skipWhitespace()
            if current == "}" {
                index += 1
                return .object(members)
            }

            try consume(",")
        }
    }

    private func parseArray() throws -> JSONValue {
        try consume("[")
        skipWhitespace()

        var values: [JSONValue] = []
        if current == "]" {
            index += 1
            return .array(values)
        }

        while true {
            values.append(try parseValue())
            skipWhitespace()
            if current == "]" {
                index += 1
                return .array(values)
            }

            try consume(",")
        }
    }

    private func parseString() throws -> String {
        try consume("\"")
        var result = ""

        while let character = current {
            index += 1

            if character == "\"" {
                return result
            }

            if character == "\\" {
                result.append(try parseEscapedCharacter())
                continue
            }

            if character.unicodeScalars.contains(where: { $0.value < 0x20 }) {
                throw error("Strings cannot contain unescaped control characters.")
            }

            result.append(character)
        }

        throw error("Unterminated string.")
    }

    private func parseEscapedCharacter() throws -> Character {
        guard let escape = current else {
            throw error("Unterminated escape sequence.")
        }
        index += 1

        switch escape {
        case "\"":
            return "\""
        case "\\":
            return "\\"
        case "/":
            return "/"
        case "b":
            return "\u{08}"
        case "f":
            return "\u{0C}"
        case "n":
            return "\n"
        case "r":
            return "\r"
        case "t":
            return "\t"
        case "u":
            let scalar = try parseUnicodeScalar()
            if (0xD800...0xDBFF).contains(scalar.value) {
                let high = scalar.value
                guard current == "\\" else {
                    throw error("Expected a low surrogate after a high surrogate.")
                }
                index += 1
                guard current == "u" else {
                    throw error("Expected a low surrogate after a high surrogate.")
                }
                index += 1
                let low = try parseUnicodeScalar().value
                guard (0xDC00...0xDFFF).contains(low) else {
                    throw error("Expected a low surrogate after a high surrogate.")
                }
                let combined = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
                guard let combinedScalar = UnicodeScalar(combined) else {
                    throw error("Invalid Unicode escape.")
                }
                return Character(combinedScalar)
            }

            if (0xDC00...0xDFFF).contains(scalar.value) {
                throw error("Low surrogate without a high surrogate.")
            }

            return Character(scalar)
        default:
            throw error("Invalid escape sequence.")
        }
    }

    private func parseUnicodeScalar() throws -> UnicodeScalar {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let character = current, let digit = character.hexDigitValue else {
                throw error("Invalid Unicode escape.")
            }
            index += 1
            value = value * 16 + UInt32(digit)
        }

        guard let scalar = UnicodeScalar(value) else {
            throw error("Invalid Unicode escape.")
        }
        return scalar
    }

    private func parseNumber() throws -> String {
        let start = index

        if current == "-" {
            index += 1
        }

        guard let firstDigit = current else {
            throw error("Invalid number.")
        }

        if firstDigit == "0" {
            index += 1
        } else if ("1"..."9").contains(firstDigit) {
            consumeDigits()
        } else {
            throw error("Invalid number.")
        }

        if current == "." {
            index += 1
            guard let digit = current, digit.isNumber else {
                throw error("Expected a digit after the decimal point.")
            }
            consumeDigits()
        }

        if current == "e" || current == "E" {
            index += 1
            if current == "+" || current == "-" {
                index += 1
            }
            guard let digit = current, digit.isNumber else {
                throw error("Expected an exponent digit.")
            }
            consumeDigits()
        }

        return String(characters[start..<index])
    }

    private func consumeDigits() {
        while let character = current, character.isNumber {
            index += 1
        }
    }

    private func consumeLiteral(_ literal: String) throws {
        for character in literal {
            try consume(character)
        }
    }

    private func consume(_ expected: Character) throws {
        guard current == expected else {
            throw error("Expected '\(expected)'.")
        }
        index += 1
    }

    private func error(_ message: String) -> JSONParserError {
        JSONParserError(message: message)
    }
}

private struct JSONParserError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private extension String {
    func dropUTF8ByteOrderMark() -> Substring {
        if first == "\u{FEFF}" {
            return dropFirst()
        }

        return self[...]
    }
}

private enum JSONText {
    static func valueDescription(_ value: JSONValue?) -> String {
        guard let value else {
            return ""
        }

        switch value {
        case .string(let string):
            return "\"\(escapedStringContent(string))\""
        case .number(let number):
            return number
        case .bool(let bool):
            return bool ? "true" : "false"
        case .null:
            return "null"
        case .object, .array:
            return ""
        }
    }

    static func escapedStringContent(_ string: String) -> String {
        var escaped = ""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"":
                escaped += "\\\""
            case "\\":
                escaped += "\\\\"
            case "\u{08}":
                escaped += "\\b"
            case "\u{0C}":
                escaped += "\\f"
            case "\n":
                escaped += "\\n"
            case "\r":
                escaped += "\\r"
            case "\t":
                escaped += "\\t"
            case let scalar where scalar.value < 0x20:
                escaped += String(format: "\\u%04X", scalar.value)
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }
        return escaped
    }
}

private enum MarkdownRenderer {
    static func attributedString(from markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            let renderedLine = renderLine(line)
            result.append(renderedLine)

            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }

        return result
    }

    private static func renderLine(_ line: String) -> NSAttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("# ") {
            return styledText(String(trimmed.dropFirst(2)), font: .systemFont(ofSize: 24, weight: .bold), paragraphSpacing: 10)
        }

        if trimmed.hasPrefix("## ") {
            return styledText(String(trimmed.dropFirst(3)), font: .systemFont(ofSize: 19, weight: .bold), paragraphSpacing: 8)
        }

        if trimmed.hasPrefix("### ") {
            return styledText(String(trimmed.dropFirst(4)), font: .systemFont(ofSize: 15, weight: .semibold), paragraphSpacing: 5)
        }

        if trimmed.hasPrefix("- ") {
            let leadingSpaces = line.prefix { $0 == " " }.count
            let nesting = CGFloat(leadingSpaces / 2)
            let bulletIndent = nesting * 30
            let textIndent = bulletIndent + 18
            return styledMarkdown(
                "• \(trimmed.dropFirst(2))",
                font: .systemFont(ofSize: 14, weight: .regular),
                firstLineHeadIndent: bulletIndent,
                headIndent: textIndent
            )
        }

        return styledMarkdown(line, font: .systemFont(ofSize: 14, weight: .regular), paragraphSpacing: trimmed.isEmpty ? 7 : 3)
    }

    private static func styledText(
        _ string: String,
        font: NSFont,
        firstLineHeadIndent: CGFloat = 0,
        headIndent: CGFloat = 0,
        paragraphSpacing: CGFloat = 3,
        backgroundColor: NSColor? = nil
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.paragraphSpacing = paragraphSpacing
        paragraphStyle.firstLineHeadIndent = firstLineHeadIndent
        paragraphStyle.headIndent = headIndent

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle
        ]
        if let backgroundColor {
            attributes[.backgroundColor] = backgroundColor
        }

        return NSAttributedString(
            string: string,
            attributes: attributes
        )
    }

    private static func styledMarkdown(
        _ string: String,
        font: NSFont,
        firstLineHeadIndent: CGFloat = 0,
        headIndent: CGFloat = 0,
        paragraphSpacing: CGFloat = 3
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var remaining = string[...]

        while let start = remaining.firstIndex(of: "`"),
              let end = remaining[remaining.index(after: start)...].firstIndex(of: "`") {
            if start > remaining.startIndex {
                result.append(styledText(String(remaining[..<start]), font: font, firstLineHeadIndent: firstLineHeadIndent, headIndent: headIndent, paragraphSpacing: paragraphSpacing))
            }

            let codeStart = remaining.index(after: start)
            let code = String(remaining[codeStart..<end])
            result.append(styledText(code, font: .monospacedSystemFont(ofSize: font.pointSize, weight: .regular), firstLineHeadIndent: firstLineHeadIndent, headIndent: headIndent, paragraphSpacing: paragraphSpacing, backgroundColor: NSColor.controlBackgroundColor))
            remaining = remaining[remaining.index(after: end)...]
        }

        if remaining.isEmpty == false {
            result.append(styledText(String(remaining), font: font, firstLineHeadIndent: firstLineHeadIndent, headIndent: headIndent, paragraphSpacing: paragraphSpacing))
        }

        return result
    }
}

private extension NSAlert {
    static func showInvalidJSON(_ error: Error, source: String) {
        showMessage(
            title: "Invalid JSON",
            message: "\(source) could not be read as valid JSON.\n\n\(error.localizedDescription)",
            style: .warning
        )
    }

    static func showMessage(title: String, message: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, NSToolbarDelegate {
    private let recentDocumentPathsKey = "JazzSONRecentDocumentPaths"
    private let maxRecentDocumentCount = 10
    private let expandAllToolbarItemIdentifier = NSToolbarItem.Identifier("local.codex.JazzSON.toolbar.expandAll")
    private let collapseAllToolbarItemIdentifier = NSToolbarItem.Identifier("local.codex.JazzSON.toolbar.collapseAll")
    private var windows: [NSWindow] = []
    private var prdWindow: NSWindow?
    private var aboutMenuItem: NSMenuItem?
    private var openRecentMenu: NSMenu?
    private var isAboutSheetOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        if windows.isEmpty {
            _ = makeWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        open(urls: [URL(fileURLWithPath: filename)])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        open(urls: filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        open(urls: urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func newDocument(_ sender: Any?) {
        _ = makeWindow()
    }

    @objc private func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Open JSON File"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.json, .plainText]

        if panel.runModal() == .OK {
            open(urls: panel.urls)
        }
    }

    @objc private func pasteJSON(_ sender: Any?) {
        let controller = controllerForNewContent()
        controller.openClipboard()
    }

    @objc private func reloadDocument(_ sender: Any?) {
        activeController()?.reload()
    }

    @objc private func expandAll(_ sender: Any?) {
        activeController()?.expandAll()
    }

    @objc private func collapseAll(_ sender: Any?) {
        activeController()?.collapseAll()
    }

    @objc private func showFind(_ sender: Any?) {
        activeController()?.performFindAction(.showFindInterface)
    }

    @objc private func findNext(_ sender: Any?) {
        activeController()?.performFindAction(.nextMatch)
    }

    @objc private func findPrevious(_ sender: Any?) {
        activeController()?.performFindAction(.previousMatch)
    }

    @objc private func showHelp(_ sender: Any?) {
        guard isAboutSheetOpen == false else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "JazzSON version 1.3.0"
        alert.informativeText = "Built by KC Kong on Codex"
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "OK")
        isAboutSheetOpen = true
        aboutMenuItem?.isEnabled = false

        if let window = NSApp.keyWindow ?? windows.last(where: { $0.isVisible }) {
            alert.beginSheetModal(for: window) { [weak self] _ in
                self?.isAboutSheetOpen = false
                self?.aboutMenuItem?.isEnabled = true
            }
        } else {
            alert.runModal()
            isAboutSheetOpen = false
            aboutMenuItem?.isEnabled = true
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(showHelp(_:)) {
            return isAboutSheetOpen == false
        }

        if menuItem.action == #selector(openRecentDocument(_:)),
           let path = menuItem.representedObject as? String {
            return FileManager.default.fileExists(atPath: path)
        }

        if menuItem.action == #selector(clearRecentDocuments(_:)) {
            return recentDocumentURLs().isEmpty == false
        }

        if menuItem.action == #selector(showFind(_:)) ||
            menuItem.action == #selector(findNext(_:)) ||
            menuItem.action == #selector(findPrevious(_:)) {
            return activeController() != nil
        }

        return true
    }

    @objc private func showPRD(_ sender: Any?) {
        if let prdWindow {
            prdWindow.makeKeyAndOrderFront(nil)
            return
        }

        let prdText: String
        if let url = Bundle.main.url(forResource: "JazzSON-PRD", withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            prdText = text
        } else {
            prdText = "JazzSON PRD could not be loaded from the app bundle."
        }

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 820, height: 700))
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 820, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textStorage?.setAttributedString(MarkdownRenderer.attributedString(from: prdText))

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "JazzSON PRD"
        window.minSize = NSSize(width: 560, height: 360)
        window.contentView = scrollView
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        prdWindow = window
    }

    func windowWillClose(_ notification: Notification) {
        // Keep closed windows retained while AppKit finishes its close animation teardown.
        if notification.object as AnyObject? === prdWindow {
            prdWindow = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === openRecentMenu {
            refreshOpenRecentMenu()
        }
    }

    @objc private func openRecentDocument(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else {
            return
        }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            removeRecentDocument(url)
            refreshOpenRecentMenu()
            NSAlert.showMessage(
                title: "File Not Found",
                message: "\(url.lastPathComponent) could not be found."
            )
            return
        }

        open(urls: [url])
    }

    @objc private func clearRecentDocuments(_ sender: Any?) {
        UserDefaults.standard.removeObject(forKey: recentDocumentPathsKey)
        refreshOpenRecentMenu()
    }

    private func open(urls: [URL]) {
        for url in urls {
            guard isSupportedDocumentURL(url) else {
                NSAlert.showMessage(
                    title: "Unsupported File",
                    message: "JazzSON can open local .json and .txt files."
                )
                continue
            }

            let controller = controllerForNewContent()
            if controller.open(url: url) {
                noteRecentDocument(url)
            }
        }
    }

    private func isSupportedDocumentURL(_ url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }

        let supportedExtensions = Set(["json", "txt"])
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private func controllerForNewContent() -> JSONViewController {
        if let controller = activeController(), !controller.hasLoadedJSON {
            return controller
        }
        return makeWindow()
    }

    private func activeController() -> JSONViewController? {
        if let controller = NSApp.keyWindow?.contentViewController as? JSONViewController {
            return controller
        }
        return windows.last(where: { $0.isVisible })?.contentViewController as? JSONViewController
    }

    private func makeWindow() -> JSONViewController {
        let controller = JSONViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "JazzSON"
        window.minSize = NSSize(width: 560, height: 360)
        window.contentViewController = controller
        window.delegate = self
        window.toolbar = makeToolbar()
        window.toolbarStyle = .unified
        window.center()
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
        return controller
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "local.codex.JazzSON.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        return toolbar
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            expandAllToolbarItemIdentifier,
            collapseAllToolbarItemIdentifier,
            .flexibleSpace
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            expandAllToolbarItemIdentifier,
            collapseAllToolbarItemIdentifier,
            .flexibleSpace
        ]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case expandAllToolbarItemIdentifier:
            return makeToolbarItem(
                identifier: itemIdentifier,
                label: "Expand All",
                chevron: "▾",
                action: #selector(expandAll(_:))
            )
        case collapseAllToolbarItemIdentifier:
            return makeToolbarItem(
                identifier: itemIdentifier,
                label: "Collapse All",
                chevron: "▸",
                action: #selector(collapseAll(_:))
            )
        default:
            return nil
        }
    }

    private func makeToolbarItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        chevron: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.target = self
        item.action = action
        item.image = makeToolbarChevronImage(chevron, accessibilityDescription: label)
        return item
    }

    private func makeToolbarChevronImage(_ chevron: String, accessibilityDescription: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 28, height: 28))
        image.accessibilityDescription = accessibilityDescription
        image.lockFocus()

        let font = NSFont.monospacedSystemFont(ofSize: 20, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let attributedChevron = NSAttributedString(string: chevron, attributes: attributes)
        let textSize = attributedChevron.size()
        let rect = NSRect(
            x: (image.size.width - textSize.width) / 2,
            y: (image.size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        attributedChevron.draw(in: rect)

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func recentDocumentURLs() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: recentDocumentPathsKey) ?? []
        var seenPaths = Set<String>()
        var urls: [URL] = []

        for path in paths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard seenPaths.insert(url.path).inserted else {
                continue
            }
            urls.append(url)
        }

        return Array(urls.prefix(maxRecentDocumentCount))
    }

    private func noteRecentDocument(_ url: URL) {
        let path = url.standardizedFileURL.path
        var paths = recentDocumentURLs().map(\.standardizedFileURL.path)
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(maxRecentDocumentCount)), forKey: recentDocumentPathsKey)
        refreshOpenRecentMenu()
    }

    private func removeRecentDocument(_ url: URL) {
        let path = url.standardizedFileURL.path
        let paths = recentDocumentURLs()
            .map(\.standardizedFileURL.path)
            .filter { $0 != path }
        UserDefaults.standard.set(paths, forKey: recentDocumentPathsKey)
    }

    private func refreshOpenRecentMenu() {
        guard let openRecentMenu else {
            return
        }

        openRecentMenu.removeAllItems()
        let urls = recentDocumentURLs()

        if urls.isEmpty {
            let emptyItem = openRecentMenu.addItem(withTitle: "No Recent Documents", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
        } else {
            for url in urls {
                let item = openRecentMenu.addItem(
                    withTitle: url.lastPathComponent,
                    action: #selector(openRecentDocument(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = url.path
                item.toolTip = url.path
            }
        }

        openRecentMenu.addItem(NSMenuItem.separator())
        let clearItem = openRecentMenu.addItem(
            withTitle: "Clear Menu",
            action: #selector(clearRecentDocuments(_:)),
            keyEquivalent: ""
        )
        clearItem.target = self
        clearItem.isEnabled = urls.isEmpty == false
    }

    private func buildMenu() {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.autoenablesItems = false
        appMenuItem.submenu = appMenu
        aboutMenuItem = appMenu.addItem(withTitle: "About JazzSON", action: #selector(showHelp(_:)), keyEquivalent: "")
        aboutMenuItem?.target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide JazzSON", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit JazzSON", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "New", action: #selector(newDocument(_:)), keyEquivalent: "n").target = self
        fileMenu.addItem(withTitle: "Open...", action: #selector(openDocument(_:)), keyEquivalent: "o").target = self
        let openRecentItem = fileMenu.addItem(withTitle: "Open Recent", action: nil, keyEquivalent: "")
        let openRecentMenu = NSMenu(title: "Open Recent")
        openRecentMenu.delegate = self
        openRecentItem.submenu = openRecentMenu
        self.openRecentMenu = openRecentMenu
        refreshOpenRecentMenu()
        fileMenu.addItem(withTitle: "Open from Clipboard", action: #selector(pasteJSON(_:)), keyEquivalent: "").target = self
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Paste", action: #selector(pasteJSON(_:)), keyEquivalent: "v").target = self
        editMenu.addItem(NSMenuItem.separator())

        let findMenuItem = editMenu.addItem(withTitle: "Find", action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: "Find")
        findMenuItem.submenu = findMenu
        findMenu.addItem(withTitle: "Find...", action: #selector(showFind(_:)), keyEquivalent: "f").target = self
        findMenu.addItem(withTitle: "Find Next", action: #selector(findNext(_:)), keyEquivalent: "g").target = self
        let findPreviousItem = findMenu.addItem(withTitle: "Find Previous", action: #selector(findPrevious(_:)), keyEquivalent: "g")
        findPreviousItem.target = self
        findPreviousItem.keyEquivalentModifierMask = [.command, .shift]

        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Expand All", action: #selector(expandAll(_:)), keyEquivalent: "").target = self
        viewMenu.addItem(withTitle: "Collapse All", action: #selector(collapseAll(_:)), keyEquivalent: "").target = self
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f").keyEquivalentModifierMask = [.command, .control]

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu
        helpMenu.addItem(withTitle: "JazzSON PRD", action: #selector(showPRD(_:)), keyEquivalent: "").target = self
        NSApp.helpMenu = helpMenu
    }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
