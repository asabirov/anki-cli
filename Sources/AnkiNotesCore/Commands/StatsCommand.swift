import ArgumentParser
import Foundation

public struct StatsCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "Show deck statistics dashboard"
    )

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Option(name: .long, help: "Path to database")
    var db: String?

    public init() {}

    public func run() throws {
        let database = try openDatabase(path: db)
        let dash = try database.getDashboardStats()

        if json {
            printJSON(dash)
        } else {
            printDashboard(dash)
        }
    }

    // MARK: - Dashboard View

    private func printDashboard(_ d: DashboardStats) {
        let s = d.deck
        let w = 55  // total width

        print("Anki Notes Dashboard")
        print(String(repeating: "═", count: w))
        print()

        // Overview
        let overdueSuffix = d.overdueCards > 0 ? " (\(d.overdueCards) overdue)" : ""
        print("Overview        \(s.totalCards) cards | \(s.totalNotes) notes | \(s.totalTags) tags")
        print("Due today       \(s.dueToday) cards\(overdueSuffix)")
        print()

        // By Status
        let active = s.reviewCards + s.newCards + s.learningCards + s.suspendedCards
        print("By Status")
        printBar("  review", count: s.reviewCards, total: active)
        printBar("  new", count: s.newCards, total: active)
        printBar("  learning", count: s.learningCards, total: active)
        if s.suspendedCards > 0 {
            printBar("  suspended", count: s.suspendedCards, total: active)
        }
        print()

        // Maturity
        let matTotal = d.matureCards + d.youngCards + d.unseenCards
        print("Maturity")
        printBar("  mature (>21d)", count: d.matureCards, total: matTotal)
        printBar("  young (≤21d)", count: d.youngCards, total: matTotal)
        if d.unseenCards > 0 {
            printBar("  unseen", count: d.unseenCards, total: matTotal)
        }
        print()

        // Retention
        let retentionPct: Double
        if d.totalRepetitions > 0 {
            retentionPct = Double(d.totalRepetitions - d.totalLapses) / Double(d.totalRepetitions) * 100
        } else {
            retentionPct = 0
        }
        print("Retention       \(String(format: "%.1f", retentionPct))%  (\(d.totalRepetitions) reviews, \(d.totalLapses) lapses)")
        if s.averageEase > 0 {
            print("Avg ease        \(String(format: "%.1f", s.averageEase))  |  Avg interval: \(formatInterval(Int64(s.averageInterval)))")
        }
        print()

        // By Tag
        if !d.tagStats.isEmpty {
            print("By Tag")

            // Header
            let nameW = 16
            let cardsW = 8
            let retW = 10
            let ivlW = 10
            let matW = 10
            print("  " +
                  "Tag".padding(toLength: nameW, withPad: " ", startingAt: 0) +
                  "Cards".padding(toLength: cardsW, withPad: " ", startingAt: 0) +
                  "Retain".padding(toLength: retW, withPad: " ", startingAt: 0) +
                  "Avg ivl".padding(toLength: ivlW, withPad: " ", startingAt: 0) +
                  "Mature".padding(toLength: matW, withPad: " ", startingAt: 0))
            print("  " + String(repeating: "─", count: nameW + cardsW + retW + ivlW + matW))

            for tag in d.tagStats {
                let ret = String(format: "%.1f%%", tag.retentionPercent)
                let ivl = formatInterval(Int64(tag.averageInterval))
                let matPct = tag.totalCards > 0
                    ? String(format: "%.0f%%", Double(tag.matureCards) / Double(tag.totalCards) * 100)
                    : "-"
                print("  " +
                      truncate(tag.name, to: nameW - 1).padding(toLength: nameW, withPad: " ", startingAt: 0) +
                      String(tag.totalCards).padding(toLength: cardsW, withPad: " ", startingAt: 0) +
                      ret.padding(toLength: retW, withPad: " ", startingAt: 0) +
                      ivl.padding(toLength: ivlW, withPad: " ", startingAt: 0) +
                      matPct.padding(toLength: matW, withPad: " ", startingAt: 0))
            }
        }
    }

    // MARK: - Bar Chart

    private func printBar(_ label: String, count: Int64, total: Int64) {
        let barWidth = 20
        let pct = total > 0 ? Double(count) / Double(total) : 0
        let filled = Int(pct * Double(barWidth))
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: barWidth - filled)
        let pctStr = String(format: "%4.0f%%", pct * 100)
        let labelPad = label.padding(toLength: 18, withPad: " ", startingAt: 0)
        print("\(labelPad)\(bar) \(formatCount(count)) \(pctStr)")
    }

    private func formatCount(_ n: Int64) -> String {
        if n >= 1000 {
            return String(format: "%5.1fk", Double(n) / 1000)
        }
        return String(format: "%5d", n)
    }

    // MARK: - JSON

    private func printJSON(_ d: DashboardStats) {
        let retentionPct: Double
        if d.totalRepetitions > 0 {
            retentionPct = Double(d.totalRepetitions - d.totalLapses) / Double(d.totalRepetitions) * 100
        } else {
            retentionPct = 0
        }

        var dict: [String: Any] = [
            "totalCards": d.deck.totalCards,
            "newCards": d.deck.newCards,
            "learningCards": d.deck.learningCards,
            "reviewCards": d.deck.reviewCards,
            "suspendedCards": d.deck.suspendedCards,
            "favoriteCards": d.deck.favoriteCards,
            "archivedCards": d.deck.archivedCards,
            "totalNotes": d.deck.totalNotes,
            "totalTags": d.deck.totalTags,
            "averageEase": d.deck.averageEase,
            "averageInterval": d.deck.averageInterval,
            "dueToday": d.deck.dueToday,
            "matureCards": d.matureCards,
            "youngCards": d.youngCards,
            "unseenCards": d.unseenCards,
            "overdueCards": d.overdueCards,
            "totalLapses": d.totalLapses,
            "totalRepetitions": d.totalRepetitions,
            "retentionPercent": retentionPct,
        ]

        let tagsList: [[String: Any]] = d.tagStats.map { tag in
            [
                "name": tag.name,
                "totalCards": tag.totalCards,
                "totalLapses": tag.totalLapses,
                "totalRepetitions": tag.totalRepetitions,
                "averageInterval": tag.averageInterval,
                "averageEase": tag.averageEase,
                "matureCards": tag.matureCards,
                "youngCards": tag.youngCards,
                "retentionPercent": tag.retentionPercent,
            ]
        }
        dict["tags"] = tagsList

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }
}
