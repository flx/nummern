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

struct CommandBatch: Command {
    let commandId: String
    let timestamp: Date
    let commands: [any Command]

    init(commandId: String = ModelID.make(),
         timestamp: Date = Date(),
         commands: [any Command]) {
        self.commandId = commandId
        self.timestamp = timestamp
        self.commands = commands
    }

    func apply(to project: inout ProjectModel) {
        for command in commands {
            command.apply(to: &project)
        }
    }

    func invert(previous: ProjectModel) -> (any Command)? {
        var snapshot = previous
        var inverses: [any Command] = []
        for command in commands {
            if let inverse = command.invert(previous: snapshot) {
                inverses.append(inverse)
            }
            command.apply(to: &snapshot)
        }
        guard !inverses.isEmpty else {
            return nil
        }
        return CommandBatch(commands: inverses.reversed())
    }

    func serializeToPython() -> String {
        commands.map { $0.serializeToPython() }.joined(separator: "\n")
    }
}
