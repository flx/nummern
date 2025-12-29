import Foundation

struct ProjectModel: Codable, Equatable {
    var sheets: [SheetModel]

    init(sheets: [SheetModel] = []) {
        self.sheets = sheets
    }
}
