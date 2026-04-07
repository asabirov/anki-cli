import ArgumentParser
import Foundation

public struct ListCards: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "List flashcards"
    )

    @Option(name: .shortAndLong, help: "Maximum number of cards to show")
    var limit: Int = 30

    @Option(name: .long, help: "Number of cards to skip")
    var offset: Int = 0

    @Option(name: .shortAndLong, help: "Filter by tag (partial match)")
    var tag: String?

    @Option(name: .long, help: "Filter by type: new, learning, review")
    var type: String?

    @Option(name: .long, help: "Sort by: modified, due, created, ease, interval")
    var sort: String = "modified"

    @Flag(name: .long, help: "Sort ascending")
    var asc: Bool = false

    @Flag(name: .long, help: "Show only favorites")
    var favorites: Bool = false

    @Flag(name: .long, help: "Show archived cards")
    var archived: Bool = false

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Option(name: .long, help: "Path to database (auto-detected by default)")
    var db: String?

    public init() {}

    public func run() throws {
        let database = try openDatabase(path: db)
        let cardType = type.flatMap { CardType(rawValue: Int64(["new": 0, "learning": 1, "review": 2][$0] ?? -1)) }
        let sortField = SortField(rawValue: sort) ?? .modified

        let cards = try database.listFlashcards(
            limit: limit,
            offset: offset,
            tag: tag,
            type: cardType,
            favorites: favorites,
            archived: archived,
            sortBy: sortField,
            ascending: asc
        )

        if json {
            printJSON(cards)
        } else {
            printTable(cards)
        }
    }

    private func printTable(_ cards: [Flashcard]) {
        if cards.isEmpty {
            print("No flashcards found.")
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        print("ID".padding(toLength: 8, withPad: " ", startingAt: 0) +
              "Type".padding(toLength: 10, withPad: " ", startingAt: 0) +
              "Ivl".padding(toLength: 8, withPad: " ", startingAt: 0) +
              "Due".padding(toLength: 18, withPad: " ", startingAt: 0) +
              "Front")
        print(String(repeating: "─", count: 100))

        for card in cards {
            let fav = card.isFavorite ? "* " : ""
            let front = truncate("\(fav)\(card.frontPlain)", to: 55)
            let tags = card.tags.isEmpty ? "" : " [\(card.tags.joined(separator: ", "))]"
            let ivl = card.interval > 0 ? formatInterval(card.interval) : "-"
            let due = card.nextDate.map { dateFormatter.string(from: $0) } ?? "-"

            print(String(card.id).padding(toLength: 8, withPad: " ", startingAt: 0) +
                  card.type.description.padding(toLength: 10, withPad: " ", startingAt: 0) +
                  ivl.padding(toLength: 8, withPad: " ", startingAt: 0) +
                  due.padding(toLength: 18, withPad: " ", startingAt: 0) +
                  front + tags)
        }

        print("\n\(cards.count) cards")
    }

    private func printJSON(_ cards: [Flashcard]) {
        var output: [[String: Any]] = []
        for card in cards {
            var dict: [String: Any] = [
                "id": card.id,
                "front": card.frontPlain,
                "back": card.backPlain,
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
            output.append(dict)
        }
        if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }
}

func truncate(_ str: String, to length: Int) -> String {
    if str.count <= length { return str }
    return String(str.prefix(length - 1)) + "…"
}

func formatInterval(_ days: Int64) -> String {
    if days >= 365 {
        let years = Double(days) / 365.0
        return String(format: "%.1fy", years)
    } else if days >= 30 {
        let months = Double(days) / 30.0
        return String(format: "%.1fm", months)
    } else {
        return "\(days)d"
    }
}
