import Foundation

struct CommandAction: Identifiable {
    let id: UUID
    let title: String
    let keywords: [String]
    let iconSystemName: String
    let perform: () -> Void
    var isEnabled: Bool
    var isContextual: Bool

    init(id: UUID = UUID(), title: String, keywords: [String] = [], iconSystemName: String = "command", isEnabled: Bool = true, isContextual: Bool = false, perform: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.iconSystemName = iconSystemName
        self.perform = perform
        self.isEnabled = isEnabled
        self.isContextual = isContextual
    }
}

protocol Command {
    var name: String { get }
    var keywords: [String] { get }
    var iconSystemName: String { get }
    func execute()
}

struct AnyCommand: Command {
    let name: String
    let keywords: [String]
    let iconSystemName: String
    private let action: () -> Void

    init(name: String, keywords: [String] = [], iconSystemName: String = "command", action: @escaping () -> Void) {
        self.name = name
        self.keywords = keywords
        self.iconSystemName = iconSystemName
        self.action = action
    }

    func execute() {
        action()
    }
}

final class CommandInvoker {
    static let shared = CommandInvoker()
    private init() {}

    func invoke(_ command: Command) {
        command.execute()
    }
}
