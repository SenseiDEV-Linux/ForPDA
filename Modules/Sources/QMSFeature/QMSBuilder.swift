//
//  QMSBuilder.swift
//  QMSFeature
//
//  Created by Ilia Lubianoi on 24.10.2025.
//

import BBBuilder
import Foundation
import Models
import UIKit

public struct QMSBuilder {
    
    private let text: String
    
    public init(text: String) {
        self.text = text
    }
    
    // TODO: Change to full BBBuilder with container nodes later
    public func build() -> AttributedString {
        let renderedText = BBRenderer().render(text: text)
        let result = NSMutableAttributedString(attributedString: renderedText)
        
        let pattern = #"\[attachment=([^,\]]+),(\d+)(?:,(\d+))?\]"#
        let regex = try! NSRegularExpression(pattern: pattern, options: [])

        let fullRange = NSRange(location: 0, length: result.length)
        let matches = regex.matches(in: result.string, options: [], range: fullRange).reversed()
        
        for match in matches {
            guard
                match.numberOfRanges == 4,
                let nameRange = Range(match.range(at: 1), in: result.string),
                let idRange = Range(match.range(at: 2), in: result.string)
            else { continue }

            let fileName = String(result.string[nameRange])
            let attachmentID = String(result.string[idRange])
            let fileSize = match.range(at: 3).location == NSNotFound
                ? nil
                : Int((result.string as NSString).substring(with: match.range(at: 3)))

            let downloadLink = "https://4pda.to/forum/dl/post/\(attachmentID)/\(fileName)"
            guard let encodedLink = downloadLink.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let downloadUrl = URL(string: encodedLink)
            else { continue }
            
            let icon = NSTextAttachment()
            icon.image = UIImage(systemName: fileSymbolName(for: fileName))?
                .withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
            icon.bounds = CGRect(x: 0, y: -3, width: 17, height: 17)
            
            let fileCard = NSMutableAttributedString(attachment: icon)
            fileCard.append(NSAttributedString(string: " "))
            let name = NSMutableAttributedString(string: fileName)
            name.addAttribute(.link, value: downloadUrl, range: NSRange(location: 0, length: name.length))
            fileCard.append(name)
            
            if let fileSize {
                let sizeText = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
                fileCard.append(NSAttributedString(
                    string: "  \(sizeText)",
                    attributes: [
                        .font: UIFont.preferredFont(forTextStyle: .caption2),
                        .foregroundColor: UIColor.secondaryLabel
                    ]
                ))
            }
            fileCard.addAttribute(.link, value: downloadUrl, range: NSRange(location: 0, length: fileCard.length))
            result.replaceCharacters(in: match.range, with: fileCard)
        }
        
        return AttributedString(result)
    }
    
    private func fileSymbolName(for fileName: String) -> String {
        switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "webp":
            return "photo"
        case "mp3", "m4a", "wav", "aac", "flac", "ogg":
            return "music.note"
        case "mp4", "mov", "m4v", "avi", "mkv":
            return "video"
        case "zip", "rar", "7z", "gz", "tar":
            return "archivebox"
        case "pdf":
            return "doc.richtext"
        default:
            return "doc"
        }
    }
}
