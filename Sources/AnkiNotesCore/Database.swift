import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

/// Read-only access to the Anki Notes local SQLite database.
public final class AnkiDatabase {
    private let db: OpaquePointer

    public static let defaultPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Containers/maccatalyst.social.street.MemoryAssistant/Data/Library/Application Support/Anki Notes/Model1.sqlite"
    }()

    public init(path: String? = nil) throws {
        let dbPath = path ?? Self.defaultPath
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw AnkiCLIError.databaseNotFound(dbPath)
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(dbPath, &handle, flags, nil)
        guard rc == SQLITE_OK, let h = handle else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let h = handle { sqlite3_close(h) }
            throw AnkiCLIError.databaseError("Failed to open database: \(msg)")
        }
        self.db = h
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Flashcards

    public func listFlashcards(
        limit: Int = 50,
        offset: Int = 0,
        tag: String? = nil,
        type: CardType? = nil,
        queue: CardQueue? = nil,
        favorites: Bool = false,
        archived: Bool = false,
        sortBy: SortField = .modified,
        ascending: Bool = false
    ) throws -> [Flashcard] {
        var conditions: [String] = []
        var params: [Any] = []

        if favorites {
            conditions.append("f.ZISFAVORITE = 1")
        }
        if archived {
            conditions.append("f.ZISARCHIVED = 1")
        } else {
            conditions.append("f.ZISARCHIVED = 0")
        }
        if let type = type {
            conditions.append("f.ZTYPE = ?")
            params.append(type.rawValue)
        }
        if let queue = queue {
            conditions.append("f.ZQUEUE = ?")
            params.append(queue.rawValue)
        }

        var joinClause = ""
        if let tag = tag {
            joinClause = """
                JOIN Z_1TAGS jt ON jt.Z_1FLASHCARDS = f.Z_PK
                JOIN ZCOREDATATAG t ON t.Z_PK = jt.Z_2TAGS
            """
            conditions.append("LOWER(t.ZNAME) LIKE LOWER(?)")
            params.append("%\(tag)%")
        }

        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")

        let orderColumn: String
        switch sortBy {
        case .modified: orderColumn = "f.ZMOD"
        case .due: orderColumn = "f.ZDUE"
        case .created: orderColumn = "f.ZRECORDDATE"
        case .ease: orderColumn = "f.ZEASINESSFACTOR"
        case .interval: orderColumn = "f.ZIVL"
        }
        let direction = ascending ? "ASC" : "DESC"

        let sql = """
            SELECT DISTINCT f.Z_PK, f.ZFRONT, f.ZBACK, f.ZTYPE, f.ZQUEUE, f.ZDUE,
                   f.ZIVL, f.ZREPETITION, f.ZLAPSES, f.ZEASINESSFACTOR,
                   f.ZISFAVORITE, f.ZISARCHIVED, f.ZNOTE, f.ZSOURCE, f.ZAUTHOR,
                   f.ZMOD, f.ZNEXTDATE, f.ZPREVIOUSDATE
            FROM ZCOREDATAFLASHCARD f
            \(joinClause)
            \(whereClause)
            ORDER BY \(orderColumn) \(direction)
            LIMIT ? OFFSET ?
        """
        params.append(limit)
        params.append(offset)

        var cards: [Flashcard] = []
        try query(sql, params: params) { stmt in
            let id = sqlite3_column_int64(stmt, 0)
            let tags = try self.tagsForFlashcard(id: id)
            cards.append(Flashcard(
                id: id,
                front: columnText(stmt, 1),
                back: columnText(stmt, 2),
                type: CardType(rawValue: sqlite3_column_int64(stmt, 3)) ?? .new,
                queue: CardQueue(rawValue: sqlite3_column_int64(stmt, 4)) ?? .new,
                due: sqlite3_column_int64(stmt, 5),
                interval: sqlite3_column_int64(stmt, 6),
                repetitions: sqlite3_column_int64(stmt, 7),
                lapses: sqlite3_column_int64(stmt, 8),
                easeFactor: sqlite3_column_double(stmt, 9),
                isFavorite: sqlite3_column_int64(stmt, 10) == 1,
                isArchived: sqlite3_column_int64(stmt, 11) == 1,
                noteID: sqlite3_column_type(stmt, 12) != SQLITE_NULL ? sqlite3_column_int64(stmt, 12) : nil,
                source: columnTextOptional(stmt, 13),
                author: columnTextOptional(stmt, 14),
                modificationDate: columnDate(stmt, 15),
                nextDate: columnDate(stmt, 16),
                previousDate: columnDate(stmt, 17),
                tags: tags
            ))
        }
        return cards
    }

    public func getFlashcard(id: Int64) throws -> Flashcard? {
        let sql = """
            SELECT f.Z_PK, f.ZFRONT, f.ZBACK, f.ZTYPE, f.ZQUEUE, f.ZDUE,
                   f.ZIVL, f.ZREPETITION, f.ZLAPSES, f.ZEASINESSFACTOR,
                   f.ZISFAVORITE, f.ZISARCHIVED, f.ZNOTE, f.ZSOURCE, f.ZAUTHOR,
                   f.ZMOD, f.ZNEXTDATE, f.ZPREVIOUSDATE
            FROM ZCOREDATAFLASHCARD f
            WHERE f.Z_PK = ?
        """
        var card: Flashcard?
        try query(sql, params: [id]) { stmt in
            let tags = try self.tagsForFlashcard(id: id)
            card = Flashcard(
                id: id,
                front: columnText(stmt, 1),
                back: columnText(stmt, 2),
                type: CardType(rawValue: sqlite3_column_int64(stmt, 3)) ?? .new,
                queue: CardQueue(rawValue: sqlite3_column_int64(stmt, 4)) ?? .new,
                due: sqlite3_column_int64(stmt, 5),
                interval: sqlite3_column_int64(stmt, 6),
                repetitions: sqlite3_column_int64(stmt, 7),
                lapses: sqlite3_column_int64(stmt, 8),
                easeFactor: sqlite3_column_double(stmt, 9),
                isFavorite: sqlite3_column_int64(stmt, 10) == 1,
                isArchived: sqlite3_column_int64(stmt, 11) == 1,
                noteID: sqlite3_column_type(stmt, 12) != SQLITE_NULL ? sqlite3_column_int64(stmt, 12) : nil,
                source: columnTextOptional(stmt, 13),
                author: columnTextOptional(stmt, 14),
                modificationDate: columnDate(stmt, 15),
                nextDate: columnDate(stmt, 16),
                previousDate: columnDate(stmt, 17),
                tags: tags
            )
        }
        return card
    }

    public func searchFlashcards(query searchTerm: String, limit: Int = 50) throws -> [Flashcard] {
        let sql = """
            SELECT DISTINCT f.Z_PK, f.ZFRONT, f.ZBACK, f.ZTYPE, f.ZQUEUE, f.ZDUE,
                   f.ZIVL, f.ZREPETITION, f.ZLAPSES, f.ZEASINESSFACTOR,
                   f.ZISFAVORITE, f.ZISARCHIVED, f.ZNOTE, f.ZSOURCE, f.ZAUTHOR,
                   f.ZMOD, f.ZNEXTDATE, f.ZPREVIOUSDATE
            FROM ZCOREDATAFLASHCARD f
            LEFT JOIN ZNOTE n ON f.ZNOTE = n.Z_PK
            WHERE f.ZFRONT LIKE ? OR f.ZBACK LIKE ? OR n.ZFLDS LIKE ?
            ORDER BY f.ZMOD DESC
            LIMIT ?
        """
        let pattern = "%\(searchTerm)%"

        var cards: [Flashcard] = []
        try query(sql, params: [pattern, pattern, pattern, limit]) { stmt in
            let id = sqlite3_column_int64(stmt, 0)
            let tags = try self.tagsForFlashcard(id: id)
            cards.append(Flashcard(
                id: id,
                front: columnText(stmt, 1),
                back: columnText(stmt, 2),
                type: CardType(rawValue: sqlite3_column_int64(stmt, 3)) ?? .new,
                queue: CardQueue(rawValue: sqlite3_column_int64(stmt, 4)) ?? .new,
                due: sqlite3_column_int64(stmt, 5),
                interval: sqlite3_column_int64(stmt, 6),
                repetitions: sqlite3_column_int64(stmt, 7),
                lapses: sqlite3_column_int64(stmt, 8),
                easeFactor: sqlite3_column_double(stmt, 9),
                isFavorite: sqlite3_column_int64(stmt, 10) == 1,
                isArchived: sqlite3_column_int64(stmt, 11) == 1,
                noteID: sqlite3_column_type(stmt, 12) != SQLITE_NULL ? sqlite3_column_int64(stmt, 12) : nil,
                source: columnTextOptional(stmt, 13),
                author: columnTextOptional(stmt, 14),
                modificationDate: columnDate(stmt, 15),
                nextDate: columnDate(stmt, 16),
                previousDate: columnDate(stmt, 17),
                tags: tags
            ))
        }
        return cards
    }

    // MARK: - Notes

    public func listNotes(limit: Int = 50) throws -> [Note] {
        let sql = """
            SELECT n.Z_PK, n.ZMODEL, n.ZFLDS,
                   (SELECT COUNT(*) FROM ZCOREDATAFLASHCARD f WHERE f.ZNOTE = n.Z_PK) as cnt
            FROM ZNOTE n
            ORDER BY n.Z_PK DESC
            LIMIT ?
        """
        var notes: [Note] = []
        try query(sql, params: [limit]) { stmt in
            notes.append(Note(
                id: sqlite3_column_int64(stmt, 0),
                modelID: sqlite3_column_type(stmt, 1) != SQLITE_NULL ? sqlite3_column_int64(stmt, 1) : nil,
                fields: columnText(stmt, 2),
                flashcardCount: sqlite3_column_int64(stmt, 3)
            ))
        }
        return notes
    }

    // MARK: - Tags

    public func listTags() throws -> [Tag] {
        let sql = """
            SELECT t.Z_PK, t.ZNAME,
                   (SELECT COUNT(*) FROM Z_1TAGS jt WHERE jt.Z_2TAGS = t.Z_PK) as cnt
            FROM ZCOREDATATAG t
            ORDER BY cnt DESC
        """
        var tags: [Tag] = []
        try query(sql, params: []) { stmt in
            tags.append(Tag(
                id: sqlite3_column_int64(stmt, 0),
                name: columnText(stmt, 1),
                flashcardCount: sqlite3_column_int64(stmt, 2)
            ))
        }
        return tags
    }

    private func tagsForFlashcard(id: Int64) throws -> [String] {
        let sql = """
            SELECT t.ZNAME FROM ZCOREDATATAG t
            JOIN Z_1TAGS jt ON jt.Z_2TAGS = t.Z_PK
            WHERE jt.Z_1FLASHCARDS = ?
        """
        var tags: [String] = []
        try query(sql, params: [id]) { stmt in
            tags.append(columnText(stmt, 0))
        }
        return tags
    }

    // MARK: - Media

    /// Get media blobs attached to a flashcard via ZMEDIA table.
    public func mediaForFlashcard(id: Int64) throws -> [(filename: String, data: Data)] {
        let sql = "SELECT ZFNAME, ZDATA FROM ZMEDIA WHERE ZCARD = ? AND ZDATA IS NOT NULL AND LENGTH(ZDATA) > 100"
        var results: [(String, Data)] = []
        try query(sql, params: [id]) { stmt in
            let fname = columnText(stmt, 0)
            if let blob = sqlite3_column_blob(stmt, 1) {
                let len = Int(sqlite3_column_bytes(stmt, 1))
                results.append((fname, Data(bytes: blob, count: len)))
            }
        }
        return results
    }

    /// Get the embedded image data from ZIMAGEDATA column on a flashcard.
    public func imageDataForFlashcard(id: Int64) throws -> Data? {
        let sql = "SELECT ZIMAGEDATA FROM ZCOREDATAFLASHCARD WHERE Z_PK = ? AND ZIMAGEDATA IS NOT NULL AND LENGTH(ZIMAGEDATA) > 100"
        var result: Data?
        try query(sql, params: [id]) { stmt in
            let len = Int(sqlite3_column_bytes(stmt, 0))
            guard len > 2, let blob = sqlite3_column_blob(stmt, 0) else { return }
            let data = Data(bytes: blob, count: len)
            // Strip 1-byte length prefix if present (data starts with 0x01 then JPEG FFD8)
            if data[0] == 0x01 && data[1] == 0xFF {
                result = Data(data.dropFirst())
            } else {
                result = data
            }
        }
        return result
    }

    /// Get all flashcard IDs (for full extraction).
    public func allFlashcardIDs() throws -> [Int64] {
        let sql = "SELECT Z_PK FROM ZCOREDATAFLASHCARD ORDER BY Z_PK"
        var ids: [Int64] = []
        try query(sql, params: []) { stmt in
            ids.append(sqlite3_column_int64(stmt, 0))
        }
        return ids
    }

    // MARK: - Stats

    public func getStats() throws -> DeckStats {
        var total: Int64 = 0, new: Int64 = 0, learning: Int64 = 0
        var review: Int64 = 0, suspended: Int64 = 0
        var favorites: Int64 = 0, archived: Int64 = 0
        var totalNotes: Int64 = 0, totalTags: Int64 = 0
        var avgEase: Double = 0, avgInterval: Double = 0
        var dueToday: Int64 = 0

        try query("SELECT COUNT(*) FROM ZCOREDATAFLASHCARD", params: []) { stmt in
            total = sqlite3_column_int64(stmt, 0)
        }
        try query("SELECT COUNT(*) FROM ZCOREDATAFLASHCARD WHERE ZTYPE = 0", params: []) { stmt in
            new = sqlite3_column_int64(stmt, 0)
        }
        try query("SELECT COUNT(*) FROM ZCOREDATAFLASHCARD WHERE ZTYPE = 1", params: []) { stmt in
            learning = sqlite3_column_int64(stmt, 0)
        }
        try query("SELECT COUNT(*) FROM ZCOREDATAFLASHCARD WHERE ZTYPE = 2", params: []) { stmt in
            review = sqlite3_column_int64(stmt, 0)
        }
        try query("SELECT COUNT(*) FROM ZCOREDATAFLASHCARD WHERE ZQUEUE = 3", params: []) { stmt in
            suspended = sqlite3_column_int64(stmt, 0)
        }
        try query("SELECT COUNT(*) FROM ZCOREDATAFLASHCARD WHERE ZISFAVORITE = 1", params: []) { stmt in
            favorites = sqlite3_column_int64(stmt, 0)
        }
        try query("SELECT COUNT(*) FROM ZCOREDATAFLASHCARD WHERE ZISARCHIVED = 1", params: []) { stmt in
            archived = sqlite3_column_int64(stmt, 0)
        }
        try query("SELECT COUNT(*) FROM ZNOTE", params: []) { stmt in
            totalNotes = sqlite3_column_int64(stmt, 0)
        }
        try query("SELECT COUNT(*) FROM ZCOREDATATAG", params: []) { stmt in
            totalTags = sqlite3_column_int64(stmt, 0)
        }
        try query("SELECT AVG(ZEASINESSFACTOR) FROM ZCOREDATAFLASHCARD WHERE ZEASINESSFACTOR > 0", params: []) { stmt in
            avgEase = sqlite3_column_double(stmt, 0)
        }
        try query("SELECT AVG(ZIVL) FROM ZCOREDATAFLASHCARD WHERE ZIVL > 0", params: []) { stmt in
            avgInterval = sqlite3_column_double(stmt, 0)
        }

        // Due today: cards with ZNEXTDATE <= now
        let now = Date().timeIntervalSinceReferenceDate
        try query("SELECT COUNT(*) FROM ZCOREDATAFLASHCARD WHERE ZNEXTDATE IS NOT NULL AND ZNEXTDATE <= ? AND ZQUEUE != 3", params: [now]) { stmt in
            dueToday = sqlite3_column_int64(stmt, 0)
        }

        return DeckStats(
            totalCards: total,
            newCards: new,
            learningCards: learning,
            reviewCards: review,
            suspendedCards: suspended,
            favoriteCards: favorites,
            archivedCards: archived,
            totalNotes: totalNotes,
            totalTags: totalTags,
            averageEase: avgEase,
            averageInterval: avgInterval,
            dueToday: dueToday
        )
    }

    // MARK: - Dashboard

    public func getDashboardStats() throws -> DashboardStats {
        let deck = try getStats()
        let now = Date().timeIntervalSinceReferenceDate

        var mature: Int64 = 0, young: Int64 = 0, unseen: Int64 = 0
        var overdue: Int64 = 0, totalLapses: Int64 = 0, totalReps: Int64 = 0

        try query("""
            SELECT
                SUM(CASE WHEN ZIVL > 21 THEN 1 ELSE 0 END),
                SUM(CASE WHEN ZIVL > 0 AND ZIVL <= 21 THEN 1 ELSE 0 END),
                SUM(CASE WHEN ZIVL = 0 THEN 1 ELSE 0 END)
            FROM ZCOREDATAFLASHCARD WHERE ZISARCHIVED = 0
        """, params: []) { stmt in
            mature = sqlite3_column_int64(stmt, 0)
            young = sqlite3_column_int64(stmt, 1)
            unseen = sqlite3_column_int64(stmt, 2)
        }

        try query("""
            SELECT COUNT(*) FROM ZCOREDATAFLASHCARD
            WHERE ZNEXTDATE IS NOT NULL AND ZNEXTDATE < ?
            AND ZQUEUE != 3 AND ZISARCHIVED = 0
        """, params: [now - 86400]) { stmt in  // overdue = due before yesterday
            overdue = sqlite3_column_int64(stmt, 0)
        }

        try query("""
            SELECT COALESCE(SUM(ZLAPSES), 0), COALESCE(SUM(ZREPETITION), 0)
            FROM ZCOREDATAFLASHCARD WHERE ZISARCHIVED = 0
        """, params: []) { stmt in
            totalLapses = sqlite3_column_int64(stmt, 0)
            totalReps = sqlite3_column_int64(stmt, 1)
        }

        // Per-tag stats
        let sql = """
            SELECT t.ZNAME,
                COUNT(*) as total,
                COALESCE(SUM(f.ZLAPSES), 0),
                COALESCE(SUM(f.ZREPETITION), 0),
                AVG(f.ZIVL),
                AVG(f.ZEASINESSFACTOR),
                SUM(CASE WHEN f.ZIVL > 21 THEN 1 ELSE 0 END),
                SUM(CASE WHEN f.ZIVL > 0 AND f.ZIVL <= 21 THEN 1 ELSE 0 END)
            FROM ZCOREDATAFLASHCARD f
            JOIN Z_1TAGS jt ON jt.Z_1FLASHCARDS = f.Z_PK
            JOIN ZCOREDATATAG t ON t.Z_PK = jt.Z_2TAGS
            WHERE f.ZISARCHIVED = 0
            GROUP BY t.ZNAME
            ORDER BY total DESC
        """
        var tagStats: [TagStats] = []
        try query(sql, params: []) { stmt in
            tagStats.append(TagStats(
                name: columnText(stmt, 0),
                totalCards: sqlite3_column_int64(stmt, 1),
                totalLapses: sqlite3_column_int64(stmt, 2),
                totalRepetitions: sqlite3_column_int64(stmt, 3),
                averageInterval: sqlite3_column_double(stmt, 4),
                averageEase: sqlite3_column_double(stmt, 5),
                matureCards: sqlite3_column_int64(stmt, 6),
                youngCards: sqlite3_column_int64(stmt, 7)
            ))
        }

        return DashboardStats(
            deck: deck,
            matureCards: mature,
            youngCards: young,
            unseenCards: unseen,
            overdueCards: overdue,
            totalLapses: totalLapses,
            totalRepetitions: totalReps,
            tagStats: tagStats
        )
    }

    // MARK: - SQLite Helpers

    private func query(_ sql: String, params: [Any], handler: (OpaquePointer) throws -> Void) throws {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let s = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw AnkiCLIError.databaseError("Prepare failed: \(msg)")
        }
        defer { sqlite3_finalize(s) }

        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            switch param {
            case let v as Int:
                sqlite3_bind_int64(s, idx, Int64(v))
            case let v as Int64:
                sqlite3_bind_int64(s, idx, v)
            case let v as Double:
                sqlite3_bind_double(s, idx, v)
            case let v as String:
                sqlite3_bind_text(s, idx, (v as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            default:
                break
            }
        }

        while sqlite3_step(s) == SQLITE_ROW {
            try handler(s)
        }
    }

    private func columnText(_ stmt: OpaquePointer, _ col: Int32) -> String {
        if let cstr = sqlite3_column_text(stmt, col) {
            return String(cString: cstr)
        }
        return ""
    }

    private func columnTextOptional(_ stmt: OpaquePointer, _ col: Int32) -> String? {
        if sqlite3_column_type(stmt, col) == SQLITE_NULL { return nil }
        if let cstr = sqlite3_column_text(stmt, col) {
            return String(cString: cstr)
        }
        return nil
    }

    private func columnDate(_ stmt: OpaquePointer, _ col: Int32) -> Date? {
        if sqlite3_column_type(stmt, col) == SQLITE_NULL { return nil }
        let ts = sqlite3_column_double(stmt, col)
        guard ts > 0 else { return nil }
        // Core Data stores dates as seconds since 2001-01-01 (NSDate reference date)
        return Date(timeIntervalSinceReferenceDate: ts)
    }
}

// MARK: - Sort Options

public enum SortField: String, CaseIterable {
    case modified
    case due
    case created
    case ease
    case interval
}

// MARK: - Errors

public enum AnkiCLIError: Error, CustomStringConvertible {
    case databaseNotFound(String)
    case databaseError(String)
    case cardNotFound(Int64)

    public var description: String {
        switch self {
        case .databaseNotFound(let path):
            return "Anki Notes database not found at: \(path)\nMake sure Anki Notes is installed from the Mac App Store."
        case .databaseError(let msg):
            return "Database error: \(msg)"
        case .cardNotFound(let id):
            return "Flashcard not found: \(id)"
        }
    }
}
