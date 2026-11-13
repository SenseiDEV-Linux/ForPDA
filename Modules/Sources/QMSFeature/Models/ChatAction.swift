//
//  ChatAction.swift
//  ForPDA
//
//  Created by Ilia Lubianoi on 29.11.2025.
//

import ExyteChat
import SwiftUI

enum ChatAction: MessageMenuAction {
    case copy
    case saveToPhotos
    case saveToFiles
    case delete
    
    func title() -> String {
        switch self {
        case .copy:
            return String(localized: "Copy", bundle: .module)
        case .saveToPhotos:
            return String(localized: "qms.image.save.photos", bundle: .module)
        case .saveToFiles:
            return String(localized: "qms.image.save.files", bundle: .module)
        case .delete:
            return String(localized: "qms.message.delete", bundle: .module)
        }
    }
    
    func icon() -> Image {
        switch self {
        case .copy:
            return Image(systemSymbol: .clipboard)
        case .saveToPhotos:
            return Image(systemName: "square.and.arrow.down")
        case .saveToFiles:
            return Image(systemName: "folder")
        case .delete:
            return Image(systemName: "trash")
        }
    }

    static func menuItems(for message: Message) -> [ChatAction] {
        var actions: [ChatAction] = message.text.isEmpty ? [] : [.copy]
        if message.attachments.contains(where: { $0.type == .image }) {
            actions += [.saveToPhotos, .saveToFiles]
        }
        actions.append(.delete)
        return actions
    }
}
