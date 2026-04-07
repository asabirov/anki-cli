import ArgumentParser
import Foundation

public struct SearchCards: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search flashcards by text"
    )

    @Argument(help: "Search term")
    var query: String

    @Option(name: .shortAndLong, help: "Maximum results")
    var limit: Int = 30

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Option(name: .long, help: "Path to database")
    var db: String?

    public init() {}

    public func run() throws {
        let database = try openDatabase(path: db)
        let cards = try database.searchFlashcards(query: query, limit: limit)

        if json {
            printJSON(cards)
        } else {
            if cards.isEmpty {
                print("No cards matching \"\(query)\".")
                return
            }

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

            print("ID".padding(toLength: 8, withPad: " ", startingAt: 0) +
                  "Type".padding(toLength: 10, withPad: " ", startingAt: 0) +
                  "Front".padding(toLength: 45, withPad: " ", startingAt: 0) +
                  "Back")
            print(String(repeating: "─", count: 100))

            for card in cards {
                let front = truncate(card.frontPlain, to: 43)
                let back = truncate(card.backPlain, to: 40)
                print(String(card.id).padding(toLength: 8, withPad: " ", startingAt: 0) +
                      card.type.description.padding(toLength: 10, withPad: " ", startingAt: 0) +
                      front.padding(toLength: 45, withPad: " ", startingAt: 0) +
                      back)
            }

            print("\n\(cards.count) results")
        }
    }

    private func printJSON(_ cards: [Flashcard]) {
        let output: [[String: Any]] = cards.map { card in
            var dict: [String: Any] = [
                "id": card.id,
                "front": card.frontPlain,
                "back": card.backPlain,
                "type": card.type.description,
                "tags": card.tags,
            ]
            if let date = card.modificationDate {
                dict["modificationDate"] = ISO8601DateFormatter().string(from: date)
            }
            return dict
        }
        if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }
}
