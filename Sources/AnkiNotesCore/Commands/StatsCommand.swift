import ArgumentParser
import Foundation

public struct StatsCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "Show deck statistics"
    )

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Option(name: .long, help: "Path to database")
    var db: String?

    public init() {}

    public func run() throws {
        let database = try openDatabase(path: db)
        let stats = try database.getStats()

        if json {
            let dict: [String: Any] = [
                "totalCards": stats.totalCards,
                "newCards": stats.newCards,
                "learningCards": stats.learningCards,
                "reviewCards": stats.reviewCards,
                "suspendedCards": stats.suspendedCards,
                "favoriteCards": stats.favoriteCards,
                "archivedCards": stats.archivedCards,
                "totalNotes": stats.totalNotes,
                "totalTags": stats.totalTags,
                "averageEase": stats.averageEase,
                "averageInterval": stats.averageInterval,
                "dueToday": stats.dueToday,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            print("Anki Notes Statistics")
            print(String(repeating: "═", count: 35))
            print()
            print("Cards")
            print("  Total:       \(stats.totalCards)")
            print("  New:         \(stats.newCards)")
            print("  Learning:    \(stats.learningCards)")
            print("  Review:      \(stats.reviewCards)")
            print("  Suspended:   \(stats.suspendedCards)")
            print("  Favorites:   \(stats.favoriteCards)")
            print("  Archived:    \(stats.archivedCards)")
            print()
            print("Content")
            print("  Notes:       \(stats.totalNotes)")
            print("  Tags:        \(stats.totalTags)")
            print()
            print("SRS")
            if stats.averageEase > 0 {
                print("  Avg ease:    \(String(format: "%.1f", stats.averageEase))")
            }
            if stats.averageInterval > 0 {
                print("  Avg interval: \(formatInterval(Int64(stats.averageInterval)))")
            }
            print("  Due today:   \(stats.dueToday)")
        }
    }
}
