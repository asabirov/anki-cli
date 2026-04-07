import ArgumentParser
import Foundation

public struct ExtractCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "extract",
        abstract: "Extract all cards to markdown files with media"
    )

    @Argument(help: "Output directory")
    var output: String

    @Option(name: .shortAndLong, help: "Filter by tag")
    var tag: String?

    @Option(name: .long, help: "Filter by type: new, learning, review")
    var type: String?

    @Flag(name: .long, help: "Include archived cards")
    var archived: Bool = false

    @Flag(name: .long, help: "Strip HTML from card content (default: keep HTML)")
    var plain: Bool = false

    @Option(name: .long, help: "Path to database")
    var db: String?

    public init() {}

    public func run() throws {
        let database = try openDatabase(path: db)
        let cardType = type.flatMap { CardType(rawValue: Int64(["new": 0, "learning": 1, "review": 2][$0] ?? -1)) }

        let cards = try database.listFlashcards(
            limit: 1_000_000,
            tag: tag,
            type: cardType,
            archived: archived
        )

        let fm = FileManager.default
        let cardsDir = (output as NSString).appendingPathComponent("cards")
        let mediaDir = (output as NSString).appendingPathComponent("media")
        try fm.createDirectory(atPath: cardsDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: mediaDir, withIntermediateDirectories: true)

        let isoFormatter = ISO8601DateFormatter()
        var indexEntries: [[String: Any]] = []
        var mediaCount = 0

        for (i, card) in cards.enumerated() {
            // Extract media for this card
            var cardMediaFiles: [String] = []

            // 1. ZMEDIA attachments
            let mediaItems = try database.mediaForFlashcard(id: card.id)
            for (fname, data) in mediaItems {
                let ext = (fname as NSString).pathExtension
                let safeName = ext.isEmpty ? "\(card.id)-\(fname).bin" : "\(card.id)-\(fname)"
                let mediaPath = (mediaDir as NSString).appendingPathComponent(safeName)
                try data.write(to: URL(fileURLWithPath: mediaPath))
                cardMediaFiles.append("media/\(safeName)")
                mediaCount += 1
            }

            // 2. ZIMAGEDATA embedded image
            if let imageData = try database.imageDataForFlashcard(id: card.id) {
                let ext = detectImageExtension(imageData)
                let imageName = "\(card.id)-image.\(ext)"
                let imagePath = (mediaDir as NSString).appendingPathComponent(imageName)
                try imageData.write(to: URL(fileURLWithPath: imagePath))
                cardMediaFiles.append("media/\(imageName)")
                mediaCount += 1
            }

            // Build markdown
            let front = plain ? card.frontPlain : card.front
            let back = plain ? card.backPlain : card.back
            var md = buildFrontmatter(card: card, mediaFiles: cardMediaFiles, formatter: isoFormatter)
            md += "\n## Front\n\n\(front)\n\n## Back\n\n\(back)\n"

            if !cardMediaFiles.isEmpty {
                md += "\n## Media\n\n"
                for file in cardMediaFiles {
                    md += "- [\(file)](../\(file))\n"
                }
            }

            let cardPath = (cardsDir as NSString).appendingPathComponent("\(card.id).md")
            try md.write(toFile: cardPath, atomically: true, encoding: .utf8)

            // Index entry
            var entry: [String: Any] = [
                "id": card.id,
                "front": card.frontPlain,
                "back": card.backPlain,
                "type": card.type.description,
                "tags": card.tags,
                "interval": card.interval,
                "repetitions": card.repetitions,
                "lapses": card.lapses,
                "easeFactor": card.easeFactor,
                "isFavorite": card.isFavorite,
                "isArchived": card.isArchived,
                "file": "cards/\(card.id).md",
            ]
            if !cardMediaFiles.isEmpty {
                entry["media"] = cardMediaFiles
            }
            if let date = card.modificationDate {
                entry["modificationDate"] = isoFormatter.string(from: date)
            }
            if let date = card.nextDate {
                entry["nextDate"] = isoFormatter.string(from: date)
            }
            indexEntries.append(entry)

            // Progress
            if (i + 1) % 500 == 0 || i == cards.count - 1 {
                fputs("\r\(i + 1)/\(cards.count) cards extracted", stderr)
            }
        }
        fputs("\n", stderr)

        // Write index.json
        let indexPath = (output as NSString).appendingPathComponent("index.json")
        if let data = try? JSONSerialization.data(withJSONObject: indexEntries, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            try str.write(toFile: indexPath, atomically: true, encoding: .utf8)
        }

        print("Extracted \(cards.count) cards to \(output)/")
        print("  cards/    \(cards.count) markdown files")
        print("  media/    \(mediaCount) files")
        print("  index.json")
    }

    private func buildFrontmatter(card: Flashcard, mediaFiles: [String], formatter: ISO8601DateFormatter) -> String {
        var lines: [String] = ["---"]
        lines.append("id: \(card.id)")
        lines.append("type: \(card.type)")
        lines.append("queue: \(card.queue)")
        if !card.tags.isEmpty {
            lines.append("tags: [\(card.tags.map { "\"\($0)\"" }.joined(separator: ", "))]")
        }
        if card.isFavorite { lines.append("favorite: true") }
        if card.isArchived { lines.append("archived: true") }
        lines.append("interval: \(card.interval)")
        lines.append("repetitions: \(card.repetitions)")
        lines.append("lapses: \(card.lapses)")
        if card.easeFactor > 0 {
            lines.append("ease: \(String(format: "%.1f", card.easeFactor))")
        }
        if let date = card.modificationDate {
            lines.append("modified: \(formatter.string(from: date))")
        }
        if let date = card.nextDate {
            lines.append("nextDate: \(formatter.string(from: date))")
        }
        if !mediaFiles.isEmpty {
            lines.append("media:")
            for f in mediaFiles {
                lines.append("  - \(f)")
            }
        }
        lines.append("---")
        return lines.joined(separator: "\n") + "\n"
    }

    private func detectImageExtension(_ data: Data) -> String {
        guard data.count >= 4 else { return "bin" }
        if data[0] == 0xFF && data[1] == 0xD8 { return "jpg" }
        if data[0] == 0x89 && data[1] == 0x50 { return "png" }
        if data[0] == 0x47 && data[1] == 0x49 { return "gif" }
        if data[0] == 0x52 && data[1] == 0x49 { return "webp" }
        return "bin"
    }
}
