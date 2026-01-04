import Foundation

enum CellValue: Codable, Equatable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case date(Date)
    case time(TimeInterval)
    case empty

    private enum ValueType: String, Codable {
        case string
        case number
        case bool
        case date
        case time
        case empty
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)
        switch type {
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .number:
            self = .number(try container.decode(Double.self, forKey: .value))
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .value))
        case .date:
            let raw = try container.decode(String.self, forKey: .value)
            guard let date = CellValue.jsonDateFormatter.date(from: raw) else {
                self = .empty
                return
            }
            self = .date(date)
        case .time:
            let raw = try container.decode(String.self, forKey: .value)
            guard let date = CellValue.jsonTimeFormatter.date(from: raw) else {
                self = .empty
                return
            }
            let components = Calendar(identifier: .gregorian).dateComponents([.hour, .minute, .second], from: date)
            let hours = Double(components.hour ?? 0)
            let minutes = Double(components.minute ?? 0)
            let seconds = Double(components.second ?? 0)
            self = .time(hours * 3600 + minutes * 60 + seconds)
        case .empty:
            self = .empty
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let value):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case .number(let value):
            try container.encode(ValueType.number, forKey: .type)
            try container.encode(value, forKey: .value)
        case .bool(let value):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(value, forKey: .value)
        case .date(let value):
            try container.encode(ValueType.date, forKey: .type)
            let string = CellValue.jsonDateFormatter.string(from: value)
            try container.encode(string, forKey: .value)
        case .time(let value):
            try container.encode(ValueType.time, forKey: .type)
            let string = CellValue.jsonTimeFormatter.string(from: CellValue.referenceDate.addingTimeInterval(value))
            try container.encode(string, forKey: .value)
        case .empty:
            try container.encode(ValueType.empty, forKey: .type)
        }
    }

    static func fromUserInput(_ input: String) -> CellValue {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .empty
        }
        let lower = trimmed.lowercased()
        if lower == "true" {
            return .bool(true)
        }
        if lower == "false" {
            return .bool(false)
        }
        if let number = Double(trimmed) {
            return .number(number)
        }
        return .string(trimmed)
    }

    static func fromUserInput(_ input: String, columnType: ColumnDataType) -> CellValue? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .empty
        }
        switch columnType {
        case .string:
            return .string(trimmed)
        case .number:
            return fromUserInput(trimmed)
        case .currency:
            return parseCurrency(trimmed).map(CellValue.number)
        case .percentage:
            return parsePercentage(trimmed).map(CellValue.number)
        case .date:
            return parseDate(trimmed).map(CellValue.date)
        case .time:
            return parseTime(trimmed).map(CellValue.time)
        }
    }

    var displayString: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return value ? "TRUE" : "FALSE"
        case .date(let value):
            return CellValue.displayDateFormatter.string(from: value)
        case .time(let value):
            let date = CellValue.referenceDate.addingTimeInterval(value)
            return CellValue.displayTimeFormatter.string(from: date)
        case .empty:
            return ""
        }
    }

    static func displayString(_ value: CellValue, columnType: ColumnDataType) -> String {
        switch columnType {
        case .string:
            return value.displayString
        case .number:
            return value.displayString
        case .currency:
            if case .number(let number) = value {
                return currencyFormatter.string(from: NSNumber(value: number)) ?? value.displayString
            }
            return value.displayString
        case .percentage:
            if case .number(let number) = value {
                return percentFormatter.string(from: NSNumber(value: number)) ?? value.displayString
            }
            return value.displayString
        case .date:
            switch value {
            case .date(let date):
                return displayDateFormatter.string(from: date)
            case .number(let number):
                let date = Date(timeIntervalSinceReferenceDate: number)
                return displayDateFormatter.string(from: date)
            default:
                return value.displayString
            }
        case .time:
            switch value {
            case .time(let seconds):
                let date = referenceDate.addingTimeInterval(seconds)
                return displayTimeFormatter.string(from: date)
            case .number(let number):
                let date = referenceDate.addingTimeInterval(number)
                return displayTimeFormatter.string(from: date)
            default:
                return value.displayString
            }
        }
    }

    private static let referenceDate = Date(timeIntervalSinceReferenceDate: 0)

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    private static let displayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let jsonDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let jsonTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let jsonTimeFormatterShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .currency
        return formatter
    }()

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .percent
        return formatter
    }()

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static func parseDate(_ text: String) -> Date? {
        if let date = jsonDateFormatter.date(from: text) {
            return date
        }
        if let date = localeDateFormatterShort.date(from: text) ?? localeDateFormatterMedium.date(from: text) {
            return Calendar.current.startOfDay(for: date)
        }
        return nil
    }

    private static func parseTime(_ text: String) -> TimeInterval? {
        if let date = jsonTimeFormatter.date(from: text) ?? jsonTimeFormatterShort.date(from: text) {
            let comps = Calendar(identifier: .gregorian).dateComponents([.hour, .minute, .second], from: date)
            let hours = Double(comps.hour ?? 0)
            let minutes = Double(comps.minute ?? 0)
            let seconds = Double(comps.second ?? 0)
            return hours * 3600 + minutes * 60 + seconds
        }
        if let date = localeTimeFormatterShort.date(from: text) ?? localeTimeFormatterMedium.date(from: text) {
            let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            let hours = Double(comps.hour ?? 0)
            let minutes = Double(comps.minute ?? 0)
            let seconds = Double(comps.second ?? 0)
            return hours * 3600 + minutes * 60 + seconds
        }
        return nil
    }

    private static func parseCurrency(_ text: String) -> Double? {
        if let number = currencyFormatter.number(from: text) {
            return number.doubleValue
        }
        if let number = decimalFormatter.number(from: text) {
            return number.doubleValue
        }
        return nil
    }

    private static func parsePercentage(_ text: String) -> Double? {
        if let number = percentFormatter.number(from: text) {
            return number.doubleValue
        }
        if let number = decimalFormatter.number(from: text) {
            let value = number.doubleValue
            if value >= 1 {
                return value / 100.0
            }
            return value
        }
        return nil
    }

    private static let localeDateFormatterShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    private static let localeDateFormatterMedium: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let localeTimeFormatterShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let localeTimeFormatterMedium: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}
