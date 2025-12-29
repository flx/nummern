import Foundation

final class TransactionManager {
    private var currentTransaction: CommandTransaction?
    private(set) var transactions: [CommandTransaction] = []

    func begin(kind: TransactionKind = .general) {
        currentTransaction = CommandTransaction(id: ModelID.make(), timestamp: Date(), kind: kind, commands: [])
    }

    func record(_ command: any Command) {
        if currentTransaction == nil {
            begin()
        }

        guard var current = currentTransaction else {
            return
        }

        if current.kind == .cellEdit, let setCells = command as? SetCellsCommand {
            if let last = current.commands.last as? SetCellsCommand,
               let merged = last.merged(with: setCells) {
                current.commands.removeLast()
                current.commands.append(merged)
                currentTransaction = current
                return
            }
        }

        current.commands.append(command)
        currentTransaction = current
    }

    @discardableResult
    func commit() -> CommandTransaction? {
        guard let current = currentTransaction else {
            return nil
        }
        transactions.append(current)
        currentTransaction = nil
        return current
    }

    func allCommands() -> [String] {
        transactions.flatMap { $0.commands.map { $0.serializeToPython() } }
    }

    func pythonLog() -> String {
        allCommands().joined(separator: "\n")
    }

    func reset() {
        currentTransaction = nil
        transactions = []
    }
}
