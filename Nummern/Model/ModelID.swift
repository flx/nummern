import Foundation

enum ModelID {
    static func make() -> String {
        UUID().uuidString
    }

    static func nextSheetId(existingIDs: [String]) -> String {
        nextSequentialId(prefix: "sheet", existingIDs: existingIDs)
    }

    static func nextTableId(existingIDs: [String]) -> String {
        nextSequentialId(prefix: "table", existingIDs: existingIDs)
    }

    private static func nextSequentialId(prefix: String, existingIDs: [String]) -> String {
        let normalizedPrefix = prefix.hasSuffix("_") ? prefix : "\(prefix)_"
        var maxValue = 0
        for id in existingIDs {
            guard id.hasPrefix(normalizedPrefix) else {
                continue
            }
            let suffix = id.dropFirst(normalizedPrefix.count)
            guard let value = Int(suffix) else {
                continue
            }
            maxValue = max(maxValue, value)
        }
        return "\(normalizedPrefix)\(maxValue + 1)"
    }
}
