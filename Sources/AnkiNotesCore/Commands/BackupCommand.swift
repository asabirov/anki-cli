import ArgumentParser
import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

public struct BackupCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "backup",
        abstract: "Back up the Anki Notes database"
    )

    @Argument(help: "Output path for the backup file (.sqlite)")
    var output: String?

    @Option(name: .long, help: "Path to source database")
    var db: String?

    public init() {}

    public func run() throws {
        let sourcePath = db ?? AnkiDatabase.defaultPath
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            throw AnkiCLIError.databaseNotFound(sourcePath)
        }

        let destPath = output ?? defaultBackupPath()

        // Create parent directory if needed
        let destDir = (destPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: destDir, withIntermediateDirectories: true)

        // Use SQLite backup API for a consistent snapshot
        var sourceDB: OpaquePointer?
        var destDB: OpaquePointer?

        let srcRC = sqlite3_open_v2(sourcePath, &sourceDB, SQLITE_OPEN_READONLY, nil)
        guard srcRC == SQLITE_OK, let src = sourceDB else {
            let msg = sourceDB.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let s = sourceDB { sqlite3_close(s) }
            throw AnkiCLIError.databaseError("Failed to open source: \(msg)")
        }
        defer { sqlite3_close(src) }

        let dstRC = sqlite3_open(destPath, &destDB)
        guard dstRC == SQLITE_OK, let dst = destDB else {
            let msg = destDB.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let d = destDB { sqlite3_close(d) }
            throw AnkiCLIError.databaseError("Failed to create backup: \(msg)")
        }
        defer { sqlite3_close(dst) }

        guard let backup = sqlite3_backup_init(dst, "main", src, "main") else {
            let msg = String(cString: sqlite3_errmsg(dst))
            throw AnkiCLIError.databaseError("Backup init failed: \(msg)")
        }

        let stepRC = sqlite3_backup_step(backup, -1)  // copy everything in one step
        sqlite3_backup_finish(backup)

        guard stepRC == SQLITE_DONE else {
            throw AnkiCLIError.databaseError("Backup failed with code \(stepRC)")
        }

        let size = fileSize(destPath)
        print("Backed up to: \(destPath)")
        print("Size: \(formatSize(size))")
    }

    private func defaultBackupPath() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.local/share/anki-notes-cli/backups/anki-notes-\(timestamp).sqlite"
    }

    private func fileSize(_ path: String) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return attrs?[.size] as? Int64 ?? 0
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes >= 1_000_000 {
            return String(format: "%.1f MB", Double(bytes) / 1_000_000)
        } else if bytes >= 1_000 {
            return String(format: "%.1f KB", Double(bytes) / 1_000)
        }
        return "\(bytes) bytes"
    }
}
