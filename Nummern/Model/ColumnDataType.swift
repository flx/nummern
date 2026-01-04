import Foundation

enum ColumnDataType: String, Codable, CaseIterable, Equatable, Hashable {
    case number
    case string
    case date
    case time
    case currency
    case percentage

    var displayName: String {
        switch self {
        case .number:
            return "Number"
        case .string:
            return "Text"
        case .date:
            return "Date"
        case .time:
            return "Time"
        case .currency:
            return "Currency"
        case .percentage:
            return "Percentage"
        }
    }

    var usesNumericStorage: Bool {
        switch self {
        case .string:
            return false
        case .number, .date, .time, .currency, .percentage:
            return true
        }
    }
}
