import ArgumentParser
import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

public struct RestoreCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "restore",
        abstract: "Restore the Anki Notes database from a backup"
    )

    @Argument(help: "Path to the backup file (.sqlite)")
    var input: String

    @Flag(name: .long, help: "Skip confirmation prompt")
    var force: Bool = false

    @Option(name: .long, help: "Path to target database")
    var db: String?

    public init() {}

    public func run() throws {
        let backupPath = input
        guard FileManager.default.fileExists(atPath: backupPath) else {
            throw AnkiCLIError.databaseError("Backup file not found: \(backupPath)")
        }

        let targetPath = db ?? AnkiDatabase.defaultPath

        // Verify the backup is a valid SQLite database with expected tables
        try verifyBackup(backupPath)

        // Check if Anki Notes is running (only matters when restoring to the real database)
        if db == nil && isAppRunning() {
            fputs("WARNING: Anki Notes appears to be running. Quit the app before restoring.\n", stderr)
            throw AnkiCLIError.databaseError("Quit Anki Notes before restoring.")
        }

        if !force {
            fputs("This will replace your Anki Notes database at:\n  \(targetPath)\n\n", stderr)
            fputs("Backup source:\n  \(backupPath)\n\n", stderr)
            fputs("Type 'yes' to confirm: ", stderr)

            guard let answer = readLine(), answer.lowercased() == "yes" else {
                print("Restore cancelled.")
                return
            }
        }

        // Create a safety backup of current database before overwriting
        if FileManager.default.fileExists(atPath: targetPath) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            let safetyPath = targetPath + ".pre-restore-\(timestamp).bak"

            try FileManager.default.copyItem(atPath: targetPath, toPath: safetyPath)
            fputs("Safety backup: \(safetyPath)\n", stderr)
        }

        // Remove WAL and SHM files so Core Data rebuilds them
        for ext in ["-wal", "-shm"] {
            let path = targetPath + ext
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
        }

        // Use SQLite backup API for a safe copy
        var sourceDB: OpaquePointer?
        var destDB: OpaquePointer?

        let srcRC = sqlite3_open_v2(backupPath, &sourceDB, SQLITE_OPEN_READONLY, nil)
        guard srcRC == SQLITE_OK, let src = sourceDB else {
            let msg = sourceDB.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let s = sourceDB { sqlite3_close(s) }
            throw AnkiCLIError.databaseError("Failed to open backup: \(msg)")
        }
        defer { sqlite3_close(src) }

        let dstRC = sqlite3_open(targetPath, &destDB)
        guard dstRC == SQLITE_OK, let dst = destDB else {
            let msg = destDB.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let d = destDB { sqlite3_close(d) }
            throw AnkiCLIError.databaseError("Failed to open target: \(msg)")
        }
        defer { sqlite3_close(dst) }

        guard let backup = sqlite3_backup_init(dst, "main", src, "main") else {
            let msg = String(cString: sqlite3_errmsg(dst))
            throw AnkiCLIError.databaseError("Restore init failed: \(msg)")
        }

        let stepRC = sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)

        guard stepRC == SQLITE_DONE else {
            throw AnkiCLIError.databaseError("Restore failed with code \(stepRC)")
        }

        print("Restored from: \(backupPath)")
        print("Open Anki Notes to sync changes to iCloud.")
    }

    private func verifyBackup(_ path: String) throws {
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard rc == SQLITE_OK, let handle = db else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let d = db { sqlite3_close(d) }
            throw AnkiCLIError.databaseError("Not a valid SQLite database: \(msg)")
        }
        defer { sqlite3_close(handle) }

        // Check for expected tables
        var stmt: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('ZCOREDATAFLASHCARD', 'ZNOTE', 'ZCOREDATATAG')"
        let prepRC = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard prepRC == SQLITE_OK, let s = stmt else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw AnkiCLIError.databaseError("Failed to verify backup: \(msg)")
        }
        defer { sqlite3_finalize(s) }

        guard sqlite3_step(s) == SQLITE_ROW else {
            throw AnkiCLIError.databaseError("Failed to query backup file")
        }

        let tableCount = sqlite3_column_int64(s, 0)
        guard tableCount == 3 else {
            throw AnkiCLIError.databaseError("Backup does not look like an Anki Notes database (found \(tableCount)/3 expected tables)")
        }
    }

    private func isAppRunning() -> Bool {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "Anki Notes"]  // exact match to avoid matching our own CLI
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
