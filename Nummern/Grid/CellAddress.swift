import Foundation

/// A1-style address helpers (Swift mirror of python/canvassheets/address.py).
/// Columns are letters; rows are 0-based.
enum CellAddress {
    static func columnLabel(_ index: Int) -> String {
        var n = index + 1
        var chars: [Character] = []
        while n > 0 {
            let r = (n - 1) % 26
            chars.append(Character(UnicodeScalar(UInt8(65 + r))))
            n = (n - 1) / 26
        }
        return String(chars.reversed())
    }

    static func columnIndex(_ label: String) -> Int? {
        let upper = label.uppercased()
        guard !upper.isEmpty, upper.allSatisfy({ $0.isLetter && $0.isASCII }) else { return nil }
        var value = 0
        for ch in upper.unicodeScalars { value = value * 26 + Int(ch.value - 64) }
        return value - 1
    }

    /// `"B3"` -> `(row: 3, col: 1)`.
    static func parseCell(_ ref: String) -> (row: Int, col: Int)? {
        let trimmed = ref.trimmingCharacters(in: .whitespaces)
        let letters = trimmed.prefix { $0.isLetter }
        let digits = trimmed.dropFirst(letters.count)
        guard !letters.isEmpty, !digits.isEmpty, digits.allSatisfy(\.isNumber),
              let col = columnIndex(String(letters)), let row = Int(digits) else { return nil }
        return (row, col)
    }

    /// `"A0:C9"` -> normalized `(r0,c0,r1,c1)`; a single cell yields a 1x1 range.
    static func parseRange(_ ref: String) -> (r0: Int, c0: Int, r1: Int, c1: Int)? {
        let parts = ref.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 1 {
            guard let c = parseCell(parts[0]) else { return nil }
            return (c.row, c.col, c.row, c.col)
        }
        guard let a = parseCell(parts[0]), let b = parseCell(parts[1]) else { return nil }
        return (min(a.row, b.row), min(a.col, b.col), max(a.row, b.row), max(a.col, b.col))
    }

    static func cellRef(row: Int, col: Int) -> String { "\(columnLabel(col))\(row)" }
}
