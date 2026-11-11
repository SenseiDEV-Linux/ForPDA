//
//  QMSMessage.swift
//  ForPDA
//
//  Created by Ilia Lubianoi on 17.11.2024.
//

import Foundation

public struct QMSMessage: Sendable, Codable, Hashable, Identifiable {
    public let id: Int
    public let senderId: Int
    public let date: Date
    public let text: String
    public let attachments: [Attachment]
    
    public var processedText: String {
        let textAttachments = attachments.filter {
            $0.type == .file || $0.metadata == nil
        }
        guard !textAttachments.isEmpty else { return text }
        
        let attachmentsText = textAttachments
            .map { "[attachment=\($0.name),\($0.id),\($0.size)]" }
            .joined(separator: "\n\n")
        return attachmentsText + (text.isEmpty ? "" : "\n\n\(text)")
    }
    
    public init(
        id: Int,
        senderId: Int,
        date: Date,
        text: String,
        attachments: [Attachment]
    ) {
        self.id = id
        self.senderId = senderId
        self.date = date
        self.text = text
        self.attachments = attachments
    }
}

// MARK: - Mock

public extension QMSMessage {
    
    static func mock() -> QMSMessage {
        let id = Int.random(in: 0...100000)
        return QMSMessage(
            id: id,
            senderId: 1,
            date: .now,
            text: "test \(id)",
            attachments: []
        )
    }
}
