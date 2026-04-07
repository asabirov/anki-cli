import ArgumentParser
import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

public struct ImportCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import flashcards from a JSON or TSV file"
    )

    @Argument(help: "Path to import file (.json or .tsv)")
    var input: String

    @Option(name: .shortAndLong, help: "Format: json, tsv (auto-detected from extension)")
    var format: String?

    @Flag(name: .long, help: "Dry run — show what would be imported without writing")
    var dryRun: Bool = false

    @Option(name: .long, help: "Path to database")
    var db: String?

    public init() {}

    public func run() throws {
        let inputPath = input
        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw AnkiCLIError.databaseError("File not found: \(inputPath)")
        }

        let fmt = format ?? detectFormat(inputPath)
        let cards: [ImportCard]
        switch fmt {
        case "json":
            cards = try parseJSON(path: inputPath)
        case "tsv":
            cards = try parseTSV(path: inputPath)
        default:
            throw AnkiCLIError.databaseError("Unknown format: \(fmt). Use json or tsv.")
        }

        guard !cards.isEmpty else {
            print("No cards found in \(inputPath)")
            return
        }

        // Validate
        var warnings: [String] = []
        for (i, card) in cards.enumerated() {
            if card.front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && card.back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                warnings.append("Card \(i + 1): both front and back are empty")
            }
        }
        for w in warnings { fputs("WARNING: \(w)\n", stderr) }

        // Collect tags
        let allTags = Set(cards.flatMap { $0.tags })

        fputs("Import summary:\n", stderr)
        fputs("  Cards: \(cards.count)\n", stderr)
        fputs("  Tags:  \(allTags.sorted().joined(separator: ", "))\n", stderr)
        fputs("  File:  \(inputPath)\n", stderr)

        if dryRun {
            print("\nDry run — no changes made.")
            fputs("\nSample cards:\n", stderr)
            for card in cards.prefix(5) {
                let front = String(card.front.prefix(50))
                let back = String(card.back.prefix(50))
                let tags = card.tags.isEmpty ? "" : " [\(card.tags.joined(separator: ", "))]"
                fputs("  \(front) → \(back)\(tags)\n", stderr)
            }
            return
        }

        // Check app is not running (only matters when writing to the real database)
        if db == nil && isAppRunning() {
            throw AnkiCLIError.databaseError("Quit Anki Notes before importing.")
        }

        let dbPath = db ?? AnkiDatabase.defaultPath
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw AnkiCLIError.databaseNotFound(dbPath)
        }

        let imported = try writeCards(cards, to: dbPath)
        print("Imported \(imported) cards.")
        print("Open Anki Notes to sync to iCloud.")
    }

    // MARK: - Parse JSON

    /// Expected format:
    /// ```json
    /// [
    ///   { "front": "Hello", "back": "Hola", "tags": ["Spanish"] },
    ///   { "front": "Cat", "back": "Gato", "image": "/path/to/photo.jpg" }
    /// ]
    /// ```
    private func parseJSON(path: String) throws -> [ImportCard] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw AnkiCLIError.databaseError("JSON must be an array of objects")
        }

        return array.map { obj in
            ImportCard(
                front: obj["front"] as? String ?? "",
                back: obj["back"] as? String ?? "",
                tags: obj["tags"] as? [String] ?? [],
                imagePath: obj["image"] as? String
            )
        }
    }

    // MARK: - Parse TSV

    /// Expected format (tab-separated, first line is header):
    /// ```
    /// front\tback\ttags
    /// Hello\tHola\tSpanish
    /// Cat\tGato\tSpanish;Animals
    /// ```
    private func parseTSV(path: String) throws -> [ImportCard] {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else {
            throw AnkiCLIError.databaseError("TSV file must have a header row and at least one data row")
        }

        let header = lines[0].lowercased().split(separator: "\t").map(String.init)
        let frontIdx = header.firstIndex(of: "front") ?? 0
        let backIdx = header.firstIndex(of: "back") ?? 1
        let tagsIdx = header.firstIndex(of: "tags")

        return lines.dropFirst().map { line in
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            let front = frontIdx < cols.count ? cols[frontIdx] : ""
            let back = backIdx < cols.count ? cols[backIdx] : ""
            let tags: [String]
            if let ti = tagsIdx, ti < cols.count, !cols[ti].isEmpty {
                tags = cols[ti].split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                tags = []
            }
            return ImportCard(front: front, back: back, tags: tags, imagePath: nil)
        }
    }

    // MARK: - Write to Core Data SQLite

    private func writeCards(_ cards: [ImportCard], to dbPath: String) throws -> Int {
        var handle: OpaquePointer?
        let rc = sqlite3_open(dbPath, &handle)
        guard rc == SQLITE_OK, let db = handle else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let h = handle { sqlite3_close(h) }
            throw AnkiCLIError.databaseError("Failed to open database for writing: \(msg)")
        }
        defer { sqlite3_close(db) }

        // Begin transaction
        try exec(db, "BEGIN EXCLUSIVE TRANSACTION")

        do {
            // Get current max PKs
            let maxFlashcard = try maxPK(db, table: "ZCOREDATAFLASHCARD")
            let maxNote = try maxPK(db, table: "ZNOTE")
            let maxTag = try maxPK(db, table: "ZCOREDATATAG")
            let maxChange = try maxPK(db, table: "ACHANGE")
            let maxTransaction = try maxPK(db, table: "ATRANSACTION")

            // Load existing tags
            var existingTags: [String: Int64] = [:]
            try queryDB(db, "SELECT Z_PK, ZNAME FROM ZCOREDATATAG") { stmt in
                let pk = sqlite3_column_int64(stmt, 0)
                if let name = sqlite3_column_text(stmt, 1) {
                    existingTags[String(cString: name)] = pk
                }
            }

            // Create transaction record
            let txnPK = maxTransaction + 1
            let now = Date().timeIntervalSinceReferenceDate
            try exec(db, """
                INSERT INTO ATRANSACTION (Z_PK, Z_ENT, Z_OPT, ZAUTHORTS, ZBUNDLEIDTS, ZCONTEXTNAMETS, ZPROCESSIDTS, ZTIMESTAMP)
                VALUES (\(txnPK), 16002, NULL, 1, 2, NULL, 3, \(now))
            """)

            var nextFlashcard = maxFlashcard
            var nextNote = maxNote
            var nextTag = maxTag
            var nextChange = maxChange
            var imported = 0

            for card in cards {
                nextNote += 1
                nextFlashcard += 1

                // Build note fields (front^_back format)
                let noteFields = "\(card.front)\u{1F}\(card.back)"

                // Insert note
                try execBind(db, """
                    INSERT INTO ZNOTE (Z_PK, Z_ENT, Z_OPT, ZMODEL, ZFLDS)
                    VALUES (?, 5, 1, 1, ?)
                """, params: [.int(nextNote), .text(noteFields)])

                // Generate UUID for flashcard
                let uuid = UUID()
                let uuidData = withUnsafeBytes(of: uuid.uuid) { Data($0) }
                let recordDate = now

                // Load image data if provided
                var imageData: Data?
                if let imgPath = card.imagePath {
                    let resolvedPath = (imgPath as NSString).expandingTildeInPath
                    guard FileManager.default.fileExists(atPath: resolvedPath) else {
                        throw AnkiCLIError.databaseError("Image not found: \(imgPath)")
                    }
                    var raw = try Data(contentsOf: URL(fileURLWithPath: resolvedPath))
                    // Add 0x01 prefix byte (Anki Notes ZIMAGEDATA format)
                    var prefixed = Data([0x01])
                    prefixed.append(raw)
                    imageData = prefixed
                }

                // Insert flashcard
                if let imgData = imageData {
                    try execBind(db, """
                        INSERT INTO ZCOREDATAFLASHCARD
                        (Z_PK, Z_ENT, Z_OPT, ZDUE, ZISARCHIVED, ZISFAVORITE, ZIVL, ZLAPSES, ZLEFT,
                         ZODUE, ZORD, ZQUEUE, ZREPETITION, ZTYPE, ZNOTE,
                         ZEASINESSFACTOR, ZINTERVALDOUBLE, ZMOD, ZRECORDDATE,
                         ZFRONT, ZBACK, ZUUID, ZIMAGEDATA)
                        VALUES (?, 1, 1, 0, 0, 0, 0, 0, 0,
                         0, 0, 0, 0, 0, ?,
                         2.5, 0.0, ?, ?,
                         ?, ?, ?, ?)
                    """, params: [
                        .int(nextFlashcard), .int(nextNote),
                        .double(recordDate), .double(recordDate),
                        .text(card.front), .text(card.back), .blob(uuidData), .blob(imgData)
                    ])
                } else {
                    try execBind(db, """
                        INSERT INTO ZCOREDATAFLASHCARD
                        (Z_PK, Z_ENT, Z_OPT, ZDUE, ZISARCHIVED, ZISFAVORITE, ZIVL, ZLAPSES, ZLEFT,
                         ZODUE, ZORD, ZQUEUE, ZREPETITION, ZTYPE, ZNOTE,
                         ZEASINESSFACTOR, ZINTERVALDOUBLE, ZMOD, ZRECORDDATE,
                         ZFRONT, ZBACK, ZUUID)
                        VALUES (?, 1, 1, 0, 0, 0, 0, 0, 0,
                         0, 0, 0, 0, 0, ?,
                         2.5, 0.0, ?, ?,
                         ?, ?, ?)
                    """, params: [
                        .int(nextFlashcard), .int(nextNote),
                        .double(recordDate), .double(recordDate),
                        .text(card.front), .text(card.back), .blob(uuidData)
                    ])
                }

                // Handle tags
                for tagName in card.tags {
                    let tagPK: Int64
                    if let existing = existingTags[tagName] {
                        tagPK = existing
                    } else {
                        nextTag += 1
                        tagPK = nextTag
                        let tagUUID = UUID()
                        let tagUUIDData = withUnsafeBytes(of: tagUUID.uuid) { Data($0) }
                        try execBind(db, """
                            INSERT INTO ZCOREDATATAG (Z_PK, Z_ENT, Z_OPT, ZNAME, ZUUID)
                            VALUES (?, 2, 1, ?, ?)
                        """, params: [.int(tagPK), .text(tagName), .blob(tagUUIDData)])
                        existingTags[tagName] = tagPK

                        // Track tag creation
                        nextChange += 1
                        try exec(db, """
                            INSERT INTO ACHANGE (Z_PK, Z_ENT, Z_OPT, ZCHANGETYPE, ZENTITY, ZENTITYPK, ZTRANSACTIONID)
                            VALUES (\(nextChange), 16001, NULL, 2, 2, \(tagPK), \(txnPK))
                        """)
                    }

                    // Insert tag-flashcard relationship
                    try exec(db, """
                        INSERT OR IGNORE INTO Z_1TAGS (Z_1FLASHCARDS, Z_2TAGS)
                        VALUES (\(nextFlashcard), \(tagPK))
                    """)
                }

                // Track flashcard creation in change history
                nextChange += 1
                try exec(db, """
                    INSERT INTO ACHANGE (Z_PK, Z_ENT, Z_OPT, ZCHANGETYPE, ZENTITY, ZENTITYPK, ZTRANSACTIONID)
                    VALUES (\(nextChange), 16001, NULL, 2, 1, \(nextFlashcard), \(txnPK))
                """)

                // Track note creation
                nextChange += 1
                try exec(db, """
                    INSERT INTO ACHANGE (Z_PK, Z_ENT, Z_OPT, ZCHANGETYPE, ZENTITY, ZENTITYPK, ZTRANSACTIONID)
                    VALUES (\(nextChange), 16001, NULL, 2, 5, \(nextNote), \(txnPK))
                """)

                imported += 1
            }

            // Update Z_PRIMARYKEY counters
            try exec(db, "UPDATE Z_PRIMARYKEY SET Z_MAX = \(nextFlashcard) WHERE Z_NAME = 'CoreDataFlashcard'")
            try exec(db, "UPDATE Z_PRIMARYKEY SET Z_MAX = \(nextNote) WHERE Z_NAME = 'Note'")
            if nextTag > maxTag {
                try exec(db, "UPDATE Z_PRIMARYKEY SET Z_MAX = \(nextTag) WHERE Z_NAME = 'CoreDataTag'")
            }

            try exec(db, "COMMIT")
            return imported
        } catch {
            try? exec(db, "ROLLBACK")
            throw error
        }
    }

    // MARK: - SQLite Helpers

    private enum BindValue {
        case int(Int64)
        case double(Double)
        case text(String)
        case blob(Data)
    }

    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw AnkiCLIError.databaseError("SQL error: \(msg)")
        }
    }

    private func execBind(_ db: OpaquePointer, _ sql: String, params: [BindValue]) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw AnkiCLIError.databaseError("Prepare failed: \(msg)")
        }
        defer { sqlite3_finalize(s) }

        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            switch param {
            case .int(let v):
                sqlite3_bind_int64(s, idx, v)
            case .double(let v):
                sqlite3_bind_double(s, idx, v)
            case .text(let v):
                sqlite3_bind_text(s, idx, (v as NSString).utf8String, -1,
                    unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .blob(let v):
                v.withUnsafeBytes { buf in
                    sqlite3_bind_blob(s, idx, buf.baseAddress, Int32(v.count),
                        unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            }
        }

        let rc = sqlite3_step(s)
        guard rc == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw AnkiCLIError.databaseError("Step failed: \(msg)")
        }
    }

    private func maxPK(_ db: OpaquePointer, table: String) throws -> Int64 {
        var result: Int64 = 0
        try queryDB(db, "SELECT MAX(Z_PK) FROM \(table)") { stmt in
            result = sqlite3_column_int64(stmt, 0)
        }
        return result
    }

    private func queryDB(_ db: OpaquePointer, _ sql: String, handler: (OpaquePointer) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw AnkiCLIError.databaseError("Prepare failed: \(msg)")
        }
        defer { sqlite3_finalize(s) }
        while sqlite3_step(s) == SQLITE_ROW { handler(s) }
    }

    // MARK: - Helpers

    private func detectFormat(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "json": return "json"
        case "tsv", "txt", "tab": return "tsv"
        default: return "json"
        }
    }

    private func isAppRunning() -> Bool {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "Anki Notes"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

// MARK: - Import Card Model

struct ImportCard {
    let front: String
    let back: String
    let tags: [String]
    let imagePath: String?  // optional path to an image file
}
