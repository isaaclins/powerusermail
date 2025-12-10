import Foundation

struct CommandAction: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    let keywords: [String]
    let iconSystemName: String
    let iconColor: CommandIconColor
    var shortcut: String
    let perform: () -> Void
    var isEnabled: Bool
    var isContextual: Bool
    var showInPalette: Bool

    init(
        id: UUID = UUID(), 
        title: String, 
        subtitle: String = "",
        keywords: [String] = [], 
        iconSystemName: String = "command", 
        iconColor: CommandIconColor = .purple,
        shortcut: String = "",
        isEnabled: Bool = true, 
        isContextual: Bool = false, 
        showInPalette: Bool = true,
        perform: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.iconSystemName = iconSystemName
        self.iconColor = iconColor
        self.shortcut = shortcut
        self.perform = perform
        self.isEnabled = isEnabled
        self.isContextual = isContextual
        self.showInPalette = showInPalette
    }
}

enum CommandIconColor {
    case purple, blue, orange, red, green, yellow, gray, pink
    
    var color: Color {
        switch self {
        case .purple: return .purple
        case .blue: return .blue
        case .orange: return .orange
        case .red: return .red
        case .green: return .green
        case .yellow: return .yellow
        case .gray: return .gray
        case .pink: return .pink
        }
    }
}

import SwiftUI

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
