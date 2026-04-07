import Foundation

// MARK: - Domain Models

public struct Flashcard {
    public let id: Int64
    public let front: String
    public let back: String
    public let type: CardType
    public let queue: CardQueue
    public let due: Int64
    public let interval: Int64
    public let repetitions: Int64
    public let lapses: Int64
    public let easeFactor: Double
    public let isFavorite: Bool
    public let isArchived: Bool
    public let noteID: Int64?
    public let source: String?
    public let author: String?
    public let modificationDate: Date?
    public let nextDate: Date?
    public let previousDate: Date?
    public let tags: [String]

    /// Front text with HTML stripped
    public var frontPlain: String { Self.stripHTML(front) }

    /// Back text with HTML stripped
    public var backPlain: String { Self.stripHTML(back) }

    static func stripHTML(_ html: String) -> String {
        guard !html.isEmpty else { return html }
        // Remove HTML tags
        var result = html.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        // Decode common entities
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        // Collapse whitespace
        result = result.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
}

public enum CardType: Int64, CustomStringConvertible {
    case new = 0
    case learning = 1
    case review = 2

    public var description: String {
        switch self {
        case .new: return "new"
        case .learning: return "learning"
        case .review: return "review"
        }
    }
}

public enum CardQueue: Int64, CustomStringConvertible {
    case new = 0
    case learning = 1
    case review = 2
    case suspended = 3

    public var description: String {
        switch self {
        case .new: return "new"
        case .learning: return "learning"
        case .review: return "review"
        case .suspended: return "suspended"
        }
    }
}

public struct Note {
    public let id: Int64
    public let modelID: Int64?
    public let fields: String  // raw "front\u{1F}back" format
    public let flashcardCount: Int64

    /// Parse the fields string into individual field values
    public var fieldValues: [String] {
        fields.components(separatedBy: "\u{1F}")
    }

    public var front: String { fieldValues.first ?? "" }
    public var back: String { fieldValues.count > 1 ? fieldValues[1] : "" }
}

public struct Tag {
    public let id: Int64
    public let name: String
    public let flashcardCount: Int64
}

public struct CardModel {
    public let id: Int64
    public let name: String
    public let type: Int64
    public let css: String?
}

// MARK: - Stats

public struct DeckStats {
    public let totalCards: Int64
    public let newCards: Int64
    public let learningCards: Int64
    public let reviewCards: Int64
    public let suspendedCards: Int64
    public let favoriteCards: Int64
    public let archivedCards: Int64
    public let totalNotes: Int64
    public let totalTags: Int64
    public let averageEase: Double
    public let averageInterval: Double
    public let dueToday: Int64
}

public struct DashboardStats {
    public let deck: DeckStats
    public let matureCards: Int64    // interval > 21 days
    public let youngCards: Int64     // interval 1-21 days
    public let unseenCards: Int64    // interval = 0
    public let overdueCards: Int64
    public let totalLapses: Int64
    public let totalRepetitions: Int64
    public let tagStats: [TagStats]
    public let pastReviews: [DayCount]   // cards reviewed per day (by ZMOD)
    public let futureDue: [DayCount]     // cards due per day (by ZNEXTDATE)
    public let overdueBreakdown: OverdueBreakdown
}

public struct DayCount {
    public let date: String   // yyyy-MM-dd
    public let count: Int64
}

public struct OverdueBreakdown {
    public let last7d: Int64
    public let last30d: Int64
    public let last90d: Int64
    public let older: Int64
}

public struct TagStats {
    public let name: String
    public let totalCards: Int64
    public let totalLapses: Int64
    public let totalRepetitions: Int64
    public let averageInterval: Double
    public let averageEase: Double
    public let matureCards: Int64
    public let youngCards: Int64

    public var retentionPercent: Double {
        guard totalRepetitions > 0 else { return 0 }
        return Double(totalRepetitions - totalLapses) / Double(totalRepetitions) * 100
    }
}
