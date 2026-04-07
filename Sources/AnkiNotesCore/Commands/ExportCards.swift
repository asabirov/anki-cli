import ArgumentParser
import Foundation

public struct ExportCards: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export flashcards as JSON, CSV, or TSV"
    )

    @Option(name: .shortAndLong, help: "Output format: json, csv, tsv")
    var format: String = "json"

    @Option(name: .shortAndLong, help: "Filter by tag")
    var tag: String?

    @Option(name: .long, help: "Filter by type: new, learning, review")
    var type: String?

    @Flag(name: .long, help: "Include archived cards")
    var archived: Bool = false

    @Option(name: .shortAndLong, help: "Output file (stdout if omitted)")
    var output: String?

    @Option(name: .long, help: "Path to database")
    var db: String?

    public init() {}

    public func run() throws {
        let database = try openDatabase(path: db)
        let cardType = type.flatMap { CardType(rawValue: Int64(["new": 0, "learning": 1, "review": 2][$0] ?? -1)) }

        let cards = try database.listFlashcards(
            limit: 100_000,
            tag: tag,
            type: cardType,
            archived: archived
        )

        let content: String
        switch format.lowercased() {
        case "csv":
            content = exportCSV(cards, separator: ",")
        case "tsv":
            content = exportCSV(cards, separator: "\t")
        default:
            content = exportJSON(cards)
        }

        if let outputPath = output {
            try content.write(toFile: outputPath, atomically: true, encoding: .utf8)
            fputs("Exported \(cards.count) cards to \(outputPath)\n", stderr)
        } else {
            print(content)
        }
    }

    private func exportJSON(_ cards: [Flashcard]) -> String {
        let output: [[String: Any]] = cards.map { card in
            var dict: [String: Any] = [
                "id": card.id,
                "front": card.frontPlain,
                "back": card.backPlain,
                "frontHTML": card.front,
                "backHTML": card.back,
                "type": card.type.description,
                "queue": card.queue.description,
                "interval": card.interval,
                "repetitions": card.repetitions,
                "lapses": card.lapses,
                "easeFactor": card.easeFactor,
                "isFavorite": card.isFavorite,
                "isArchived": card.isArchived,
                "tags": card.tags,
            ]
            if let date = card.modificationDate {
                dict["modificationDate"] = ISO8601DateFormatter().string(from: date)
            }
            if let date = card.nextDate {
                dict["nextDate"] = ISO8601DateFormatter().string(from: date)
            }
            return dict
        }

        if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "[]"
    }

    private func exportCSV(_ cards: [Flashcard], separator: String) -> String {
        var lines: [String] = []
        let header = ["id", "front", "back", "type", "interval", "repetitions",
                      "lapses", "ease", "favorite", "archived", "tags"].joined(separator: separator)
        lines.append(header)

        for card in cards {
            let fields = [
                String(card.id),
                csvEscape(card.frontPlain, separator: separator),
                csvEscape(card.backPlain, separator: separator),
                card.type.description,
                String(card.interval),
                String(card.repetitions),
                String(card.lapses),
                String(format: "%.2f", card.easeFactor),
                card.isFavorite ? "1" : "0",
                card.isArchived ? "1" : "0",
                csvEscape(card.tags.joined(separator: ";"), separator: separator),
            ]
            lines.append(fields.joined(separator: separator))
        }

        return lines.joined(separator: "\n")
    }

    private func csvEscape(_ value: String, separator: String) -> String {
        if value.contains(separator) || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
