import ArgumentParser
import Foundation

public struct GetCard: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "View a flashcard by ID"
    )

    @Argument(help: "Flashcard ID")
    var id: Int64

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Flag(name: .long, help: "Show raw HTML content")
    var raw: Bool = false

    @Option(name: .long, help: "Path to database")
    var db: String?

    public init() {}

    public func run() throws {
        let database = try openDatabase(path: db)
        guard let card = try database.getFlashcard(id: id) else {
            throw AnkiCLIError.cardNotFound(id)
        }

        if json {
            printJSON(card)
        } else {
            printDetail(card)
        }
    }

    private func printDetail(_ card: Flashcard) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        print("ID:          \(card.id)")
        print("Type:        \(card.type)")
        print("Queue:       \(card.queue)")
        print("Favorite:    \(card.isFavorite ? "yes" : "no")")
        print("Archived:    \(card.isArchived ? "yes" : "no")")
        if !card.tags.isEmpty {
            print("Tags:        \(card.tags.joined(separator: ", "))")
        }
        print()

        print("── Front ──")
        print(raw ? card.front : card.frontPlain)
        print()
        print("── Back ──")
        print(raw ? card.back : card.backPlain)
        print()

        print("── SRS ──")
        print("Interval:    \(card.interval > 0 ? formatInterval(card.interval) : "n/a")")
        print("Repetitions: \(card.repetitions)")
        print("Lapses:      \(card.lapses)")
        if card.easeFactor > 0 {
            print("Ease:        \(String(format: "%.1f", card.easeFactor))")
        }
        if let next = card.nextDate {
            print("Next review: \(dateFormatter.string(from: next))")
        }
        if let prev = card.previousDate {
            print("Last review: \(dateFormatter.string(from: prev))")
        }
        if let mod = card.modificationDate {
            print("Modified:    \(dateFormatter.string(from: mod))")
        }
    }

    private func printJSON(_ card: Flashcard) {
        var dict: [String: Any] = [
            "id": card.id,
            "front": card.frontPlain,
            "frontHTML": card.front,
            "back": card.backPlain,
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
        if let date = card.previousDate {
            dict["previousDate"] = ISO8601DateFormatter().string(from: date)
        }
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }
}
