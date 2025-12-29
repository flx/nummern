import Foundation

struct RangeValue: Codable, Equatable, Hashable {
    var values: [[CellValue]]
    var dtype: String?

    init(values: [[CellValue]], dtype: String? = nil) {
        self.values = values
        self.dtype = dtype
    }
}
