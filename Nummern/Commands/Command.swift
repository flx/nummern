import Foundation

protocol Command {
    var commandId: String { get }
    var timestamp: Date { get }

    func apply(to project: inout ProjectModel)
    func invert(previous: ProjectModel) -> (any Command)?
    func serializeToPython() -> String
}

extension Command {
    func invert(previous: ProjectModel) -> (any Command)? {
        nil
    }
}

enum TransactionKind {
    case general
    case cellEdit
}

struct CommandTransaction {
    let id: String
    let timestamp: Date
    let kind: TransactionKind
    var commands: [any Command]
}
