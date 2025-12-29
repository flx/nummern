import Foundation

enum GridRegion: String, Codable, CaseIterable {
    case body = "body"
    case topLabels = "top_labels"
    case bottomLabels = "bottom_labels"
    case leftLabels = "left_labels"
    case rightLabels = "right_labels"
}

struct CellAddress: Equatable, Hashable {
    let row: Int
    let col: Int
}

struct RangeAddress: Equatable, Hashable {
    let region: GridRegion
    let start: CellAddress
    let end: CellAddress
}

enum RangeParserError: Error, Equatable {
    case invalidFormat
    case invalidRegion
    case invalidCellReference
}

struct RangeParser {
    static func parse(_ input: String) throws -> RangeAddress {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bracketStart = trimmed.firstIndex(of: "["),
              trimmed.hasSuffix("]") else {
            throw RangeParserError.invalidFormat
        }

        let regionRaw = String(trimmed[..<bracketStart])
        let region = GridRegion(rawValue: regionRaw)
        guard let region else {
            throw RangeParserError.invalidRegion
        }

        let innerStart = trimmed.index(after: bracketStart)
        let innerEnd = trimmed.index(before: trimmed.endIndex)
        let rangeBody = String(trimmed[innerStart..<innerEnd])

        let parts = rangeBody.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 1 {
            let cell = try parseCell(String(parts[0]))
            return RangeAddress(region: region, start: cell, end: cell)
        }
        if parts.count == 2 {
            let start = try parseCell(String(parts[0]))
            let end = try parseCell(String(parts[1]))
            return RangeAddress(region: region, start: start, end: end)
        }

        throw RangeParserError.invalidFormat
    }

    static func parseCell(_ input: String) throws -> CellAddress {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RangeParserError.invalidCellReference
        }

        let letters = trimmed.prefix { $0.isLetter }
        let numbers = trimmed.drop { $0.isLetter }

        guard !letters.isEmpty, !numbers.isEmpty,
              let rowNumber = Int(numbers), rowNumber > 0 else {
            throw RangeParserError.invalidCellReference
        }

        let colIndex = try columnIndex(from: String(letters))
        return CellAddress(row: rowNumber - 1, col: colIndex)
    }

    static func columnIndex(from label: String) throws -> Int {
        let upper = label.uppercased()
        guard !upper.isEmpty else {
            throw RangeParserError.invalidCellReference
        }

        var value = 0
        for scalar in upper.unicodeScalars {
            let ascii = scalar.value
            guard ascii >= 65, ascii <= 90 else {
                throw RangeParserError.invalidCellReference
            }
            value = value * 26 + Int(ascii - 64)
        }
        return value - 1
    }

    static func columnLabel(from index: Int) -> String {
        precondition(index >= 0, "Column index must be non-negative")
        var number = index + 1
        var chars: [Character] = []
        while number > 0 {
            let remainder = (number - 1) % 26
            guard let scalar = UnicodeScalar(65 + remainder) else {
                break
            }
            chars.append(Character(scalar))
            number = (number - 1) / 26
        }
        return String(chars.reversed())
    }

    static func cellLabel(row: Int, col: Int) -> String {
        "\(columnLabel(from: col))\(row + 1)"
    }
}
