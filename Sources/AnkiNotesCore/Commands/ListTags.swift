import ArgumentParser
import Foundation

public struct ListTags: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "tags",
        abstract: "List all tags"
    )

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Option(name: .long, help: "Path to database")
    var db: String?

    public init() {}

    public func run() throws {
        let database = try openDatabase(path: db)
        let tags = try database.listTags()

        if json {
            let output: [[String: Any]] = tags.map {
                ["id": $0.id, "name": $0.name, "flashcardCount": $0.flashcardCount]
            }
            if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            if tags.isEmpty {
                print("No tags found.")
                return
            }

            print("ID".padding(toLength: 8, withPad: " ", startingAt: 0) +
                  "Cards".padding(toLength: 10, withPad: " ", startingAt: 0) +
                  "Name")
            print(String(repeating: "─", count: 50))

            for tag in tags {
                print(String(tag.id).padding(toLength: 8, withPad: " ", startingAt: 0) +
                      String(tag.flashcardCount).padding(toLength: 10, withPad: " ", startingAt: 0) +
                      tag.name)
            }

            print("\n\(tags.count) tags")
        }
    }
}
