import Foundation

struct SheetModel: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var tables: [TableModel]

    init(id: String = ModelID.make(), name: String, tables: [TableModel] = []) {
        self.id = id
        self.name = name
        self.tables = tables
    }
}
